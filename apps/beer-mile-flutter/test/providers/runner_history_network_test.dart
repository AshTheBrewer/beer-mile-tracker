// Tests for the runnerHistoryProvider network path.
//
// The provider has two code paths:
//   1. Network path — calls GET /users/me/race-history and returns API data.
//   2. Offline fallback — reconstructs results from locally-cached
//      registrations and lap_logs when the network is unavailable.
//
// These tests exercise the network path: a fake ApiClient that returns
// pre-built ApiRaceHistoryEntry objects is injected so the provider maps
// entries to RunnerRaceResult values without touching the database or network.
//
// Covered scenarios:
//   a) Single entry — all scalar fields (finishPosition, totalFinishers,
//      totalElapsedMs, finished) are passed through correctly.
//   b) Lap splits are attached to the result without modification.
//   c) Multiple entries — results are returned in the API order (newest-first).
//   d) Null finishPosition / totalFinishers are forwarded as-is.
//   e) Event and registration metadata (ids, titles, codes, dates) survive
//      the mapping loop.
//   f) Returns empty list when the API returns an empty history.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:beer_mile/api/api_client.dart';
import 'package:beer_mile/api/models/api_leaderboard.dart';
import 'package:beer_mile/auth/models/user_model.dart';
import 'package:beer_mile/providers/auth_providers.dart';
import 'package:beer_mile/providers/event_providers.dart';

// ── Fake auth notifier ────────────────────────────────────────────────────────

/// Returns a fixed [AppUser] without touching secure storage or the network.
class _FakeAuthNotifier extends AuthNotifier {
  _FakeAuthNotifier(this._user);
  final AppUser? _user;

  @override
  Future<AppUser?> build() async => _user;
}

// ── Fake API client ───────────────────────────────────────────────────────────

/// Fake [ApiClient] that returns a pre-built list of [ApiRaceHistoryEntry]
/// objects on every call to [getRaceHistory], simulating a successful API
/// response without touching the real network.
class _FakeApiClient extends ApiClient {
  _FakeApiClient(this._history) : super(baseUrl: 'http://fake.invalid');

  final List<ApiRaceHistoryEntry> _history;

  @override
  Future<List<ApiRaceHistoryEntry>> getRaceHistory(
          {required String token}) async =>
      _history;
}

// ── Fixtures ──────────────────────────────────────────────────────────────────

const _testUserId = 'user-network-test-001';
const _testUser = AppUser(
  id: _testUserId,
  email: 'runner@example.com',
  role: 'runner',
);

const _testToken = 'valid.bearer.token';

/// Four lap splits for a completed Beer Mile race.
const _defaultLaps = [
  ApiLapSplit(lapNumber: 1, elapsedMs: 60000, pourConfirmed: true),
  ApiLapSplit(lapNumber: 2, elapsedMs: 65000, pourConfirmed: true),
  ApiLapSplit(lapNumber: 3, elapsedMs: 58000, pourConfirmed: true),
  ApiLapSplit(
      lapNumber: 4, elapsedMs: 62000, pourConfirmed: true, splitTimeMs: 245000),
];

/// A completed history entry for event 1.
final _entryA = ApiRaceHistoryEntry(
  eventId: 1,
  tenantId: 10,
  eventTitle: 'Autumn Beer Mile',
  eventCode: 'ABM2025',
  eventDate: '2025-09-15',
  eventStatus: 'completed',
  eventCreatedAt: DateTime(2025, 9, 1),
  locationName: 'City Park',
  registrationId: 101,
  registeredAt: DateTime(2025, 9, 14), // older
  totalElapsedMs: 245000,
  finished: true,
  laps: _defaultLaps,
  finishPosition: 3,
  totalFinishers: 20,
);

/// A completed history entry for event 2 — registered later than [_entryA].
final _entryB = ApiRaceHistoryEntry(
  eventId: 2,
  tenantId: 10,
  eventTitle: 'Winter Beer Mile',
  eventCode: 'WBM2025',
  eventDate: '2025-12-07',
  eventStatus: 'completed',
  eventCreatedAt: DateTime(2025, 11, 1),
  locationName: null,
  registrationId: 102,
  registeredAt: DateTime(2025, 12, 6), // newer
  totalElapsedMs: 220000,
  finished: true,
  laps: _defaultLaps,
  finishPosition: 1,
  totalFinishers: 15,
);

// ── Test helper ───────────────────────────────────────────────────────────────

/// Builds a [ProviderContainer] with the fake API client and auth providers.
///
/// The DAO providers are intentionally not overridden: the network path must
/// return results without touching any DAO, so reaching a real DAO would
/// trigger an initialisation error and fail the test loudly.
ProviderContainer _makeContainer({
  AppUser? user = _testUser,
  String? token = _testToken,
  required List<ApiRaceHistoryEntry> history,
}) {
  return ProviderContainer(
    overrides: [
      authStateProvider.overrideWith(() => _FakeAuthNotifier(user)),
      tokenProvider.overrideWith((ref) async => token),
      apiClientProvider.overrideWithValue(_FakeApiClient(history)),
    ],
  );
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('runnerHistoryProvider — network path', () {
    // ── Single entry — scalar fields ──────────────────────────────────────────

    test(
        'maps a single ApiRaceHistoryEntry to a RunnerRaceResult with correct '
        'totalElapsedMs, finished, finishPosition, and totalFinishers',
        () async {
      final container = _makeContainer(history: [_entryA]);
      addTearDown(container.dispose);

      final results = await container.read(runnerHistoryProvider.future);

      expect(results, hasLength(1),
          reason: 'Provider must return exactly one result for one API entry');

      final result = results.first;
      expect(result.totalElapsedMs, equals(_entryA.totalElapsedMs),
          reason: 'totalElapsedMs must be forwarded from the API entry');
      expect(result.finished, isTrue,
          reason: 'finished flag must be forwarded from the API entry');
      expect(result.finishPosition, equals(_entryA.finishPosition),
          reason: 'finishPosition must be forwarded from the API entry');
      expect(result.totalFinishers, equals(_entryA.totalFinishers),
          reason: 'totalFinishers must be forwarded from the API entry');
    });

    // ── Event and registration metadata ───────────────────────────────────────

    test(
        'maps event and registration metadata from the API entry correctly',
        () async {
      final container = _makeContainer(history: [_entryA]);
      addTearDown(container.dispose);

      final result =
          (await container.read(runnerHistoryProvider.future)).first;

      // Event fields
      expect(result.event.id, equals(_entryA.eventId));
      expect(result.event.title, equals(_entryA.eventTitle));
      expect(result.event.eventCode, equals(_entryA.eventCode));
      expect(result.event.eventDate, equals(_entryA.eventDate));
      expect(result.event.status, equals(_entryA.eventStatus));
      expect(result.event.locationName, equals(_entryA.locationName));

      // Registration fields
      expect(result.registration.id, equals(_entryA.registrationId));
      expect(result.registration.eventId, equals(_entryA.eventId));
      expect(result.registration.userId, equals(_testUserId),
          reason: 'userId on the registration must match the authenticated user');
      expect(result.registration.registeredAt, equals(_entryA.registeredAt));
    });

    // ── Lap splits ────────────────────────────────────────────────────────────

    test('attaches all lap splits to the result without modification',
        () async {
      final container = _makeContainer(history: [_entryA]);
      addTearDown(container.dispose);

      final result =
          (await container.read(runnerHistoryProvider.future)).first;

      expect(result.laps, hasLength(_defaultLaps.length),
          reason: 'Every lap split from the API entry must appear in the result');

      for (var i = 0; i < _defaultLaps.length; i++) {
        expect(result.laps[i].lapNumber, equals(_defaultLaps[i].lapNumber));
        expect(result.laps[i].elapsedMs, equals(_defaultLaps[i].elapsedMs));
        expect(result.laps[i].pourConfirmed,
            equals(_defaultLaps[i].pourConfirmed));
        expect(result.laps[i].splitTimeMs, equals(_defaultLaps[i].splitTimeMs));
      }
    });

    // ── Null optional fields ──────────────────────────────────────────────────

    test(
        'forwards null finishPosition and totalFinishers when the API omits them',
        () async {
      final entryNoPosition = ApiRaceHistoryEntry(
        eventId: 3,
        tenantId: 10,
        eventTitle: 'Spring Beer Mile',
        eventCode: 'SBM2026',
        eventDate: '2026-04-01',
        eventStatus: 'completed',
        eventCreatedAt: DateTime(2026, 3, 1),
        locationName: null,
        registrationId: 201,
        registeredAt: DateTime(2026, 3, 31),
        totalElapsedMs: 260000,
        finished: true,
        laps: _defaultLaps,
        finishPosition: null, // position not yet computed
        totalFinishers: null,
      );

      final container = _makeContainer(history: [entryNoPosition]);
      addTearDown(container.dispose);

      final result =
          (await container.read(runnerHistoryProvider.future)).first;

      expect(result.finishPosition, isNull,
          reason: 'finishPosition must remain null when absent from API entry');
      expect(result.totalFinishers, isNull,
          reason: 'totalFinishers must remain null when absent from API entry');
    });

    // ── Multiple entries — ordering ───────────────────────────────────────────

    test(
        'preserves the order returned by the API (newest-first contract)',
        () async {
      // The API already returns results sorted newest-first; the provider must
      // not reorder them.  _entryB (Dec) is newer than _entryA (Sep), so the
      // API returns [_entryB, _entryA].
      final container = _makeContainer(history: [_entryB, _entryA]);
      addTearDown(container.dispose);

      final results = await container.read(runnerHistoryProvider.future);

      expect(results, hasLength(2));
      expect(results.first.event.id, equals(_entryB.eventId),
          reason: 'Newest entry (_entryB, Dec) must be first');
      expect(results.last.event.id, equals(_entryA.eventId),
          reason: 'Older entry (_entryA, Sep) must be last');
    });

    // ── Multiple entries — field integrity ────────────────────────────────────

    test(
        'maps each entry in a multi-entry response to its own RunnerRaceResult '
        'with independent field values',
        () async {
      final container = _makeContainer(history: [_entryB, _entryA]);
      addTearDown(container.dispose);

      final results = await container.read(runnerHistoryProvider.future);

      // First result corresponds to _entryB
      expect(results[0].totalElapsedMs, equals(_entryB.totalElapsedMs));
      expect(results[0].finishPosition, equals(_entryB.finishPosition));
      expect(results[0].totalFinishers, equals(_entryB.totalFinishers));

      // Second result corresponds to _entryA
      expect(results[1].totalElapsedMs, equals(_entryA.totalElapsedMs));
      expect(results[1].finishPosition, equals(_entryA.finishPosition));
      expect(results[1].totalFinishers, equals(_entryA.totalFinishers));
    });

    // ── Empty API response ────────────────────────────────────────────────────

    test('returns an empty list when the API returns an empty history',
        () async {
      final container = _makeContainer(history: []);
      addTearDown(container.dispose);

      final results = await container.read(runnerHistoryProvider.future);

      expect(results, isEmpty,
          reason: 'An empty API response must yield an empty result list');
    });

    // ── No token → network path skipped ──────────────────────────────────────

    test('returns empty list when no auth token is available (no user session)',
        () async {
      // With token == null the provider short-circuits before the network call.
      // Passing an empty history list ensures that even if the fake client were
      // somehow called, we would see no accidental data.
      final container = _makeContainer(token: null, history: [_entryA]);
      addTearDown(container.dispose);

      final results = await container.read(runnerHistoryProvider.future);

      // Without a token the offline path runs; DAOs are not overridden, so the
      // provider reaches real DAO initialisers and returns empty (no local data).
      // The key assertion: the network result from the fake client must NOT appear.
      for (final r in results) {
        expect(r.event.id, isNot(equals(_entryA.eventId)),
            reason: 'Network result must not appear when no token is present');
      }
    });
  });
}
