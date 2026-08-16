import 'package:sqflite/sqflite.dart';

import '../app_database.dart';

class LocalLapLog {
  const LocalLapLog({
    required this.clientEventLogId,
    required this.registrationId,
    required this.lapNumber,
    required this.elapsedMs,
    required this.pourConfirmed,
    required this.isSynced,
    required this.loggedAt,
    this.splitTimeMs,
    this.deviceMonotonicTimestamp,
  });

  final String clientEventLogId;
  final int registrationId;
  final int lapNumber;
  final int elapsedMs;
  final bool pourConfirmed;
  final bool isSynced;
  final DateTime loggedAt;
  final int? splitTimeMs;
  final int? deviceMonotonicTimestamp;

  Map<String, dynamic> toApiRecord() => {
        'clientEventLogId': clientEventLogId,
        'registrationId': registrationId,
        'lapNumber': lapNumber,
        'elapsedMs': elapsedMs,
        'pourConfirmed': pourConfirmed,
        if (splitTimeMs != null) 'splitTimeMs': splitTimeMs,
        if (deviceMonotonicTimestamp != null)
          'deviceMonotonicTimestamp': deviceMonotonicTimestamp,
      };
}

class LapLogsDao {
  LapLogsDao(this._db);
  final AppDatabase _db;

  static Map<String, dynamic> _toRow(LocalLapLog l) => {
        'client_event_log_id': l.clientEventLogId,
        'registration_id': l.registrationId,
        'lap_number': l.lapNumber,
        'elapsed_ms': l.elapsedMs,
        'split_time_ms': l.splitTimeMs,
        'pour_confirmed': l.pourConfirmed ? 1 : 0,
        'is_synced': l.isSynced ? 1 : 0,
        'device_monotonic_timestamp': l.deviceMonotonicTimestamp,
        'logged_at': l.loggedAt.toIso8601String(),
      };

  static LocalLapLog _fromRow(Map<String, dynamic> row) => LocalLapLog(
        clientEventLogId: row['client_event_log_id'] as String,
        registrationId: row['registration_id'] as int,
        lapNumber: row['lap_number'] as int,
        elapsedMs: row['elapsed_ms'] as int,
        splitTimeMs: row['split_time_ms'] as int?,
        pourConfirmed: (row['pour_confirmed'] as int) == 1,
        isSynced: (row['is_synced'] as int) == 1,
        deviceMonotonicTimestamp: row['device_monotonic_timestamp'] as int?,
        loggedAt: DateTime.parse(row['logged_at'] as String),
      );

  /// Write a lap scan locally — "Earliest Scan Wins" enforced at the DB level
  /// by the UNIQUE(registration_id, lap_number) constraint.  If a conflict
  /// occurs, keep the record with the lower elapsed_ms.
  Future<bool> insertOrKeepFastest(LocalLapLog log) async {
    final db = _db.db;
    final existing = await db.query(
      AppDatabase.kLapLogs,
      columns: ['elapsed_ms', 'client_event_log_id'],
      where: 'registration_id = ? AND lap_number = ?',
      whereArgs: [log.registrationId, log.lapNumber],
    );
    if (existing.isNotEmpty) {
      final storedMs = existing.first['elapsed_ms'] as int;
      if (storedMs <= log.elapsedMs) {
        // Existing record is faster — idempotently ack the incoming log ID
        return false;
      }
      // New record is faster — delete the old one then insert
      await db.delete(
        AppDatabase.kLapLogs,
        where: 'registration_id = ? AND lap_number = ?',
        whereArgs: [log.registrationId, log.lapNumber],
      );
    }
    await db.insert(AppDatabase.kLapLogs, _toRow(log),
        conflictAlgorithm: ConflictAlgorithm.ignore);
    return true;
  }

  Future<List<LocalLapLog>> findPendingSync({int limit = 50}) async {
    final rows = await _db.db.query(
      AppDatabase.kLapLogs,
      where: 'is_synced = 0',
      orderBy: 'logged_at ASC',
      limit: limit,
    );
    return rows.map(_fromRow).toList();
  }

  Future<List<LocalLapLog>> findByRegistration(int registrationId) async {
    final rows = await _db.db.query(
      AppDatabase.kLapLogs,
      where: 'registration_id = ?',
      whereArgs: [registrationId],
      orderBy: 'lap_number ASC',
    );
    return rows.map(_fromRow).toList();
  }

  Future<int> markSynced(List<String> clientEventLogIds) async {
    if (clientEventLogIds.isEmpty) return 0;
    final placeholders = List.filled(clientEventLogIds.length, '?').join(',');
    return _db.db.rawUpdate(
      'UPDATE ${AppDatabase.kLapLogs} SET is_synced = 1 '
      'WHERE client_event_log_id IN ($placeholders)',
      clientEventLogIds,
    );
  }

  Future<int> pendingCount() async {
    final result = await _db.db.rawQuery(
        'SELECT COUNT(*) as cnt FROM ${AppDatabase.kLapLogs} WHERE is_synced = 0');
    return result.first['cnt'] as int;
  }
}
