import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:beer_mile/auth/auth_migrations.dart';

void main() {
  group('AuthMigrations.run()', () {
    setUp(() async {
      // Reset SharedPreferences to a clean state before each test.
      SharedPreferences.setMockInitialValues({});
    });

    test(
        'v1 — removes legacy bg_sync_token when it exists in SharedPreferences',
        () async {
      // Simulate a device that ran the old build which wrote a plaintext token.
      SharedPreferences.setMockInitialValues({
        AuthMigrations.kLegacyBgSyncToken: 'old.jwt.token',
      });

      await AuthMigrations.run();

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.containsKey(AuthMigrations.kLegacyBgSyncToken),
        isFalse,
        reason: 'Migration should have deleted the legacy plaintext JWT key',
      );
    });

    test('v1 — no-ops cleanly when bg_sync_token is absent (fresh install)',
        () async {
      // SharedPreferences is already empty (set in setUp).
      await expectLater(
        AuthMigrations.run(),
        completes,
        reason: 'Migration should succeed even when the key was never present',
      );

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.containsKey(AuthMigrations.kLegacyBgSyncToken),
        isFalse,
      );
    });

    test('v1 — does not disturb unrelated SharedPreferences keys', () async {
      SharedPreferences.setMockInitialValues({
        AuthMigrations.kLegacyBgSyncToken: 'old.jwt.token',
        'some_other_key': 'value_that_must_survive',
      });

      await AuthMigrations.run();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('some_other_key'), equals('value_that_must_survive'));
    });

    test('v1 — is idempotent (safe to run multiple times)', () async {
      SharedPreferences.setMockInitialValues({
        AuthMigrations.kLegacyBgSyncToken: 'old.jwt.token',
      });

      await AuthMigrations.run();
      await AuthMigrations.run(); // second invocation must not throw

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey(AuthMigrations.kLegacyBgSyncToken), isFalse);
    });
  });
}
