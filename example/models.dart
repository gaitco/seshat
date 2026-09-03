// Example models shared by the example scripts.
import 'package:seshat/seshat.dart';

enum Role { admin, member }

class User extends Model<User> with SoftDeletes<User> {
  User({
    this.id,
    required this.name,
    required this.email,
    this.role = Role.member,
    this.active = true,
    this.createdAt,
    this.updatedAt,
    this.deletedAt,
  });

  // Everything Seshat keeps in static properties lives here.
  static final ModelDefinition<User> def = ModelDefinition<User>(
    table: 'users',
    fromMap: User.fromMap,
    fillable: ['name', 'email', 'role', 'active'],
    casts: {
      'role': Cast.enumeration(Role.values),
      'active': Cast.boolean,
      'created_at': Cast.dateTime,
      'updated_at': Cast.dateTime,
      'deleted_at': Cast.dateTime,
    },
    softDeletes: true,
    relations: (r) => r.hasMany('posts', Post.def, foreignKey: 'user_id'),
    events: ModelEvents<User>(
      created: (u) => print('  [event] created user #${u.id}'),
    ),
  );

  @override
  ModelDefinition<User> get definition => def;

  // Dart has no static inheritance: forward the statics you want.
  static QueryBuilder<User> query() => def.query();
  static Future<User?> find(Object id) => def.find(id);
  static Future<User> findOrFail(Object id) => def.findOrFail(id);
  static Future<User> create(Map<String, Object?> attrs) =>
      def.query().create(attrs);
  static QueryBuilder<User> with_(List<String> relations) =>
      def.with_(relations);
  static QueryBuilder<User> using(Connection tx) => def.using(tx);

  HasMany<Post> posts() => relation('posts');

  final int? id;
  final String name;
  final String email;
  final Role role;
  final bool active;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  @override
  final DateTime? deletedAt;

  static User fromMap(Map<String, Object?> m) => User(
    id: m['id'] as int?,
    name: m['name'] as String,
    email: m['email'] as String,
    role: m['role'] as Role? ?? Role.member,
    active: m['active'] as bool? ?? true,
    createdAt: m['created_at'] as DateTime?,
    updatedAt: m['updated_at'] as DateTime?,
    deletedAt: m['deleted_at'] as DateTime?,
  );

  @override
  Map<String, Object?> toMap() => {
    'id': id,
    'name': name,
    'email': email,
    'role': role,
    'active': active,
    'created_at': createdAt,
    'updated_at': updatedAt,
    'deleted_at': deletedAt,
  };
}

/// Local scopes are extension methods on the typed builder.
extension UserScopes on QueryBuilder<User> {
  QueryBuilder<User> active() => where('active', true);
  QueryBuilder<User> recent() => orderBy('created_at', descending: true);
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
    relations: (r) => r.belongsTo('user', User.def, foreignKey: 'user_id'),
  );

  @override
  ModelDefinition<Post> get definition => def;
  static QueryBuilder<Post> query() => def.query();

  BelongsTo<User> user() => relation('user');

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
