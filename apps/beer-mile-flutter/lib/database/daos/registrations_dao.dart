import 'package:sqflite/sqflite.dart';

import '../app_database.dart';
import '../../api/models/api_registration.dart';

/// DAO for cached registration records and the local runner-token map.
///
/// PII policy: [upsertRunnerToken] stores only opaque IDs.  Display names
/// and email addresses are never written to the local database — they are
/// held in memory during a scanner session only.  See SECURITY.md.
class RegistrationsDao {
  RegistrationsDao(this._db);
  final AppDatabase _db;

  static Map<String, dynamic> _regToRow(ApiRegistration r) => {
        'id': r.id,
        'event_id': r.eventId,
        'user_id': r.userId,
        'payment_status': r.paymentStatus,
        'tag_uid': r.tagUid,
        'runner_token': r.runnerToken,
        'registered_at': r.registeredAt.toIso8601String(),
        'updated_at': r.updatedAt?.toIso8601String(),
      };

  static ApiRegistration _rowToReg(Map<String, dynamic> row) =>
      ApiRegistration(
        id: row['id'] as int,
        eventId: row['event_id'] as int,
        userId: row['user_id'] as String,
        paymentStatus: row['payment_status'] as String,
        registeredAt: DateTime.parse(row['registered_at'] as String),
        tagUid: row['tag_uid'] as String?,
        runnerToken: row['runner_token'] as String?,
        updatedAt: row['updated_at'] != null
            ? DateTime.parse(row['updated_at'] as String)
            : null,
      );

  Future<List<ApiRegistration>> findByUser(String userId) async {
    final rows = await _db.db.query(
      AppDatabase.kRegistrations,
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'registered_at DESC',
    );
    return rows.map(_rowToReg).toList();
  }

  Future<List<ApiRegistration>> findByEvent(int eventId) async {
    final rows = await _db.db.query(
      AppDatabase.kRegistrations,
      where: 'event_id = ?',
      whereArgs: [eventId],
    );
    return rows.map(_rowToReg).toList();
  }

  Future<ApiRegistration?> findByUserAndEvent(
      String userId, int eventId) async {
    final rows = await _db.db.query(
      AppDatabase.kRegistrations,
      where: 'user_id = ? AND event_id = ?',
      whereArgs: [userId, eventId],
    );
    if (rows.isEmpty) return null;
    return _rowToReg(rows.first);
  }

  Future<void> upsertAll(List<ApiRegistration> regs) async {
    final batch = _db.db.batch();
    for (final r in regs) {
      batch.insert(AppDatabase.kRegistrations, _regToRow(r),
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<void> upsert(ApiRegistration reg) async {
    await _db.db.insert(AppDatabase.kRegistrations, _regToRow(reg),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ── Runner token map ───────────────────────────────────────────────────────

  /// Persists a token → registration mapping for offline NFC/QR lookup.
  ///
  /// **PII policy**: only opaque IDs are stored.  Callers must NOT pass a
  /// display name; names must be kept in the calling scope's memory only.
  Future<void> upsertRunnerToken({
    required String token,
    required int registrationId,
    required int eventId,
    required String userId,
  }) async {
    await _db.db.insert(
      AppDatabase.kRunnerTokens,
      {
        'runner_token': token,
        'registration_id': registrationId,
        'event_id': eventId,
        'user_id': userId,
        // display_name intentionally absent — PII must not be persisted locally.
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, dynamic>?> findByToken(String token) async {
    final rows = await _db.db.query(
      AppDatabase.kRunnerTokens,
      where: 'runner_token = ?',
      whereArgs: [token],
    );
    if (rows.isEmpty) return null;
    return rows.first;
  }

  Future<List<Map<String, dynamic>>> findTokensByEvent(int eventId) async {
    return _db.db.query(
      AppDatabase.kRunnerTokens,
      where: 'event_id = ?',
      whereArgs: [eventId],
    );
  }
}
