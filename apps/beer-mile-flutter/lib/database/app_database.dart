import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' show getDatabasesPath, Database;
import 'package:sqflite_sqlcipher/sqflite.dart' show openDatabase;

/// Single SQLite database instance for offline-first storage.
///
/// The database file is encrypted at rest using SQLCipher.  A per-device
/// 32-byte key is generated on first launch and stored in FlutterSecureStorage
/// (Android Keystore-backed EncryptedSharedPreferences / iOS Keychain).
///
/// ## PII policy
/// No display names, email addresses, or other personal data are stored in this
/// database.  Runner identity is represented only by opaque IDs (integer
/// registration_id, Clerk user_id string).  Display names are held in memory
/// during a race session only (populated at pre-race sync, discarded when the
/// scanner screen is closed).
///
/// See SECURITY.md for the full on-device / server-only data boundary.
class AppDatabase {
  AppDatabase._();

  static final AppDatabase instance = AppDatabase._();

  Database? _db;
  Database get db {
    assert(_db != null, 'AppDatabase.init() must be called first');
    return _db!;
  }

  /// Bump this version when the schema changes.  Add a migration branch in
  /// [_onUpgrade] for every increment.
  static const int _version = 2;

  // ── Secure storage key for the SQLCipher database key ─────────────────────
  @visibleForTesting
  static const String kDbKeyStorageKey = 'sqlcipher_db_key';

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  // ── Table names ────────────────────────────────────────────────────────────
  static const String kEvents = 'events';
  static const String kRegistrations = 'registrations';
  static const String kLapLogs = 'lap_logs';
  static const String kRunnerTokens = 'runner_tokens';

  /// DDL for the runner_tokens table — exposed as a constant so tests can
  /// verify the schema without spinning up a full database.
  ///
  /// **PII constraint**: this table must never contain display_name, email, or
  /// any other human-readable personal data field.  Only opaque IDs are stored.
  static const String kRunnerTokensDdl = '''
    CREATE TABLE $kRunnerTokens (
      runner_token TEXT PRIMARY KEY,
      registration_id INTEGER NOT NULL,
      event_id INTEGER NOT NULL,
      user_id TEXT NOT NULL
    )
  ''';

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  Future<void> init() async {
    if (_db != null) return;

    final dir = await getDatabasesPath();
    final path = p.join(dir, 'beer_mile.db');

    // Get or generate the per-device encryption key.
    final key = await _getOrCreateKey();

    // Migrate from unencrypted plain-sqflite database if this is an upgrade.
    await _migrateFromUnencryptedIfNeeded(path, key);

    _db = await openDatabase(
      path,
      password: key,
      version: _version,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  // ── Key management ─────────────────────────────────────────────────────────

  /// Returns the hex-encoded 32-byte database key, generating and securely
  /// persisting it on first launch.
  static Future<String> _getOrCreateKey() async {
    final existing = await _storage.read(key: kDbKeyStorageKey);
    if (existing != null && existing.isNotEmpty) return existing;

    final rng = Random.secure();
    final bytes = List<int>.generate(32, (_) => rng.nextInt(256));
    final key =
        bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    await _storage.write(key: kDbKeyStorageKey, value: key);
    return key;
  }

  // ── Upgrade migration from unencrypted database ────────────────────────────

  /// Re-encrypts a legacy plain-sqflite database using SQLCipher's
  /// `sqlcipher_export`.
  ///
  /// **Security contract**
  /// - Throws on any failure; `init()` must not open the database while
  ///   plaintext data may remain on disk.
  /// - WAL/SHM sidecars at the *original* path are deleted immediately after
  ///   the plaintext handle is closed and BEFORE the main file is renamed;
  ///   they never survive to the `.bak` path.
  /// - The `.bak` sentinel means a prior migration placed the encrypted DB
  ///   but did not finish cleanup.  Recovery verifies the encrypted file is
  ///   readable before deleting the backup; if not, it restores the backup.
  /// - Plaintext file deletion is never swallowed — errors propagate to
  ///   `init()` which blocks startup; the next launch retries.
  /// - All handles use `singleInstance: false` to prevent connection-pool
  ///   collisions across the probe → export → final-open sequence.
  static Future<void> _migrateFromUnencryptedIfNeeded(
      String path, String key) async {
    final file = File(path);
    final backupPath = '$path.bak';
    final backupFile = File(backupPath);

    // ── Interrupted-cleanup / failed-swap recovery ─────────────────────────
    if (await backupFile.exists()) {
      // A .bak exists from a prior launch.  Verify the encrypted database is
      // actually readable before deleting the only copy of the original data.
      if (!await File(path).exists() || !await _isEncrypted(path, key)) {
        // The encrypted file is missing or unreadable (the rename or a prior
        // recovery step failed).  Restore the plaintext backup so data is not
        // lost, then throw so the next launch retries migration from scratch.
        debugPrint(
            '[AppDatabase] Encrypted db absent/unreadable — restoring backup…');
        if (await File(path).exists()) {
          await File(path).delete().catchError((_) {});
        }
        await backupFile.rename(path);
        throw StateError(
          'Encrypted database absent or unreadable; restored plaintext backup. '
          'Migration will retry on next launch.',
        );
      }
      // Encrypted database confirmed readable — safe to delete backup files.
      debugPrint('[AppDatabase] Resuming plaintext cleanup from prior migration…');
      await _deletePlaintextFiles(backupPath);
      return;
    }

    if (!await file.exists()) return; // Fresh install
    if (await _isEncrypted(path, key)) return; // Already encrypted

    debugPrint('[AppDatabase] Migrating plaintext database to SQLCipher…');
    final encPath = '$path.enc';
    Database? plainDb;
    try {
      // Isolated, non-cached connection so it cannot interfere with subsequent
      // opens of the same path.
      plainDb = await openDatabase(
        path,
        password: '', // empty password = plain SQLite in SQLCipher
        singleInstance: false,
      );

      // Checkpoint WAL into the main file.  TRUNCATE mode zeroes the WAL file;
      // log a warning but do not abort — the data is still in the main file.
      final cpRows =
          await plainDb.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
      final cpBusy =
          cpRows.isNotEmpty ? (cpRows.first['busy'] as int? ?? 0) : 0;
      if (cpBusy > 0) {
        debugPrint(
            '[AppDatabase] wal_checkpoint busy=$cpBusy; WAL may not be fully folded.');
      }

      // Export all data to a new encrypted copy.  ATTACH KEY does not support
      // `?` binding; key is hex-only and encPath is single-quote–escaped.
      final safeEncPath = encPath.replaceAll("'", "''");
      await plainDb
          .execute("ATTACH DATABASE '$safeEncPath' AS encrypted KEY '$key'");
      await plainDb.rawQuery("SELECT sqlcipher_export('encrypted')");
      await plainDb.execute('DETACH DATABASE encrypted');

      // Close BEFORE any file operations to release all OS locks.
      await plainDb.close();
      plainDb = null;

      // Delete the WAL/SHM sidecars at the ORIGINAL path NOW, while the main
      // file is still at [path].  After we rename, these paths will refer to
      // the new encrypted database's sidecars — not the plaintext ones.
      // Errors are not swallowed: a failure here means plaintext data would
      // remain, so we propagate to the catch block.
      await _deletePlaintextSidecars(path);

      // Atomic swap: original → .bak, encrypted → original path.
      await file.rename(backupPath);
      try {
        await File(encPath).rename(path);
      } catch (_) {
        // Rename failed — restore the original from backup so data is intact.
        await File(backupPath).rename(path);
        rethrow;
      }

      // Validate the encrypted database BEFORE deleting the only backup copy.
      // If sqlcipher_export produced an invalid or unreadable file, we must
      // restore the plaintext backup rather than deleting it.
      if (!await _isEncrypted(path, key)) {
        debugPrint(
            '[AppDatabase] Encrypted db failed post-swap validation — restoring backup.');
        await File(path).delete().catchError((_) {});
        await File(backupPath).rename(path);
        throw StateError(
          'Encrypted database failed validation after migration; '
          'restored plaintext backup. Migration will retry on next launch.',
        );
      }

      // Delete the plaintext backup.  If this fails, the next launch detects
      // .bak, verifies the encrypted db (which is confirmed readable above),
      // and retries deletion.
      await _deletePlaintextFiles(backupPath);

      debugPrint('[AppDatabase] Migration to SQLCipher complete.');
    } catch (e) {
      debugPrint('[AppDatabase] Migration failed ($e) — preserving original.');
      await plainDb?.close();
      await File(encPath).delete().catchError((_) {});
      rethrow;
    }
  }

  /// Deletes WAL and SHM sidecars for [dbPath] (not the main database file).
  /// Errors propagate — no silent swallowing.
  static Future<void> _deletePlaintextSidecars(String dbPath) async {
    for (final suffix in ['-wal', '-shm']) {
      final f = File('$dbPath$suffix');
      if (await f.exists()) await f.delete();
    }
  }

  /// Deletes [bakPath] and its `-wal` / `-shm` sidecars.
  ///
  /// **Deletion order: sidecars first, `.bak` last.**
  /// If a sidecar deletion throws, the sentinel `.bak` is still on disk, so
  /// the next launch's interrupted-cleanup path will retry the full deletion.
  /// If `.bak` were deleted first and a sidecar deletion then failed, the
  /// sentinel would be gone and the plaintext sidecar would remain permanently.
  ///
  /// Errors propagate — no silent swallowing.
  static Future<void> _deletePlaintextFiles(String bakPath) async {
    // 1. Sidecars first (not the sentinel yet).
    for (final suffix in ['-wal', '-shm']) {
      final f = File('$bakPath$suffix');
      if (await f.exists()) await f.delete();
    }
    // 2. Sentinel last — only removed once all sidecars are gone.
    final bak = File(bakPath);
    if (await bak.exists()) await bak.delete();
  }

  /// Returns `true` if [path] is already SQLCipher-encrypted with [key].
  ///
  /// Uses `singleInstance: false` and a `finally` block to guarantee the probe
  /// handle is always closed before the caller opens the same path again.
  static Future<bool> _isEncrypted(String path, String key) async {
    Database? probe;
    try {
      probe = await openDatabase(
        path,
        password: key,
        readOnly: true,
        singleInstance: false, // isolate from the production connection pool
      );
      await probe.rawQuery('SELECT name FROM sqlite_master LIMIT 1');
      return true;
    } catch (_) {
      return false;
    } finally {
      // Always close — even when the query threw — so no cached handle blocks
      // the subsequent plaintext-migration open of the same path.
      await probe?.close();
    }
  }

  // ── Test helpers ───────────────────────────────────────────────────────────

  /// Deletes the stored encryption key.  Only for use in integration tests
  /// that need to simulate a fresh install.
  @visibleForTesting
  static Future<void> clearStoredKeyForTesting() async {
    await _storage.delete(key: kDbKeyStorageKey);
  }

  // ── Schema creation ────────────────────────────────────────────────────────

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE $kEvents (
        id INTEGER PRIMARY KEY,
        tenant_id INTEGER NOT NULL,
        title TEXT NOT NULL,
        event_code TEXT NOT NULL,
        event_date TEXT NOT NULL,
        location_name TEXT,
        location_lat REAL,
        location_lng REAL,
        beer_type TEXT,
        entry_fee TEXT,
        payment_instructions TEXT,
        prizes_json TEXT,
        status TEXT NOT NULL DEFAULT 'draft',
        created_at TEXT NOT NULL,
        updated_at TEXT,
        synced_at TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE $kRegistrations (
        id INTEGER PRIMARY KEY,
        event_id INTEGER NOT NULL,
        user_id TEXT NOT NULL,
        payment_status TEXT NOT NULL DEFAULT 'pending',
        tag_uid TEXT,
        runner_token TEXT,
        registered_at TEXT NOT NULL,
        updated_at TEXT,
        UNIQUE(event_id, user_id)
      )
    ''');

    await db.execute('''
      CREATE TABLE $kLapLogs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        client_event_log_id TEXT NOT NULL UNIQUE,
        registration_id INTEGER NOT NULL,
        lap_number INTEGER NOT NULL CHECK(lap_number BETWEEN 1 AND 4),
        elapsed_ms INTEGER NOT NULL CHECK(elapsed_ms > 0),
        split_time_ms INTEGER,
        pour_confirmed INTEGER NOT NULL DEFAULT 0,
        is_synced INTEGER NOT NULL DEFAULT 0,
        device_monotonic_timestamp INTEGER,
        logged_at TEXT NOT NULL,
        UNIQUE(registration_id, lap_number)
      )
    ''');

    // Maps NFC tag UID or QR payload → runner registration for offline lookup.
    // PII policy: no display_name or email — opaque IDs only.
    await db.execute(kRunnerTokensDdl);

    await db.execute(
        'CREATE INDEX idx_lap_logs_registration ON $kLapLogs(registration_id)');
    await db.execute(
        'CREATE INDEX idx_lap_logs_synced ON $kLapLogs(is_synced)');
    await db.execute(
        'CREATE INDEX idx_registrations_event ON $kRegistrations(event_id)');
    await db.execute(
        'CREATE INDEX idx_runner_tokens_event ON $kRunnerTokens(event_id)');
  }

  // ── Schema migrations ──────────────────────────────────────────────────────

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // v1→v2: remove display_name (PII) from runner_tokens.
      // SQLite <3.35.0 does not support ALTER TABLE DROP COLUMN, so we
      // recreate the table without that column.
      await db.execute('''
        CREATE TABLE runner_tokens_v2 (
          runner_token TEXT PRIMARY KEY,
          registration_id INTEGER NOT NULL,
          event_id INTEGER NOT NULL,
          user_id TEXT NOT NULL
        )
      ''');
      await db.execute(
          'INSERT INTO runner_tokens_v2 '
          'SELECT runner_token, registration_id, event_id, user_id '
          'FROM $kRunnerTokens');
      await db.execute('DROP TABLE $kRunnerTokens');
      await db.execute(
          'ALTER TABLE runner_tokens_v2 RENAME TO $kRunnerTokens');
      await db.execute(
          'CREATE INDEX idx_runner_tokens_event ON $kRunnerTokens(event_id)');
    }
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
