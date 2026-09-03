# Seshat Core

<p align="center"><img src="assets/icon.svg" width="96" alt="Seshat Core icon"></p>

Seshat is an ORM for pure Dart servers with a parameterized query
builder, typed immutable models, relationships with eager loading, scopes,
soft deletes, transactions, migrations and pagination. Works with Shelf,
Dart Frog, Serverpod, or a bare `dart:io` server. No Flutter, no code
generation, no reflection.

Adapters: **SQLite** (`package:sqlite3`, FFI) and **PostgreSQL**
(`package:postgres`). MySQL is on the roadmap.

```dart
final users = await User.query()
    .where('active', true)
    .whereLike('name', '%Abdullah%')
    .orderBy('created_at', descending: true)
    .limit(20)
    .get();
```

## Installation

```yaml
dependencies:
  maat_seshat_core: ^0.1.0
```

```dart
import 'package:maat_seshat_core/maat_seshat_core.dart';
import 'package:maat_seshat_core/sqlite.dart';     // or postgres.dart

final db = SqliteConnection.open('storage/app.sqlite');
// final db = await PostgresConnection.open(host: 'localhost', database: 'app', username: 'app', password: '...');
DB.use(db);
```

SQLite needs `libsqlite3` on the host (present on macOS; `apt install
libsqlite3-0` on Debian/Ubuntu).

## Defining a model

Dart has no static inheritance and no runtime property bag, so a model is
a plain immutable class plus one `ModelDefinition` that holds everything
Seshat keeps in static properties:

```dart
class User extends Model<User> with SoftDeletes<User> {
  User({this.id, required this.name, required this.email, this.active = true,
        this.createdAt, this.updatedAt, this.deletedAt});

  static final ModelDefinition<User> def = ModelDefinition<User>(
    table: 'users',
    fromMap: User.fromMap,
    fillable: ['name', 'email', 'active'],
    casts: {'active': Cast.boolean, 'created_at': Cast.dateTime,
            'updated_at': Cast.dateTime, 'deleted_at': Cast.dateTime},
    softDeletes: true,
    relations: (r) => r
      ..hasMany('posts', Post.def, foreignKey: 'user_id')
      ..belongsToMany('roles', Role.def, pivotTable: 'role_user',
          foreignPivotKey: 'user_id', relatedPivotKey: 'role_id'),
    events: ModelEvents<User>(created: (u) async => mailer.welcome(u)),
  );

  @override
  ModelDefinition<User> get definition => def;

  // Forward the statics you want; the rest hangs off query().
  static QueryBuilder<User> query() => def.query();
  static Future<User?> find(Object id) => def.find(id);
  static Future<User> create(Map<String, Object?> a) => def.query().create(a);
  static QueryBuilder<User> with_(List<String> r) => def.with_(r);
  static QueryBuilder<User> using(Connection tx) => def.using(tx);

  HasMany<Post> posts() => relation('posts');
  BelongsToMany<Role> roles() => relation('roles');

  final int? id;
  final String name;
  final String email;
  final bool active;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  @override
  final DateTime? deletedAt;

  static User fromMap(Map<String, Object?> m) => User(
    id: m['id'] as int?, name: m['name'] as String, email: m['email'] as String,
    active: m['active'] as bool? ?? true,
    createdAt: m['created_at'] as DateTime?, updatedAt: m['updated_at'] as DateTime?,
    deletedAt: m['deleted_at'] as DateTime?,
  );

  @override
  Map<String, Object?> toMap() => {'id': id, 'name': name, 'email': email,
    'active': active, 'created_at': createdAt, 'updated_at': updatedAt,
    'deleted_at': deletedAt};
}
```

Notes on the departures from Laravel Eloquent, and why:

| Laravel Eloquent | Seshat | Why |
|---|---|---|
| `User::where()` inherited from `Model` | `static QueryBuilder<User> query() => def.query();` | Statics are not inherited in Dart. One line per static you want. |
| `$user->name = 'x'; $user->save()` | `final renamed = await user.update({'name': 'x'});` returns a new instance | Typed final fields instead of a property bag. Dirty tracking still writes only changed columns. |
| `$user->posts` may silently query | `user.posts().value` (eager loaded only, throws otherwise) / `user.posts().get()` | No hidden queries behind property access. |
| `protected $casts` | `casts: {...}` plus `Cast` helpers; `fromMap` receives Dart values | `fromMap`/`toMap` are the typed boundary. |
| `boot()`, observers, traits | `ModelDefinition(globalScopes:, events:, softDeletes:)` | Explicit and greppable. |
| `hasMany()` declared on the instance | declared once in `relations: (r) => r.hasMany(...)`, accessed via `relation('posts')` | Static knowledge lets `with_()` and `whereHas()` work without an instance. |

Write `static final ModelDefinition<User> def` with the explicit type when
models reference each other; the relations closure is evaluated lazily so
`User.def` and `Post.def` may refer to one another.

## Querying

```dart
final user = await User.find(1);
final user = await User.query().where('email', email).first();       // null when missing
final user = await User.query().where('email', email).firstOrFail(); // ModelNotFoundException
final user = await User.create({'name': 'Abdullah', 'email': 'a@example.com'});
final renamed = await user.update({'name': 'Abdullah Ghanem'});
await renamed.delete();
```

Builder methods: `select`, `addSelect`, `selectRaw`, `distinct`, `join`,
`leftJoin`, `rightJoin`, `crossJoin`, `where` (2 or 3 args, or a closure
for a nested group), `orWhere`, `whereNot`, `whereNull`, `whereNotNull`,
`whereIn` (list or subquery), `whereNotIn`, `whereBetween`,
`whereNotBetween`, `whereLike` (`caseInsensitive:` for `ilike`),
`whereColumn`, `whereExists`, `whereRaw`, `whereKey`, `whereHas`,
`orWhereHas`, `whereDoesntHave`, `has`, `groupBy`, `having`, `havingRaw`,
`orderBy(column, descending:)`, `orderByDesc`, `orderByRaw`, `latest`,
`oldest`, `reorder`, `limit`/`take`, `offset`/`skip`, `forPage`, `with_`,
`withWhere`, `withoutGlobalScope(s)`, `withTrashed`, `onlyTrashed`, `using`.

Terminal methods: `get`, `first`, `firstOrNull`, `firstOrFail`, `find`,
`findOrFail`, `findMany`, `count`, `exists`, `doesntExist`, `sum`, `avg`,
`min`, `max`, `pluck(column, [key])`, `value`, `paginate`, `chunk`, `lazy`,
`insert`, `insertGetId`, `update`, `increment`, `decrement`, `delete`,
`forceDelete`, `restore`, `truncate`, `create`, `forceCreate`,
`firstOrCreate`, `updateOrCreate`, `toSql`, `compile`.

`DB.table('users')` gives the same builder over plain `Map` rows.

### Scopes

Local scopes are extension methods on the typed builder; global scopes are
named on the definition and can be removed by name:

```dart
extension UserScopes on QueryBuilder<User> {
  QueryBuilder<User> active() => where('active', true);
  QueryBuilder<User> recent() => orderBy('created_at', descending: true);
}
await User.query().active().recent().get();

// ModelDefinition(globalScopes: {'tenant': (q) => q.where('tenant_id', tenant)})
await User.query().withoutGlobalScope('tenant').get();
```

### Relationships

```dart
final posts = await user.posts().get();
await user.posts().create({'title': 'Hello'});

final users = await User.with_(['posts', 'posts.comments', 'roles']).get();
users.first.posts().value;                       // List<Post>, no query
await User.query().withWhere('posts', (q) => q.where('published', true)).get();
await User.query().whereHas('posts', (q) => q.where('published', true)).get();

await user.roles().attach(2, {'granted_by': 'admin'});
await user.roles().sync([1, 2]);
roles.first.pivot;                               // pivot columns as a map
```

### Pagination and streaming

```dart
final page = await User.query().paginate(page: 1, perPage: 20);
page.data; page.total; page.currentPage; page.lastPage; page.hasMorePages;
page.toJson();                                   // Laravel-shaped

await User.query().chunk(500, (rows) { ... });   // return false to stop
await for (final u in User.query().lazy()) { ... }
```

### Transactions

```dart
await db.transaction((tx) async {
  final user = await User.using(tx).create(data);
  await Profile.query().using(tx).create({'user_id': user.id});
  await tx.transaction((inner) async { ... });   // savepoint
});
```

Commits when the callback returns, rolls back and rethrows when it throws.
On SQLite the transaction object is the connection itself (single
handle); on PostgreSQL it is a dedicated session, so always use the
object you were handed.

### Migrations

```dart
class CreateUsersTable extends Migration {
  @override
  Future<void> up(SchemaBuilder schema) => schema.create('users', (table) {
    table.id();
    table.string('name');
    table.string('email').unique();
    table.boolean('active').defaultValue(true);
    table.foreignId('team_id').constrained().onDelete('cascade');
    table.timestamps();
    table.softDeletes();
  });

  @override
  Future<void> down(SchemaBuilder schema) => schema.dropIfExists('users');
}

final migrator = Migrator(db, [CreateUsersTable()], log: print);
await migrator.run();          // rollback({steps}), reset(), refresh(), status()
```

`bin/console.dart` shows a five-line CLI: `migrate`, `migrate:rollback
--step=N`, `migrate:reset`, `migrate:refresh`, `migrate:status`.

### Events

```dart
events: ModelEvents<User>(
  creating: (u) => u.email.contains('@'),   // return false to abort
  created:  (u) async => audit.log('created', u.id),
)
```

Hooks: `saving`, `creating`, `updating`, `deleting`, `restoring` (can veto)
and `saved`, `created`, `updated`, `deleted`, `restored`. Models are
immutable, so hooks observe and veto; they do not rewrite attributes.

### Observing queries

```dart
db.listen((e) => log.debug('${e.duration.inMilliseconds}ms ${e.sql} ${e.bindings}'));
db.enableQueryLog(); ...; db.queryLog.length;   // handy in tests
```

## Security

- Every value is a bound parameter. Nothing you pass as a value is ever
  concatenated into SQL.
- Table, column and alias names must match `[A-Za-z_][A-Za-z0-9_]*`
  (dot-qualified allowed) or `InvalidIdentifierException` is thrown.
  Operators come from a whitelist. Sort direction is a `bool`.
- `RawSql.expression('...')` / `whereRaw` / `orderByRaw` are the only way
  to put text into a statement verbatim. They are **trusted code**: never
  build them from request input. Values inside raw fragments still go
  through `?` bindings.
- Mass assignment: `fillable` whitelists, `guarded` blacklists. A model
  with neither is totally guarded and `create()`/`update()` throw
  `MassAssignmentException`. `forceCreate`/`forceUpdate` bypass for
  trusted data.
- Sorting from a request: map the input through your own whitelist and
  pass `descending: input == 'desc'`.

## Not in this release (and why)

- `morphTo`/`morphMany`, `hasManyThrough`: postponed until the four core
  relations have real-world mileage.
- MySQL adapter: the maintained drivers are stale; the grammar hooks are in
  place (`Grammar`, `SchemaGrammar`).
- Attribute mutation (`$user->name = ...`), `$appends`, `$hidden`,
  accessors/mutators: replaced by typed fields and `toMap`/`toJson`.
- Model factories/seeders, observers as classes, query caching, read/write
  splitting, JSON path where clauses, `withCount`, `chunkById`, cursor
  pagination, `lockForUpdate`: not needed for the MVP.
- Code generation for `fromMap`/`toMap`: designed as a future optional
  package; the runtime API does not depend on it.

## Development

```sh
dart test                                   # SQLite, in-memory
PG_TEST_URL=postgres://user@host:5432/db dart test test/postgres_test.dart
dart run benchmark/orm_benchmark.dart
```
