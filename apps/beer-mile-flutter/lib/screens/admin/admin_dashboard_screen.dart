import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../api/api_client.dart';
import '../../api/models/api_admin.dart';
import '../../core/config.dart';
import '../../providers/auth_providers.dart';
import '../../widgets/loading_indicator.dart';

final _analyticsProvider = FutureProvider<ApiAdminAnalytics>((ref) async {
  final token = await ref.watch(tokenProvider.future);
  if (token == null) throw Exception('Not authenticated');
  final api = ApiClient(baseUrl: AppConfig.apiBaseUrl);
  return api.getAnalytics(token: token);
});

final _tenantsProvider =
    FutureProvider<List<ApiTenantWithUser>>((ref) async {
  final token = await ref.watch(tokenProvider.future);
  if (token == null) throw Exception('Not authenticated');
  final api = ApiClient(baseUrl: AppConfig.apiBaseUrl);
  return api.listTenants(token: token);
});

class AdminDashboardScreen extends ConsumerWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final analyticsAsync = ref.watch(_analyticsProvider);
    final tenantsAsync = ref.watch(_tenantsProvider);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Platform Settings',
            onPressed: () => context.push('/admin/platform-settings'),
          ),
          IconButton(
            icon: const Icon(Icons.person_outline),
            onPressed: () => context.push('/runner/profile'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(_analyticsProvider);
          ref.invalidate(_tenantsProvider);
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Platform Analytics',
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            analyticsAsync.when(
              data: (a) => _AnalyticsGrid(analytics: a),
              loading: () => const LoadingIndicator(message: 'Loading analytics…'),
              error: (e, _) => ErrorView(
                error: e,
                onRetry: () => ref.invalidate(_analyticsProvider),
              ),
            ),
            const SizedBox(height: 24),
            Text('Tenants',
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            tenantsAsync.when(
              data: (tenants) => tenants.isEmpty
                  ? const Center(child: Text('No tenants yet'))
                  : Column(
                      children: tenants
                          .map((t) => Card(
                                margin: const EdgeInsets.only(bottom: 8),
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: cs.primaryContainer,
                                    child: Text(
                                        t.organizationName.substring(0, 1)),
                                  ),
                                  title: Text(t.organizationName),
                                  subtitle: Text(t.userEmail ?? t.userId),
                                  trailing: Text('#${t.id}',
                                      style: theme.textTheme.bodySmall),
                                ),
                              ))
                          .toList(),
                    ),
              loading: () => const LoadingIndicator(message: 'Loading tenants…'),
              error: (e, _) => ErrorView(
                error: e,
                onRetry: () => ref.invalidate(_tenantsProvider),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnalyticsGrid extends StatelessWidget {
  const _AnalyticsGrid({required this.analytics});
  final ApiAdminAnalytics analytics;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.5,
      children: [
        _Stat(
          label: 'Total Events',
          value: '${analytics.totalEvents}',
          icon: Icons.event,
          color: Colors.blue,
        ),
        _Stat(
          label: 'Runners',
          value: '${analytics.totalRunners}',
          icon: Icons.directions_run,
          color: Colors.green,
        ),
        _Stat(
          label: 'Tenants',
          value: '${analytics.totalTenants}',
          icon: Icons.business,
          color: Colors.purple,
        ),
        _Stat(
          label: 'Finishers',
          value: '${analytics.totalFinishers}',
          icon: Icons.emoji_events,
          color: Colors.amber,
        ),
        if (analytics.avgLapTimeMs != null)
          _Stat(
            label: 'Avg Lap Time',
            value: _formatMs(analytics.avgLapTimeMs!),
            icon: Icons.timer,
            color: Colors.orange,
          ),
      ],
    );
  }

  String _formatMs(int ms) {
    final m = ms ~/ 60000;
    final s = (ms % 60000) ~/ 1000;
    return '${m}m ${s}s';
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 4),
            Text(value,
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            Text(label,
                style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}
