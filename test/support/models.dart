import 'package:maat_seshat_core/maat_seshat_core.dart';
import 'package:maat_seshat_core/sqlite.dart';

enum Role { admin, member }

class User extends Model<User> with SoftDeletes<User> {
  User({
    this.id,
    required this.name,
    required this.email,
    this.active = true,
    this.role = Role.member,
    this.age,
    this.meta,
    this.createdAt,
    this.updatedAt,
    this.deletedAt,
  });

  static final ModelDefinition<User> def = ModelDefinition<User>(
    table: 'users',
    fromMap: User.fromMap,
    fillable: ['name', 'email', 'active', 'role', 'age', 'meta'],
    casts: {
      'active': Cast.boolean,
      'role': Cast.enumeration(Role.values),
      'meta': Cast.json,
      'created_at': Cast.dateTime,
      'updated_at': Cast.dateTime,
      'deleted_at': Cast.dateTime,
    },
    softDeletes: true,
    relations: (r) => r
      ..hasMany('posts', Post.def, foreignKey: 'user_id')
      // Self-referencing, and User soft-deletes: proves an aliased
      // subquery's global scopes qualify against the alias too.
      ..hasMany('invitees', User.def, foreignKey: 'invited_by')
      ..hasOne('profile', Profile.def, foreignKey: 'user_id')
      ..belongsToMany(
        'roles',
        RoleModel.def,
        pivotTable: 'role_user',
        foreignPivotKey: 'user_id',
        relatedPivotKey: 'role_id',
        pivotColumns: ['granted_by'],
      ),
    events: ModelEvents<User>(
      creating: (u) => !u.email.endsWith('@blocked.test'),
      deleting: (u) => u.name != 'Immortal',
      restored: (u) => log.add('restored ${u.name}'),
      created: (u) => log.add('created ${u.name}'),
      updated: (u) => log.add('updated ${u.name}'),
      deleted: (u) => log.add('deleted ${u.name}'),
    ),
  );

  static final log = <String>[];

  @override
  ModelDefinition<User> get definition => def;

  static QueryBuilder<User> query() => def.query();
  static Future<User?> find(Object id) => def.find(id);
  static Future<User> findOrFail(Object id) => def.findOrFail(id);
  static Future<User> create(Map<String, Object?> attrs) =>
      def.query().create(attrs);
  static QueryBuilder<User> with_(List<String> relations) =>
      def.with_(relations);
  static QueryBuilder<User> using(Connection tx) => def.using(tx);
  static QueryBuilder<User> withTrashed() => def.withTrashed();
  static QueryBuilder<User> onlyTrashed() => def.onlyTrashed();

  HasMany<Post> posts() => relation('posts');
  HasOne<Profile> profile() => relation('profile');
  BelongsToMany<RoleModel> roles() => relation('roles');

  final int? id;
  final String name;
  final String email;
  final bool active;
  final Role role;
  final int? age;
  final Map<String, Object?>? meta;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  @override
  final DateTime? deletedAt;

  static User fromMap(Map<String, Object?> map) => User(
    id: map['id'] as int?,
    name: map['name'] as String,
    email: map['email'] as String,
    active: map['active'] as bool? ?? true,
    role: map['role'] as Role? ?? Role.member,
    age: map['age'] as int?,
    meta: (map['meta'] as Map?)?.cast<String, Object?>(),
    createdAt: map['created_at'] as DateTime?,
    updatedAt: map['updated_at'] as DateTime?,
    deletedAt: map['deleted_at'] as DateTime?,
  );

  @override
  Map<String, Object?> toMap() => {
    'id': id,
    'name': name,
    'email': email,
    'active': active,
    'role': role,
    'age': age,
    'meta': meta,
    'created_at': createdAt,
    'updated_at': updatedAt,
    'deleted_at': deletedAt,
  };
}

/// A model with no timestamps, no fillable list (totally guarded) and a
/// string primary key.
class Setting extends Model<Setting> {
  Setting({required this.key, required this.value});

  static final def = ModelDefinition<Setting>(
    table: 'settings',
    fromMap: (m) =>
        Setting(key: m['key'] as String, value: m['value'] as String?),
    primaryKey: 'key',
    incrementing: false,
    timestamps: false,
  );

  @override
  ModelDefinition<Setting> get definition => def;
  static QueryBuilder<Setting> query() => def.query();

  @override
  final String key;
  final String? value;

  @override
  Map<String, Object?> toMap() => {'key': key, 'value': value};
}

extension UserScopes on QueryBuilder<User> {
  QueryBuilder<User> active() => where('active', true);
  QueryBuilder<User> recent() => orderBy('created_at', descending: true);
}

/// Fresh in-memory database with the test schema, set as the default.
Future<SqliteConnection> setUpDatabase() async {
  final db = SqliteConnection.inMemory();
  DB.use(db);
  await db.execute('''
    create table users (
      id integer primary key autoincrement,
      name text not null,
      email text not null unique,
      active integer not null default 1,
      role text not null default 'member',
      age integer,
      meta text,
      invited_by integer references users(id),
      created_at text,
      updated_at text,
      deleted_at text
    )''');
  await db.execute('''
    create table settings (key text primary key, value text)''');
  await db.execute('''
    create table posts (
      id integer primary key autoincrement,
      user_id integer not null references users(id),
      title text not null,
      published integer not null default 0,
      created_at text,
      updated_at text
    )''');
  await db.execute('''
    create table comments (
      id integer primary key autoincrement,
      post_id integer not null references posts(id),
      body text not null,
      created_at text,
      updated_at text
    )''');
  await db.execute('''
    create table profiles (
      id integer primary key autoincrement,
      user_id integer not null unique references users(id),
      bio text,
      created_at text,
      updated_at text
    )''');
  await db.execute(
    '''
    create table roles (id integer primary key autoincrement, name text not null)''',
  );
  await db.execute('''
    create table tasks (
      id integer primary key autoincrement,
      title text not null,
      done integer not null default 0,
      parent_id integer references tasks(id)
    )''');
  await db.execute('''
    create table task_links (
      task_id integer not null references tasks(id),
      related_id integer not null references tasks(id),
      primary key (task_id, related_id)
    )''');
  await db.execute('''
    create table role_user (
      user_id integer not null references users(id),
      role_id integer not null references roles(id),
      granted_by text,
      primary key (user_id, role_id)
    )''');
  User.log.clear();
  return db;
}

class Post extends Model<Post> {
  Post({
    this.id,
    required this.userId,
    required this.title,
    this.published = false,
    this.createdAt,
    this.updatedAt,
  });

  static final ModelDefinition<Post> def = ModelDefinition<Post>(
    table: 'posts',
    fromMap: (m) => Post(
      id: m['id'] as int?,
      userId: m['user_id'] as int,
      title: m['title'] as String,
      published: m['published'] as bool? ?? false,
      createdAt: m['created_at'] as DateTime?,
      updatedAt: m['updated_at'] as DateTime?,
    ),
    fillable: ['user_id', 'title', 'published'],
    casts: {
      'published': Cast.boolean,
      'created_at': Cast.dateTime,
      'updated_at': Cast.dateTime,
    },
    relations: (r) => r
      ..belongsTo('user', User.def, foreignKey: 'user_id')
      ..hasMany('comments', Comment.def, foreignKey: 'post_id'),
  );

  @override
  ModelDefinition<Post> get definition => def;
  static QueryBuilder<Post> query() => def.query();

  BelongsTo<User> user() => relation('user');
  HasMany<Comment> comments() => relation('comments');

  final int? id;
  final int userId;
  final String title;
  final bool published;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  @override
  Map<String, Object?> toMap() => {
    'id': id,
    'user_id': userId,
    'title': title,
    'published': published,
    'created_at': createdAt,
    'updated_at': updatedAt,
  };
}

class Comment extends Model<Comment> {
  Comment({this.id, required this.postId, required this.body});

  static final ModelDefinition<Comment> def = ModelDefinition<Comment>(
    table: 'comments',
    fromMap: (m) => Comment(
      id: m['id'] as int?,
      postId: m['post_id'] as int,
      body: m['body'] as String,
    ),
    fillable: ['post_id', 'body'],
    relations: (r) => r.belongsTo('post', Post.def, foreignKey: 'post_id'),
  );

  @override
  ModelDefinition<Comment> get definition => def;
  static QueryBuilder<Comment> query() => def.query();
  BelongsTo<Post> post() => relation('post');

  final int? id;
  final int postId;
  final String body;

  @override
  Map<String, Object?> toMap() => {'id': id, 'post_id': postId, 'body': body};
}

class Profile extends Model<Profile> {
  Profile({this.id, required this.userId, this.bio});

  static final def = ModelDefinition<Profile>(
    table: 'profiles',
    fromMap: (m) => Profile(
      id: m['id'] as int?,
      userId: m['user_id'] as int,
      bio: m['bio'] as String?,
    ),
    fillable: ['user_id', 'bio'],
  );

  @override
  ModelDefinition<Profile> get definition => def;
  static QueryBuilder<Profile> query() => def.query();

  final int? id;
  final int userId;
  final String? bio;

  @override
  Map<String, Object?> toMap() => {'id': id, 'user_id': userId, 'bio': bio};
}

class RoleModel extends Model<RoleModel> {
  RoleModel({this.id, required this.name});

  static final def = ModelDefinition<RoleModel>(
    table: 'roles',
    name: 'Role',
    fromMap: (m) => RoleModel(id: m['id'] as int?, name: m['name'] as String),
    fillable: ['name'],
    timestamps: false,
  );

  @override
  ModelDefinition<RoleModel> get definition => def;
  static QueryBuilder<RoleModel> query() => def.query();

  final int? id;
  final String name;

  @override
  Map<String, Object?> toMap() => {'id': id, 'name': name};
}

/// A self-referencing model: `tasks.parent_id → tasks.id`, plus a
/// self-referencing many-to-many through `task_links`.
class Task extends Model<Task> {
  Task({this.id, required this.title, this.done = false, this.parentId});

  static final ModelDefinition<Task> def = ModelDefinition<Task>(
    table: 'tasks',
    fromMap: (m) => Task(
      id: m['id'] as int?,
      title: m['title'] as String,
      done: m['done'] as bool? ?? false,
      parentId: m['parent_id'] as int?,
    ),
    fillable: ['title', 'done', 'parent_id'],
    casts: {'done': Cast.boolean},
    timestamps: false,
    relations: (r) => r
      ..hasMany('subtasks', Task.def, foreignKey: 'parent_id')
      ..belongsTo('parent', Task.def, foreignKey: 'parent_id')
      ..belongsToMany(
        'links',
        Task.def,
        pivotTable: 'task_links',
        foreignPivotKey: 'task_id',
        relatedPivotKey: 'related_id',
      ),
  );

  @override
  ModelDefinition<Task> get definition => def;
  static QueryBuilder<Task> query() => def.query();

  HasMany<Task> subtasks() => relation('subtasks');
  BelongsTo<Task> parent() => relation('parent');
  BelongsToMany<Task> links() => relation('links');

  final int? id;
  final String title;
  final bool done;
  final int? parentId;

  @override
  Map<String, Object?> toMap() => {
    'id': id,
    'title': title,
    'done': done,
    'parent_id': parentId,
  };
}
