import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_client.dart';
import '../../api/models/api_registration.dart';
import '../../core/config.dart';
import '../../providers/auth_providers.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/loading_indicator.dart';

class RegistrationsScreen extends ConsumerStatefulWidget {
  const RegistrationsScreen({super.key, required this.eventId});
  final int eventId;

  @override
  ConsumerState<RegistrationsScreen> createState() =>
      _RegistrationsScreenState();
}

class _RegistrationsScreenState extends ConsumerState<RegistrationsScreen> {
  List<ApiRegistrationWithUser>? _regs;
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final token = await ref.read(tokenProvider.future);
      final api = ApiClient(baseUrl: AppConfig.apiBaseUrl);
      final regs =
          await api.listRegistrations(widget.eventId, token: token!);
      if (mounted) setState(() => _regs = regs);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _togglePayment(ApiRegistrationWithUser reg) async {
    final newStatus =
        reg.paymentStatus == 'confirmed' ? 'pending' : 'confirmed';
    try {
      final token = await ref.read(tokenProvider.future);
      final api = ApiClient(baseUrl: AppConfig.apiBaseUrl);
      await api.updateRegistration(
        reg.id,
        {'paymentStatus': newStatus},
        token: token!,
      );
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Registrations'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const LoadingIndicator(message: 'Loading registrations…')
          : _error != null
              ? ErrorView(error: _error!, onRetry: _load)
              : _regs!.isEmpty
                  ? const EmptyState(
                      icon: Icons.person_off,
                      title: 'No registrations yet',
                      subtitle: 'Runners will appear here after registering.',
                    )
                  : Column(
                      children: [
                        Container(
                          color: theme.colorScheme.primaryContainer
                              .withOpacity(0.4),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          child: Row(
                            children: [
                              Text(
                                '${_regs!.length} total · '
                                '${_regs!.where((r) => r.isConfirmed).length} confirmed',
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: ListView.separated(
                            itemCount: _regs!.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (_, i) =>
                                _RegRow(reg: _regs![i], onToggle: _togglePayment),
                          ),
                        ),
                      ],
                    ),
    );
  }
}

class _RegRow extends StatelessWidget {
  const _RegRow({required this.reg, required this.onToggle});
  final ApiRegistrationWithUser reg;
  final void Function(ApiRegistrationWithUser) onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return ListTile(
      leading: CircleAvatar(
        backgroundColor:
            reg.isConfirmed ? cs.primaryContainer : cs.surfaceContainerHighest,
        child: Text(
          reg.displayName.substring(0, 1).toUpperCase(),
          style: TextStyle(
              color: reg.isConfirmed ? cs.onPrimaryContainer : cs.onSurface),
        ),
      ),
      title: Text(reg.displayName),
      subtitle: Text(
        '${reg.userEmail ?? reg.userId}'
        '${reg.tagUid != null ? ' · NFC: ${reg.tagUid}' : ''}',
        style: theme.textTheme.bodySmall
            ?.copyWith(color: cs.onSurfaceVariant),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: InkWell(
        onTap: () => onToggle(reg),
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: reg.isConfirmed
                ? Colors.green.withOpacity(0.15)
                : Colors.orange.withOpacity(0.15),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            reg.isConfirmed ? 'Confirmed' : 'Pending',
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: reg.isConfirmed
                    ? Colors.green.shade700
                    : Colors.orange.shade700),
          ),
        ),
      ),
    );
  }
}
