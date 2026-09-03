import 'package:seshat/seshat.dart';
import 'package:seshat/sqlite.dart';
import 'package:test/test.dart';

import 'support/models.dart';

/// Same table as [User] but with an `active` global scope and no soft
/// deletes, to test scopes in isolation.
class ActiveUser extends Model<ActiveUser> {
  ActiveUser({this.id, required this.name, this.active = true});

  static final def = ModelDefinition<ActiveUser>(
    table: 'users',
    fromMap: (m) => ActiveUser(
      id: m['id'] as int?,
      name: m['name'] as String,
      active: m['active'] as bool,
    ),
    casts: {'active': Cast.boolean},
    timestamps: false,
    globalScopes: {'active': (q) => q.where('users.active', true)},
  );

  @override
  ModelDefinition<ActiveUser> get definition => def;
  static QueryBuilder<ActiveUser> query() => def.query();

  final int? id;
  final String name;
  final bool active;

  @override
  Map<String, Object?> toMap() => {'id': id, 'name': name, 'active': active};
}

void main() {
  late SqliteConnection db;
  setUp(() async {
    db = await setUpDatabase();
    await User.create({'name': 'On', 'email': 'on@x.test', 'active': true});
    await User.create({'name': 'Off', 'email': 'off@x.test', 'active': false});
  });
  tearDown(() => db.close());

  test('global scopes apply to reads, aggregates and writes', () async {
    expect(
      ActiveUser.query().toSql(),
      'select * from "users" where "users"."active" = ?',
    );
    expect(await ActiveUser.query().pluck('name'), ['On']);
    expect(await ActiveUser.query().count(), 1);
    expect(await ActiveUser.query().find(2), isNull);
    expect(await ActiveUser.query().update({'name': 'Changed'}), 1);
    expect(await DB.table('users').where('id', 2).value('name'), 'Off');
  });

  test('withoutGlobalScope and withoutGlobalScopes', () async {
    expect(await ActiveUser.query().withoutGlobalScope('active').count(), 2);
    expect(await ActiveUser.query().withoutGlobalScopes().count(), 2);
    expect(User.query().withoutGlobalScopes().toSql(), 'select * from "users"');
  });

  test('scopes are applied once even when the builder is reused', () async {
    final q = ActiveUser.query();
    await q.count();
    await q.get();
    expect(q.toSql(), 'select * from "users" where "users"."active" = ?');
  });

  test('scopes apply inside subqueries', () async {
    final sub = ActiveUser.query().select(['id']);
    final q = DB.table('users').whereIn('id', sub);
    expect(q.toSql(), contains('where "users"."active" = ?'));
    expect(await q.count(), 1);
  });

  test('local scopes compose with everything else', () async {
    final users = await User.query()
        .active()
        .recent()
        .where('name', 'On')
        .get();
    expect(users.single.name, 'On');
  });
}
