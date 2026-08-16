import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../database/app_database.dart';
import '../database/daos/lap_logs_dao.dart';
import '../database/daos/registrations_dao.dart';

// Per-event race state (active during Scanner Mode)
final activeEventIdProvider = StateProvider<int?>((ref) => null);

// Race T0 (milliseconds since epoch) — captured when "Start Race" is pressed
final raceStartTimeProvider = StateProvider<int?>((ref) => null);

// Per-runner lap tracking (registration_id → list of elapsed_ms per lap)
final runnerLapsProvider =
    StateProvider<Map<int, List<int>>>((ref) => {});

/// Record a lap scan.  Returns true if the scan was accepted (no faster record).
final lapScanNotifierProvider =
    NotifierProvider<LapScanNotifier, void>(() => LapScanNotifier());

class LapScanNotifier extends Notifier<void> {
  @override
  void build() {}

  Future<bool> recordScan({
    required int registrationId,
    required int lapNumber,
    required int elapsedMs,
    required bool pourConfirmed,
    int? splitTimeMs,
    int? deviceMonotonicTimestamp,
  }) async {
    final dao = LapLogsDao(AppDatabase.instance);
    final log = LocalLapLog(
      clientEventLogId: const Uuid().v4(),
      registrationId: registrationId,
      lapNumber: lapNumber,
      elapsedMs: elapsedMs,
      splitTimeMs: splitTimeMs,
      pourConfirmed: pourConfirmed,
      isSynced: false,
      loggedAt: DateTime.now(),
      deviceMonotonicTimestamp: deviceMonotonicTimestamp,
    );
    final accepted = await dao.insertOrKeepFastest(log);
    if (accepted) {
      // Update in-memory lap map
      ref.read(runnerLapsProvider.notifier).update((laps) {
        final updated = Map<int, List<int>>.from(laps);
        updated[registrationId] = [...(updated[registrationId] ?? []), elapsedMs]
          ..sort();
        return updated;
      });
    }
    return accepted;
  }
}

/// Lookup a runner by NFC/QR token payload.
final runnerTokenLookupProvider =
    FutureProvider.family<Map<String, dynamic>?, String>((ref, token) async {
  final dao = RegistrationsDao(AppDatabase.instance);
  return dao.findByToken(token);
});
