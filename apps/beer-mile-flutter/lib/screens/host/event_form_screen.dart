import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../api/api_client.dart';
import '../../api/models/api_event.dart';
import '../../core/config.dart';
import '../../providers/auth_providers.dart';
import '../../providers/event_providers.dart';
import '../../widgets/loading_indicator.dart';

class EventFormScreen extends ConsumerStatefulWidget {
  const EventFormScreen({super.key, this.eventId});
  final int? eventId;

  @override
  ConsumerState<EventFormScreen> createState() => _EventFormScreenState();
}

class _EventFormScreenState extends ConsumerState<EventFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _dateCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  final _beerTypeCtrl = TextEditingController();
  final _entryFeeCtrl = TextEditingController();
  final _paymentInstructionsCtrl = TextEditingController();

  String _status = 'draft';
  bool _saving = false;
  ApiEvent? _existing;

  @override
  void initState() {
    super.initState();
    if (widget.eventId != null) _loadExisting();
  }

  Future<void> _loadExisting() async {
    final token = await ref.read(tokenProvider.future);
    final api = ApiClient(baseUrl: AppConfig.apiBaseUrl);
    try {
      final event = await api.getEvent(widget.eventId!, token: token);
      setState(() {
        _existing = event;
        _titleCtrl.text = event.title;
        _dateCtrl.text = event.eventDate;
        _locationCtrl.text = event.locationName ?? '';
        _beerTypeCtrl.text = event.beerType ?? '';
        _entryFeeCtrl.text = event.entryFee ?? '';
        _paymentInstructionsCtrl.text = event.paymentInstructions ?? '';
        _status = event.status;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading event: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _dateCtrl.dispose();
    _locationCtrl.dispose();
    _beerTypeCtrl.dispose();
    _entryFeeCtrl.dispose();
    _paymentInstructionsCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.eventId != null;

    return Scaffold(
      appBar: AppBar(title: Text(isEdit ? 'Edit Event' : 'New Event')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            TextFormField(
              controller: _titleCtrl,
              decoration: const InputDecoration(labelText: 'Event title *'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _dateCtrl,
              decoration: const InputDecoration(
                labelText: 'Event date *',
                hintText: '2026-08-16',
                suffixIcon: Icon(Icons.calendar_today),
              ),
              readOnly: true,
              onTap: () async {
                final date = await showDatePicker(
                  context: context,
                  initialDate: DateTime.now(),
                  firstDate: DateTime.now().subtract(const Duration(days: 30)),
                  lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
                );
                if (date != null) {
                  _dateCtrl.text =
                      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
                }
              },
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _locationCtrl,
              decoration: const InputDecoration(labelText: 'Location name'),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _beerTypeCtrl,
              decoration: const InputDecoration(
                  labelText: 'Beer type', hintText: 'e.g. Lager, 355ml cans'),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _entryFeeCtrl,
              decoration:
                  const InputDecoration(labelText: 'Entry fee', hintText: 'e.g. \$20'),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _paymentInstructionsCtrl,
              decoration: const InputDecoration(
                  labelText: 'Payment instructions',
                  hintText: 'How runners should pay'),
              maxLines: 3,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(labelText: 'Status'),
              value: _status,
              items: const [
                DropdownMenuItem(value: 'draft', child: Text('Draft')),
                DropdownMenuItem(value: 'open', child: Text('Open (accepting registrations)')),
                DropdownMenuItem(value: 'active', child: Text('Active (race day)')),
                DropdownMenuItem(value: 'completed', child: Text('Completed')),
                DropdownMenuItem(value: 'cancelled', child: Text('Cancelled')),
              ],
              onChanged: (v) => setState(() => _status = v ?? 'draft'),
            ),
            const SizedBox(height: 32),
            FilledButton(
              onPressed: _saving ? null : _submit,
              child: _saving
                  ? const SizedBox(
                      width: 24, height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(isEdit ? 'Save Changes' : 'Create Event'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final body = {
      'title': _titleCtrl.text.trim(),
      'eventDate': _dateCtrl.text.trim(),
      if (_locationCtrl.text.trim().isNotEmpty)
        'locationName': _locationCtrl.text.trim(),
      if (_beerTypeCtrl.text.trim().isNotEmpty)
        'beerType': _beerTypeCtrl.text.trim(),
      if (_entryFeeCtrl.text.trim().isNotEmpty)
        'entryFee': _entryFeeCtrl.text.trim(),
      if (_paymentInstructionsCtrl.text.trim().isNotEmpty)
        'paymentInstructions': _paymentInstructionsCtrl.text.trim(),
      'status': _status,
    };

    try {
      final token = await ref.read(tokenProvider.future);
      if (token == null) throw Exception('Not signed in');
      final api = ApiClient(baseUrl: AppConfig.apiBaseUrl);

      if (widget.eventId != null) {
        await api.updateEvent(widget.eventId!, body, token: token);
      } else {
        await api.createEvent(body, token: token);
      }

      ref.invalidate(eventsProvider);
      if (mounted) {
        context.pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(widget.eventId != null
                  ? 'Event updated'
                  : 'Event created')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
