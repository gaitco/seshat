import '../database/connection.dart';
import '../database/database.dart';
import '../events/model_events.dart';
import '../exceptions/exceptions.dart';
import '../query/query_builder.dart';
import '../relations/relation.dart';
import '../relations/relation_registry.dart';
import 'casts.dart';
import 'model.dart';

/// Name of the global scope soft deletes register.
const softDeletesScope = 'softDeletes';

/// A global scope: `(q) => q.where('tenant_id', currentTenant)`.
typedef GlobalScope<T> = void Function(QueryBuilder<T> query);

/// Everything Seshat keeps in static properties and `boot()`: table,
/// key, timestamps, fillable/guarded, casts, relations, global scopes,
/// soft deletes, events. One per model class, declared as a static:
///
/// ```dart
/// class User extends Model<User> {
///   static final ModelDefinition<User> def = ModelDefinition<User>(
///     table: 'users',
///     fromMap: User.fromMap,
///     fillable: ['name', 'email'],
///     casts: {'active': Cast.boolean},
///     relations: (r) => r.hasMany('posts', Post.def, foreignKey: 'user_id'),
///   );
///   @override
///   ModelDefinition<User> get definition => def;
///   static QueryBuilder<User> query() => def.query();
///   ...
/// }
/// ```
class ModelDefinition<T> {
  ModelDefinition({
    required this.table,
    required this._fromMap,
    String? name,
    this.primaryKey = 'id',
    this.incrementing = true,
    this.timestamps = true,
    this.createdAtColumn = 'created_at',
    this.updatedAtColumn = 'updated_at',
    this.fillable = const [],
    this.guarded = const ['*'],
    this.casts = const {},
    this._relations,
    Map<String, GlobalScope<T>> globalScopes = const {},
    this.softDeletes = false,
    this.deletedAtColumn = 'deleted_at',
    this.events,
    this._connection,
  }) : modelName = name ?? T.toString(),
       globalScopes = Map.unmodifiable({
         if (softDeletes)
           softDeletesScope: (QueryBuilder<T> q) =>
               q.whereNull('${q.qualifier}.$deletedAtColumn'),
         ...globalScopes,
       });

  final String table;
  final String modelName;
  final String primaryKey;
  final bool incrementing;
  final bool timestamps;
  final String createdAtColumn;
  final String updatedAtColumn;

  /// Attributes `create()`/`update()`/`fill()` may set. When empty, every
  /// attribute not in [guarded] is fillable.
  final List<String> fillable;

  /// Defaults to `['*']`: everything guarded until you list [fillable].
  final List<String> guarded;

  final Map<String, Cast> casts;
  final void Function(RelationRegistry relations)? _relations;

  /// Built on first use so `User.def` and `Post.def` may reference each
  /// other without a static-initialisation cycle.
  late final Map<String, Relation<Object?>> relations = () {
    final registry = RelationRegistry();
    _relations?.call(registry);
    final map = registry.relations;
    for (final entry in map.entries) {
      entry.value
        ..parent = this
        ..name = entry.key;
    }
    return Map<String, Relation<Object?>>.unmodifiable(map);
  }();
  final Map<String, GlobalScope<T>> globalScopes;
  final bool softDeletes;
  final String deletedAtColumn;
  final ModelEvents<T>? events;

  final T Function(Map<String, Object?> map) _fromMap;
  final Connection Function()? _connection;

  Connection get connection => _connection?.call() ?? DB.connection;

  String get qualifiedKey => '$table.$primaryKey';

  // ---------------------------------------------------------------------------
  // Queries
  // ---------------------------------------------------------------------------

  QueryBuilder<T> query({Connection? connection}) => QueryBuilder<T>(
    connection ?? this.connection,
    table,
    hydrate: (row) => hydrate(row),
    definition: this,
  );

  QueryBuilder<T> using(Connection connection) => query(connection: connection);
  Future<T?> find(Object id) => query().find(id);
  Future<T> findOrFail(Object id) => query().findOrFail(id);
  Future<List<T>> all() => query().get();
  QueryBuilder<T> with_(List<String> relations) => query().with_(relations);
  QueryBuilder<T> withTrashed() => query().withTrashed();
  QueryBuilder<T> onlyTrashed() => query().onlyTrashed();
  QueryBuilder<T> withoutGlobalScope(String name) =>
      query().withoutGlobalScope(name);

  // ---------------------------------------------------------------------------
  // Hydration and casting
  // ---------------------------------------------------------------------------

  /// Database row → model: decode casts, call `fromMap`, mark as existing.
  T hydrate(Row row, {Connection? connection}) {
    Map<String, Object?>? pivot;
    var attributes = row;
    if (row.keys.any((k) => k.startsWith(Model.pivotPrefix))) {
      pivot = {};
      attributes = {};
      for (final e in row.entries) {
        if (e.key.startsWith(Model.pivotPrefix)) {
          pivot[e.key.substring(Model.pivotPrefix.length)] = e.value;
        } else {
          attributes[e.key] = e.value;
        }
      }
    }
    final model = instantiate(
      decodeAttributes(attributes),
      connection: connection,
      exists: true,
    );
    if (pivot != null) (model as Model).pivot = pivot;
    return model;
  }

  /// Dart-valued attributes → model (no cast decoding).
  T instantiate(
    Map<String, Object?> attributes, {
    Connection? connection,
    bool exists = false,
  }) {
    final T model;
    try {
      model = _fromMap(attributes);
    } on TypeError catch (e) {
      throw DatabaseException(
        '$modelName.fromMap failed: $e. Is a required attribute missing or '
        'of the wrong type? Attributes: ${attributes.keys.toList()}',
        cause: e,
      );
    }
    (model as Model)
      ..exists = exists
      ..connection = connection
      ..setOriginal(exists ? attributes : null);
    return model;
  }

  Map<String, Object?> decodeAttributes(Row row) => {
    for (final e in row.entries)
      e.key: casts[e.key]?.decode(e.value) ?? _passthrough(e.key, e.value),
  };

  Object? _passthrough(String key, Object? value) => value;

  Map<String, Object?> encodeAttributes(Map<String, Object?> attributes) => {
    for (final e in attributes.entries)
      e.key: casts[e.key]?.encode?.call(e.value) ?? e.value,
  };

  // ---------------------------------------------------------------------------
  // Mass assignment
  // ---------------------------------------------------------------------------

  bool get totallyGuarded => fillable.isEmpty && guarded.contains('*');

  bool isFillable(String attribute) {
    if (fillable.isNotEmpty) return fillable.contains(attribute);
    return !guarded.contains('*') && !guarded.contains(attribute);
  }

  /// Drops non-fillable attributes. Throws [MassAssignmentException] when
  /// the model is totally guarded, matching Laravel's behaviour.
  Map<String, Object?> fillableAttributes(Map<String, Object?> attributes) {
    final result = <String, Object?>{};
    for (final e in attributes.entries) {
      if (isFillable(e.key)) {
        result[e.key] = e.value;
      } else if (totallyGuarded) {
        throw MassAssignmentException(e.key, modelName);
      }
    }
    return result;
  }

  Future<T> create(
    Map<String, Object?> attributes, {
    Connection? connection,
    bool force = false,
  }) {
    final attrs = force ? attributes : fillableAttributes(attributes);
    final model = instantiate(attrs, connection: connection) as Model;
    return model.save() as Future<T>;
  }

  // ---------------------------------------------------------------------------
  // Relations
  // ---------------------------------------------------------------------------

  Relation<Object?> relationFor(String name) =>
      relations[name] ??
      (throw DatabaseException(
        "Relation '$name' is not defined on $modelName. Add it to the "
        'relations map of its ModelDefinition.',
      ));
}
