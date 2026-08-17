// Tests for the offline fallback paths in event_providers.dart.
//
// Two provider paths are covered:
//   1. eventsProvider (EventsNotifier.build()) — network-first list of all
//      events, with a local DB fallback when the API is unreachable.
//   2. eventDetailProvider — network-first single event detail, with a local
//      DB fallback when the API is unreachable.
//
// All database I/O is avoided: fake DAO implementations are injected via
// Riverpod provider overrides, following the same pattern established in
// runner_history_offline_test.dart.

import 'dart:io' show SocketException;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:beer_mile/api/api_client.dart';
import 'package:beer_mile/api/models/api_event.dart';
import 'package:beer_mile/database/daos/events_dao.dart';
import 'package:beer_mile/providers/auth_providers.dart';
import 'package:beer_mile/providers/event_providers.dart';

// ── Fake API client ───────────────────────────────────────────────────────────

/// Simulates an unreachable API by throwing [SocketException] on every call.
class _ThrowingApiClient extends ApiClient {
  _ThrowingApiClient() : super(baseUrl: 'http://unreachable.invalid');

  @override
  Future<List<ApiEvent>> listEvents({String? token}) async =>
      throw const SocketException('Network unreachable — simulated offline');

  @override
  Future<ApiEvent> getEvent(int id, {String? token}) async =>
      throw const SocketException('Network unreachable — simulated offline');
}

// ── Fake DAO implementations ──────────────────────────────────────────────────

/// [EventsDao] backed by a pre-seeded in-memory list.
class _FakeEventsDao implements EventsDao {
  _FakeEventsDao(this._events);
  final List<ApiEvent> _events;

  @override
  Future<List<ApiEvent>> findAll() async => List.unmodifiable(_events);

  @override
  Future<ApiEvent?> findById(int id) async =>
      _events.where((e) => e.id == id).firstOrNull;

  @override
  Future<void> upsertAll(List<ApiEvent> events) async {}

  @override
  Future<void> upsert(ApiEvent event) async {}

  @override
  Future<void> deleteById(int id) async {}
}

// ── Fixtures ──────────────────────────────────────────────────────────────────

final _eventA = ApiEvent(
  id: 1,
  tenantId: 10,
  title: 'Autumn Beer Mile',
  eventCode: 'ABM2025',
  eventDate: '2025-09-15',
  status: 'upcoming',
  createdAt: DateTime(2025, 9, 1),
  locationName: 'City Park',
);

final _eventB = ApiEvent(
  id: 2,
  tenantId: 10,
  title: 'Winter Beer Mile',
  eventCode: 'WBM2025',
  eventDate: '2025-12-07',
  status: 'upcoming',
  createdAt: DateTime(2025, 11, 1),
);

// ── Test helpers ──────────────────────────────────────────────────────────────

/// Builds a [ProviderContainer] with the API client and DAO overridden.
///
/// [throwOnNetwork] — when true, injects [_ThrowingApiClient] so both
/// [listEvents] and [getEvent] raise a [SocketException].
ProviderContainer _makeContainer({
  String? token,
  bool throwOnNetwork = false,
  List<ApiEvent> events = const [],
}) {
  return ProviderContainer(
    overrides: [
      tokenProvider.overrideWith((ref) async => token),
      if (throwOnNetwork)
        apiClientProvider.overrideWithValue(_ThrowingApiClient()),
      eventsDaoProvider.overrideWithValue(_FakeEventsDao(events)),
    ],
  );
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  // ── eventsProvider (EventsNotifier) ─────────────────────────────────────────

  group('eventsProvider — offline fallback', () {
    test(
        'returns locally-cached events when the API throws a SocketException '
        '(simulated signal drop)', () async {
      final container = _makeContainer(
        token: 'valid.bearer.token',
        throwOnNetwork: true,
        events: [_eventA, _eventB],
      );
      addTearDown(container.dispose);

      final events = await container.read(eventsProvider.future);

      expect(events, hasLength(2),
          reason: 'Both cached events must appear when the API is unreachable');
      expect(events.map((e) => e.id), containsAll([_eventA.id, _eventB.id]));
    });

    test(
        'returns locally-cached events when no token is present '
        '(device never synced auth state)', () async {
      final container = _makeContainer(
        token: null,
        throwOnNetwork: true,
        events: [_eventA],
      );
      addTearDown(container.dispose);

      final events = await container.read(eventsProvider.future);

      expect(events, hasLength(1));
      expect(events.first.id, equals(_eventA.id));
      expect(events.first.title, equals(_eventA.title));
    });

    test('returns empty list when the local cache is also empty', () async {
      final container = _makeContainer(
        token: 'valid.bearer.token',
        throwOnNetwork: true,
        events: [], // nothing cached
      );
      addTearDown(container.dispose);

      final events = await container.read(eventsProvider.future);

      expect(events, isEmpty,
          reason: 'No cached events → provider must return an empty list, '
              'not throw');
    });

    test('preserves event fields from the local cache', () async {
      final container = _makeContainer(
        token: 'valid.bearer.token',
        throwOnNetwork: true,
        events: [_eventA],
      );
      addTearDown(container.dispose);

      final events = await container.read(eventsProvider.future);

      final event = events.first;
      expect(event.id, equals(_eventA.id));
      expect(event.title, equals(_eventA.title));
      expect(event.eventCode, equals(_eventA.eventCode));
      expect(event.eventDate, equals(_eventA.eventDate));
      expect(event.status, equals(_eventA.status));
      expect(event.locationName, equals(_eventA.locationName));
    });
  });

  // ── eventDetailProvider ──────────────────────────────────────────────────────

  group('eventDetailProvider — offline fallback', () {
    test(
        'returns the cached event when the API throws a SocketException '
        '(simulated signal drop on event detail screen)', () async {
      final container = _makeContainer(
        token: 'valid.bearer.token',
        throwOnNetwork: true,
        events: [_eventA, _eventB],
      );
      addTearDown(container.dispose);

      final event = await container.read(eventDetailProvider(1).future);

      expect(event, isNotNull,
          reason: 'Cached event must be returned when the API is unreachable');
      expect(event!.id, equals(_eventA.id));
      expect(event.title, equals(_eventA.title));
    });

    test(
        'returns null when the API throws and the event is not in local cache '
        '(event was never seen on this device)', () async {
      final container = _makeContainer(
        token: 'valid.bearer.token',
        throwOnNetwork: true,
        events: [_eventB], // eventA (id=1) is NOT cached
      );
      addTearDown(container.dispose);

      final event = await container.read(eventDetailProvider(1).future);

      expect(event, isNull,
          reason: 'If the event was never synced to the device the provider '
              'must return null rather than throw');
    });

    test(
        'returns the correct event by id when multiple events are cached '
        '(no cross-event data bleed)', () async {
      final container = _makeContainer(
        token: 'valid.bearer.token',
        throwOnNetwork: true,
        events: [_eventA, _eventB],
      );
      addTearDown(container.dispose);

      final eventOne = await container.read(eventDetailProvider(1).future);
      final eventTwo = await container.read(eventDetailProvider(2).future);

      expect(eventOne?.id, equals(1));
      expect(eventOne?.title, equals(_eventA.title));
      expect(eventTwo?.id, equals(2));
      expect(eventTwo?.title, equals(_eventB.title));
    });

    test(
        'returns locally-cached event when no token is present '
        '(device never authenticated online)', () async {
      final container = _makeContainer(
        token: null,
        throwOnNetwork: true,
        events: [_eventA],
      );
      addTearDown(container.dispose);

      final event = await container.read(eventDetailProvider(_eventA.id).future);

      expect(event, isNotNull);
      expect(event!.id, equals(_eventA.id));
    });
  });
}
