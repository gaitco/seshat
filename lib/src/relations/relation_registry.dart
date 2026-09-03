import '../model/model_definition.dart';
import 'belongs_to.dart';
import 'belongs_to_many.dart';
import 'has_many.dart';
import 'has_one.dart';
import 'relation.dart';

/// Collects a model's relations with fully inferred types:
///
/// ```dart
/// relations: (r) => r
///   ..hasMany('posts', Post.def, foreignKey: 'user_id')
///   ..hasOne('profile', Profile.def, foreignKey: 'user_id')
///   ..belongsToMany('roles', Role.def, pivotTable: 'role_user',
///       foreignPivotKey: 'user_id', relatedPivotKey: 'role_id'),
/// ```
class RelationRegistry {
  final Map<String, Relation<Object?>> _relations = {};

  Map<String, Relation<Object?>> get relations => _relations;

  void add(String name, Relation<Object?> relation) {
    if (_relations.containsKey(name)) {
      throw ArgumentError("Relation '$name' is declared twice");
    }
    _relations[name] = relation;
  }

  HasMany<R> hasMany<R>(
    String name,
    ModelDefinition<R> related, {
    required String foreignKey,
    String? localKey,
  }) {
    final r = HasMany<R>(related, foreignKey: foreignKey, localKey: localKey);
    add(name, r);
    return r;
  }

  HasOne<R> hasOne<R>(
    String name,
    ModelDefinition<R> related, {
    required String foreignKey,
    String? localKey,
  }) {
    final r = HasOne<R>(related, foreignKey: foreignKey, localKey: localKey);
    add(name, r);
    return r;
  }

  BelongsTo<R> belongsTo<R>(
    String name,
    ModelDefinition<R> related, {
    required String foreignKey,
    String? ownerKey,
  }) {
    final r = BelongsTo<R>(related, foreignKey: foreignKey, ownerKey: ownerKey);
    add(name, r);
    return r;
  }

  BelongsToMany<R> belongsToMany<R>(
    String name,
    ModelDefinition<R> related, {
    required String pivotTable,
    required String foreignPivotKey,
    required String relatedPivotKey,
    String? parentKey,
    String? relatedKey,
    List<String> pivotColumns = const [],
  }) {
    final r = BelongsToMany<R>(
      related,
      pivotTable: pivotTable,
      foreignPivotKey: foreignPivotKey,
      relatedPivotKey: relatedPivotKey,
      parentKey: parentKey,
      relatedKey: relatedKey,
      pivotColumns: pivotColumns,
    );
    add(name, r);
    return r;
  }
}
