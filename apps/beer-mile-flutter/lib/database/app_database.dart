import 'dart:async';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Single SQLite database instance for offline-first storage.
///
/// Tables mirror the server schema.  All writes use sqflite transactions for
/// safety.  The [SyncEngine] uses the `is_synced` flag on [kLapLogs] to drive
/// background upload.
class AppDatabase {
  AppDatabase._();

  static final AppDatabase instance = AppDatabase._();

  Database? _db;
  Database get db {
    assert(_db != null, 'AppDatabase.init() must be called first');
    return _db!;
  }

  static const int _version = 1;

  // Table names
  static const String kEvents = 'events';
  static const String kRegistrations = 'registrations';
  static const String kLapLogs = 'lap_logs';
  static const String kRunnerTokens = 'runner_tokens';

  Future<void> init() async {
    if (_db != null) return;
    final dir = await getDatabasesPath();
    final path = p.join(dir, 'beer_mile.db');
    _db = await openDatabase(
      path,
      version: _version,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

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

    // Maps NFC tag UID or QR payload → runner registration for offline lookup
    await db.execute('''
      CREATE TABLE $kRunnerTokens (
        runner_token TEXT PRIMARY KEY,
        registration_id INTEGER NOT NULL,
        event_id INTEGER NOT NULL,
        user_id TEXT NOT NULL,
        display_name TEXT
      )
    ''');

    await db.execute(
        'CREATE INDEX idx_lap_logs_registration ON $kLapLogs(registration_id)');
    await db.execute(
        'CREATE INDEX idx_lap_logs_synced ON $kLapLogs(is_synced)');
    await db.execute(
        'CREATE INDEX idx_registrations_event ON $kRegistrations(event_id)');
    await db.execute(
        'CREATE INDEX idx_runner_tokens_event ON $kRunnerTokens(event_id)');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // Future migrations go here
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
