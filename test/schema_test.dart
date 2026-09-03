import 'package:seshat/seshat.dart';
import 'package:seshat/sqlite.dart';
import 'package:test/test.dart';

Blueprint usersBlueprint() => Blueprint('users')
  ..id()
  ..string('name')
  ..string('email').unique()
  ..boolean('active').defaultValue(false)
  ..foreignId('team_id').constrained().onDelete('cascade')
  ..decimal('balance')
  ..timestamps()
  ..softDeletes()
  ..index(['name']);

void main() {
  group('compiled DDL', () {
    test('sqlite create', () {
      expect(const SqliteSchemaGrammar().compileCreate(usersBlueprint()), [
        'create table "users" ('
            '"id" integer primary key autoincrement not null, '
            '"name" text not null, '
            '"email" text not null, '
            '"active" integer not null default 0, '
            '"team_id" integer not null references "teams" ("id") on delete cascade, '
            '"balance" numeric not null, '
            '"created_at" text null, '
            '"updated_at" text null, '
            '"deleted_at" text null)',
        'create unique index "users_email_unique" on "users" ("email")',
        'create index "users_name_index" on "users" ("name")',
      ]);
    });
    test('postgres create', () {
      expect(const PostgresSchemaGrammar().compileCreate(usersBlueprint()), [
        'create table "users" ('
            '"id" bigserial primary key not null, '
            '"name" varchar(255) not null, '
            '"email" varchar(255) not null, '
            '"active" boolean not null default false, '
            '"team_id" bigint not null references "teams" ("id") on delete cascade, '
            '"balance" numeric(8, 2) not null, '
            '"created_at" timestamp null, '
            '"updated_at" timestamp null, '
            '"deleted_at" timestamp null)',
        'create unique index "users_email_unique" on "users" ("email")',
        'create index "users_name_index" on "users" ("name")',
      ]);
    });
    test('alter, drop, rename, string defaults and raw defaults', () {
      const g = PostgresSchemaGrammar();
      final b = Blueprint('users')
        ..string('nick').nullable().defaultValue("o'k")
        ..timestamp('seen_at').useCurrent()
        ..json('meta').defaultValue(const RawSql("'{}'::jsonb"))
        ..dropColumn('old')
        ..renameColumn('a', 'b')
        ..dropIndex('users_a_index')
        ..unique(['x', 'y']);
      expect(g.compileAlter(b), [
        'alter table "users" add column "nick" varchar(255) null default \'o\'\'k\'',
        'alter table "users" add column "seen_at" timestamp not null default current_timestamp',
        'alter table "users" add column "meta" jsonb not null default \'{}\'::jsonb',
        'alter table "users" drop column "old"',
        'alter table "users" rename column "a" to "b"',
        'drop index "users_a_index"',
        'create unique index "users_x_y_unique" on "users" ("x", "y")',
      ]);
      expect(g.compileDrop('users'), 'drop table "users"');
      expect(g.compileDropIfExists('users'), 'drop table if exists "users"');
      expect(g.compileRename('a', 'b'), 'alter table "a" rename to "b"');
      expect(g.compileTableExists().$1, contains('pg_tables'));
      expect(g.compileColumnListing('users').$2, ['users']);
    });
    test('invalid identifiers throw', () {
      expect(
        () => Blueprint('users; drop'),
        throwsA(isA<InvalidIdentifierException>()),
      );
      expect(
        () => Blueprint('users').string('bad name'),
        throwsA(isA<InvalidIdentifierException>()),
      );
      expect(
        () => Blueprint('users').index(['a"b']),
        throwsA(isA<InvalidIdentifierException>()),
      );
      expect(
        () => Blueprint('users').foreignId('x_id').constrained('te ams'),
        throwsA(isA<InvalidIdentifierException>()),
      );
    });
    test('invalid default value throws', () {
      expect(
        () => Blueprint('t').string('a').defaultValue(DateTime(2020)),
        throwsArgumentError,
      );
    });
    test('invalid onDelete action throws', () {
      expect(
        () => Blueprint('t').foreignId('u_id').constrained().onDelete('drop'),
        throwsArgumentError,
      );
    });
    test('sqlite rejects adding a primary key by alter', () {
      expect(
        () => const SqliteSchemaGrammar().compileAlter(
          Blueprint('t')..primary(['a']),
        ),
        throwsA(isA<DatabaseException>()),
      );
    });
  });

  group('sqlite execution', () {
    late SqliteConnection db;
    late SchemaBuilder schema;
    setUp(() {
      db = SqliteConnection.inMemory();
      schema = Schema.on(db);
    });
    tearDown(() => db.close());

    Future<void> createTables() async {
      await schema.create('teams', (t) {
        t.id();
        t.string('name');
      });
      await schema.create('users', (t) {
        t.id();
        t.string('email').unique();
        t.foreignId('team_id').constrained().onDelete('cascade');
        t.timestamps();
      });
    }

    test('create, hasTable, hasColumn, columnListing', () async {
      await createTables();
      expect(await schema.hasTable('users'), isTrue);
      expect(await schema.hasTable('nope'), isFalse);
      expect(await schema.hasColumn('users', 'email'), isTrue);
      expect(await schema.hasColumn('users', 'phone'), isFalse);
      expect(await schema.columnListing('users'), [
        'id',
        'email',
        'team_id',
        'created_at',
        'updated_at',
      ]);
    });
    test('alter: add column, insert into it, drop column', () async {
      await createTables();
      await schema.table('teams', (t) => t.string('slug').nullable());
      await db.execute('insert into "teams" ("name", "slug") values (?, ?)', [
        'A',
        'a',
      ]);
      final rows = await db.select('select "slug" from "teams"');
      expect(rows.single['slug'], 'a');
      await schema.table('teams', (t) => t.dropColumn('slug'));
      expect(await schema.columnListing('teams'), ['id', 'name']);
    });
    test('rename table and dropIfExists is idempotent', () async {
      await createTables();
      await schema.rename('teams', 'squads');
      expect(await schema.hasTable('squads'), isTrue);
      expect(await schema.hasTable('teams'), isFalse);
      await schema.dropIfExists('squads');
      await schema.dropIfExists('squads');
      expect(await schema.hasTable('squads'), isFalse);
    });
    test('foreign keys are enforced', () async {
      await createTables();
      expect(
        () => db.execute(
          'insert into "users" ("email", "team_id") values (?, ?)',
          ['a@x.test', 99],
        ),
        throwsA(isA<QueryException>()),
      );
    });
    test('Schema statics use the default connection', () async {
      DB.use(db);
      addTearDown(DB.reset);
      await Schema.create('notes', (t) => t.id());
      expect(await Schema.hasTable('notes'), isTrue);
      await Schema.dropIfExists('notes');
      expect(await Schema.hasTable('notes'), isFalse);
    });
  });
}
