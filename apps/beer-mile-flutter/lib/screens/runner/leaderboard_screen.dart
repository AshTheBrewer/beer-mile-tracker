import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/models/api_leaderboard.dart';
import '../../core/config.dart';
import '../../providers/event_providers.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/loading_indicator.dart';

class LeaderboardScreen extends ConsumerStatefulWidget {
  const LeaderboardScreen({super.key, required this.eventId});
  final int eventId;

  @override
  ConsumerState<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends ConsumerState<LeaderboardScreen> {
  String _filter = 'overall'; // overall | male | female | non_binary

  @override
  Widget build(BuildContext context) {
    final leaderboardAsync = ref.watch(leaderboardProvider(widget.eventId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Leaderboard'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                for (final (value, label) in [
                  ('overall', 'Overall'),
                  ('male', 'Male'),
                  ('female', 'Female'),
                  ('non_binary', 'Non-Binary'),
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(label),
                      selected: _filter == value,
                      onSelected: (_) => setState(() => _filter = value),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      body: leaderboardAsync.when(
        data: (entries) {
          final filtered = _filter == 'overall'
              ? entries
              : entries.where((e) => e.gender == _filter).toList();

          if (filtered.isEmpty) {
            return const EmptyState(
              icon: Icons.leaderboard,
              title: 'No results yet',
              subtitle: 'Lap scans will appear here as runners finish.',
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: filtered.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (ctx, i) => _EntryRow(entry: filtered[i], rank: i + 1),
          );
        },
        loading: () => const LoadingIndicator(message: 'Loading leaderboard…'),
        error: (e, _) => ErrorView(
          error: e,
          onRetry: () => ref.invalidate(leaderboardProvider(widget.eventId)),
        ),
      ),
    );
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({required this.entry, required this.rank});
  final ApiLeaderboardEntry entry;
  final int rank;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final laps = entry.laps.length;
    final total = entry.laps.length;
    final maxLaps = AppConfig.lapsPerMile;

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: rank <= 3 ? cs.primaryContainer : cs.surfaceContainerHighest,
        child: Text('$rank',
            style: TextStyle(
                fontWeight: FontWeight.bold,
                color: rank <= 3 ? cs.onPrimaryContainer : cs.onSurface)),
      ),
      title: Text(entry.displayName,
          style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
      subtitle: Text(
        '$laps/$maxLaps laps${entry.gender != null ? ' · ${entry.gender}' : ''}',
        style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(entry.formattedTime,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
          if (entry.finished)
            Text('Finished',
                style: TextStyle(fontSize: 11, color: Colors.green.shade700)),
        ],
      ),
    );
  }
}
