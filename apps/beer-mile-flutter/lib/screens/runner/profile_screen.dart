import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/auth_providers.dart';
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
