import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../api/api_client.dart';
import '../../api/models/api_registration.dart';
import '../../core/config.dart';
import '../../providers/auth_providers.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/loading_indicator.dart';

class TagProvisioningScreen extends ConsumerStatefulWidget {
  const TagProvisioningScreen({super.key, required this.eventId});
  final int eventId;

  @override
  ConsumerState<TagProvisioningScreen> createState() =>
      _TagProvisioningScreenState();
}

class _TagProvisioningScreenState
    extends ConsumerState<TagProvisioningScreen> {
  List<ApiRegistrationWithUser>? _regs;
  bool _loading = true;
  Object? _error;
  ApiRegistrationWithUser? _selected;
  bool _nfcAvailable = false;
  bool _writing = false;

  @override
  void initState() {
    super.initState();
    _checkNfc();
    _load();
  }

  Future<void> _checkNfc() async {
    _nfcAvailable = await NfcManager.instance.isAvailable();
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final token = await ref.read(tokenProvider.future);
      final api = ApiClient(baseUrl: AppConfig.apiBaseUrl);
      final regs = await api.listRegistrations(widget.eventId, token: token!);
      // Only confirmed runners get a tag
      if (mounted) {
        setState(() => _regs = regs.where((r) => r.isConfirmed).toList());
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Generate a signed token payload for a runner.
  /// Format: "<registrationId>:<eventId>:<uuid>:<hmac>"
  String _buildPayload(int registrationId) {
    final nonce = const Uuid().v4().replaceAll('-', '');
    final raw = '$registrationId:${widget.eventId}:$nonce';
    final key = utf8.encode(AppConfig.nfcHmacSecret);
    final bytes = utf8.encode(raw);
    final hmac = Hmac(sha256, key).convert(bytes).toString().substring(0, 16);
    return '$raw:$hmac';
  }

  Future<void> _writeNfc(ApiRegistrationWithUser reg) async {
    if (!_nfcAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('NFC is not available on this device')),
      );
      return;
    }

    final payload = _buildPayload(reg.id);
    setState(() => _writing = true);

    try {
      await NfcManager.instance.startSession(
        onDiscovered: (NfcTag tag) async {
          try {
            final ndef = Ndef.from(tag);
            if (ndef == null || !ndef.isWritable) {
              throw Exception('Tag is not NDEF writable');
            }
            await ndef.write(NdefMessage([NdefRecord.createText(payload)]));
            await _persistRunnerToken(reg, payload);
            if (mounted) {
              HapticFeedback.lightImpact();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Tag written for ${reg.displayName}')),
              );
            }
          } catch (e) {
            if (mounted) {
              HapticFeedback.heavyImpact();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Write failed: $e')),
              );
            }
          } finally {
            await NfcManager.instance.stopSession();
            if (mounted) setState(() => _writing = false);
          }
        },
      );
      if (mounted) {
        showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (_) => AlertDialog(
            title: const Text('Tap NFC Tag'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text('Hold the NFC tag near the device to write the runner token for ${reg.displayName}'),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  await NfcManager.instance.stopSession();
                  if (mounted) {
                    Navigator.pop(context);
                    setState(() => _writing = false);
                  }
                },
                child: const Text('Cancel'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      setState(() => _writing = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('NFC error: $e')),
        );
      }
    }
  }

  Future<void> _persistRunnerToken(
      ApiRegistrationWithUser reg, String payload) async {
    final token = await ref.read(tokenProvider.future);
    if (token == null) return;
    final api = ApiClient(baseUrl: AppConfig.apiBaseUrl);
    await api.updateRegistration(
      reg.id,
      {'runnerToken': payload},
      token: token,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Tag Provisioning')),
      body: _loading
          ? const LoadingIndicator(message: 'Loading confirmed runners…')
          : _error != null
              ? ErrorView(error: _error!, onRetry: _load)
              : _regs!.isEmpty
                  ? const EmptyState(
                      icon: Icons.nfc,
                      title: 'No confirmed runners',
                      subtitle: 'Confirm payment for runners first, then assign NFC / QR tags here.',
                    )
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        if (!_nfcAvailable)
                          Card(
                            color: Colors.orange.shade50,
                            child: const ListTile(
                              leading: Icon(Icons.warning_amber, color: Colors.orange),
                              title: Text('NFC unavailable on this device'),
                              subtitle: Text('QR code mode will be used instead.'),
                            ),
                          ),
                        const SizedBox(height: 8),
                        ..._regs!.map(
                          (reg) => Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(reg.displayName,
                                                style: theme.textTheme.titleMedium
                                                    ?.copyWith(fontWeight: FontWeight.bold)),
                                            Text(reg.userEmail ?? reg.userId,
                                                style: theme.textTheme.bodySmall),
                                            if (reg.runnerToken != null)
                                              Text('Token assigned',
                                                  style: TextStyle(
                                                      fontSize: 11,
                                                      color: Colors.green.shade700,
                                                      fontWeight: FontWeight.w600)),
                                          ],
                                        ),
                                      ),
                                      if (reg.runnerToken != null) ...[
                                        SizedBox(
                                          width: 80,
                                          height: 80,
                                          child: QrImageView(data: reg.runnerToken!, size: 80),
                                        ),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      if (_nfcAvailable)
                                        Expanded(
                                          child: OutlinedButton.icon(
                                            onPressed: _writing
                                                ? null
                                                : () => _writeNfc(reg),
                                            icon: const Icon(Icons.nfc, size: 18),
                                            label: Text(reg.runnerToken != null
                                                ? 'Re-write NFC'
                                                : 'Write NFC'),
                                          ),
                                        ),
                                      if (_nfcAvailable) const SizedBox(width: 8),
                                      Expanded(
                                        child: OutlinedButton.icon(
                                          onPressed: () =>
                                              _showQr(context, reg),
                                          icon: const Icon(Icons.qr_code, size: 18),
                                          label: Text(reg.runnerToken != null
                                              ? 'Show QR'
                                              : 'Generate QR'),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
    );
  }

  Future<void> _showQr(
      BuildContext context, ApiRegistrationWithUser reg) async {
    String payload = reg.runnerToken ?? _buildPayload(reg.id);
    if (reg.runnerToken == null) {
      await _persistRunnerToken(reg, payload);
      await _load();
    }

    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(reg.displayName),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            QrImageView(data: payload, size: 200),
            const SizedBox(height: 12),
            const Text('Runner scans this QR at the start line.',
                textAlign: TextAlign.center),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
