import '../database/connection.dart';
import '../events/model_events.dart';
import '../exceptions/exceptions.dart';
import '../query/query_builder.dart';
import '../relations/relation.dart';
import 'model_definition.dart';

/// Base class for models. Subclasses are immutable value objects with
/// typed fields; persistence methods return new instances rather than
/// mutating `this`.
///
/// ```dart
/// final user = await User.query().create({'name': 'Ann', 'email': 'a@b.c'});
/// final renamed = await user.update({'name': 'Anne'});
/// await renamed.delete();
/// ```
abstract class Model<T extends Model<T>> {
  ModelDefinition<T> get definition;

  /// Column → value, in Dart types. The single source of truth for what
  /// gets written; `null` for an auto-incrementing key means "not yet".
  Map<String, Object?> toMap();

  /// Whether this instance corresponds to a row in the database.
  bool exists = false;

  /// True on the instance returned by the insert that created the row.
  bool wasRecentlyCreated = false;

  /// The connection this instance was loaded through, if not the default.
  Connection? connection;

  /// Prefix under which BelongsToMany selects pivot columns.
  static const pivotPrefix = 'pivot_';

  /// Pivot row values when loaded through a BelongsToMany relation.
  Map<String, Object?>? pivot;

  Map<String, Object?>? _original;
  final Map<String, Object?> _relations = {};

  T get _self => this as T;

  Object? get key => toMap()[definition.primaryKey];

  /// Attribute values as loaded from the database.
  Map<String, Object?> get original => Map.unmodifiable(_original ?? const {});

  /// Attributes whose current value differs from [original]. For a new
  /// model, every non-null attribute.
  Map<String, Object?> get dirty {
    final current = toMap();
    final orig = _original;
    if (orig == null) {
      return {
        for (final e in current.entries)
          if (e.value != null) e.key: e.value,
      };
    }
    return {
      for (final e in current.entries)
        if (!orig.containsKey(e.key) || orig[e.key] != e.value) e.key: e.value,
    };
  }

  bool get isDirty => dirty.isNotEmpty;

  void setOriginal(Map<String, Object?>? attributes) => _original = attributes;

  /// A query for this model's table on this instance's connection.
  QueryBuilder<T> newQuery() => definition.query(connection: connection);

  /// Pin this instance (and what it saves) to [tx]. The static
  /// `Model.using(tx)` form covers queries; this covers an instance you
  /// already hold.
  T onConnection(Connection tx) {
    connection = tx;
    return _self;
  }

  // ---------------------------------------------------------------------------
  // Persistence
  // ---------------------------------------------------------------------------

  /// Inserts a new model or writes the dirty attributes of an existing
  /// one. Returns the persisted instance (with key and timestamps).
  Future<T> save() async {
    if (!await _veto((e) => e.saving)) return _self;
    final T saved;
    if (exists) {
      final changes = dirty;
      if (changes.isEmpty) {
        await _fire((e) => e.saved);
        return _self;
      }
      if (!await _veto((e) => e.updating)) return _self;
      saved = await _performUpdate(changes);
      await _fire((e) => e.updated, saved);
    } else {
      if (!await _veto((e) => e.creating)) return _self;
      saved = await _performInsert();
      await _fire((e) => e.created, saved);
    }
    await _fire((e) => e.saved, saved);
    return saved;
  }

  Future<T> _performInsert() async {
    final def = definition;
    final attributes = {...toMap()};
    if (def.incrementing && attributes[def.primaryKey] == null) {
      attributes.remove(def.primaryKey);
    }
    if (def.timestamps) {
      final now = DateTime.now().toUtc();
      attributes[def.createdAtColumn] ??= now;
      attributes[def.updatedAtColumn] ??= now;
    }
    final query = newQuery();
    if (def.incrementing) {
      final id = await query.insertGetId(attributes);
      attributes[def.primaryKey] = id;
    } else {
      await query.insert(attributes);
    }
    final model =
        def.instantiate(attributes, connection: connection, exists: true)
            as Model;
    model
      ..wasRecentlyCreated = true
      .._relations.addAll(_relations);
    return model as T;
  }

  Future<T> _performUpdate(Map<String, Object?> changes) async {
    final def = definition;
    if (def.timestamps) changes[def.updatedAtColumn] = DateTime.now().toUtc();
    // Filter on the key as loaded, so changing the key itself still hits
    // the right row.
    final id = _original?[def.primaryKey] ?? _requireKey('update');
    await newQuery().withoutGlobalScopes().whereKey(id).update(changes);
    final model =
        def.instantiate(
              {...toMap(), ...changes},
              connection: connection,
              exists: true,
            )
            as Model;
    model._relations.addAll(_relations);
    return model as T;
  }

  /// Mass-assigns [attributes] (respecting fillable/guarded) and saves.
  Future<T> update(Map<String, Object?> attributes) {
    _requireKey('update');
    return fill(attributes).save();
  }

  /// Like [update] but ignores fillable/guarded. For trusted data only.
  Future<T> forceUpdate(Map<String, Object?> attributes) {
    _requireKey('update');
    return fill(attributes, force: true).save();
  }

  /// A copy with [attributes] applied, not yet saved.
  T fill(Map<String, Object?> attributes, {bool force = false}) {
    final def = definition;
    final attrs = force ? attributes : def.fillableAttributes(attributes);
    final model =
        def.instantiate(
              {...toMap(), ...attrs},
              connection: connection,
              exists: exists,
            )
            as Model;
    model
      ..setOriginal(_original)
      .._relations.addAll(_relations);
    return model as T;
  }

  /// Deletes the row (soft-deletes when the definition says so).
  Future<bool> delete() => _delete(force: false);

  /// Deletes the row for real, even with soft deletes.
  Future<bool> forceDelete() => _delete(force: true);

  Future<bool> _delete({required bool force}) async {
    final id = _requireKey('delete');
    if (!await _veto((e) => e.deleting)) return false;
    final query = newQuery().withoutGlobalScopes().whereKey(id);
    await (force ? query.forceDelete() : query.delete());
    // A soft-deleted row is still there; only a real delete removes it.
    exists = definition.softDeletes && !force;
    await _fire((e) => e.deleted);
    return true;
  }

  /// Re-reads the row (and any loaded relations) from the database.
  Future<T> refresh() async {
    final query = newQuery().withoutGlobalScopes().whereKey(
      _requireKey('refresh'),
    );
    if (_relations.isNotEmpty) query.with_(_relations.keys.toList());
    return query.firstOrFail();
  }

  /// The primary key, or throws when this instance was never persisted.
  Object requireKey(String operation) => _requireKey(operation);

  Object _requireKey(String operation) {
    final id = key;
    if (!exists || id == null) {
      throw ModelNotPersistedException(definition.modelName, operation);
    }
    return id;
  }

  Future<bool> _veto(VetoHook<T>? Function(ModelEvents<T> events) pick) {
    final events = definition.events;
    if (events == null) return Future.value(true);
    return events.before(pick(events), _self);
  }

  Future<void> _fire(
    AfterHook<T>? Function(ModelEvents<T> events) pick, [
    T? model,
  ]) {
    final events = definition.events;
    if (events == null) return Future.value();
    return events.after(pick(events), model ?? _self);
  }

  // ---------------------------------------------------------------------------
  // Relations
  // ---------------------------------------------------------------------------

  /// The relation named [name], bound to this instance:
  /// `HasMany<Post> posts() => relation('posts');`
  R relation<R extends Relation<Object?>>(String name) =>
      definition.relationFor(name).bind(this) as R;

  bool relationLoaded(String name) => _relations.containsKey(name);
  Object? getRelation(String name) => _relations[name];
  void setRelation(String name, Object? value) => _relations[name] = value;
  Map<String, Object?> get loadedRelations => Map.unmodifiable(_relations);

  /// Loads relations onto this instance after the fact.
  Future<T> load(List<String> relations) async {
    final fresh = await newQuery()
        .withoutGlobalScopes()
        .whereKey(_requireKey('load'))
        .with_(relations)
        .firstOrFail();
    for (final e in (fresh as Model)._relations.entries) {
      _relations[e.key] = e.value;
    }
    return _self;
  }

  // ---------------------------------------------------------------------------
  // Serialisation
  // ---------------------------------------------------------------------------

  /// [toMap] plus loaded relations, with `DateTime` as ISO-8601 and nested
  /// models serialised the same way. Suitable for `jsonEncode`.
  Map<String, Object?> toJson() => {
    for (final e in toMap().entries) e.key: _json(e.value),
    for (final e in _relations.entries) e.key: _json(e.value),
  };

  static Object? _json(Object? value) {
    if (value is DateTime) return value.toIso8601String();
    if (value is Model) return value.toJson();
    if (value is Enum) return value.name;
    if (value is List) return [for (final v in value) _json(v)];
    return value;
  }

  @override
  String toString() => '${definition.modelName}(${toMap()})';
}
