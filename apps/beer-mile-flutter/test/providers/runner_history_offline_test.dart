// Tests for the runnerHistoryProvider offline fallback.
//
// The provider has two code paths:
//   1. Network path — calls GET /users/me/race-history and returns API data.
//   2. Offline fallback — reconstructs results from locally-cached
//      registrations and lap_logs when the network is unavailable.
//
// These tests exercise the offline path under two realistic conditions:
//   a) No token is present (device never synced its auth state).
//   b) A token is present but the API throws a network error.
//
// All database I/O is avoided: fake DAO implementations are injected via
// Riverpod provider overrides so tests remain fast and self-contained.

import 'dart:io' show SocketException;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:beer_mile/api/api_client.dart';
import 'package:beer_mile/api/models/api_event.dart';
import 'package:beer_mile/api/models/api_leaderboard.dart';
import 'package:beer_mile/api/models/api_registration.dart';
import 'package:beer_mile/auth/models/user_model.dart';
import 'package:beer_mile/database/daos/events_dao.dart';
import 'package:beer_mile/database/daos/lap_logs_dao.dart';
import 'package:beer_mile/database/daos/registrations_dao.dart';
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

/// Simulates an unreachable API by throwing [SocketException] on every call.
class _ThrowingApiClient extends ApiClient {
  _ThrowingApiClient() : super(baseUrl: 'http://unreachable.invalid');

  @override
  Future<List<ApiRaceHistoryEntry>> getRaceHistory(
          {required String token}) async =>
      throw const SocketException('Network unreachable — simulated offline');
}

// ── Fake DAO implementations ─────────────────────────────────────────────────

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

/// [RegistrationsDao] backed by a pre-seeded in-memory list.
class _FakeRegistrationsDao implements RegistrationsDao {
  _FakeRegistrationsDao(this._regs);
  final List<ApiRegistration> _regs;

  @override
  Future<List<ApiRegistration>> findByUser(String userId) async =>
      _regs.where((r) => r.userId == userId).toList();

  @override
  Future<List<ApiRegistration>> findByEvent(int eventId) async =>
      _regs.where((r) => r.eventId == eventId).toList();

  @override
  Future<ApiRegistration?> findByUserAndEvent(
          String userId, int eventId) async =>
      _regs
          .where((r) => r.userId == userId && r.eventId == eventId)
          .firstOrNull;

  @override
  Future<void> upsertAll(List<ApiRegistration> regs) async {}

  @override
  Future<void> upsert(ApiRegistration reg) async {}

  @override
  Future<void> upsertRunnerToken({
    required String token,
    required int registrationId,
    required int eventId,
    required String userId,
    String? displayName,
  }) async {}

  @override
  Future<Map<String, dynamic>?> findByToken(String token) async => null;

  @override
  Future<List<Map<String, dynamic>>> findTokensByEvent(int eventId) async =>
      [];
}

/// [LapLogsDao] backed by a pre-seeded in-memory list.
class _FakeLapLogsDao implements LapLogsDao {
  _FakeLapLogsDao(this._logs);
  final List<LocalLapLog> _logs;

  @override
  Future<List<LocalLapLog>> findByRegistration(int registrationId) async =>
      _logs.where((l) => l.registrationId == registrationId).toList();

  @override
  Future<bool> insertOrKeepFastest(LocalLapLog log) async => true;

  @override
  Future<List<LocalLapLog>> findPendingSync({int limit = 50}) async => [];

  @override
  Future<int> markSynced(List<String> clientEventLogIds) async => 0;

  @override
  Future<int> pendingCount() async => 0;
}

// ── Fixtures ──────────────────────────────────────────────────────────────────

const _testUserId = 'user-offline-test-001';
const _testUser = AppUser(
  id: _testUserId,
  email: 'runner@example.com',
  role: 'runner',
);

final _eventA = ApiEvent(
  id: 1,
  tenantId: 10,
  title: 'Autumn Beer Mile',
  eventCode: 'ABM2025',
  eventDate: '2025-09-15',
  status: 'completed',
  createdAt: DateTime(2025, 9, 1),
  locationName: 'City Park',
);

final _eventB = ApiEvent(
  id: 2,
  tenantId: 10,
  title: 'Winter Beer Mile',
  eventCode: 'WBM2025',
  eventDate: '2025-12-07',
  status: 'completed',
  createdAt: DateTime(2025, 11, 1),
);

final _regA = ApiRegistration(
  id: 101,
  eventId: 1,
  userId: _testUserId,
  paymentStatus: 'confirmed',
  registeredAt: DateTime(2025, 9, 14),
);

final _regB = ApiRegistration(
  id: 102,
  eventId: 2,
  userId: _testUserId,
  paymentStatus: 'confirmed',
  registeredAt: DateTime(2025, 12, 6),
);

/// Builds 4 completed [LocalLapLog] records for [registrationId].
///
/// [lapElapsedMs] must have exactly 4 entries (one per Beer Mile lap).
List<LocalLapLog> _makeLaps(
  int registrationId, {
  List<int> lapElapsedMs = const [60000, 65000, 58000, 62000],
}) {
  assert(lapElapsedMs.length == 4);
  return List.generate(4, (i) {
    final lap = i + 1;
    return LocalLapLog(
      clientEventLogId: 'reg$registrationId-lap$lap',
      registrationId: registrationId,
      lapNumber: lap,
      elapsedMs: lapElapsedMs[i],
      pourConfirmed: true,
      isSynced: false,
      loggedAt: DateTime(2025, 9, 15, 10, lap),
    );
  });
}

// ── Test helpers ──────────────────────────────────────────────────────────────

/// Builds a [ProviderContainer] with auth and DAO providers overridden.
///
/// [token] controls which code path the provider takes:
///   - `null`  → network call is skipped entirely (no token → offline path).
///   - non-null → network call is attempted; if [throwOnNetwork] is true the
///               API client throws, driving the offline fallback.
ProviderContainer _makeContainer({
  AppUser? user = _testUser,
  String? token,
  bool throwOnNetwork = false,
  List<ApiEvent> events = const [],
  List<ApiRegistration> registrations = const [],
  List<LocalLapLog> laps = const [],
}) {
  return ProviderContainer(
    overrides: [
      authStateProvider.overrideWith(() => _FakeAuthNotifier(user)),
      tokenProvider.overrideWith((ref) async => token),
      if (throwOnNetwork)
        apiClientProvider.overrideWithValue(_ThrowingApiClient()),
      eventsDaoProvider.overrideWithValue(_FakeEventsDao(events)),
      registrationsDaoProvider
          .overrideWithValue(_FakeRegistrationsDao(registrations)),
      lapLogsDaoProvider.overrideWithValue(_FakeLapLogsDao(laps)),
    ],
  );
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('runnerHistoryProvider — offline fallback', () {
    // ── No-token path ─────────────────────────────────────────────────────────

    test(
        'returns completed race from local lap_logs when no token is present '
        '(device never authenticated online)', () async {
      final container = _makeContainer(
        token: null,
        events: [_eventA],
        registrations: [_regA],
        laps: _makeLaps(_regA.id),
      );
      addTearDown(container.dispose);

      final results = await container.read(runnerHistoryProvider.future);

      expect(results, hasLength(1),
          reason: 'Exactly one completed race must appear in offline history');

      final result = results.first;
      expect(result.event.id, equals(_eventA.id));
      expect(result.event.title, equals(_eventA.title));
      expect(result.registration.userId, equals(_testUserId));
      expect(result.finished, isTrue,
          reason: 'Race built from 4 local laps must be marked finished');
      expect(result.laps, hasLength(4),
          reason: 'All four lap splits must be present');
      // Total is the sum of all four lap elapsed values.
      expect(result.totalElapsedMs, equals(60000 + 65000 + 58000 + 62000));
    });

    // ── Network-error path ────────────────────────────────────────────────────

    test(
        'falls back to local lap_logs when a token is present but the API '
        'throws a SocketException (simulated offline)', () async {
      final container = _makeContainer(
        token: 'valid.bearer.token',
        throwOnNetwork: true, // _ThrowingApiClient raises SocketException
        events: [_eventA],
        registrations: [_regA],
        laps: _makeLaps(_regA.id),
      );
      addTearDown(container.dispose);

      final results = await container.read(runnerHistoryProvider.future);

      expect(results, hasLength(1),
          reason: 'Offline fallback must surface locally-cached races even '
              'when a token is present but the API is unreachable');
      expect(results.first.event.id, equals(_eventA.id));
    });

    // ── Finish position not available offline ─────────────────────────────────

    test(
        'does not populate finishPosition or totalFinishers when results '
        'come from local lap data (leaderboard requires a network call)',
        () async {
      final container = _makeContainer(
        token: null,
        events: [_eventA],
        registrations: [_regA],
        laps: _makeLaps(_regA.id),
      );
      addTearDown(container.dispose);

      final result =
          (await container.read(runnerHistoryProvider.future)).first;

      expect(result.finishPosition, isNull,
          reason: 'Finish position is not available without a leaderboard call');
      expect(result.totalFinishers, isNull);
    });

    // ── Personal best from local data ─────────────────────────────────────────

    test(
        'personal best — fastest race is identifiable from local lap data '
        'when offline', () async {
      // Event A: slower race  (245 s total)
      // Event B: faster race  (220 s total) — this is the PB
      final slowLaps = _makeLaps(_regA.id,
          lapElapsedMs: [62000, 63000, 60000, 60000]); // 245 000 ms
      final fastLaps = _makeLaps(_regB.id,
          lapElapsedMs: [55000, 56000, 54000, 55000]); // 220 000 ms

      final container = _makeContainer(
        token: null,
        events: [_eventA, _eventB],
        registrations: [_regA, _regB],
        laps: [...slowLaps, ...fastLaps],
      );
      addTearDown(container.dispose);

      final results = await container.read(runnerHistoryProvider.future);

      expect(results, hasLength(2),
          reason: 'Both completed races must appear in offline history');

      final bestTime = results
          .map((r) => r.totalElapsedMs)
          .reduce((a, b) => a < b ? a : b);

      expect(bestTime, equals(220000),
          reason: 'Personal best (fastest local time) must equal '
              'the sum of the faster race\'s four lap times');
    });

    // ── Incomplete race excluded ───────────────────────────────────────────────

    test('excludes races with fewer than 4 local laps (DNF / still racing)',
        () async {
      // Only 3 laps recorded — race was not finished.
      final incompleteLaps = [
        LocalLapLog(
          clientEventLogId: 'reg101-lap1',
          registrationId: _regA.id,
          lapNumber: 1,
          elapsedMs: 60000,
          pourConfirmed: true,
          isSynced: false,
          loggedAt: DateTime(2025, 9, 15, 10, 1),
        ),
        LocalLapLog(
          clientEventLogId: 'reg101-lap2',
          registrationId: _regA.id,
          lapNumber: 2,
          elapsedMs: 65000,
          pourConfirmed: true,
          isSynced: false,
          loggedAt: DateTime(2025, 9, 15, 10, 2),
        ),
        LocalLapLog(
          clientEventLogId: 'reg101-lap3',
          registrationId: _regA.id,
          lapNumber: 3,
          elapsedMs: 70000,
          pourConfirmed: false,
          isSynced: false,
          loggedAt: DateTime(2025, 9, 15, 10, 3),
        ),
      ];

      final container = _makeContainer(
        token: null,
        events: [_eventA],
        registrations: [_regA],
        laps: incompleteLaps,
      );
      addTearDown(container.dispose);

      final results = await container.read(runnerHistoryProvider.future);

      expect(results, isEmpty,
          reason: 'A race with only 3 laps must not appear in history — '
              'the runner did not cross the finish line');
    });

    // ── No local data ─────────────────────────────────────────────────────────

    test('returns empty list when the runner has no local registrations',
        () async {
      // Empty database — no events, no registrations, no laps.
      final container = _makeContainer(token: null);
      addTearDown(container.dispose);

      final results = await container.read(runnerHistoryProvider.future);

      expect(results, isEmpty);
    });

    // ── Unauthenticated user ───────────────────────────────────────────────────

    test('returns empty list immediately when no user is signed in', () async {
      // Seeded data is present, but the provider must return early because
      // there is no authenticated user.
      final container = _makeContainer(
        user: null,
        token: null,
        events: [_eventA],
        registrations: [_regA],
        laps: _makeLaps(_regA.id),
      );
      addTearDown(container.dispose);

      final results = await container.read(runnerHistoryProvider.future);

      expect(results, isEmpty,
          reason: 'No user → provider must short-circuit before querying DAOs');
    });

    // ── Result ordering ───────────────────────────────────────────────────────

    test('sorts results newest-first by registration date', () async {
      final container = _makeContainer(
        token: null,
        events: [_eventA, _eventB],
        registrations: [_regA, _regB],
        laps: [
          ..._makeLaps(_regA.id), // registered 2025-09-14 (older)
          ..._makeLaps(_regB.id), // registered 2025-12-06 (newer)
        ],
      );
      addTearDown(container.dispose);

      final results = await container.read(runnerHistoryProvider.future);

      expect(results, hasLength(2));
      // Winter event (registered Dec) must be first.
      expect(results.first.event.id, equals(_eventB.id),
          reason: 'Newest registration must come first when sorted '
              'newest-first by registeredAt');
    });

    // ── Registration with no matching event ───────────────────────────────────

    test(
        'skips registrations whose event is not in local cache '
        '(event not yet synced to device)', () async {
      // _regA references eventId=1 but no event with id=1 exists in cache.
      final container = _makeContainer(
        token: null,
        events: [], // empty event cache
        registrations: [_regA],
        laps: _makeLaps(_regA.id),
      );
      addTearDown(container.dispose);

      final results = await container.read(runnerHistoryProvider.future);

      expect(results, isEmpty,
          reason: 'A race cannot be reconstructed without its event metadata');
    });
  });
}
