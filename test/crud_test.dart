import 'package:maat_seshat_core/maat_seshat_core.dart';
import 'package:maat_seshat_core/sqlite.dart';
import 'package:test/test.dart';

import 'support/models.dart';

void main() {
  late SqliteConnection db;
  setUp(() async => db = await setUpDatabase());
  tearDown(() => db.close());

  group('create', () {
    test('inserts, returns key, timestamps and flags', () async {
      final user = await User.create({'name': 'Ann', 'email': 'ann@x.test'});
      expect(user.id, 1);
      expect(user.exists, isTrue);
      expect(user.wasRecentlyCreated, isTrue);
      expect(user.createdAt, isNotNull);
      expect(user.updatedAt, isNotNull);
      expect(user.active, isTrue);
      expect(await User.query().count(), 1);
    });
    test('casts round-trip: bool, enum, json, dates', () async {
      final created = await User.create({
        'name': 'Bo',
        'email': 'bo@x.test',
        'active': false,
        'role': Role.admin,
        'meta': {'plan': 'pro', 'n': 2},
      });
      final loaded = await User.findOrFail(created.id!);
      expect(loaded.active, isFalse);
      expect(loaded.role, Role.admin);
      expect(loaded.meta, {'plan': 'pro', 'n': 2});
      expect(loaded.createdAt, isA<DateTime>());
      expect(loaded.wasRecentlyCreated, isFalse);
      final raw = await DB.table('users').where('id', created.id).first();
      expect(raw!['active'], 0);
      expect(raw['role'], 'admin');
      expect(raw['meta'], '{"plan":"pro","n":2}');
    });
    test(
      'mass assignment drops unfillable attributes silently when fillable is set',
      () async {
        final user = await User.create({
          'name': 'C',
          'email': 'c@x.test',
          'id': 99,
        });
        expect(user.id, 1);
      },
    );
    test('totally guarded model throws on mass assignment', () async {
      expect(
        () => Setting.query().create({'key': 'a', 'value': 'b'}),
        throwsA(isA<MassAssignmentException>()),
      );
      final s = await Setting.query().forceCreate({'key': 'a', 'value': 'b'});
      expect(s.key, 'a');
      expect(s.exists, isTrue);
      expect((await Setting.query().find('a'))?.value, 'b');
    });
    test('missing required attribute is a clear error', () async {
      expect(
        () => User.create({'email': 'x@x.test'}),
        throwsA(
          isA<DatabaseException>().having(
            (e) => e.message,
            'message',
            contains('User.fromMap failed'),
          ),
        ),
      );
    });
    test('duplicate unique email', () async {
      await User.create({'name': 'A', 'email': 'dup@x.test'});
      expect(
        () => User.create({'name': 'B', 'email': 'dup@x.test'}),
        throwsA(isA<UniqueConstraintException>()),
      );
    });
    test('creating hook can veto', () async {
      final user = await User.create({
        'name': 'Spam',
        'email': 'x@blocked.test',
      });
      expect(user.exists, isFalse);
      expect(await User.query().count(), 0);
    });
    test('events fire in order', () async {
      final u = await User.create({'name': 'E', 'email': 'e@x.test'});
      final u2 = await u.update({'name': 'E2'});
      await u2.delete();
      expect(User.log, ['created E', 'updated E2', 'deleted E2']);
    });
    test('save() on a new instance inserts', () async {
      final saved = await User(name: 'S', email: 's@x.test').save();
      expect(saved.id, 1);
      expect(saved.exists, isTrue);
    });
  });

  group('read', () {
    setUp(() async {
      for (var i = 1; i <= 5; i++) {
        await User.create({
          'name': 'User $i',
          'email': 'u$i@x.test',
          'active': i.isOdd,
          'age': i * 10,
        });
      }
    });
    test('find, findOrFail, first, firstOrFail, exists', () async {
      expect((await User.find(2))?.name, 'User 2');
      expect(await User.find(99), isNull);
      expect(() => User.findOrFail(99), throwsA(isA<ModelNotFoundException>()));
      expect((await User.query().where('email', 'u3@x.test').first())?.id, 3);
      expect(await User.query().where('email', 'nope').firstOrNull(), isNull);
      expect(
        () => User.query().where('email', 'nope').firstOrFail(),
        throwsA(isA<ModelNotFoundException>()),
      );
      expect(await User.query().where('age', '>', 40).exists(), isTrue);
      expect(await User.query().where('age', '>', 50).doesntExist(), isTrue);
    });
    test('get with where, like, order, limit', () async {
      final users = await User.query()
          .where('active', true)
          .whereLike('name', '%User%')
          .orderBy('age', descending: true)
          .limit(2)
          .get();
      expect(users.map((u) => u.name), ['User 5', 'User 3']);
    });
    test('local scopes via extension', () async {
      final users = await User.query().active().recent().get();
      expect(users.length, 3);
    });
    test('aggregates', () async {
      expect(await User.query().count(), 5);
      expect(await User.query().where('active', true).count(), 3);
      expect(await User.query().sum('age'), 150);
      expect(await User.query().avg('age'), 30);
      expect(await User.query().min('age'), 10);
      expect(await User.query().max('age'), 50);
      expect(await User.query().distinct().select(['active']).count(), 2);
      expect(await User.query().groupBy(['active']).count(), 2);
    });
    test('pluck and value', () async {
      expect(await User.query().orderBy('id').pluck('name'), [
        'User 1',
        'User 2',
        'User 3',
        'User 4',
        'User 5',
      ]);
      expect(await User.query().where('id', '<', 3).pluck('name', 'id'), {
        1: 'User 1',
        2: 'User 2',
      });
      expect(await User.query().orderBy('id').value('email'), 'u1@x.test');
    });
    test('paginate', () async {
      final page = await User.query()
          .orderBy('id')
          .paginate(page: 2, perPage: 2);
      expect(page.data.map((u) => u.id), [3, 4]);
      expect(page.total, 5);
      expect(page.lastPage, 3);
      expect(page.currentPage, 2);
      expect(page.hasMorePages, isTrue);
      expect(page.from, 3);
      expect(page.to, 4);
      final last = await User.query().paginate(page: 3, perPage: 2);
      expect(last.hasMorePages, isFalse);
      expect(last.data.length, 1);
      final empty = await User.query().where('id', 0).paginate();
      expect(empty.total, 0);
      expect(empty.lastPage, 1);
      expect(empty.toJson()['data'], isEmpty);
    });
    test('chunk and lazy stream by pages', () async {
      db.enableQueryLog();
      final seen = <int>[];
      await User.query().chunk(2, (rows) {
        seen.addAll(rows.map((u) => u.id!));
        return true;
      });
      expect(seen, [1, 2, 3, 4, 5]);
      expect(db.queryLog.length, 3);
      db.flushQueryLog();
      final streamed = await User.query()
          .lazy(chunkSize: 4)
          .map((u) => u.id)
          .toList();
      expect(streamed, [1, 2, 3, 4, 5]);
      expect(db.queryLog.length, 2);
    });
    test('DB.table returns plain rows', () async {
      final rows = await DB
          .table('users')
          .select(['id', 'name'])
          .where('id', 1)
          .get();
      expect(rows, [
        {'id': 1, 'name': 'User 1'},
      ]);
    });
    test('query log and listener observe statements', () async {
      final seen = <QueryEvent>[];
      db.listen(seen.add);
      await User.query().where('id', 1).first();
      expect(seen.single.sql, contains('where "id" = ?'));
      expect(seen.single.bindings, [1]);
    });
  });

  group('update', () {
    test(
      'update() writes only dirty columns and returns a new instance',
      () async {
        final user = await User.create({'name': 'A', 'email': 'a@x.test'});
        db.enableQueryLog();
        final updated = await user.update({'name': 'B'});
        expect(updated.name, 'B');
        expect(updated.id, user.id);
        expect(user.name, 'A', reason: 'models are immutable');
        final sql = db.queryLog.single.sql;
        expect(
          sql,
          startsWith('update "users" set "name" = ?, "updated_at" = ?'),
        );
        expect((await User.findOrFail(user.id!)).name, 'B');
      },
    );
    test('no-op update issues no query', () async {
      final user = await User.create({'name': 'A', 'email': 'a@x.test'});
      db.enableQueryLog();
      await user.update({'name': 'A'});
      expect(db.queryLog, isEmpty);
    });
    test('fill + save, forceUpdate bypasses guard', () async {
      final user = await User.create({'name': 'A', 'email': 'a@x.test'});
      final filled = user.fill({'age': 30});
      expect(filled.isDirty, isTrue);
      expect(filled.dirty, {'age': 30});
      final saved = await filled.save();
      expect(saved.age, 30);
      final forced = await saved.forceUpdate({'id': 7});
      expect(forced.id, 7);
      expect(await User.find(7), isNotNull);
    });
    test('bulk update, increment, decrement', () async {
      await User.create({'name': 'A', 'email': 'a@x.test', 'age': 1});
      await User.create({'name': 'B', 'email': 'b@x.test', 'age': 1});
      expect(await User.query().update({'active': false}), 2);
      expect(await User.query().where('name', 'A').increment('age', 5), 1);
      expect(await User.query().where('name', 'B').decrement('age'), 1);
      expect(await User.query().pluck('age', 'name'), {'A': 6, 'B': 0});
    });
    test('update on a never-saved model throws', () async {
      final u = User(name: 'x', email: 'x@x.test');
      expect(
        () => u.update({'name': 'y'}),
        throwsA(isA<ModelNotPersistedException>()),
      );
    });
    test('firstOrCreate and updateOrCreate', () async {
      final a = await User.query().firstOrCreate(
        {'email': 'a@x.test'},
        {'name': 'A'},
      );
      final again = await User.query().firstOrCreate(
        {'email': 'a@x.test'},
        {'name': 'Z'},
      );
      expect(again.id, a.id);
      expect(again.name, 'A');
      final b = await User.query().updateOrCreate(
        {'email': 'a@x.test'},
        {'name': 'B'},
      );
      expect(b.id, a.id);
      expect(b.name, 'B');
      expect(await User.query().count(), 1);
    });
  });

  group('delete and refresh', () {
    test('delete and refresh', () async {
      final user = await User.create({'name': 'A', 'email': 'a@x.test'});
      await DB.table('users').where('id', user.id).update({'name': 'changed'});
      final fresh = await user.refresh();
      expect(fresh.name, 'changed');
      expect(await user.forceDelete(), isTrue);
      expect(user.exists, isFalse);
      expect(await User.withTrashed().count(), 0);
      expect(() => user.refresh(), throwsA(isA<ModelNotPersistedException>()));
    });
    test('bulk delete and truncate', () async {
      await User.create({'name': 'A', 'email': 'a@x.test'});
      await User.create({'name': 'B', 'email': 'b@x.test'});
      expect(await User.query().where('name', 'A').forceDelete(), 1);
      await User.query().truncate();
      expect(await User.withTrashed().count(), 0);
    });
    test('insert and insertGetId on the builder', () async {
      expect(await User.query().insert({'name': 'A', 'email': 'a@x.test'}), 1);
      final id = await User.query().insertGetId({
        'name': 'B',
        'email': 'b@x.test',
      });
      expect(id, 2);
      expect(
        await DB.table('users').insert([
          {'name': 'C', 'email': 'c@x.test'},
          {'name': 'D', 'email': 'd@x.test'},
        ]),
        2,
      );
      expect(await User.query().count(), 4);
    });
  });

  group('null values', () {
    test('null columns hydrate as null and can be set to null', () async {
      final u = await User.create({'name': 'A', 'email': 'a@x.test', 'age': 5});
      expect(u.meta, isNull);
      final cleared = await u.update({'age': null});
      expect(cleared.age, isNull);
      expect((await User.findOrFail(u.id!)).age, isNull);
      expect(await User.query().whereNull('age').count(), 1);
    });
  });

  group('connection failures', () {
    test('opening an impossible path throws ConnectionException', () {
      expect(
        () => SqliteConnection.open('/nonexistent/dir/x.sqlite'),
        throwsA(isA<ConnectionException>()),
      );
    });
    test('unknown table is a QueryException with the SQL attached', () async {
      expect(
        () => DB.table('nope').get(),
        throwsA(
          isA<QueryException>().having(
            (e) => e.sql,
            'sql',
            'select * from "nope"',
          ),
        ),
      );
    });
    test('no default connection is a clear error', () async {
      final saved = DB.connection;
      DB.reset();
      expect(() => DB.table('users'), throwsA(isA<ConnectionException>()));
      DB.use(saved);
    });
  });
}
