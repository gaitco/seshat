import 'package:maat_seshat_core/maat_seshat_core.dart';
import 'package:maat_seshat_core/sqlite.dart';
import 'package:test/test.dart';

import 'support/models.dart';

void main() {
  late SqliteConnection db;
  setUp(() async {
    db = await setUpDatabase();
    await User.create({'name': 'Ann', 'email': 'ann@x.test'});
    await User.create({'name': 'Bob', 'email': 'bob@x.test', 'active': false});
  });
  tearDown(() => db.close());

  group('values are bound, never interpolated', () {
    const payloads = [
      "' or '1'='1",
      "'; drop table users; --",
      '" or 1=1 --',
      r'\x27 or 1=1',
      'ann@x.test ',
    ];
    for (final p in payloads) {
      test('where value: $p', () async {
        expect(await User.query().where('name', p).count(), 0);
        expect(await User.query().whereLike('name', p).count(), 0);
        expect(await User.query().whereIn('name', [p]).count(), 0);
        expect(await User.query().count(), 2, reason: 'table intact');
      });
      test('create value: $p', () async {
        final u = await User.create({'name': p, 'email': '$p@x.test'});
        expect((await User.findOrFail(u.id!)).name, p);
        expect(await User.query().count(), 3);
      });
      test('update value: $p', () async {
        await User.query().where('name', 'Ann').update({'name': p});
        expect(await User.query().where('name', p).count(), 1);
      });
    }
    test('like wildcards are data too', () async {
      expect(await User.query().whereLike('name', '%').count(), 2);
      expect(await User.query().whereLike('name', 'A%').count(), 1);
    });
  });

  group('identifiers from user input are rejected', () {
    const bad = [
      'name; drop table users',
      'name"',
      'name`',
      'users.name; --',
      '(select 1)',
    ];
    for (final b in bad) {
      test('column: $b', () {
        final q = User.query();
        expect(() => q.orderBy(b), throwsA(isA<InvalidIdentifierException>()));
        expect(() => q.where(b, 1), throwsA(isA<InvalidIdentifierException>()));
        expect(() => q.select([b]), throwsA(isA<InvalidIdentifierException>()));
        expect(
          () => q.groupBy([b]),
          throwsA(isA<InvalidIdentifierException>()),
        );
        expect(() => q.pluck(b), throwsA(isA<InvalidIdentifierException>()));
        expect(
          () => q.increment(b),
          throwsA(isA<InvalidIdentifierException>()),
        );
        expect(
          () => q.insert({b: 1}),
          throwsA(isA<InvalidIdentifierException>()),
        );
        expect(
          () => q.update({b: 1}),
          throwsA(isA<InvalidIdentifierException>()),
        );
        expect(
          () => DB.table(b).get(),
          throwsA(isA<InvalidIdentifierException>()),
        );
        expect(
          () => q.join(b, 'a', '=', 'b'),
          throwsA(isA<InvalidIdentifierException>()),
        );
      });
    }
    test('operators are whitelisted', () {
      expect(
        () => User.query().where('name', '= 1 or 1', 1),
        throwsA(isA<DatabaseException>()),
      );
      expect(
        () => User.query().whereColumn('a', 'b; drop', 'c'),
        throwsA(isA<DatabaseException>()),
      );
    });
  });

  group('safe sorting from request input', () {
    test('a whitelist plus a boolean direction is the pattern', () async {
      const allowed = {'name', 'created_at'};
      String sortFrom(String input) =>
          allowed.contains(input) ? input : 'created_at';
      const requested = 'desc';
      final names = await User.query()
          .orderBy(sortFrom('name'), descending: requested == 'desc')
          .pluck('name');
      expect(names, ['Bob', 'Ann']);
      expect(
        () => User.query().orderBy('name desc'),
        throwsA(isA<InvalidIdentifierException>()),
      );
      expect(
        () => User.query().orderBy('name; --'),
        throwsA(isA<InvalidIdentifierException>()),
      );
    });
  });

  group('mass assignment', () {
    test('guarded attributes are dropped or rejected', () async {
      final u = await User.create({
        'name': 'X',
        'email': 'x@x.test',
        'created_at': DateTime(2000),
      });
      expect(u.createdAt!.year, isNot(2000));
      expect(
        () => Setting.query().create({'key': 'admin', 'value': '1'}),
        throwsA(isA<MassAssignmentException>()),
      );
    });
    test('update() cannot change the key through mass assignment', () async {
      final u = await User.findOrFail(1);
      final same = await u.update({'id': 999, 'name': 'Y'});
      expect(same.id, 1);
      expect(await User.find(999), isNull);
    });
  });

  group('RawSql is the only escape hatch', () {
    test('and it still binds its own values', () async {
      final q = User.query().whereRaw('lower("name") = ?', ['ann']);
      expect(q.compile().$2.first, 'ann');
      expect(await q.count(), 1);
    });
    test('RawSql.expression in select and order', () async {
      final rows = await DB
          .table('users')
          .select([RawSql.expression('upper(name) as shout')])
          .orderByRaw('length(name) desc, name')
          .get();
      expect(rows.first['shout'], 'ANN');
    });
  });
}
