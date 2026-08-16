import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One-time security migrations for the auth subsystem.
///
/// Each migration is idempotent: running it multiple times has the same
/// effect as running it once.  Add new migrations as static methods and call
/// them from [run].
///
/// ### v1 — purge legacy plaintext JWT
/// An earlier build mirrored the Clerk session token from
/// FlutterSecureStorage into SharedPreferences under the key `bg_sync_token`
/// so that the WorkManager background isolate could read it without
/// initialising the Flutter engine.  This left a reusable bearer token in
/// ordinary (unencrypted) app storage, accessible via device backups, ADB
/// data extraction, and rooted-device inspection.
///
/// The WorkManager callback now uses WidgetsFlutterBinding.ensureInitialized()
/// and reads the token directly from FlutterSecureStorage
/// (EncryptedSharedPreferences on Android), so the plaintext copy is no
/// longer written.  This migration removes any existing plaintext copy on
/// devices that ran the old build.
class AuthMigrations {
  AuthMigrations._();

  /// Legacy SharedPreferences key that stored a plaintext copy of the JWT.
  /// Kept here only so this migration can delete it.
  @visibleForTesting
  static const kLegacyBgSyncToken = 'bg_sync_token';

  /// Run all migrations.  Safe to call on every cold start.
  static Future<void> run() async {
    await _v1PurgeLegacyPlaintextToken();
  }

  /// v1: Remove the plaintext JWT from SharedPreferences if it exists.
  static Future<void> _v1PurgeLegacyPlaintextToken() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.containsKey(kLegacyBgSyncToken)) {
      await prefs.remove(kLegacyBgSyncToken);
    }
  }
}
