/// Integration tests for SQLCipher database encryption and migration.
///
/// Run on a real device or emulator:
///   flutter test integration_test/database_encryption_test.dart
///
/// These tests cannot run in the standard `flutter test` host environment
/// because SQLCipher requires a native build target (Android / iOS).
/// They use real FlutterSecureStorage and real SQLite/SQLCipher native libs.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' show getDatabasesPath, openDatabase;

import 'package:beer_mile/database/app_database.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late String dbPath;

  // ── Helpers ──────────────────────────────────────────────────────────────

  Future<void> _wipeDatabaseFiles() async {
    for (final suffix in ['', '-wal', '-shm', '.enc', '.bak']) {
      final f = File('$dbPath$suffix');
      if (await f.exists()) await f.delete();
    }
  }

  /// Seed a plaintext v1 database at [dbPath], simulating an installation
  /// that used sqflite without encryption.
  Future<void> _seedPlaintextV1({int registrationRows = 1}) async {
    final db = await openDatabase(
      dbPath,
      version: 1,
      singleInstance: false,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE runner_tokens (
            runner_token TEXT PRIMARY KEY,
            registration_id INTEGER NOT NULL,
            event_id INTEGER NOT NULL,
            user_id TEXT NOT NULL,
            display_name TEXT
          )
        ''');
      },
    );
    for (var i = 0; i < registrationRows; i++) {
      await db.insert('runner_tokens', {
        'runner_token': 'token-$i',
        'registration_id': i + 1,
        'event_id': 99,
        'user_id': 'user_clerk_$i',
        'display_name': 'Runner $i', // legacy PII field — must be stripped
      });
    }
    await db.close();
  }

  setUp(() async {
    final dir = await getDatabasesPath();
    dbPath = p.join(dir, 'beer_mile.db');

    await AppDatabase.instance.close();
    await _wipeDatabaseFiles();
    await AppDatabase.clearStoredKeyForTesting();
  });

  tearDown(() async {
    await AppDatabase.instance.close();
  });

  // ── Test cases ─────────────────────────────────────────────────────────

  group('Fresh install', () {
    testWidgets('creates an encrypted database on first init', (tester) async {
      await AppDatabase.instance.init();

      expect(await File(dbPath).exists(), isTrue,
          reason: 'Database file must be created on first init');

      // Verify that a plain SQLite open (no password) cannot read the file.
      bool plainOpenSucceeded = false;
      try {
        final probe = await openDatabase(
          dbPath,
          readOnly: true,
          singleInstance: false,
        );
        await probe.rawQuery('SELECT count(*) FROM sqlite_master');
        await probe.close();
        plainOpenSucceeded = true;
      } catch (_) {
        // Expected — the database must be encrypted.
      }

      expect(plainOpenSucceeded, isFalse,
          reason: 'Plain SQLite open must fail on an SQLCipher-encrypted file');
    });

    testWidgets('creates all expected tables', (tester) async {
      await AppDatabase.instance.init();
      final tables = await AppDatabase.instance.db
          .rawQuery("SELECT name FROM sqlite_master WHERE type='table'");
      final names = tables.map((r) => r['name'] as String).toSet();
      expect(names, containsAll(['events', 'registrations', 'lap_logs', 'runner_tokens']));
    });
  });

  group('Encrypted reopen', () {
    testWidgets('second init reuses the stored key and opens successfully',
        (tester) async {
      // First init — generates key and creates encrypted DB.
      await AppDatabase.instance.init();
      await AppDatabase.instance.close();

      // Second init — must succeed with the persisted key.
      await AppDatabase.instance.init();

      final rows = await AppDatabase.instance.db
          .rawQuery("SELECT name FROM sqlite_master WHERE type='table'");
      expect(rows, isNotEmpty,
          reason: 'Re-opening with stored key must return valid schema');
    });
  });

  group('Plaintext v1 → SQLCipher migration', () {
    testWidgets('migrates data and strips display_name from runner_tokens',
        (tester) async {
      await _seedPlaintextV1(registrationRows: 3);

      // Init triggers the migration.
      await AppDatabase.instance.init();

      // All rows must be present after migration.
      final rows = await AppDatabase.instance.db
          .rawQuery('SELECT count(*) AS cnt FROM runner_tokens');
      expect(rows.first['cnt'], equals(3),
          reason: 'All pre-migration rows must survive the encryption migration');

      // display_name must have been stripped by the v1→v2 schema upgrade.
      final cols = await AppDatabase.instance.db
          .rawQuery('PRAGMA table_info(runner_tokens)');
      final colNames = cols.map((r) => r['name'] as String).toList();
      expect(colNames.contains('display_name'), isFalse,
          reason: 'display_name must be removed by the v1→v2 migration '
              '(PII policy — see SECURITY.md)');
    });

    testWidgets('encrypted file cannot be read without the password after migration',
        (tester) async {
      await _seedPlaintextV1();
      await AppDatabase.instance.init();
      await AppDatabase.instance.close();

      bool plainOpenSucceeded = false;
      try {
        final probe = await openDatabase(
          dbPath,
          readOnly: true,
          singleInstance: false,
        );
        await probe.rawQuery('SELECT count(*) FROM sqlite_master');
        await probe.close();
        plainOpenSucceeded = true;
      } catch (_) {}

      expect(plainOpenSucceeded, isFalse,
          reason: 'Migrated database must be unreadable without the password');
    });

    testWidgets('WAL and SHM sidecars of the plaintext file are deleted after migration',
        (tester) async {
      await _seedPlaintextV1();
      // Force a WAL file to exist by opening in WAL mode.
      final walDb = await openDatabase(
        dbPath,
        singleInstance: false,
      );
      await walDb.execute('PRAGMA journal_mode=WAL');
      await walDb.insert('runner_tokens', {
        'runner_token': 'wal-token',
        'registration_id': 999,
        'event_id': 99,
        'user_id': 'user_wal',
        'display_name': 'WAL Runner',
      });
      // Close without checkpointing to ensure WAL file exists.
      await walDb.close();

      await AppDatabase.instance.init();

      // No plaintext sidecar files must remain.
      expect(await File('$dbPath-wal').exists(), isFalse,
          reason: 'WAL sidecar must be deleted after migration');
      expect(await File('$dbPath-shm').exists(), isFalse,
          reason: 'SHM sidecar must be deleted after migration');
    });
  });

  group('Interrupted-cleanup recovery — encrypted db confirmed readable', () {
    /// Simulates the state after a migration that placed the encrypted database
    /// but crashed before deleting the plaintext .bak backup.
    Future<void> _simulateInterruptedCleanup() async {
      // 1. Perform a real migration so the encrypted database is in place.
      await _seedPlaintextV1(registrationRows: 2);
      await AppDatabase.instance.init();
      await AppDatabase.instance.close();
      // 2. Re-create plaintext .bak and sidecar to simulate unfinished cleanup.
      await File('$dbPath.bak').writeAsBytes([0x53, 0x51, 0x4c, 0x69]);
      await File('$dbPath.bak-wal').writeAsBytes([0x01, 0x02, 0x03]);
    }

    testWidgets(
        'init() verifies encrypted db, deletes .bak and sidecars, opens db',
        (tester) async {
      await _simulateInterruptedCleanup();

      // Re-init — .bak detected, encrypted db verified, cleanup resumes.
      await AppDatabase.instance.init();

      expect(await File('$dbPath.bak').exists(), isFalse,
          reason: '.bak must be deleted after verified cleanup');
      expect(await File('$dbPath.bak-wal').exists(), isFalse,
          reason: '.bak-wal must be deleted after verified cleanup');

      final rows = await AppDatabase.instance.db
          .rawQuery("SELECT name FROM sqlite_master WHERE type='table'");
      expect(rows, isNotEmpty,
          reason: 'Database must be operational after resumed cleanup');
    });

    testWidgets('migrated row data survives interrupted cleanup', (tester) async {
      await _simulateInterruptedCleanup();
      await AppDatabase.instance.init();

      final count = await AppDatabase.instance.db
          .rawQuery('SELECT count(*) AS cnt FROM runner_tokens');
      expect(count.first['cnt'], equals(2),
          reason: 'Rows must survive across interrupted cleanup resume');
    });
  });

  group('Interrupted-cleanup recovery — encrypted db absent/unreadable', () {
    testWidgets(
        'init() restores .bak and throws when encrypted file is absent',
        (tester) async {
      // Simulate: .bak exists (original was renamed) but encrypted rename
      // failed, so nothing is at dbPath.
      await _seedPlaintextV1(registrationRows: 3);
      final plainBytes = await File(dbPath).readAsBytes();
      await File('$dbPath.bak').writeAsBytes(plainBytes);
      // dbPath itself does not exist — simulates a failed encrypted rename.
      await File(dbPath).delete();

      await expectLater(
        AppDatabase.instance.init(),
        throwsA(isA<StateError>()),
        reason: 'init() must throw when encrypted db is absent after prior swap',
      );

      // The backup must have been restored to dbPath so data is not lost.
      expect(await File(dbPath).exists(), isTrue,
          reason: 'Backup must be restored to dbPath after failed-swap recovery');
    });

    testWidgets(
        'init() restores .bak and throws when main file is not encrypted',
        (tester) async {
      // Simulate: .bak exists and dbPath contains a non-SQLCipher file
      // (e.g., a zero-byte file from a crashed encrypted rename).
      await _seedPlaintextV1(registrationRows: 1);
      final plainBytes = await File(dbPath).readAsBytes();
      await File('$dbPath.bak').writeAsBytes(plainBytes);
      // Replace dbPath with garbage to simulate a corrupted/partial write.
      await File(dbPath).writeAsBytes([0x00, 0x00, 0x00, 0x00]);

      await expectLater(
        AppDatabase.instance.init(),
        throwsA(isA<StateError>()),
        reason: 'init() must throw when dbPath is not encrypted with stored key',
      );

      // The original plaintext bytes must be restored at dbPath.
      final restored = await File(dbPath).readAsBytes();
      expect(restored, equals(plainBytes),
          reason: 'Backup contents must be restored verbatim after failed swap');
    });
  });

  group('WAL/SHM sidecar cleanup', () {
    testWidgets(
        'original-path WAL and SHM sidecars are deleted after successful migration',
        (tester) async {
      // Force a WAL-mode plaintext database.
      await _seedPlaintextV1();
      final walDb = await openDatabase(dbPath, singleInstance: false);
      await walDb.execute('PRAGMA journal_mode=WAL');
      await walDb.insert('runner_tokens', {
        'runner_token': 'wal-sentinel',
        'registration_id': 999,
        'event_id': 99,
        'user_id': 'user_wal',
        'display_name': 'WAL Runner',
      });
      await walDb.close();

      expect(await File('$dbPath-wal').exists(), isTrue,
          reason: 'Precondition: WAL sidecar must exist before migration');

      await AppDatabase.instance.init();

      // After migration, the original-path sidecars must be gone.
      expect(await File('$dbPath-wal').exists(), isFalse,
          reason: 'Plaintext WAL at original path must be deleted by migration');
      expect(await File('$dbPath-shm').exists(), isFalse,
          reason: 'Plaintext SHM at original path must be deleted by migration');
    });

    testWidgets('no .bak-wal or .bak-shm files remain after successful migration',
        (tester) async {
      await _seedPlaintextV1();
      await AppDatabase.instance.init();

      expect(await File('$dbPath.bak').exists(), isFalse);
      expect(await File('$dbPath.bak-wal').exists(), isFalse);
      expect(await File('$dbPath.bak-shm').exists(), isFalse);
    });
  });
}
