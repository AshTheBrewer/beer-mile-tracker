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

final _apiProvider = Provider<ApiClient>(
    (_) => ApiClient(baseUrl: AppConfig.apiBaseUrl));

final _eventsDaoProvider =
    Provider<EventsDao>((ref) => EventsDao(AppDatabase.instance));

final _registrationsDaoProvider =
    Provider<RegistrationsDao>((ref) => RegistrationsDao(AppDatabase.instance));

final _lapLogsDaoProvider =
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
  });

  final ApiRegistration registration;
  final ApiEvent event;
  final int totalElapsedMs;
  final bool finished;
  final List<ApiLapSplit> laps;

  String get formattedTime {
    final m = totalElapsedMs ~/ 60000;
    final s = (totalElapsedMs % 60000) / 1000;
    return '${m}m ${s.toStringAsFixed(1)}s';
  }
}

/// Fetches the current runner's complete race history (network-first, local
/// fallback).  Returns results sorted newest-first.
final runnerHistoryProvider =
    FutureProvider<List<RunnerRaceResult>>((ref) async {
  final user = await ref.watch(authStateProvider.future);
  if (user == null) return [];

  final token = await ref.watch(tokenProvider.future);
  final api = ref.read(_apiProvider);
  final eventsDao = ref.read(_eventsDaoProvider);
  final regsDao = ref.read(_registrationsDaoProvider);
  final lapLogsDao = ref.read(_lapLogsDaoProvider);

  // 1. Get all cached registrations for this user from local DB.
  final localRegs = await regsDao.findByUser(user.id);
  if (localRegs.isEmpty) return [];

  // 2. Build a map of eventId → event (from local cache, refresh if possible).
  List<ApiEvent> allEvents;
  try {
    allEvents = await api.listEvents(token: token);
    await eventsDao.upsertAll(allEvents);
  } catch (_) {
    allEvents = await eventsDao.findAll();
  }
  final eventMap = {for (final e in allEvents) e.id: e};

  // 3. For each registration, try to fetch leaderboard entry from network;
  //    fall back to reconstructing from local lap_logs.
  final results = <RunnerRaceResult>[];

  for (final reg in localRegs) {
    final event = eventMap[reg.eventId];
    if (event == null) continue;

    ApiLeaderboardEntry? entry;
    try {
      final board = await api.getLeaderboard(reg.eventId, token: token);
      entry = board.where((e) => e.userId == user.id).firstOrNull;
    } catch (_) {
      // Network unavailable — reconstruct from local lap_logs below.
    }

    if (entry != null && entry.finished) {
      results.add(RunnerRaceResult(
        registration: reg,
        event: event,
        totalElapsedMs: entry.totalElapsedMs,
        finished: entry.finished,
        laps: entry.laps,
      ));
    } else {
      // Offline fallback: build from cached lap_logs.
      final localLaps = await lapLogsDao.findByRegistration(reg.id);
      if (localLaps.isEmpty) continue;
      final allFour = localLaps.length == 4;
      final totalMs = allFour
          ? localLaps.map((l) => l.elapsedMs).reduce((a, b) => a + b)
          : 0;
      if (!allFour) continue; // Only show completed races.
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
      ));
    }
  }

  // Sort newest event first.
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
    final api = ref.read(_apiProvider);
    final dao = ref.read(_eventsDaoProvider);
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
  final api = ref.read(_apiProvider);
  final dao = ref.read(_eventsDaoProvider);
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
  final api = ref.read(_apiProvider);
  return api.getLeaderboard(eventId, token: token);
});
