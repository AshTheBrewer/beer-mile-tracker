import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../api/models/api_event.dart';
import '../api/models/api_leaderboard.dart';
import '../core/config.dart';
import '../database/app_database.dart';
import '../database/daos/events_dao.dart';
import 'auth_providers.dart';

final _apiProvider = Provider<ApiClient>(
    (_) => ApiClient(baseUrl: AppConfig.apiBaseUrl));

final _eventsDaoProvider =
    Provider<EventsDao>((ref) => EventsDao(AppDatabase.instance));

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
