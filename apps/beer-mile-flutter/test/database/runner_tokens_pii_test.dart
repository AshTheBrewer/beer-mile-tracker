// ignore_for_file: avoid_relative_lib_imports

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:beer_mile/database/app_database.dart';

/// Regression tests that verify the runner_tokens table never stores PII.
///
/// These tests guard against accidental reintroduction of display_name, email,
/// or other personal data fields into the local SQLite database.
/// See SECURITY.md for the full on-device / server-only data boundary.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
  });

  group('runner_tokens schema — PII boundary', () {
    test('kRunnerTokensDdl does not declare a display_name column', () {
      expect(
        AppDatabase.kRunnerTokensDdl.toLowerCase().contains('display_name'),
        isFalse,
        reason: 'runner_tokens must not declare a display_name column '
            '(PII — see SECURITY.md)',
      );
    });

    test('kRunnerTokensDdl declares no personal data fields', () {
      final ddl = AppDatabase.kRunnerTokensDdl.toLowerCase();
      const forbidden = [
        'display_name',
        'preferred_name',
        'email',
        'gender',
        'birthdate',
        'birth_date',
        'phone',
      ];
      for (final field in forbidden) {
        expect(
          ddl.contains(field),
          isFalse,
          reason: '"$field" must not appear in the runner_tokens DDL '
              '(PII — see SECURITY.md)',
        );
      }
    });

    test('kRunnerTokensDdl contains exactly the four permitted columns', () {
      final ddl = AppDatabase.kRunnerTokensDdl.toLowerCase();
      expect(ddl.contains('runner_token'), isTrue);
      expect(ddl.contains('registration_id'), isTrue);
      expect(ddl.contains('event_id'), isTrue);
      expect(ddl.contains('user_id'), isTrue);
    });

    test('in-memory table created from kRunnerTokensDdl has no display_name',
        () async {
      sqfliteFfiInit();
      final factory = databaseFactoryFfi;
      final db = await factory.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, _) async {
            await db.execute(AppDatabase.kRunnerTokensDdl);
          },
        ),
      );

      // Successful insert with only the four permitted columns.
      await db.insert('runner_tokens', {
        'runner_token': 'token-abc123',
        'registration_id': 42,
        'event_id': 7,
        'user_id': 'user_clerk_xyz',
      });

      final rows = await db.query('runner_tokens');
      expect(rows.length, equals(1));
      final row = rows.first;

      expect(row.containsKey('display_name'), isFalse,
          reason: 'display_name must not exist in runner_tokens rows');
      expect(row['registration_id'], equals(42));
      expect(row['event_id'], equals(7));
      expect(row['user_id'], equals('user_clerk_xyz'));

      await db.close();
    });

    test('inserting display_name into runner_tokens throws DatabaseException',
        () async {
      sqfliteFfiInit();
      final factory = databaseFactoryFfi;
      final db = await factory.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, _) async {
            await db.execute(AppDatabase.kRunnerTokensDdl);
          },
        ),
      );

      // Attempting to write PII to the table must fail because the column
      // does not exist in the schema.
      await expectLater(
        () => db.insert('runner_tokens', {
          'runner_token': 'token-xyz',
          'registration_id': 1,
          'event_id': 1,
          'user_id': 'user_a',
          'display_name': 'Alice Runner', // ← PII that must be rejected
        }),
        throwsA(isA<DatabaseException>()),
        reason: 'Inserting display_name must throw — column must not exist',
      );

      await db.close();
    });
  });
}
