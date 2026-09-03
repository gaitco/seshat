import '../database/connection.dart';
import '../database/database.dart';
import '../model/model.dart';
import '../query/query_builder.dart';
import '../support/identifiers.dart';
import 'relation.dart';

/// `users ↔ role_user ↔ roles`: many-to-many through a pivot table.
///
/// ```dart
/// relations: (r) => r.belongsToMany('roles', Role.def,
///     pivotTable: 'role_user', foreignPivotKey: 'user_id',
///     relatedPivotKey: 'role_id', pivotColumns: ['granted_by']),
/// final roles = await user.roles().get();
/// roles.first.pivot; // {'user_id': 1, 'role_id': 2, 'granted_by': ...}
/// await user.roles().attach(2, {'granted_by': 'admin'});
/// ```
class BelongsToMany<R> extends Relation<R> {
  BelongsToMany(
    super.related, {
    required this.pivotTable,
    required this.foreignPivotKey,
    required this.relatedPivotKey,
    this._parentKey,
    this._relatedKey,
    this.pivotColumns = const [],
  }) {
    assertIdentifier(pivotTable);
  }

  final String pivotTable;

  /// Pivot column pointing at the parent (`user_id`).
  final String foreignPivotKey;

  /// Pivot column pointing at the related model (`role_id`).
  final String relatedPivotKey;
  final String? _parentKey;
  final String? _relatedKey;

  /// Extra pivot columns to select onto `model.pivot`.
  final List<String> pivotColumns;

  String get parentKey => _parentKey ?? parent.primaryKey;
  String get relatedKey => _relatedKey ?? related.primaryKey;

  @override
  BelongsToMany<R> bind(Model model) =>
      BelongsToMany<R>(
          related,
          pivotTable: pivotTable,
          foreignPivotKey: foreignPivotKey,
          relatedPivotKey: relatedPivotKey,
          parentKey: _parentKey,
          relatedKey: _relatedKey,
          pivotColumns: pivotColumns,
        )
        ..parent = parent
        ..name = name
        ..instance = model;

  List<R> get value => (loaded as List).cast<R>();

  Object? get parentKeyValue => boundInstance.toMap()[parentKey];

  /// Related rows joined to the pivot, with pivot columns selected as
  /// `pivot_<column>` so hydration can move them onto `model.pivot`.
  QueryBuilder<R> _joined(Connection? connection) =>
      related.query(connection: connection)
        ..join(
          pivotTable,
          '$pivotTable.$relatedPivotKey',
          '=',
          '${related.table}.$relatedKey',
        )
        ..select([
          '${related.table}.*',
          for (final c in {foreignPivotKey, relatedPivotKey, ...pivotColumns})
            '$pivotTable.$c as ${Model.pivotPrefix}$c',
        ]);

  @override
  QueryBuilder<R> query() =>
      _joined(connection).where('$pivotTable.$foreignPivotKey', parentKeyValue);

  Future<List<R>> get() => query().get();

  @override
  void addExistenceConstraint(QueryBuilder<R> query, String parentQualifier) =>
      query
        ..join(
          pivotTable,
          '$pivotTable.$relatedPivotKey',
          '=',
          '${query.qualifier}.$relatedKey',
        )
        ..whereColumn(
          '$pivotTable.$foreignPivotKey',
          '$parentQualifier.$parentKey',
        );

  @override
  Future<void> eagerLoad(
    List<Model> parents,
    Connection connection, {
    RelationConstraint? constraint,
    List<String> nested = const [],
  }) async {
    final keys = {for (final p in parents) p.toMap()[parentKey]}..remove(null);
    final grouped = <Object?, List<R>>{};
    if (keys.isNotEmpty) {
      final query = _joined(connection)
        ..whereIn('$pivotTable.$foreignPivotKey', keys.toList());
      for (final row in await prepareEagerQuery(
        query,
        constraint,
        nested,
      ).get()) {
        grouped
            .putIfAbsent((row as Model).pivot?[foreignPivotKey], () => [])
            .add(row);
      }
    }
    for (final p in parents) {
      p.setRelation(name, grouped[p.toMap()[parentKey]] ?? <R>[]);
    }
  }

  // ---------------------------------------------------------------------------
  // Pivot writes
  // ---------------------------------------------------------------------------

  QueryBuilder<Row> _pivot() => DB
      .table(pivotTable, connection: connection ?? parent.connection)
      .where(foreignPivotKey, parentKeyValue);

  /// Links [ids] (one id or a list) to the parent, with optional extra
  /// pivot columns.
  Future<void> attach(
    Object ids, [
    Map<String, Object?> extra = const {},
  ]) async {
    final list = ids is Iterable ? ids.toList() : [ids];
    if (list.isEmpty) return;
    await DB
        .table(pivotTable, connection: connection ?? parent.connection)
        .insert([
          for (final id in list)
            {foreignPivotKey: parentKeyValue, relatedPivotKey: id, ...extra},
        ]);
  }

  /// Unlinks [ids], or everything when [ids] is `null`. Returns rows removed.
  Future<int> detach([Object? ids]) {
    final q = _pivot();
    if (ids != null) {
      q.whereIn(relatedPivotKey, ids is Iterable ? ids.toList() : [ids]);
    }
    return q.delete();
  }

  /// Makes the pivot contain exactly [ids]. Returns what changed.
  Future<({List<Object?> attached, List<Object?> detached})> sync(
    Iterable<Object?> ids,
  ) async {
    final wanted = ids.toSet();
    final current = (await _pivot().pluckList(relatedPivotKey)).toSet();
    final toDetach = current.difference(wanted).toList();
    final toAttach = wanted.difference(current).toList();
    if (toDetach.isNotEmpty) await detach(toDetach);
    if (toAttach.isNotEmpty) await attach(toAttach);
    return (attached: toAttach, detached: toDetach);
  }
}
