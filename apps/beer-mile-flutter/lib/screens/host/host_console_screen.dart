import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../api/models/api_event.dart';
import '../../providers/auth_providers.dart';
import '../../providers/event_providers.dart';
import '../../providers/sync_providers.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/loading_indicator.dart';
import '../../widgets/sync_status_banner.dart';

class HostConsoleScreen extends ConsumerWidget {
  const HostConsoleScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventsAsync = ref.watch(eventsProvider);
    final user = ref.watch(authStateProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Host Console'),
        actions: [
          IconButton(
            icon: const Icon(Icons.sync),
            tooltip: 'Force sync',
            onPressed: () async {
              final token = await ref.read(tokenProvider.future);
              await ref.read(syncEngineProvider).syncPendingLogs(token: token);
            },
          ),
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
                // Show only this host's events
                final hostEvents = events
                    .where((e) => e.status != 'cancelled')
                    .toList();

                if (hostEvents.isEmpty) {
                  return EmptyState(
                    icon: Icons.event_note,
                    title: 'No events yet',
                    subtitle: 'Create your first Beer Mile event.',
                    action: FilledButton.icon(
                      onPressed: () => context.push('/host/events/new'),
                      icon: const Icon(Icons.add),
                      label: const Text('Create Event'),
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: () =>
                      ref.read(eventsProvider.notifier).refresh(),
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: hostEvents.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: 12),
                    itemBuilder: (_, i) =>
                        _HostEventCard(event: hostEvents[i]),
                  ),
                );
              },
              loading: () =>
                  const LoadingIndicator(message: 'Loading events…'),
              error: (e, _) => ErrorView(
                error: e,
                onRetry: () =>
                    ref.read(eventsProvider.notifier).refresh(),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/host/events/new'),
        icon: const Icon(Icons.add),
        label: const Text('New Event'),
      ),
    );
  }
}

class _HostEventCard extends StatelessWidget {
  const _HostEventCard({required this.event});
  final ApiEvent event;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Card(
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
            const SizedBox(height: 4),
            Text('Code: ${event.eventCode}',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: cs.onSurfaceVariant, fontFamily: 'monospace')),
            Text(event.eventDate,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: cs.onSurfaceVariant)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _ActionBtn(
                  icon: Icons.people,
                  label: 'Registrations',
                  onTap: () => context.push(
                      '/host/events/${event.id}/registrations'),
                ),
                _ActionBtn(
                  icon: Icons.nfc,
                  label: 'Tags',
                  onTap: () =>
                      context.push('/host/events/${event.id}/tags'),
                ),
                if (event.isActive)
                  _ActionBtn(
                    icon: Icons.sensors,
                    label: 'Scanner',
                    primary: true,
                    onTap: () => context.push(
                        '/host/events/${event.id}/scanner'),
                  ),
                _ActionBtn(
                  icon: Icons.edit,
                  label: 'Edit',
                  onTap: () => context.push(
                      '/host/events/${event.id}/edit'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  const _ActionBtn({
    required this.icon,
    required this.label,
    required this.onTap,
    this.primary = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    if (primary) {
      return FilledButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 16),
        label: Text(label),
        style: FilledButton.styleFrom(
            minimumSize: const Size(0, 36),
            padding: const EdgeInsets.symmetric(horizontal: 12)),
      );
    }
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16),
      label: Text(label),
      style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 36),
          padding: const EdgeInsets.symmetric(horizontal: 12)),
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
