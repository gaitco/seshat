import 'package:seshat/seshat.dart';
import 'package:seshat/sqlite.dart';
import 'package:test/test.dart';

import 'support/models.dart';

void main() {
  late SqliteConnection db;
  setUp(() async => db = await setUpDatabase());
  tearDown(() => db.close());

  test('commits on success and returns the callback value', () async {
    final id = await db.transaction((tx) async {
      final user = await User.using(
        tx,
      ).create({'name': 'A', 'email': 'a@x.test'});
      await Profile.query().using(tx).create({'user_id': user.id, 'bio': 'x'});
      return user.id;
    });
    expect(id, 1);
    expect(await User.query().count(), 1);
    expect(await Profile.query().count(), 1);
    expect(db.transactionDepth, 0);
  });

  test('rolls back everything and rethrows on exception', () async {
    await expectLater(
      db.transaction((tx) async {
        await User.using(tx).create({'name': 'A', 'email': 'a@x.test'});
        await Profile.query().using(tx).create({'user_id': 1, 'bio': 'x'});
        throw StateError('boom');
      }),
      throwsStateError,
    );
    expect(await User.query().count(), 0);
    expect(await Profile.query().count(), 0);
    expect(db.transactionDepth, 0);
  });

  test('a database error inside the transaction rolls back too', () async {
    await expectLater(
      db.transaction((tx) async {
        await User.using(tx).create({'name': 'A', 'email': 'dup@x.test'});
        await User.using(tx).create({'name': 'B', 'email': 'dup@x.test'});
      }),
      throwsA(isA<UniqueConstraintException>()),
    );
    expect(await User.query().count(), 0);
  });

  test('DB.transaction uses the default connection', () async {
    await DB.transaction((tx) async {
      await DB.table('users', connection: tx).insert({
        'name': 'A',
        'email': 'a@x.test',
      });
    });
    expect(await User.query().count(), 1);
  });

  group('nested transactions use savepoints', () {
    test('inner failure caught by the outer keeps outer work', () async {
      await db.transaction((tx) async {
        await User.using(tx).create({'name': 'Outer', 'email': 'o@x.test'});
        try {
          await tx.transaction((inner) async {
            await User.using(
              inner,
            ).create({'name': 'Inner', 'email': 'i@x.test'});
            expect(db.transactionDepth, 2);
            throw StateError('inner');
          });
        } on StateError {
          // swallowed on purpose
        }
        expect(db.transactionDepth, 1);
      });
      expect(await User.query().pluck('name'), ['Outer']);
    });

    test('outer failure discards a committed inner savepoint', () async {
      await expectLater(
        db.transaction((tx) async {
          await tx.transaction((inner) async {
            await User.using(
              inner,
            ).create({'name': 'Inner', 'email': 'i@x.test'});
          });
          await User.using(tx).create({'name': 'Outer', 'email': 'o@x.test'});
          throw StateError('outer');
        }),
        throwsStateError,
      );
      expect(await User.query().count(), 0);
      expect(db.transactionDepth, 0);
    });
  });

  test('model instances pinned with onConnection save through it', () async {
    await expectLater(
      db.transaction((tx) async {
        final u = await User(
          name: 'P',
          email: 'p@x.test',
        ).onConnection(tx).save();
        expect(u.connection, same(tx));
        await u.update({'name': 'Q'});
        throw StateError('x');
      }),
      throwsStateError,
    );
    expect(await User.query().count(), 0);
  });
}
