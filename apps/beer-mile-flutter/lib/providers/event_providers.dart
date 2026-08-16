import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../api/models/api_event.dart';
import '../api/models/api_leaderboard.dart';
import '../api/models/api_registration.dart';
import '../core/config.dart';
import '../database/app_database.dart';
import '../database/daos/events_dao.dart';
import '../database/daos/lap_logs_dao.dart';
import '../database/daos/registrations_dao.dart';
import 'auth_providers.dart';

/// API client provider.  Exposed so tests can override it with a fake client
/// that throws a [SocketException] to exercise the offline fallback path.
final apiClientProvider = Provider<ApiClient>(
    (_) => ApiClient(baseUrl: AppConfig.apiBaseUrl));

/// DAO providers are public so tests can inject fakes via [ProviderContainer]
/// overrides, keeping tests free of any SQLite infrastructure.
final eventsDaoProvider =
    Provider<EventsDao>((ref) => EventsDao(AppDatabase.instance));

final registrationsDaoProvider =
    Provider<RegistrationsDao>((ref) => RegistrationsDao(AppDatabase.instance));

final lapLogsDaoProvider =
    Provider<LapLogsDao>((ref) => LapLogsDao(AppDatabase.instance));

// ── Runner race history ────────────────────────────────────────────────────

/// A single race result for the current runner, combining registration,
/// event metadata, final time, and per-lap splits.
class RunnerRaceResult {
  const RunnerRaceResult({
    required this.registration,
    required this.event,
    required this.totalElapsedMs,
    required this.finished,
    required this.laps,
    this.finishPosition,
    this.totalFinishers,
  });

  final ApiRegistration registration;
  final ApiEvent event;
  final int totalElapsedMs;
  final bool finished;
  final List<ApiLapSplit> laps;

  /// 1-based finishing position among all finishers in the event, or null
  /// when leaderboard data was unavailable (e.g. offline fallback).
  final int? finishPosition;

  /// Total number of finishers in the event, or null when unavailable.
  final int? totalFinishers;

  String get formattedTime {
    final m = totalElapsedMs ~/ 60000;
    final s = (totalElapsedMs % 60000) / 1000;
    return '${m}m ${s.toStringAsFixed(1)}s';
  }
}

/// Fetches the current runner's complete race history.
///
/// Network path: calls `GET /users/me/race-history` — a single endpoint that
/// returns all completed results with finish positions in one round-trip,
/// avoiding the old per-event leaderboard loop.
///
/// Offline fallback: when the network is unavailable the provider reconstructs
/// results from locally-cached registrations and lap_logs so that previously
/// seen history still appears without a connection.
///
/// Returns results sorted newest-first.
final runnerHistoryProvider =
    FutureProvider<List<RunnerRaceResult>>((ref) async {
  final user = await ref.watch(authStateProvider.future);
  if (user == null) return [];

  final token = await ref.watch(tokenProvider.future);
  final api = ref.read(apiClientProvider);

  // ── Network path ────────────────────────────────────────────────────────
  if (token != null) {
    try {
      final history = await api.getRaceHistory(token: token);
      // The API only returns finished races, already sorted newest-first.
      return history.map((entry) {
        // Reconstruct the lightweight model objects the UI expects.
        final event = ApiEvent(
          id: entry.eventId,
          tenantId: entry.tenantId,
          title: entry.eventTitle,
          eventCode: entry.eventCode,
          eventDate: entry.eventDate,
          status: entry.eventStatus,
          createdAt: entry.eventCreatedAt,
          locationName: entry.locationName,
        );
        final registration = ApiRegistration(
          id: entry.registrationId,
          eventId: entry.eventId,
          userId: user.id,
          paymentStatus: 'confirmed',
          registeredAt: entry.registeredAt,
        );
        return RunnerRaceResult(
          registration: registration,
          event: event,
          totalElapsedMs: entry.totalElapsedMs,
          finished: entry.finished,
          laps: entry.laps,
          finishPosition: entry.finishPosition,
          totalFinishers: entry.totalFinishers,
        );
      }).toList();
    } catch (_) {
      // Network unavailable — fall through to offline reconstruction.
    }
  }

  // ── Offline fallback ────────────────────────────────────────────────────
  final eventsDao = ref.read(eventsDaoProvider);
  final regsDao = ref.read(registrationsDaoProvider);
  final lapLogsDao = ref.read(lapLogsDaoProvider);

  final localRegs = await regsDao.findByUser(user.id);
  if (localRegs.isEmpty) return [];

  final allEvents = await eventsDao.findAll();
  final eventMap = {for (final e in allEvents) e.id: e};

  final results = <RunnerRaceResult>[];
  for (final reg in localRegs) {
    final event = eventMap[reg.eventId];
    if (event == null) continue;

    final localLaps = await lapLogsDao.findByRegistration(reg.id);
    if (localLaps.length < 4) continue; // Only show completed races.

    final totalMs = localLaps.map((l) => l.elapsedMs).reduce((a, b) => a + b);
    results.add(RunnerRaceResult(
      registration: reg,
      event: event,
      totalElapsedMs: totalMs,
      finished: true,
      laps: localLaps
          .map((l) => ApiLapSplit(
                lapNumber: l.lapNumber,
                elapsedMs: l.elapsedMs,
                pourConfirmed: l.pourConfirmed,
                splitTimeMs: l.splitTimeMs,
              ))
          .toList(),
      // Finish position unavailable offline.
    ));
  }

  results.sort((a, b) =>
      b.registration.registeredAt.compareTo(a.registration.registeredAt));
  return results;
});

/// List of all events — network-first with local fallback.
final eventsProvider = AsyncNotifierProvider<EventsNotifier, List<ApiEvent>>(
    () => EventsNotifier());

class EventsNotifier extends AsyncNotifier<List<ApiEvent>> {
  @override
  Future<List<ApiEvent>> build() async {
    final token = await ref.watch(tokenProvider.future);
    final api = ref.read(apiClientProvider);
    final dao = ref.read(eventsDaoProvider);
    try {
      final remote = await api.listEvents(token: token);
      await dao.upsertAll(remote);
      return remote;
    } catch (_) {
      return dao.findAll();
    }
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => build());
  }
}

/// Single event detail provider.
final eventDetailProvider =
    FutureProvider.family<ApiEvent?, int>((ref, id) async {
  final token = await ref.watch(tokenProvider.future);
  final api = ref.read(apiClientProvider);
  final dao = ref.read(eventsDaoProvider);
  try {
    final event = await api.getEvent(id, token: token);
    await dao.upsert(event);
    return event;
  } catch (_) {
    return dao.findById(id);
  }
});

/// Leaderboard — always fetches from network (live timing).
final leaderboardProvider =
    FutureProvider.family<List<ApiLeaderboardEntry>, int>((ref, eventId) async {
  final token = await ref.watch(tokenProvider.future);
  final api = ref.read(apiClientProvider);
  return api.getLeaderboard(eventId, token: token);
});
