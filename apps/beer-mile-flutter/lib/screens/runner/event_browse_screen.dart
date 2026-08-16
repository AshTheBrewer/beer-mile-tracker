import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../api/api_client.dart';
import '../../api/models/api_event.dart';
import '../../core/config.dart';
import '../../providers/auth_providers.dart';
import '../../providers/event_providers.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/loading_indicator.dart';
import '../../widgets/sync_status_banner.dart';

class EventBrowseScreen extends ConsumerStatefulWidget {
  const EventBrowseScreen({super.key});

  @override
  ConsumerState<EventBrowseScreen> createState() => _EventBrowseScreenState();
}

class _EventBrowseScreenState extends ConsumerState<EventBrowseScreen> {
  final _codeController = TextEditingController();

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final eventsAsync = ref.watch(eventsProvider);
    final user = ref.watch(authStateProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Beer Mile'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_outline),
            onPressed: () => context.push('/runner/profile'),
          ),
        ],
      ),
      body: Column(
        children: [
          const SyncStatusBanner(),
          Expanded(
            child: eventsAsync.when(
              data: (events) {
                if (events.isEmpty) {
                  return EmptyState(
                    icon: Icons.event_busy,
                    title: 'No events yet',
                    subtitle: 'Join with a private code or check back later.',
                    action: _joinByCodeButton(),
                  );
                }
                return RefreshIndicator(
                  onRefresh: () =>
                      ref.read(eventsProvider.notifier).refresh(),
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _joinByCodeCard(),
                      const SizedBox(height: 16),
                      ...events.map((e) => _EventCard(event: e)),
                    ],
                  ),
                );
              },
              loading: () => const LoadingIndicator(message: 'Loading events…'),
              error: (e, _) => ErrorView(
                error: e,
                onRetry: () => ref.read(eventsProvider.notifier).refresh(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _joinByCodeButton() => FilledButton.icon(
        onPressed: _showJoinDialog,
        icon: const Icon(Icons.vpn_key),
        label: const Text('Join with code'),
      );

  Widget _joinByCodeCard() => Card(
        child: ListTile(
          leading: const Icon(Icons.vpn_key),
          title: const Text('Have a private code?'),
          subtitle: const Text('Tap to join a private event'),
          trailing: const Icon(Icons.chevron_right),
          onTap: _showJoinDialog,
        ),
      );

  Future<void> _showJoinDialog() async {
    _codeController.clear();
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Join Event'),
        content: TextField(
          controller: _codeController,
          decoration: const InputDecoration(
            labelText: 'Event code',
            hintText: 'e.g. A1B2C3',
          ),
          textCapitalization: TextCapitalization.characters,
          autofocus: true,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final code = _codeController.text.trim().toUpperCase();
              Navigator.pop(ctx);
              await _joinByCode(code);
            },
            child: const Text('Join'),
          ),
        ],
      ),
    );
  }

  Future<void> _joinByCode(String code) async {
    if (code.isEmpty) return;
    final token = await ref.read(tokenProvider.future);
    if (token == null) return;

    try {
      final api = ApiClient(baseUrl: AppConfig.apiBaseUrl);
      final event = await api.joinEventByCode(code, token: token);
      // Refresh local cache and navigate to the resolved event
      ref.invalidate(eventsProvider);
      if (mounted) {
        context.push('/runner/events/${event.id}');
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.isNotFound
                ? 'No event found with that code'
                : 'Error: ${e.message}'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }
}

class _EventCard extends StatelessWidget {
  const _EventCard({required this.event});
  final ApiEvent event;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.push('/runner/events/${event.id}'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(event.title,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold)),
                  ),
                  _StatusChip(status: event.status),
                ],
              ),
              if (event.locationName != null) ...[
                const SizedBox(height: 4),
                Row(children: [
                  Icon(Icons.place, size: 14, color: cs.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Text(event.locationName!,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: cs.onSurfaceVariant)),
                ]),
              ],
              const SizedBox(height: 4),
              Row(children: [
                Icon(Icons.calendar_today, size: 14, color: cs.onSurfaceVariant),
                const SizedBox(width: 4),
                Text(event.eventDate,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: cs.onSurfaceVariant)),
              ]),
              if (event.entryFee != null) ...[
                const SizedBox(height: 4),
                Row(children: [
                  Icon(Icons.monetization_on, size: 14, color: cs.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Text('Entry: ${event.entryFee}',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: cs.onSurfaceVariant)),
                ]),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (status) {
      'open' => (Colors.green, 'Open'),
      'active' => (Colors.blue, 'Live'),
      'completed' => (Colors.grey, 'Done'),
      'cancelled' => (Colors.red, 'Cancelled'),
      _ => (Colors.orange, 'Draft'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 11, color: color, fontWeight: FontWeight.w600)),
    );
  }
}
