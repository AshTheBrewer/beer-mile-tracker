import 'dart:convert';

import '../app_database.dart';
import '../../api/models/api_event.dart';

/// Data access object for cached [ApiEvent] records.
class EventsDao {
  EventsDao(this._db);
  final AppDatabase _db;

  static Map<String, dynamic> _toRow(ApiEvent e) => {
        'id': e.id,
        'tenant_id': e.tenantId,
        'title': e.title,
        'event_code': e.eventCode,
        'event_date': e.eventDate,
        'location_name': e.locationName,
        'location_lat': e.locationLat,
        'location_lng': e.locationLng,
        'beer_type': e.beerType,
        'entry_fee': e.entryFee,
        'payment_instructions': e.paymentInstructions,
        'prizes_json':
            e.prizesJson != null ? jsonEncode(e.prizesJson) : null,
        'status': e.status,
        'created_at': e.createdAt.toIso8601String(),
        'updated_at': e.updatedAt?.toIso8601String(),
        'synced_at': DateTime.now().toIso8601String(),
      };

  static ApiEvent _fromRow(Map<String, dynamic> row) => ApiEvent(
        id: row['id'] as int,
        tenantId: row['tenant_id'] as int,
        title: row['title'] as String,
        eventCode: row['event_code'] as String,
        eventDate: row['event_date'] as String,
        status: row['status'] as String,
        createdAt: DateTime.parse(row['created_at'] as String),
        locationName: row['location_name'] as String?,
        locationLat: row['location_lat'] as double?,
        locationLng: row['location_lng'] as double?,
        beerType: row['beer_type'] as String?,
        entryFee: row['entry_fee'] as String?,
        paymentInstructions: row['payment_instructions'] as String?,
        prizesJson: row['prizes_json'] != null
            ? (jsonDecode(row['prizes_json'] as String) as List<dynamic>)
                .cast<Map<String, dynamic>>()
            : null,
        updatedAt: row['updated_at'] != null
            ? DateTime.parse(row['updated_at'] as String)
            : null,
      );

  Future<List<ApiEvent>> findAll() async {
    final rows = await _db.db.query(AppDatabase.kEvents,
        orderBy: 'event_date DESC');
    return rows.map(_fromRow).toList();
  }

  Future<ApiEvent?> findById(int id) async {
    final rows = await _db.db.query(AppDatabase.kEvents,
        where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return _fromRow(rows.first);
  }

  Future<void> upsertAll(List<ApiEvent> events) async {
    final batch = _db.db.batch();
    for (final e in events) {
      batch.insert(AppDatabase.kEvents, _toRow(e),
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<void> upsert(ApiEvent event) async {
    await _db.db.insert(AppDatabase.kEvents, _toRow(event),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteById(int id) async {
    await _db.db
        .delete(AppDatabase.kEvents, where: 'id = ?', whereArgs: [id]);
  }
}

// Re-export sqflite ConflictAlgorithm so callers don't need a separate import
export 'package:sqflite/sqflite.dart' show ConflictAlgorithm;
