import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../core/config.dart';
import '../api/api_client.dart';
import 'models/user_model.dart';

/// Persists and provides the Clerk JWT session token.
/// Sign-in itself is handled in [SignInScreen] via a WebView.
class AuthRepository {
  AuthRepository({ApiClient? apiClient})
      : _api = apiClient ?? ApiClient(baseUrl: AppConfig.apiBaseUrl);

  static const _kTokenKey = 'clerk_session_token';
  static const _kUserKey = 'current_user';

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  final ApiClient _api;

  // ── Token ──────────────────────────────────────────────────────────────────

  Future<String?> readToken() => _storage.read(key: _kTokenKey);

  Future<void> saveToken(String token) =>
      _storage.write(key: _kTokenKey, value: token);

  Future<void> clearToken() => _storage.delete(key: _kTokenKey);

  // ── User ───────────────────────────────────────────────────────────────────

  Future<AppUser?> readCachedUser() async {
    final raw = await _storage.read(key: _kUserKey);
    if (raw == null) return null;
    try {
      return AppUser.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveUser(AppUser user) =>
      _storage.write(key: _kUserKey, value: jsonEncode(user.toJson()));

  Future<void> _clearUser() => _storage.delete(key: _kUserKey);

  // ── Session lifecycle ──────────────────────────────────────────────────────

  /// Called after WebView sign-in extracts the Clerk JWT.
  /// Provisions the user in the backend and caches their profile.
  Future<AppUser> signIn(String token) async {
    await saveToken(token);
    final user = await _api.provisionUser(token: token);
    await _saveUser(user);
    return user;
  }

  /// Re-hydrate session from secure storage (app restart).
  Future<AppUser?> restoreSession() async {
    final token = await readToken();
    if (token == null) return null;

    try {
      final user = await _api.getMe(token: token);
      await _saveUser(user);
      return user;
    } catch (_) {
      // Token may be expired; cached user returned for offline use
      return readCachedUser();
    }
  }

  /// Sign out — clears token and cached profile.
  Future<void> signOut() async {
    await clearToken();
    await _clearUser();
  }

  /// Update profile and persist.
  Future<AppUser> updateProfile({
    required String token,
    String? preferredName,
    String? gender,
    String? birthdate,
  }) async {
    final user = await _api.updateMe(
      token: token,
      preferredName: preferredName,
      gender: gender,
      birthdate: birthdate,
    );
    await _saveUser(user);
    return user;
  }
}
