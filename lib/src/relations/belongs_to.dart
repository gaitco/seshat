import '../database/connection.dart';
import '../model/model.dart';
import '../query/query_builder.dart';
import 'relation.dart';

/// `posts.user_id → users.id`: the parent points at one [R].
///
/// ```dart
/// relations: (r) => r.belongsTo('user', User.def, foreignKey: 'user_id'),
/// BelongsTo<User> user() => relation('user');
/// ```
class BelongsTo<R> extends Relation<R> {
  BelongsTo(super.related, {required this.foreignKey, this._ownerKey});

  /// Column on the parent's table.
  final String foreignKey;
  final String? _ownerKey;

  /// Column on the related table, defaults to its primary key.
  String get ownerKey => _ownerKey ?? related.primaryKey;
  String get qualifiedOwnerKey => '${related.table}.$ownerKey';

  @override
  BelongsTo<R> bind(Model model) =>
      BelongsTo<R>(related, foreignKey: foreignKey, ownerKey: _ownerKey)
        ..parent = parent
        ..name = name
        ..instance = model;

  R? get value => loaded as R?;

  Object? get foreignKeyValue => boundInstance.toMap()[foreignKey];

  @override
  QueryBuilder<R> query() => related
      .query(connection: connection)
      .where(qualifiedOwnerKey, foreignKeyValue);

  Future<R?> get() => query().first();

  Future<R?> first() => get();

  @override
  void addExistenceConstraint(QueryBuilder<R> query, String parentQualifier) =>
      query.whereColumn(
        '${query.qualifier}.$ownerKey',
        '$parentQualifier.$foreignKey',
      );

  @override
  Future<void> eagerLoad(
    List<Model> parents,
    Connection connection, {
    RelationConstraint? constraint,
    List<String> nested = const [],
  }) async {
    final keys = {for (final p in parents) p.toMap()[foreignKey]}..remove(null);
    final byKey = <Object?, R>{};
    if (keys.isNotEmpty) {
      final query = related.query(connection: connection)
        ..whereIn(qualifiedOwnerKey, keys.toList());
      for (final row in await prepareEagerQuery(
        query,
        constraint,
        nested,
      ).get()) {
        byKey[(row as Model).toMap()[ownerKey]] = row;
      }
    }
    for (final p in parents) {
      p.setRelation(name, byKey[p.toMap()[foreignKey]]);
    }
  }
}
