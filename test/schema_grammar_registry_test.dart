import 'package:seshat/seshat.dart';
import 'package:seshat/sqlite.dart';
import 'package:test/test.dart';

import 'support/recording_connection.dart';

void main() {
  test('sqlite connection resolves SqliteSchemaGrammar', () {
    final db = SqliteConnection.inMemory();
    addTearDown(db.close);
    expect(schemaGrammarFor(db), isA<SqliteSchemaGrammar>());
  });

  test('unregistered driver throws DatabaseException naming the driver', () {
    final db = RecordingConnection();
    expect(
      () => schemaGrammarFor(db),
      throwsA(
        isA<DatabaseException>().having(
          (e) => e.message,
          'message',
          allOf(contains('mysql'), contains('registerSchemaGrammar')),
        ),
      ),
    );
  });

  test('registerSchemaGrammar makes a driver resolvable', () {
    final db = RecordingConnection();
    final fake = const FakeMysqlSchemaGrammar();
    registerSchemaGrammar('mysql', fake);
    expect(schemaGrammarFor(db), same(fake));
  });
}
