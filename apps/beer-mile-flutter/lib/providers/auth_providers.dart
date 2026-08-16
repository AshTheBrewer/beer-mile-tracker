import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_repository.dart';
import '../auth/models/user_model.dart';
import '../core/config.dart';
import '../api/api_client.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(
    apiClient: ApiClient(baseUrl: AppConfig.apiBaseUrl),
  );
});

/// The currently signed-in user, or null.  Loading = checking secure storage.
final authStateProvider =
    AsyncNotifierProvider<AuthNotifier, AppUser?>(() => AuthNotifier());

class AuthNotifier extends AsyncNotifier<AppUser?> {
  @override
  Future<AppUser?> build() async {
    final repo = ref.read(authRepositoryProvider);
    return repo.restoreSession();
  }

  Future<void> signInWithToken(String token) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final repo = ref.read(authRepositoryProvider);
      return repo.signIn(token);
    });
  }

  Future<void> signOut() async {
    final repo = ref.read(authRepositoryProvider);
    await repo.signOut();
    state = const AsyncValue.data(null);
  }

  Future<void> updateProfile({
    String? preferredName,
    String? gender,
    String? birthdate,
  }) async {
    final repo = ref.read(authRepositoryProvider);
    final token = await repo.readToken();
    if (token == null) return;
    state = await AsyncValue.guard(() => repo.updateProfile(
          token: token,
          preferredName: preferredName,
          gender: gender,
          birthdate: birthdate,
        ));
  }
}

/// Convenience provider — current user's JWT, or null.
final tokenProvider = FutureProvider<String?>((ref) async {
  ref.watch(authStateProvider); // invalidate when auth changes
  final repo = ref.read(authRepositoryProvider);
  return repo.readToken();
});
