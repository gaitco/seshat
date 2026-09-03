import 'package:seshat/seshat.dart';
import 'package:seshat/sqlite.dart';
import 'package:test/test.dart';

import 'support/recording_connection.dart';

class CreateTeams extends Migration {
  @override
  Future<void> up(SchemaBuilder schema) => schema.create('teams', (t) {
    t.id();
    t.string('name');
  });

  @override
  Future<void> down(SchemaBuilder schema) => schema.dropIfExists('teams');
}

class CreateUsers extends Migration {
  @override
  Future<void> up(SchemaBuilder schema) => schema.create('users', (t) {
    t.id();
    t.string('email').unique();
    t.foreignId('team_id').constrained().onDelete('cascade');
  });

  @override
  Future<void> down(SchemaBuilder schema) => schema.dropIfExists('users');
}

class AddPhoneToUsers extends Migration {
  @override
  Future<void> up(SchemaBuilder schema) =>
      schema.table('users', (t) => t.string('phone').nullable());

  @override
  Future<void> down(SchemaBuilder schema) =>
      schema.table('users', (t) => t.dropColumn('phone'));
}

class Broken extends Migration {
  @override
  Future<void> up(SchemaBuilder schema) async {
    await schema.create('broken', (t) => t.id());
    throw StateError('boom');
  }

  @override
  Future<void> down(SchemaBuilder schema) => schema.dropIfExists('broken');
}

void main() {
  late SqliteConnection db;
  late SchemaBuilder schema;
  setUp(() {
    db = SqliteConnection.inMemory();
    schema = Schema.on(db);
  });
  tearDown(() => db.close());

  Migrator migrator(List<Migration> migrations) => Migrator(db, migrations);

  test('run, status, batches, rollback, reset, refresh', () async {
    final first = migrator([CreateTeams(), CreateUsers()]);
    expect(await first.run(), ['CreateTeams', 'CreateUsers']);
    expect(await first.run(), isEmpty);
    expect(await schema.hasTable('users'), isTrue);

    final all = migrator([CreateTeams(), CreateUsers(), AddPhoneToUsers()]);
    expect((await all.status()).map((s) => (s.name, s.batch)), [
      ('CreateTeams', 1),
      ('CreateUsers', 1),
      ('AddPhoneToUsers', null),
    ]);
    expect(await all.run(), ['AddPhoneToUsers']);
    expect((await all.status()).last.batch, 2);
    expect(await schema.hasColumn('users', 'phone'), isTrue);

    expect(await all.rollback(), ['AddPhoneToUsers']);
    expect(await schema.hasColumn('users', 'phone'), isFalse);
    expect(await schema.hasTable('users'), isTrue);
    expect((await all.status()).map((s) => s.batch), [1, 1, null]);

    expect(await all.reset(), ['CreateUsers', 'CreateTeams']);
    expect(await schema.hasTable('users'), isFalse);
    expect(await schema.hasTable('teams'), isFalse);
    expect((await all.status()).every((s) => s.isPending), isTrue);

    expect(await all.refresh(), [
      'CreateTeams',
      'CreateUsers',
      'AddPhoneToUsers',
    ]);
    expect((await all.status()).map((s) => s.batch), [1, 1, 1]);
    expect(await all.refresh(), hasLength(3));
  });

  test('rollback steps spans batches', () async {
    await migrator([CreateTeams()]).run();
    final m = migrator([CreateTeams(), CreateUsers(), AddPhoneToUsers()]);
    await m.run();
    expect(await m.rollback(steps: 2), [
      'AddPhoneToUsers',
      'CreateUsers',
      'CreateTeams',
    ]);
  });

  test('failing migration leaves no row and no table', () async {
    final log = <String>[];
    final m = Migrator(db, [CreateTeams(), Broken()], log: log.add);
    await expectLater(m.run(), throwsStateError);
    expect(await schema.hasTable('teams'), isTrue);
    expect(await schema.hasTable('broken'), isFalse);
    expect((await m.status()).map((s) => s.batch), [1, null]);
    expect(log, ['Migrated: CreateTeams']);
  });

  test('duplicate names throw', () {
    expect(
      () => migrator([CreateTeams(), CreateTeams()]),
      throwsA(isA<DatabaseException>()),
    );
  });

  test('unregistered ran migration cannot be rolled back', () async {
    await migrator([CreateTeams()]).run();
    expect(
      () => migrator([CreateUsers()]).reset(),
      throwsA(isA<DatabaseException>()),
    );
  });

  test('repository SQL is quoted through the connection grammar', () async {
    registerSchemaGrammar('mysql', const FakeMysqlSchemaGrammar());
    final db = RecordingConnection();
    final m = Migrator(db, const []);
    await m.status();
    // The migrator's own raw SQL (the final `select ... from migrations`
    // it issues, past the repository's create-table DDL) must be quoted
    // through the connection grammar's backticks, not hard-coded ANSI
    // double quotes.
    final select = db.sqlLog.last;
    expect(select, contains('`migration`'));
    expect(select, contains('`batch`'));
    expect(select, isNot(contains('"migration"')));
  });

  group('console', () {
    test('migrate:status prints names and returns 0', () async {
      final m = migrator([CreateTeams(), CreateUsers()]);
      final out = StringBuffer();
      expect(await runMigrationConsole(['migrate'], m, out: out), 0);
      expect(await runMigrationConsole(['migrate:status'], m, out: out), 0);
      final text = out.toString();
      expect(text, contains('Migrated: CreateTeams'));
      expect(text, contains('CreateUsers'));
      expect(text, contains('1'));
    });
    test('rollback --step and refresh', () async {
      final m = migrator([CreateTeams(), CreateUsers()]);
      final out = StringBuffer();
      await runMigrationConsole(['migrate'], m, out: out);
      expect(
        await runMigrationConsole(
          ['migrate:rollback', '--step=1'],
          m,
          out: out,
        ),
        0,
      );
      expect(await schema.hasTable('teams'), isFalse);
      expect(await runMigrationConsole(['migrate:refresh'], m, out: out), 0);
      expect(await schema.hasTable('teams'), isTrue);
      expect(await runMigrationConsole(['migrate:reset'], m, out: out), 0);
      expect(out.toString(), contains('Rolled back: CreateUsers'));
    });
    test('unknown command prints usage and returns 1', () async {
      final err = StringBuffer();
      expect(await runMigrationConsole(['nope'], migrator([]), err: err), 1);
      expect(err.toString(), contains('Usage'));
      expect(await runMigrationConsole([], migrator([]), err: err), 1);
    });
  });
}
