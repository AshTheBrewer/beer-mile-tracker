import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:nfc_manager/nfc_manager.dart';

import '../../core/config.dart';
import '../../core/theme.dart';
import '../../database/daos/registrations_dao.dart';
import '../../database/app_database.dart';
import '../../providers/auth_providers.dart';
import '../../providers/race_providers.dart';
import '../../providers/sync_providers.dart';

class ScannerModeScreen extends ConsumerStatefulWidget {
  const ScannerModeScreen({super.key, required this.eventId});
  final int eventId;

  @override
  ConsumerState<ScannerModeScreen> createState() => _ScannerModeScreenState();
}

class _ScannerModeScreenState extends ConsumerState<ScannerModeScreen> {
  // Race state
  int? _raceStartMs;
  bool _raceStarted = false;

  // Per-runner display: registrationId → list of elapsed_ms per lap
  final Map<int, List<int>> _runnerLaps = {};
  final Map<int, String> _runnerNames = {};

  // Scan feedback
  bool _scanFeedback = false;
  bool _scanSuccess = false;
  String _feedbackMessage = '';

  // NFC
  bool _nfcAvailable = false;
  bool _nfcListening = false;

  // QR scanner controller
  MobileScannerController? _qrController;
  bool _scanMode = false; // false = NFC, true = QR

  // DAO for runner-token lookup
  late RegistrationsDao _regsDao;

  Timer? _clockTimer;
  int _elapsedMs = 0;

  @override
  void initState() {
    super.initState();
    _regsDao = RegistrationsDao(AppDatabase.instance);
    _checkNfc();
  }

  Future<void> _checkNfc() async {
    _nfcAvailable = await NfcManager.instance.isAvailable();
    if (mounted) setState(() {});
  }

  // ── Pre-race sync ──────────────────────────────────────────────────────────

  /// Shows a blocking dialog that runs [SyncEngine.preRaceSync].
  /// Returns true if the race can proceed (sync OK or user accepts offline).
  Future<bool> _runPreRaceSync() async {
    final token = await ref.read(tokenProvider.future);
    if (token == null) return false;

    bool? result;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _PreRaceSyncDialog(
        eventId: widget.eventId,
        token: token,
        onResult: (ok) {
          result = ok;
          Navigator.of(ctx).pop();
        },
      ),
    );
    return result ?? false;
  }

  Future<void> _initiateStart() async {
    final proceed = await _runPreRaceSync();
    if (!proceed || !mounted) return;
    _startRace();
  }

  void _startRace() {
    setState(() {
      _raceStartMs = DateTime.now().millisecondsSinceEpoch;
      _raceStarted = true;
      _elapsedMs = 0;
    });
    _clockTimer?.cancel();
    _clockTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (_raceStartMs != null) {
        setState(() {
          _elapsedMs = DateTime.now().millisecondsSinceEpoch - _raceStartMs!;
        });
      }
    });
    _startNfcListening();
  }

  void _startNfcListening() {
    if (!_nfcAvailable || _nfcListening) return;
    _nfcListening = true;
    NfcManager.instance.startSession(onDiscovered: (tag) async {
      final ndef = Ndef.from(tag);
      if (ndef == null) return;
      try {
        final message = await ndef.read();
        if (message != null && message.records.isNotEmpty) {
          final raw = message.records.first.payload;
          // NFC text records: first 3 bytes = status + language code
          final payload = String.fromCharCodes(
              raw.length > 3 ? raw.skip(3) : raw);
          await _handleToken(payload);
        }
      } catch (_) {}
    });
  }

  Future<void> _handleToken(String token) async {
    if (!_raceStarted) return;
    final regInfo = await _regsDao.findByToken(token);
    if (regInfo == null) {
      _showFeedback(false, 'Unknown runner — sync tags before race');
      return;
    }

    // Reject tokens that belong to a different event (stale cache from a
    // previous race).  Pre-race sync populates the cache for widget.eventId
    // only, so a mismatch here means an old or wrong tag was scanned.
    final tokenEventId = regInfo['event_id'] as int;
    if (tokenEventId != widget.eventId) {
      _showFeedback(false, 'Tag belongs to a different event — re-sync');
      return;
    }

    final registrationId = regInfo['registration_id'] as int;
    final name =
        regInfo['display_name'] as String? ?? 'Runner #$registrationId';
    final currentLaps = _runnerLaps[registrationId] ?? [];
    final nextLap = currentLaps.length + 1;

    if (nextLap > AppConfig.lapsPerMile) {
      _showFeedback(false, '$name already finished!');
      return;
    }

    final elapsed = DateTime.now().millisecondsSinceEpoch - _raceStartMs!;
    // Split = time since last lap (or since race start for lap 1)
    final split = currentLaps.isEmpty ? elapsed : elapsed - currentLaps.last;

    final accepted = await ref.read(lapScanNotifierProvider.notifier).recordScan(
      registrationId: registrationId,
      lapNumber: nextLap,
      elapsedMs: elapsed,
      splitTimeMs: split,
      pourConfirmed: true,
      deviceMonotonicTimestamp: DateTime.now().millisecondsSinceEpoch,
    );

    if (!mounted) return;

    if (accepted) {
      setState(() {
        _runnerNames[registrationId] = name;
        _runnerLaps[registrationId] = [...currentLaps, elapsed];
      });

      final finished = nextLap == AppConfig.lapsPerMile;
      _showFeedback(
        true,
        finished
            ? '$name FINISHED!  ${_formatMs(elapsed)}'
            : 'Lap $nextLap — $name  ${_formatMs(elapsed)}',
      );

      // Trigger upload after each scan
      final authToken = await ref.read(tokenProvider.future);
      ref.read(syncEngineProvider).syncPendingLogs(token: authToken);
    } else {
      _showFeedback(false, 'Faster record exists for $name lap $nextLap');
    }
  }

  void _showFeedback(bool success, String message) {
    if (success) {
      HapticFeedback.lightImpact();
    } else {
      HapticFeedback.heavyImpact();
    }
    setState(() {
      _scanFeedback = true;
      _scanSuccess = success;
      _feedbackMessage = message;
    });
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _scanFeedback = false);
    });
  }

  String _formatMs(int ms) {
    final m = ms ~/ 60000;
    final s = (ms % 60000) / 1000;
    return '${m}m ${s.toStringAsFixed(1)}s';
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    if (_nfcListening) NfcManager.instance.stopSession();
    _qrController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: AppTheme.scanner(),
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              _buildFeedbackBar(),
              Expanded(child: _buildBody()),
              if (_raceStarted) _buildFooter(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      color: const Color(0xFF111111),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          Expanded(
            child: Column(
              children: [
                Text(
                  _raceStarted ? _formatMs(_elapsedMs) : 'READY',
                  style: const TextStyle(
                    fontSize: 48,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                Text(
                  _raceStarted ? 'RACE CLOCK' : 'Pre-race sync required',
                  style: const TextStyle(fontSize: 13, color: Colors.grey),
                ),
              ],
            ),
          ),
          Consumer(builder: (_, ref, __) {
            final count = ref.watch(pendingCountProvider);
            return Stack(
              children: [
                const Icon(Icons.cloud_upload, color: Colors.grey, size: 28),
                if (count > 0)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: const BoxDecoration(
                        color: Colors.orange, shape: BoxShape.circle),
                      child: Text('$count',
                          style: const TextStyle(
                              fontSize: 9, color: Colors.white),
                          textAlign: TextAlign.center),
                    ),
                  ),
              ],
            );
          }),
        ],
      ),
    );
  }

  Widget _buildFeedbackBar() {
    if (!_scanFeedback) return const SizedBox.shrink();
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      color: _scanSuccess
          ? const Color(0xFF4ADE80)
          : const Color(0xFFF87171),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: [
          Icon(_scanSuccess ? Icons.check_circle : Icons.error,
              color: Colors.black, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _feedbackMessage,
              style: const TextStyle(
                color: Colors.black,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (!_raceStarted) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Pre-race sync downloads runner tokens\nso offline scanning works.',
              style: TextStyle(color: Colors.grey, fontSize: 15),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.black,
                minimumSize: const Size(220, 72),
                textStyle: const TextStyle(
                    fontSize: 22, fontWeight: FontWeight.bold),
              ),
              onPressed: _initiateStart,
              icon: const Icon(Icons.play_arrow, size: 32),
              label: const Text('SYNC & START'),
            ),
          ],
        ),
      );
    }

    if (_scanMode) return _buildQrScanner();

    if (_runnerLaps.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.nfc, size: 80, color: Colors.grey),
            SizedBox(height: 16),
            Text('Tap NFC or switch to QR mode',
                style: TextStyle(color: Colors.grey, fontSize: 18)),
          ],
        ),
      );
    }

    final sorted = _runnerLaps.entries.toList()
      ..sort((a, b) {
        final aF = a.value.length >= AppConfig.lapsPerMile;
        final bF = b.value.length >= AppConfig.lapsPerMile;
        if (aF != bF) return aF ? -1 : 1;
        if (a.value.isEmpty) return 1;
        if (b.value.isEmpty) return -1;
        return a.value.last.compareTo(b.value.last);
      });

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: sorted.length,
      separatorBuilder: (_, __) =>
          const Divider(color: Colors.white12, height: 1),
      itemBuilder: (_, i) {
        final entry = sorted[i];
        final laps = entry.value;
        final name = _runnerNames[entry.key] ?? 'Runner #${entry.key}';
        final finished = laps.length >= AppConfig.lapsPerMile;

        return ListTile(
          tileColor:
              finished ? const Color(0xFF1A4A1A) : const Color(0xFF111111),
          leading: CircleAvatar(
            backgroundColor: finished ? Colors.green : Colors.white24,
            child: Text('${i + 1}',
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
          ),
          title: Text(name,
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 18)),
          subtitle: Text(
            'Lap ${laps.length}/${AppConfig.lapsPerMile}'
            '${laps.isNotEmpty ? ' · ${_formatMs(laps.last)}' : ''}',
            style: const TextStyle(color: Colors.grey),
          ),
          trailing: finished
              ? const Icon(Icons.emoji_events, color: Colors.amber, size: 32)
              : Text('${laps.length}',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.w900)),
        );
      },
    );
  }

  Widget _buildQrScanner() {
    _qrController ??=
        MobileScannerController(detectionSpeed: DetectionSpeed.normal);
    return MobileScanner(
      controller: _qrController!,
      onDetect: (capture) {
        for (final barcode in capture.barcodes) {
          final raw = barcode.rawValue;
          if (raw != null && raw.isNotEmpty) {
            _handleToken(raw);
            break;
          }
        }
      },
    );
  }

  Widget _buildFooter() {
    return Container(
      color: const Color(0xFF111111),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white38),
                minimumSize: const Size(0, 52),
              ),
              onPressed: () {
                if (_scanMode) {
                  _qrController?.dispose();
                  _qrController = null;
                }
                setState(() => _scanMode = !_scanMode);
                if (!_scanMode) _startNfcListening();
              },
              icon: Icon(_scanMode ? Icons.nfc : Icons.qr_code_scanner),
              label: Text(_scanMode ? 'NFC Mode' : 'QR Mode'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white38),
                minimumSize: const Size(0, 52),
              ),
              onPressed: () async {
                final authToken = await ref.read(tokenProvider.future);
                await ref
                    .read(syncEngineProvider)
                    .syncPendingLogs(token: authToken);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Sync triggered')),
                  );
                }
              },
              icon: const Icon(Icons.sync),
              label: const Text('Force Sync'),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Pre-Race Sync Dialog ────────────────────────────────────────────────────

class _PreRaceSyncDialog extends ConsumerStatefulWidget {
  const _PreRaceSyncDialog({
    required this.eventId,
    required this.token,
    required this.onResult,
  });

  final int eventId;
  final String token;
  final void Function(bool proceed) onResult;

  @override
  ConsumerState<_PreRaceSyncDialog> createState() =>
      _PreRaceSyncDialogState();
}

class _PreRaceSyncDialogState extends ConsumerState<_PreRaceSyncDialog> {
  _SyncPhase _phase = _SyncPhase.syncing;
  String? _error;

  @override
  void initState() {
    super.initState();
    _runSync();
  }

  Future<void> _runSync() async {
    try {
      await ref.read(syncEngineProvider).preRaceSync(
            eventId: widget.eventId,
            token: widget.token,
          );
      if (mounted) setState(() => _phase = _SyncPhase.done);
      // Short delay so the user sees the success state
      await Future.delayed(const Duration(milliseconds: 800));
      if (mounted) widget.onResult(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _phase = _SyncPhase.error;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1A1A1A),
      title: const Text('Pre-Race Sync',
          style: TextStyle(color: Colors.white)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_phase == _SyncPhase.syncing) ...[
            const CircularProgressIndicator(color: Colors.green),
            const SizedBox(height: 16),
            const Text(
              'Downloading runner tokens…\nYou can scan offline once complete.',
              style: TextStyle(color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ] else if (_phase == _SyncPhase.done) ...[
            const Icon(Icons.check_circle, color: Colors.green, size: 48),
            const SizedBox(height: 12),
            const Text('Runner tokens ready',
                style: TextStyle(color: Colors.white)),
          ] else ...[
            const Icon(Icons.wifi_off, color: Colors.orange, size: 48),
            const SizedBox(height: 12),
            Text(
              'Sync failed: ${_error ?? 'unknown error'}\n\n'
              'You can still scan if tokens were cached from a previous sync.',
              style: const TextStyle(color: Colors.grey, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
      actions: _phase == _SyncPhase.error
          ? [
              TextButton(
                onPressed: () => widget.onResult(false),
                child: const Text('Cancel',
                    style: TextStyle(color: Colors.grey)),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Colors.orange),
                onPressed: () => widget.onResult(true),
                child: const Text('Proceed Offline',
                    style: TextStyle(color: Colors.black)),
              ),
            ]
          : null,
    );
  }
}

enum _SyncPhase { syncing, done, error }
