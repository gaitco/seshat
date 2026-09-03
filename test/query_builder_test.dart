import 'package:seshat/seshat.dart';
import 'package:seshat/sqlite.dart';
import 'package:test/test.dart';

void main() {
  late SqliteConnection db;
  setUp(() {
    db = SqliteConnection.inMemory();
    DB.use(db);
  });
  tearDown(() => db.close());

  QueryBuilder<Row> users() => DB.table('users');

  group('select compilation', () {
    test('plain', () {
      expect(users().toSql(), 'select * from "users"');
    });
    test('columns, alias, distinct', () {
      final q = users().select(['id', 'users.name as n']).distinct();
      expect(
        q.toSql(),
        'select distinct "id", "users"."name" as "n" from "users"',
      );
    });
    test('where and orWhere with operators', () {
      final q = users().where('age', '>', 18).orWhere('name', 'Bo');
      expect(q.toSql(), 'select * from "users" where "age" > ? or "name" = ?');
      expect(q.compile().$2, [18, 'Bo']);
    });
    test('where null forms', () {
      final q = users().where('a', null).whereNotNull('b').orWhereNull('c');
      expect(
        q.toSql(),
        'select * from "users" where "a" is null and "b" is not null or "c" is null',
      );
    });
    test('whereIn, empty whereIn, whereNotIn', () {
      expect(
        users().whereIn('id', [1, 2]).toSql(),
        'select * from "users" where "id" in (?, ?)',
      );
      expect(
        users().whereIn('id', []).toSql(),
        'select * from "users" where 0 = 1',
      );
      expect(
        users().whereNotIn('id', []).toSql(),
        'select * from "users" where 1 = 1',
      );
    });
    test('whereIn subquery', () {
      final sub = DB
          .table('posts')
          .select(['user_id'])
          .where('published', true);
      final q = users().whereIn('id', sub);
      expect(
        q.toSql(),
        'select * from "users" where "id" in (select "user_id" from "posts" where "published" = ?)',
      );
      expect(q.compile().$2, [1]);
    });
    test('whereBetween, whereLike, whereColumn', () {
      final q = users()
          .whereBetween('age', 18, 65)
          .whereLike('name', '%ab%')
          .whereColumn('updated_at', '>', 'created_at');
      expect(
        q.toSql(),
        'select * from "users" where "age" between ? and ? and "name" like ? '
        'and "updated_at" > "created_at"',
      );
      expect(q.compile().$2, [18, 65, '%ab%']);
    });
    test('nested where groups', () {
      final q = users()
          .where('active', true)
          .where((q) => q.where('a', 1).orWhere('b', 2));
      expect(
        q.toSql(),
        'select * from "users" where "active" = ? and ("a" = ? or "b" = ?)',
      );
      expect(q.compile().$2, [1, 1, 2]);
    });
    test('joins', () {
      final q = users()
          .join('posts', 'posts.user_id', '=', 'users.id')
          .leftJoin('profiles', 'profiles.user_id', '=', 'users.id')
          .select(['users.*', 'posts.title']);
      expect(
        q.toSql(),
        'select "users".*, "posts"."title" from "users" '
        'inner join "posts" on "posts"."user_id" = "users"."id" '
        'left join "profiles" on "profiles"."user_id" = "users"."id"',
      );
    });
    test('group by, having, order, limit, offset', () {
      final q = users()
          .select(['role', RawSql('count(*) as total')])
          .groupBy(['role'])
          .having('total', '>', 1)
          .orderBy('total', descending: true)
          .orderBy('role')
          .limit(10)
          .offset(20);
      expect(
        q.toSql(),
        'select "role", count(*) as total from "users" group by "role" '
        'having "total" > ? order by "total" desc, "role" asc limit 10 offset 20',
      );
    });
    test('latest, oldest, skip, take, forPage', () {
      expect(
        users().latest().toSql(),
        'select * from "users" order by "created_at" desc',
      );
      expect(
        users().oldest('id').toSql(),
        'select * from "users" order by "id" asc',
      );
      expect(
        users().skip(5).take(5).toSql(),
        'select * from "users" limit 5 offset 5',
      );
      expect(
        users().forPage(3, 10).toSql(),
        'select * from "users" limit 10 offset 20',
      );
    });
    test('raw fragments carry their own bindings in order', () {
      final q = users()
          .selectRaw('json_extract(meta, ?) as plan', [r'$.plan'])
          .where('active', true)
          .whereRaw('lower(email) = ?', ['a@b.c'])
          .orderByRaw('random()');
      expect(
        q.toSql(),
        'select json_extract(meta, ?) as plan from "users" where "active" = ? '
        'and lower(email) = ? order by random()',
      );
      expect(q.compile().$2, [r'$.plan', 1, 'a@b.c']);
    });
    test('clone does not share state', () {
      final a = users().where('a', 1);
      final b = a.clone().where('b', 2);
      expect(a.toSql(), 'select * from "users" where "a" = ?');
      expect(b.toSql(), 'select * from "users" where "a" = ? and "b" = ?');
    });
  });

  group('write compilation', () {
    test('insert single and multiple rows', () {
      final (sql, b) = db.grammar.compileInsert('users', [
        {'name': 'a', 'active': true},
        {'name': 'b', 'active': false},
      ]);
      expect(
        sql,
        'insert into "users" ("name", "active") values (?, ?), (?, ?)',
      );
      expect(b, ['a', 1, 'b', 0]);
    });
    test('update with where', () {
      final q = users().where('id', 3);
      final (sql, b) = db.grammar.compileUpdate(q, {'name': 'x', 'age': null});
      expect(sql, 'update "users" set "name" = ?, "age" = ? where "id" = ?');
      expect(b, ['x', null, 3]);
    });
    test('delete', () {
      final (sql, b) = db.grammar.compileDelete(users().where('id', 3));
      expect(sql, 'delete from "users" where "id" = ?');
      expect(b, [3]);
    });
  });

  group('value encoding', () {
    test('sqlite encodes bool, DateTime, enum, map', () {
      final g = db.grammar;
      expect(g.encode(true), 1);
      expect(
        g.encode(DateTime.utc(2026, 1, 2, 3, 4, 5)),
        '2026-01-02T03:04:05.000Z',
      );
      expect(g.encode(Role.admin), 'admin');
      expect(g.encode({'a': 1}), '{"a":1}');
      expect(g.encode(null), isNull);
    });
  });

  group('identifier safety', () {
    for (final bad in [
      'name; drop table users',
      'name"',
      "name'",
      'users.name x',
      'name--',
      '1name',
      'na me',
      '',
    ]) {
      test("rejects column '$bad'", () {
        expect(
          () => users().where(bad, 1),
          throwsA(isA<InvalidIdentifierException>()),
        );
        expect(
          () => users().orderBy(bad),
          throwsA(isA<InvalidIdentifierException>()),
        );
        expect(
          () => users().select([bad]),
          throwsA(isA<InvalidIdentifierException>()),
        );
      });
    }
    test('rejects bad table names', () {
      expect(
        () => DB.table('users; drop').toSql(),
        throwsA(isA<InvalidIdentifierException>()),
      );
      expect(
        () => users().join('x y', 'a', '=', 'b'),
        throwsA(isA<InvalidIdentifierException>()),
      );
    });
    test('rejects unknown operators', () {
      expect(
        () => users().where('a', 'union', 1),
        throwsA(isA<DatabaseException>()),
      );
      expect(
        () => users().where('a', '= 1 or 1', 1),
        throwsA(isA<DatabaseException>()),
      );
    });
    test('values are never interpolated', () {
      final q = users().where('name', "' or 1=1 --");
      expect(q.toSql(), 'select * from "users" where "name" = ?');
      expect(q.compile().$2, ["' or 1=1 --"]);
    });
    test('negative limit and offset are rejected', () {
      expect(() => users().limit(-1), throwsRangeError);
      expect(() => users().offset(-1), throwsRangeError);
    });
  });
}

enum Role { admin, member }
