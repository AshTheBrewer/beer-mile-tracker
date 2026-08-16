import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/sync_providers.dart';
import '../sync/sync_engine.dart';

/// A thin banner displayed below the AppBar that reflects sync state.
/// Green = fully synced, Yellow = offline with pending queue, Red = error.
class SyncStatusBanner extends ConsumerWidget {
  const SyncStatusBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final syncAsync = ref.watch(syncStateProvider);

    return syncAsync.when(
      data: (state) {
        if (state.status == SyncStatus.idle && state.pendingCount == 0) {
          return const SizedBox.shrink();
        }
        return _Banner(state: state);
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.state});
  final SyncState state;

  @override
  Widget build(BuildContext context) {
    final (color, icon, message) = switch (state.status) {
      SyncStatus.offline =>
        (Colors.orange.shade700, Icons.wifi_off, 'Offline — ${state.pendingCount} scan(s) queued'),
      SyncStatus.syncing =>
        (Colors.blue.shade700, Icons.sync, 'Syncing…'),
      SyncStatus.error =>
        (Colors.red.shade700, Icons.error_outline, 'Sync error — tap to retry'),
      SyncStatus.idle => state.pendingCount > 0
          ? (Colors.orange.shade600, Icons.pending, '${state.pendingCount} scan(s) pending upload')
          : (Colors.green.shade700, Icons.check_circle, 'All synced'),
    };

    return Container(
      color: color,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.white),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message,
                style: const TextStyle(color: Colors.white, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}
