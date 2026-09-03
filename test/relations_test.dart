import 'package:seshat/seshat.dart';
import 'package:seshat/sqlite.dart';
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
    await Post.query().create({
      'user_id': ann.id,
      'title': 'A1',
      'published': true,
    });
    await Post.query().create({'user_id': ann.id, 'title': 'A2'});
    await Post.query().create({
      'user_id': bob.id,
      'title': 'B1',
      'published': true,
    });
    await Comment.query().create({'post_id': 1, 'body': 'c1'});
    await Comment.query().create({'post_id': 1, 'body': 'c2'});
    await Comment.query().create({'post_id': 3, 'body': 'c3'});
    await Profile.query().create({'user_id': ann.id, 'bio': 'hi'});
    await RoleModel.query().create({'name': 'admin'});
    await RoleModel.query().create({'name': 'editor'});
    await DB.table('role_user').insert([
      {'user_id': ann.id, 'role_id': 1, 'granted_by': 'root'},
      {'user_id': ann.id, 'role_id': 2},
      {'user_id': bob.id, 'role_id': 2},
    ]);
    db.flushQueryLog();
  });
  tearDown(() => db.close());

  group('lazy relation queries', () {
    test('hasMany get/first/query', () async {
      final posts = await ann.posts().get();
      expect(posts.map((p) => p.title), ['A1', 'A2']);
      expect((await ann.posts().first())?.title, 'A1');
      expect(await ann.posts().query().where('published', true).count(), 1);
      expect(
        ann.posts().query().toSql(),
        contains('where "posts"."user_id" = ?'),
      );
    });
    test('hasMany create sets the foreign key', () async {
      final post = await ann.posts().create({'title': 'A3'});
      expect(post.userId, ann.id);
      expect(post.exists, isTrue);
    });
    test('hasOne', () async {
      expect((await ann.profile().first())?.bio, 'hi');
      expect(await bob.profile().first(), isNull);
    });
    test('belongsTo', () async {
      final post = await Post.query().findOrFail(3);
      expect((await post.user().get())?.name, 'Bob');
    });
    test('belongsToMany with pivot columns', () async {
      final roles = await ann.roles().get();
      expect(roles.map((r) => r.name), ['admin', 'editor']);
      expect(roles.first.pivot, {
        'user_id': 1,
        'role_id': 1,
        'granted_by': 'root',
      });
      expect(roles.last.pivot?['granted_by'], isNull);
      expect((await bob.roles().get()).map((r) => r.name), ['editor']);
    });
    test('value throws when not loaded', () {
      expect(
        () => ann.posts().value,
        throwsA(isA<RelationNotLoadedException>()),
      );
      expect(ann.posts().isLoaded, isFalse);
    });
    test('unknown relation is a clear error', () {
      expect(() => ann.relation('nope'), throwsA(isA<DatabaseException>()));
      expect(
        () => User.query().whereHas('nope'),
        throwsA(isA<DatabaseException>()),
      );
    });
  });

  group('eager loading', () {
    test(
      'with_ hasMany uses exactly two queries and fills every parent',
      () async {
        db.enableQueryLog();
        final users = await User.with_(['posts']).orderBy('id').get();
        expect(db.queryLog.length, 2);
        expect(db.queryLog.last.sql, contains('"posts"."user_id" in (?, ?)'));
        expect(users[0].posts().value.map((p) => p.title), ['A1', 'A2']);
        expect(users[1].posts().value.map((p) => p.title), ['B1']);
        expect(users[0].posts().isLoaded, isTrue);
      },
    );
    test('parents without children get an empty list / null', () async {
      final carl = await User.create({'name': 'Carl', 'email': 'c@x.test'});
      final loaded = await User.with_([
        'posts',
        'profile',
        'roles',
      ]).findOrFail(carl.id!);
      expect(loaded.posts().value, isEmpty);
      expect(loaded.profile().value, isNull);
      expect(loaded.roles().value, isEmpty);
    });
    test('hasOne, belongsTo, belongsToMany', () async {
      db.enableQueryLog();
      final posts = await Post.query().with_(['user']).orderBy('id').get();
      expect(db.queryLog.length, 2);
      expect(posts.map((p) => p.user().value?.name), ['Ann', 'Ann', 'Bob']);
      final users = await User.with_(['profile', 'roles']).orderBy('id').get();
      expect(users[0].profile().value?.bio, 'hi');
      expect(users[1].profile().value, isNull);
      expect(users[0].roles().value.map((r) => r.name), ['admin', 'editor']);
      expect(users[0].roles().value.first.pivot?['granted_by'], 'root');
      expect(users[1].roles().value.map((r) => r.name), ['editor']);
    });
    test('nested with dot notation', () async {
      db.enableQueryLog();
      final users = await User.with_(['posts.comments']).orderBy('id').get();
      expect(db.queryLog.length, 3);
      final annPosts = users[0].posts().value;
      expect(annPosts[0].comments().value.map((c) => c.body), ['c1', 'c2']);
      expect(annPosts[1].comments().value, isEmpty);
      expect(users[1].posts().value[0].comments().value.map((c) => c.body), [
        'c3',
      ]);
    });
    test('withWhere constrains the eager query', () async {
      final users = await User.query()
          .withWhere('posts', (q) => q.where('published', true))
          .orderBy('id')
          .get();
      expect(users[0].posts().value.map((p) => p.title), ['A1']);
    });
    test('load() after the fact and refresh keeps relations', () async {
      final user = await User.findOrFail(ann.id!);
      await user.load(['posts']);
      expect(user.posts().value.length, 2);
      final fresh = await user.refresh();
      expect(fresh.posts().isLoaded, isTrue);
    });
    test('toJson includes loaded relations', () async {
      final user = await User.with_(['posts']).findOrFail(ann.id!);
      final json = user.toJson();
      expect((json['posts'] as List).length, 2);
      expect((json['posts'] as List).first, containsPair('title', 'A1'));
      expect(json['created_at'], isA<String>());
    });
  });

  group('whereHas', () {
    test('hasMany with constraint', () async {
      final q = User.query().whereHas(
        'posts',
        (p) => p.where('published', true),
      );
      expect(
        q.toSql(),
        'select * from "users" where exists (select 1 from "posts" where '
        '"posts"."user_id" = "users"."id" and "published" = ?) '
        'and "users"."deleted_at" is null',
      );
      final withUnpublished = await User.query()
          .whereHas('posts', (p) => p.where('published', false))
          .pluck('name');
      expect(withUnpublished, ['Ann']);
    });
    test('has and whereDoesntHave', () async {
      final carl = await User.create({'name': 'Carl', 'email': 'c@x.test'});
      expect(await User.query().has('posts').pluck('name'), ['Ann', 'Bob']);
      expect(await User.query().whereDoesntHave('posts').pluck('name'), [
        'Carl',
      ]);
      expect(await User.query().whereDoesntHave('profile').pluck('name'), [
        'Bob',
        'Carl',
      ]);
      await carl.forceDelete();
    });
    test('belongsTo and belongsToMany', () async {
      expect(
        await Post.query()
            .whereHas('user', (u) => u.where('name', 'Bob'))
            .pluck('title'),
        ['B1'],
      );
      expect(
        await User.query()
            .whereHas('roles', (r) => r.where('roles.name', 'admin'))
            .pluck('name'),
        ['Ann'],
      );
    });
  });

  group('self-referencing whereHas', () {
    // Parent → Child (done) → Grandchild, plus a childless Lonely and an
    // Other that is itself done but whose only child is not.
    late Task parent;
    late Task other;
    setUp(() async {
      parent = await Task.query().create({'title': 'Parent'});
      final child = await Task.query().create({
        'title': 'Child',
        'done': true,
        'parent_id': parent.id,
      });
      await Task.query().create({'title': 'Grandchild', 'parent_id': child.id});
      await Task.query().create({'title': 'Lonely'});
      other = await Task.query().create({'title': 'Other', 'done': true});
      await Task.query().create({'title': 'Only', 'parent_id': other.id});
    });

    test('subquery correlates to the outer table', () {
      expect(
        Task.query().whereHas('subtasks').toSql(),
        'select * from "tasks" where exists (select 1 from "tasks" as '
        '"__has_0" where "__has_0"."parent_id" = "tasks"."id")',
      );
      expect(
        Task.query().whereHas('parent').toSql(),
        'select * from "tasks" where exists (select 1 from "tasks" as '
        '"__has_0" where "__has_0"."id" = "tasks"."parent_id")',
      );
    });

    test('global scopes qualify against the alias', () {
      expect(
        User.query().whereHas('invitees').toSql(),
        'select * from "users" where exists (select 1 from "users" as '
        '"__has_0" where "__has_0"."invited_by" = "users"."id" and '
        '"__has_0"."deleted_at" is null) and "users"."deleted_at" is null',
      );
    });

    test('whereHas and whereDoesntHave pick the right rows', () async {
      expect(await Task.query().has('subtasks').pluck('title'), [
        'Parent',
        'Child',
        'Other',
      ]);
      expect(await Task.query().whereDoesntHave('subtasks').pluck('title'), [
        'Grandchild',
        'Lonely',
        'Only',
      ]);
      expect(await Task.query().whereHas('parent').pluck('title'), [
        'Child',
        'Grandchild',
        'Only',
      ]);
    });

    test('constraint columns bind to the related table', () async {
      // 'Other' is done itself but its only subtask is not, so it must not
      // match: the closure has to read the inner row, not the outer one.
      expect(
        await Task.query()
            .whereHas('subtasks', (q) => q.where('done', true))
            .pluck('title'),
        ['Parent'],
      );
      // Bound to the outer row this would be ['Child'] — the only task that
      // is itself done and has a parent.
      expect(
        await Task.query()
            .whereHas('parent', (q) => q.where('done', true))
            .pluck('title'),
        ['Grandchild', 'Only'],
      );
    });

    test('nested whereHas gets its own alias', () async {
      // Only a subquery whose table would shadow what it correlates against
      // is aliased, so the middle level here stays plain "tasks". The
      // suffix is the nesting depth, which is why the second alias is
      // __has_2 and not __has_1: two live aliases can never share a name.
      expect(
        Task.query()
            .whereHas(
              'subtasks',
              (q) => q.whereHas('parent', (p) => p.whereHas('subtasks')),
            )
            .toSql(),
        'select * from "tasks" where exists (select 1 from "tasks" as '
        '"__has_0" where "__has_0"."parent_id" = "tasks"."id" and exists '
        '(select 1 from "tasks" where "tasks"."id" = "__has_0"."parent_id" '
        'and exists (select 1 from "tasks" as "__has_2" where '
        '"__has_2"."parent_id" = "tasks"."id")))',
      );
      expect(
        await Task.query()
            .whereHas('subtasks', (q) => q.whereHas('subtasks'))
            .pluck('title'),
        ['Parent'],
      );
    });

    test('self-referencing belongsToMany', () async {
      await DB.table('task_links').insert([
        {'task_id': parent.id, 'related_id': other.id},
      ]);
      expect(
        Task.query().whereHas('links').toSql(),
        'select * from "tasks" where exists (select 1 from "tasks" as '
        '"__has_0" inner join "task_links" on "task_links"."related_id" = '
        '"__has_0"."id" where "task_links"."task_id" = "tasks"."id")',
      );
      expect(await Task.query().has('links').pluck('title'), ['Parent']);
      expect(
        await Task.query()
            .whereHas('links', (q) => q.where('title', 'Other'))
            .pluck('title'),
        ['Parent'],
      );
    });
  });

  group('pivot writes', () {
    test('attach, detach, sync', () async {
      await bob.roles().attach(1, {'granted_by': 'ann'});
      var roles = await bob.roles().get();
      expect(roles.map((r) => r.name), ['admin', 'editor']);
      expect(roles.first.pivot?['granted_by'], 'ann');
      expect(await bob.roles().detach(2), 1);
      expect((await bob.roles().get()).map((r) => r.name), ['admin']);
      final result = await bob.roles().sync([2]);
      expect(result.attached, [2]);
      expect(result.detached, [1]);
      expect((await bob.roles().get()).map((r) => r.name), ['editor']);
      expect(await bob.roles().detach(), 1);
      expect(await bob.roles().get(), isEmpty);
      expect(
        await DB.table('role_user').where('user_id', ann.id).count(),
        2,
        reason: 'other users untouched',
      );
    });
  });
}
