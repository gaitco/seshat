import 'package:maat_seshat_core/maat_seshat_core.dart';
import 'package:maat_seshat_core/sqlite.dart';
import 'package:test/test.dart';

import 'support/models.dart';

void main() {
  late SqliteConnection db;
  late User ann;
  late User bob;
  setUp(() async {
    db = await setUpDatabase();
    ann = await User.create({'name': 'Ann', 'email': 'ann@x.test'});
    bob = await User.create({'name': 'Bob', 'email': 'bob@x.test'});
  });
  tearDown(() => db.close());

  test(
    'delete() sets deleted_at and hides the row from normal queries',
    () async {
      expect(await ann.delete(), isTrue);
      expect(ann.exists, isTrue, reason: 'the row is still in the table');
      expect(await User.query().count(), 1);
      expect(await User.find(ann.id!), isNull);
      expect(await User.query().pluck('name'), ['Bob']);
      final raw = await DB.table('users').where('id', ann.id).first();
      expect(raw!['deleted_at'], isNotNull);
      expect(raw['updated_at'], isNotNull);
    },
  );

  test('the scope is in the SQL of every read and write', () async {
    expect(
      User.query().toSql(),
      'select * from "users" where "users"."deleted_at" is null',
    );
    await ann.delete();
    expect(await User.query().update({'active': false}), 1, reason: 'only Bob');
    expect(await User.query().exists(), isTrue);
    expect((await User.query().paginate()).total, 1);
    expect(await User.query().where('id', ann.id).exists(), isFalse);
  });

  test('withTrashed, onlyTrashed, trashed', () async {
    await ann.delete();
    expect(await User.withTrashed().count(), 2);
    expect(await User.onlyTrashed().pluck('name'), ['Ann']);
    final trashed = await User.withTrashed().findOrFail(ann.id!);
    expect(trashed.trashed, isTrue);
    expect(trashed.deletedAt, isA<DateTime>());
    expect(bob.trashed, isFalse);
  });

  test('restore() on the instance and on the builder', () async {
    await ann.delete();
    final restored = await ann.restore();
    expect(restored.trashed, isFalse);
    expect(await User.query().count(), 2);
    expect(User.log, contains('restored Ann'));
    await bob.delete();
    expect(await User.onlyTrashed().restore(), 1);
    expect(await User.query().count(), 2);
  });

  test('forceDelete removes the row', () async {
    await ann.delete();
    expect(await ann.forceDelete(), isTrue);
    expect(ann.exists, isFalse);
    expect(await User.withTrashed().count(), 1);
    expect(await User.query().where('name', 'Bob').forceDelete(), 1);
    expect(await User.withTrashed().count(), 0);
  });

  test('bulk delete on the builder soft deletes', () async {
    expect(await User.query().delete(), 2);
    expect(await User.query().count(), 0);
    expect(await User.withTrashed().count(), 2);
  });

  test('deleting hook can veto', () async {
    final immortal = await User.create({
      'name': 'Immortal',
      'email': 'im@x.test',
    });
    expect(await immortal.delete(), isFalse);
    expect(await User.query().count(), 3);
  });

  test('relations ignore trashed rows through the global scope', () async {
    await Post.query().create({'user_id': ann.id, 'title': 'A1'});
    await ann.delete();
    final post = await Post.query().with_(['user']).findOrFail(1);
    expect(post.user().value, isNull);
    expect(await Post.query().has('user').count(), 0);
  });

  test('refresh() finds a trashed instance', () async {
    await ann.delete();
    final fresh = await ann.refresh();
    expect(fresh.trashed, isTrue);
  });
}
