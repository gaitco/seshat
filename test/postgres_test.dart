// Runs only when PG_TEST_URL is set, e.g.
//   PG_TEST_URL=postgres://postgres@127.0.0.1:54329/seshat_test dart test test/postgres_test.dart
@Tags(['postgres'])
library;

import 'dart:io';

import 'package:seshat/seshat.dart';
import 'package:seshat/postgres.dart';
import 'package:test/test.dart';

import 'support/models.dart';

Future<PostgresConnection> _open(Uri url) => PostgresConnection.open(
  host: url.host,
  port: url.port,
  database: url.path.substring(1),
  username: url.userInfo.split(':').first,
  password: url.userInfo.contains(':') ? url.userInfo.split(':').last : null,
);

Future<void> _schema(Connection db) async {
  for (final t in [
    'comments',
    'posts',
    'profiles',
    'role_user',
    'roles',
    'users',
    'settings',
  ]) {
    await db.execute('drop table if exists $t cascade');
  }
  await db.execute('''
    create table users (
      id bigserial primary key, name text not null, email text not null unique,
      active boolean not null default true, role text not null default 'member',
      age integer, meta jsonb, created_at timestamp, updated_at timestamp,
      deleted_at timestamp)''');
  await db.execute('create table settings (key text primary key, value text)');
  await db.execute('''
    create table posts (
      id bigserial primary key, user_id bigint not null references users(id),
      title text not null, published boolean not null default false,
      created_at timestamp, updated_at timestamp)''');
  await db.execute('''
    create table comments (
      id bigserial primary key, post_id bigint not null references posts(id),
      body text not null, created_at timestamp, updated_at timestamp)''');
  await db.execute('''
    create table profiles (
      id bigserial primary key, user_id bigint not null unique references users(id),
      bio text, created_at timestamp, updated_at timestamp)''');
  await db.execute(
    'create table roles (id bigserial primary key, name text not null)',
  );
  await db.execute('''
    create table role_user (
      user_id bigint not null references users(id),
      role_id bigint not null references roles(id),
      granted_by text, primary key (user_id, role_id))''');
}

void main() {
  final url = Platform.environment['PG_TEST_URL'];
  if (url == null) {
    test('postgres adapter (skipped: set PG_TEST_URL)', () {}, skip: true);
    return;
  }
  late PostgresConnection db;
  setUp(() async {
    db = await _open(Uri.parse(url));
    DB.use(db);
    await _schema(db);
    User.log.clear();
  });
  tearDown(() => db.close());

  test('connection failure is a ConnectionException', () async {
    expect(
      () => PostgresConnection.open(host: '127.0.0.1', port: 1, database: 'x'),
      throwsA(isA<ConnectionException>()),
    );
  });

  test('create, casts, find, unique violation', () async {
    final u = await User.create({
      'name': 'Ann',
      'email': 'ann@x.test',
      'role': Role.admin,
      'meta': {'plan': 'pro'},
      'active': false,
    });
    expect(u.id, 1);
    final loaded = await User.findOrFail(1);
    expect(loaded.role, Role.admin);
    expect(loaded.meta, {'plan': 'pro'});
    expect(loaded.active, isFalse);
    expect(loaded.createdAt, isA<DateTime>());
    expect(
      () => User.create({'name': 'B', 'email': 'ann@x.test'}),
      throwsA(isA<UniqueConstraintException>()),
    );
  });

  test('query builder: where, like/ilike, aggregates, pagination', () async {
    for (var i = 1; i <= 5; i++) {
      await User.create({'name': 'User $i', 'email': 'u$i@x.test', 'age': i});
    }
    expect(
      await User.query()
          .whereLike('name', 'user%', caseInsensitive: true)
          .count(),
      5,
    );
    expect(await User.query().whereLike('name', 'user%').count(), 0);
    expect(await User.query().sum('age'), 15);
    final page = await User.query().orderBy('id').paginate(page: 2, perPage: 2);
    expect(page.data.map((u) => u.id), [3, 4]);
    expect(page.total, 5);
    expect(
      await User.query().where('age', '>', 3).update({'active': false}),
      2,
    );
    expect(await User.query().where('active', false).pluck('name'), [
      'User 4',
      'User 5',
    ]);
  });

  test('transactions commit, roll back, and nest with savepoints', () async {
    await db.transaction((tx) async {
      await User.using(tx).create({'name': 'Outer', 'email': 'o@x.test'});
      try {
        await tx.transaction((inner) async {
          await User.using(
            inner,
          ).create({'name': 'Inner', 'email': 'i@x.test'});
          throw StateError('inner');
        });
      } on StateError {
        // swallowed
      }
    });
    expect(await User.query().pluck('name'), ['Outer']);
    await expectLater(
      db.transaction((tx) async {
        await User.using(tx).create({'name': 'Gone', 'email': 'g@x.test'});
        throw StateError('outer');
      }),
      throwsStateError,
    );
    expect(await User.query().count(), 1);
  });

  test('independent queries use the pool concurrently', () async {
    final watch = Stopwatch()..start();
    await Future.wait([
      db.select('select pg_sleep(0.2)'),
      db.select('select pg_sleep(0.2)'),
    ]);

    expect(watch.elapsedMilliseconds, lessThan(350));
  });

  test('relations and eager loading', () async {
    final ann = await User.create({'name': 'Ann', 'email': 'ann@x.test'});
    await ann.posts().create({'title': 'P1', 'published': true});
    await ann.posts().create({'title': 'P2'});
    await RoleModel.query().create({'name': 'admin'});
    await ann.roles().attach(1, {'granted_by': 'root'});
    db.enableQueryLog();
    final users = await User.with_(['posts', 'roles']).get();
    expect(db.queryLog.length, 3);
    expect(users.single.posts().value.map((p) => p.title), ['P1', 'P2']);
    expect(users.single.roles().value.single.pivot?['granted_by'], 'root');
    expect(
      await User.query()
          .whereHas('posts', (q) => q.where('published', true))
          .count(),
      1,
    );
  });

  test('soft deletes', () async {
    final ann = await User.create({'name': 'Ann', 'email': 'ann@x.test'});
    await ann.delete();
    expect(await User.query().count(), 0);
    expect(await User.onlyTrashed().count(), 1);
    await ann.restore();
    expect(await User.query().count(), 1);
    await User.query().truncate();
    expect(await User.withTrashed().count(), 0);
  });
}
