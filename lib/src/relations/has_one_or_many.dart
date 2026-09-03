import '../database/connection.dart';
import '../model/model.dart';
import '../query/query_builder.dart';
import 'relation.dart';

/// Shared mechanics of `hasOne` and `hasMany`: the related table carries
/// [foreignKey] pointing at the parent's [localKey].
abstract class HasOneOrMany<R> extends Relation<R> {
  HasOneOrMany(super.related, {required this.foreignKey, this._localKey});

  final String foreignKey;
  final String? _localKey;

  String get localKey => _localKey ?? parent.primaryKey;
  String get qualifiedForeignKey => '${related.table}.$foreignKey';

  Object? get parentKeyValue => boundInstance.toMap()[localKey];

  @override
  QueryBuilder<R> query() => related
      .query(connection: connection)
      .where(qualifiedForeignKey, parentKeyValue);

  Future<List<R>> get() => query().get();

  Future<R?> first() => query().first();

  /// Creates a related row already pointing at the parent.
  Future<R> create(Map<String, Object?> attributes) => related.create(
    {...attributes, foreignKey: parentKeyValue},
    connection: connection,
    force: true,
  );

  @override
  void addExistenceConstraint(QueryBuilder<R> query, String parentQualifier) =>
      query.whereColumn(
        '${query.qualifier}.$foreignKey',
        '$parentQualifier.$localKey',
      );

  /// Loads all related rows for [parents] in one query, grouped by
  /// foreign key.
  Future<Map<Object?, List<R>>> loadGrouped(
    List<Model> parents,
    Connection connection,
    RelationConstraint? constraint,
    List<String> nested,
  ) async {
    final keys = {for (final p in parents) p.toMap()[localKey]}..remove(null);
    if (keys.isEmpty) return const {};
    final query = related.query(connection: connection)
      ..whereIn(qualifiedForeignKey, keys.toList());
    final rows = await prepareEagerQuery(query, constraint, nested).get();
    final grouped = <Object?, List<R>>{};
    for (final row in rows) {
      grouped
          .putIfAbsent((row as Model).toMap()[foreignKey], () => [])
          .add(row);
    }
    return grouped;
  }
}
