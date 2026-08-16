import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';

import '../api/api_client.dart';
import '../core/config.dart';
import '../database/app_database.dart';
import '../database/daos/events_dao.dart';
import '../database/daos/registrations_dao.dart';
import '../database/daos/lap_logs_dao.dart';

enum SyncStatus { idle, syncing, error, offline }

class SyncState {
  const SyncState({
    required this.status,
    required this.pendingCount,
    this.lastError,
    this.lastSyncAt,
  });

  final SyncStatus status;
  final int pendingCount;
  final String? lastError;
  final DateTime? lastSyncAt;

  SyncState copyWith({
    SyncStatus? status,
    int? pendingCount,
    String? lastError,
    DateTime? lastSyncAt,
  }) =>
      SyncState(
        status: status ?? this.status,
        pendingCount: pendingCount ?? this.pendingCount,
        lastError: lastError,
        lastSyncAt: lastSyncAt ?? this.lastSyncAt,
      );

  static const initial = SyncState(status: SyncStatus.idle, pendingCount: 0);
}

class SyncEngine {
  SyncEngine({required AppDatabase db, required String apiBaseUrl})
      : _db = db,
        _api = ApiClient(baseUrl: apiBaseUrl),
        _eventsDao = EventsDao(db),
        _regsDao = RegistrationsDao(db),
        _lapLogsDao = LapLogsDao(db);

  static const String kBackgroundSyncTask = 'beer_mile_background_sync';

  final AppDatabase _db;
  final ApiClient _api;
  final EventsDao _eventsDao;
  final RegistrationsDao _regsDao;
  final LapLogsDao _lapLogsDao;

  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  final _stateController = StreamController<SyncState>.broadcast();

  SyncState _state = SyncState.initial;

  Stream<SyncState> get stateStream => _stateController.stream;
  SyncState get state => _state;

  void _emit(SyncState s) {
    _state = s;
    _stateController.add(s);
  }

  /// Start listening for connectivity changes and auto-sync.
  void startListening(String? token) {
    _connectivitySub?.cancel();
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      final online = results.any((r) => r != ConnectivityResult.none);
      if (online) {
        syncPendingLogs(token: token);
      } else {
        _emit(_state.copyWith(status: SyncStatus.offline));
      }
    });
  }

  void dispose() {
    _connectivitySub?.cancel();
    _stateController.close();
  }

  // ── Pre-Race Sync ──────────────────────────────────────────────────────────

  /// Download and cache event + confirmed registrations before race start.
  Future<void> preRaceSync({
    required int eventId,
    required String token,
  }) async {
    _emit(_state.copyWith(status: SyncStatus.syncing));
    try {
      final event = await _api.getEvent(eventId, token: token);
      await _eventsDao.upsert(event);

      final regs = await _api.listRegistrations(eventId, token: token);
      await _regsDao.upsertAll(regs);

      // Populate runner token map for offline NFC/QR lookup
      for (final reg in regs) {
        if (reg.runnerToken != null) {
          await _regsDao.upsertRunnerToken(
            token: reg.runnerToken!,
            registrationId: reg.id,
            eventId: reg.eventId,
            userId: reg.userId,
            displayName: reg.preferredName ?? reg.userEmail,
          );
        }
      }

      final pending = await _lapLogsDao.pendingCount();
      _emit(_state.copyWith(
        status: SyncStatus.idle,
        pendingCount: pending,
        lastSyncAt: DateTime.now(),
      ));
    } catch (e) {
      _emit(_state.copyWith(
        status: SyncStatus.error,
        lastError: e.toString(),
      ));
      rethrow;
    }
  }

  // ── Lap log upload ─────────────────────────────────────────────────────────

  /// Push all unsynced lap logs to the server in batches.
  /// Pass [token] = null in background isolate (sync is best-effort there).
  Future<int> syncPendingLogs({String? token}) async {
    if (token == null) return 0; // no auth → skip
    _emit(_state.copyWith(status: SyncStatus.syncing));

    int total = 0;
    try {
      while (true) {
        final batch =
            await _lapLogsDao.findPendingSync(limit: AppConfig.lapLogBatchSize);
        if (batch.isEmpty) break;

        final records = batch.map((l) => l.toApiRecord()).toList();
        final processed = await _api.ingestLapLogs(records, token: token);
        if (processed.isNotEmpty) {
          await _lapLogsDao.markSynced(processed);
          total += processed.length;
        } else {
          break; // Server processed nothing — avoid infinite loop
        }
      }

      final remaining = await _lapLogsDao.pendingCount();
      _emit(_state.copyWith(
        status: SyncStatus.idle,
        pendingCount: remaining,
        lastSyncAt: DateTime.now(),
      ));
    } catch (e) {
      final remaining = await _lapLogsDao.pendingCount();
      _emit(_state.copyWith(
        status: SyncStatus.error,
        pendingCount: remaining,
        lastError: e.toString(),
      ));
    }
    return total;
  }

  // ── Refresh helpers ────────────────────────────────────────────────────────

  Future<void> refreshEvents({String? token}) async {
    final events = await _api.listEvents(token: token);
    await _eventsDao.upsertAll(events);
  }
}
