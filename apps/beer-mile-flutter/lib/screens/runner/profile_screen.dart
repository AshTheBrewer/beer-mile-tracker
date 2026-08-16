import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/auth_providers.dart';
import '../../api/models/api_leaderboard.dart';
import '../../providers/event_providers.dart';
import '../../widgets/loading_indicator.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  late TextEditingController _nameController;
  String? _selectedGender;
  bool _saving = false;
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _startEdit(user) {
    _nameController.text = user.preferredName ?? '';
    _selectedGender = user.gender;
    setState(() => _editing = true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final authAsync = ref.watch(authStateProvider);
    final historyAsync = ref.watch(runnerHistoryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Profile'),
        actions: [
          authAsync.when(
            data: (user) => user != null && !_editing
                ? IconButton(
                    icon: const Icon(Icons.edit),
                    onPressed: () => _startEdit(user),
                  )
                : const SizedBox.shrink(),
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
        ],
      ),
      body: authAsync.when(
        data: (user) {
          if (user == null) return const SizedBox.shrink();

          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              // Avatar
              Center(
                child: CircleAvatar(
                  radius: 40,
                  backgroundColor: cs.primaryContainer,
                  child: Text(
                    user.displayName.substring(0, 1).toUpperCase(),
                    style: theme.textTheme.headlineLarge
                        ?.copyWith(color: cs.onPrimaryContainer),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              if (!_editing) ...[
                _InfoTile('Email', user.email),
                _InfoTile('Role', _roleLabel(user.role)),
                if (user.preferredName != null)
                  _InfoTile('Name', user.preferredName!),
                if (user.gender != null)
                  _InfoTile('Gender', user.gender!),
              ] else ...[
                TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'Preferred name'),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(labelText: 'Gender'),
                  value: _selectedGender,
                  items: const [
                    DropdownMenuItem(value: null, child: Text('Prefer not to say')),
                    DropdownMenuItem(value: 'male', child: Text('Male')),
                    DropdownMenuItem(value: 'female', child: Text('Female')),
                    DropdownMenuItem(value: 'non_binary', child: Text('Non-binary')),
                  ],
                  onChanged: (v) => setState(() => _selectedGender = v),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => setState(() => _editing = false),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: _saving ? null : _save,
                        child: _saving
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Text('Save'),
                      ),
                    ),
                  ],
                ),
              ],

              const Divider(height: 40),

              // ── Race history section ──────────────────────────────────────
              _RaceHistorySection(historyAsync: historyAsync),

              const Divider(height: 40),
              ListTile(
                leading: const Icon(Icons.logout, color: Colors.red),
                title: const Text('Sign Out', style: TextStyle(color: Colors.red)),
                onTap: () => ref.read(authStateProvider.notifier).signOut(),
              ),
            ],
          );
        },
        loading: () => const LoadingIndicator(),
        error: (e, _) => ErrorView(error: e),
      ),
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref.read(authStateProvider.notifier).updateProfile(
            preferredName: _nameController.text.trim().isEmpty
                ? null
                : _nameController.text.trim(),
            gender: _selectedGender,
          );
      if (mounted) setState(() => _editing = false);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _roleLabel(String role) => switch (role) {
        'super_admin' => 'Super Admin',
        'host' => 'Host',
        _ => 'Runner',
      };
}

// ── Race history ─────────────────────────────────────────────────────────────

class _RaceHistorySection extends StatelessWidget {
  const _RaceHistorySection({required this.historyAsync});
  final AsyncValue<List<RunnerRaceResult>> historyAsync;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Race History', style: theme.textTheme.titleMedium),
        const SizedBox(height: 12),
        historyAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text('Could not load history: $e',
                style: TextStyle(color: theme.colorScheme.error)),
          ),
          data: (results) {
            if (results.isEmpty) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: Text(
                    'No completed races yet.\nSign up for an event to get started!',
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }

            // Personal best = minimum totalElapsedMs among finished races.
            final pb = results.reduce((a, b) =>
                a.totalElapsedMs < b.totalElapsedMs ? a : b);

            return Column(
              children: [
                _PersonalBestCard(pb: pb),
                const SizedBox(height: 12),
                ...results.map((r) => _RaceResultTile(
                      result: r,
                      isPersonalBest: r == pb,
                    )),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _PersonalBestCard extends StatelessWidget {
  const _PersonalBestCard({required this.pb});
  final RunnerRaceResult pb;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Card(
      color: cs.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.emoji_events, color: cs.primary, size: 32),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Personal Best',
                    style: theme.textTheme.labelMedium
                        ?.copyWith(color: cs.onPrimaryContainer),
                  ),
                  Text(
                    pb.formattedTime,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: cs.onPrimaryContainer,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    pb.event.title,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: cs.onPrimaryContainer),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RaceResultTile extends StatefulWidget {
  const _RaceResultTile({
    required this.result,
    required this.isPersonalBest,
  });
  final RunnerRaceResult result;
  final bool isPersonalBest;

  @override
  State<_RaceResultTile> createState() => _RaceResultTileState();
}

class _RaceResultTileState extends State<_RaceResultTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final result = widget.result;
    final event = result.event;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Column(
        children: [
          ListTile(
            leading: widget.isPersonalBest
                ? Icon(Icons.emoji_events, color: cs.primary)
                : const Icon(Icons.flag_outlined),
            title: Text(event.title),
            subtitle: Text(event.eventDate),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  result.formattedTime,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: widget.isPersonalBest ? cs.primary : null,
                    fontWeight: widget.isPersonalBest
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  _expanded
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  size: 20,
                ),
              ],
            ),
            onTap: () => setState(() => _expanded = !_expanded),
          ),
          if (_expanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Lap Splits',
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 6),
                  if (result.laps.isEmpty)
                    const Text('No lap data available.')
                  else
                    ...result.laps.map((lap) => _LapSplitRow(lap: lap)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _LapSplitRow extends StatelessWidget {
  const _LapSplitRow({required this.lap});
  final ApiLapSplit lap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ms = lap.elapsedMs;
    final m = ms ~/ 60000;
    final s = (ms % 60000) / 1000;
    final timeStr =
        m > 0 ? '${m}m ${s.toStringAsFixed(1)}s' : '${s.toStringAsFixed(1)}s';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 56,
            child: Text(
              'Lap ${lap.lapNumber}',
              style: theme.textTheme.bodySmall,
            ),
          ),
          Expanded(
            child: Text(
              timeStr,
              style: theme.textTheme.bodyMedium,
            ),
          ),
          if (lap.pourConfirmed)
            Icon(Icons.sports_bar, size: 16,
                color: theme.colorScheme.secondary),
        ],
      ),
    );
  }
}

// ── Shared info tile ──────────────────────────────────────────────────────────

class _InfoTile extends StatelessWidget {
  const _InfoTile(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(label, style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant)),
      subtitle: Text(value, style: Theme.of(context).textTheme.bodyLarge),
      dense: true,
    );
  }
}
