import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../api/api_client.dart';
import '../../api/models/api_event.dart';
import '../../core/config.dart';
import '../../providers/auth_providers.dart';
import '../../providers/event_providers.dart';
import '../../widgets/loading_indicator.dart';

class EventDetailScreen extends ConsumerWidget {
  const EventDetailScreen({super.key, required this.eventId});
  final int eventId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventAsync = ref.watch(eventDetailProvider(eventId));

    return Scaffold(
      appBar: AppBar(title: const Text('Event')),
      body: eventAsync.when(
        data: (event) =>
            event == null ? const Center(child: Text('Not found')) : _Body(event: event),
        loading: () => const LoadingIndicator(message: 'Loading event…'),
        error: (e, _) => ErrorView(error: e),
      ),
    );
  }
}

class _Body extends ConsumerStatefulWidget {
  const _Body({required this.event});
  final ApiEvent event;

  @override
  ConsumerState<_Body> createState() => _BodyState();
}

class _BodyState extends ConsumerState<_Body> {
  bool _registering = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final e = widget.event;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(e.title, style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        if (e.locationName != null)
          _Row(Icons.place, e.locationName!),
        _Row(Icons.calendar_today, e.eventDate),
        if (e.beerType != null)
          _Row(Icons.sports_bar, 'Beer: ${e.beerType}'),
        if (e.entryFee != null)
          _Row(Icons.monetization_on, 'Entry fee: ${e.entryFee}'),
        const SizedBox(height: 20),
        if (e.paymentInstructions != null) ...[
          Text('Payment Instructions', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(e.paymentInstructions!, style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: 20),
        ],
        if (e.prizesJson != null && e.prizesJson!.isNotEmpty) ...[
          Text('Prizes', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ...e.prizesJson!.map((p) => ListTile(
                dense: true,
                leading: Icon(Icons.emoji_events, color: cs.primary),
                title: Text('${p['position']}. ${p['description']}'),
              )),
          const SizedBox(height: 20),
        ],
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => context.push('/runner/events/$eventId/leaderboard'),
                icon: const Icon(Icons.leaderboard),
                label: const Text('Leaderboard'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: (e.isOpen || e.isActive) && !_registering
                    ? _register
                    : null,
                icon: _registering
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.how_to_reg),
                label: const Text('Register'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _register() async {
    setState(() => _registering = true);
    try {
      final token = await ref.read(tokenProvider.future);
      if (token == null) throw Exception('Not signed in');
      final api = ApiClient(baseUrl: AppConfig.apiBaseUrl);
      await api.createRegistration(widget.event.id, token: token);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Registered! Awaiting host confirmation.')),
        );
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.isConflict ? 'Already registered' : e.message)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _registering = false);
    }
  }
}

class _Row extends StatelessWidget {
  const _Row(this.icon, this.text);
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(icon, size: 16, color: cs.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
