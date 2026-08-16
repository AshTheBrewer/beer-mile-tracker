import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import 'app.dart';
import 'auth/auth_migrations.dart';
import 'database/app_database.dart';
import 'sync/sync_engine.dart';

/// WorkManager callback — runs in a background isolate within the same
/// Android process.  Flutter bindings must be initialised before any Flutter
/// plugin (e.g. FlutterSecureStorage) is accessed.
///
/// Design: the token is read from FlutterSecureStorage (EncryptedSharedPrefs
/// on Android) — the same encrypted store the foreground session uses.  There
/// is no plaintext copy: if no token is available background sync is skipped.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task == SyncEngine.kBackgroundSyncTask) {
      try {
        // Flutter bindings must be initialised before using any platform channel.
        WidgetsFlutterBinding.ensureInitialized();

        const storage = FlutterSecureStorage(
          aOptions: AndroidOptions(encryptedSharedPreferences: true),
        );
        final token = await storage.read(key: 'clerk_session_token');

        // Skip silently if the user is not signed in (e.g. after sign-out).
        if (token == null) return Future.value(true);

        final db = AppDatabase.instance;
        await db.init();

        final engine = SyncEngine(
          db: db,
          apiBaseUrl: const String.fromEnvironment(
            'API_BASE_URL',
            defaultValue: '',
          ),
        );
        await engine.syncPendingLogs(token: token);
      } catch (_) {
        // Best-effort: never crash the WorkManager task.
      }
    }
    return Future.value(true);
  });
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Run one-time security migrations (purge legacy plaintext SharedPreferences
  // entries that pre-date encrypted-storage-only storage policy).
  await AuthMigrations.run();

  // Initialise local SQLite database
  await AppDatabase.instance.init();

  // Register background sync with WorkManager
  await Workmanager().initialize(callbackDispatcher, isInDebugMode: false);
  await Workmanager().registerPeriodicTask(
    SyncEngine.kBackgroundSyncTask,
    SyncEngine.kBackgroundSyncTask,
    frequency: const Duration(minutes: 15),
    constraints: Constraints(networkType: NetworkType.connected),
    existingWorkPolicy: ExistingWorkPolicy.keep,
  );

  runApp(const ProviderScope(child: BeerMileApp()));
}
