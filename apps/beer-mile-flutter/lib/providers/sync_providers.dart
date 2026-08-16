import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config.dart';
import '../database/app_database.dart';
import '../sync/sync_engine.dart';
import 'auth_providers.dart';

final syncEngineProvider = Provider<SyncEngine>((ref) {
  final engine = SyncEngine(
    db: AppDatabase.instance,
    apiBaseUrl: AppConfig.apiBaseUrl,
  );
  ref.onDispose(engine.dispose);

  // Auto-start connectivity listening when user is signed in
  ref.listen(tokenProvider, (_, next) {
    next.whenData((token) => engine.startListening(token));
  });

  return engine;
});

final syncStateProvider = StreamProvider<SyncState>((ref) {
  final engine = ref.watch(syncEngineProvider);
  return engine.stateStream;
});

/// Pending sync count — shown in the sync status banner.
final pendingCountProvider = Provider<int>((ref) {
  return ref.watch(syncStateProvider).valueOrNull?.pendingCount ?? 0;
});
