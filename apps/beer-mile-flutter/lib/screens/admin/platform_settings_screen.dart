import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_client.dart';
import '../../api/models/api_admin.dart';
import '../../core/config.dart';
import '../../providers/auth_providers.dart';
import '../../widgets/loading_indicator.dart';

final _platformSettingsProvider =
    FutureProvider<ApiPlatformSettings>((ref) async {
  final token = await ref.watch(tokenProvider.future);
  final api = ApiClient(baseUrl: AppConfig.apiBaseUrl);
  return api.getPlatformSettings(token: token);
});

class PlatformSettingsScreen extends ConsumerStatefulWidget {
  const PlatformSettingsScreen({super.key});

  @override
  ConsumerState<PlatformSettingsScreen> createState() =>
      _PlatformSettingsScreenState();
}

class _PlatformSettingsScreenState
    extends ConsumerState<PlatformSettingsScreen> {
  final _iosCtrl = TextEditingController();
  final _androidCtrl = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _iosCtrl.dispose();
    _androidCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(_platformSettingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Platform Settings')),
      body: settingsAsync.when(
        data: (settings) {
          _iosCtrl.text = settings.appStoreIosUrl ?? '';
          _androidCtrl.text = settings.playStoreAndroidUrl ?? '';
          return _Form(
            iosCtrl: _iosCtrl,
            androidCtrl: _androidCtrl,
            saving: _saving,
            onSave: _save,
          );
        },
        loading: () => const LoadingIndicator(message: 'Loading settings…'),
        error: (e, _) => ErrorView(
          error: e,
          onRetry: () => ref.invalidate(_platformSettingsProvider),
        ),
      ),
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final token = await ref.read(tokenProvider.future);
      if (token == null) throw Exception('Not authenticated');
      final api = ApiClient(baseUrl: AppConfig.apiBaseUrl);
      await api.updatePlatformSettings({
        if (_iosCtrl.text.trim().isNotEmpty)
          'appStoreIosUrl': _iosCtrl.text.trim(),
        if (_androidCtrl.text.trim().isNotEmpty)
          'playStoreAndroidUrl': _androidCtrl.text.trim(),
      }, token: token);
      ref.invalidate(_platformSettingsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Settings saved')),
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

class _Form extends StatelessWidget {
  const _Form({
    required this.iosCtrl,
    required this.androidCtrl,
    required this.saving,
    required this.onSave,
  });

  final TextEditingController iosCtrl;
  final TextEditingController androidCtrl;
  final bool saving;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'These URLs are shown in the app footer to help runners download the latest version.',
        ),
        const SizedBox(height: 24),
        TextFormField(
          controller: iosCtrl,
          decoration: const InputDecoration(
            labelText: 'App Store (iOS) URL',
            hintText: 'https://apps.apple.com/app/...',
            prefixIcon: Icon(Icons.apple),
          ),
          keyboardType: TextInputType.url,
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: androidCtrl,
          decoration: const InputDecoration(
            labelText: 'Google Play (Android) URL',
            hintText: 'https://play.google.com/store/apps/details?id=...',
            prefixIcon: Icon(Icons.android),
          ),
          keyboardType: TextInputType.url,
        ),
        const SizedBox(height: 32),
        FilledButton(
          onPressed: saving ? null : onSave,
          child: saving
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save Settings'),
        ),
      ],
    );
  }
}
