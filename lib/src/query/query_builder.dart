import 'dart:async';

import '../database/connection.dart';
import '../database/grammar.dart';
import '../exceptions/exceptions.dart';
import '../model/model.dart';
import '../model/model_definition.dart';
import '../relations/eager_loader.dart';
import '../relations/relation.dart';
import '../support/identifiers.dart';
import '../support/raw_sql.dart';
import 'conditions.dart';
import 'joins.dart';
import 'paginator.dart';

const _absent = Object();

/// A nested where group: `where((q) => q.where(...).orWhere(...))`.
typedef WhereGroup<T> = void Function(QueryBuilder<T> query);

/// Fluent, parameterized SQL builder. [T] is what rows hydrate into: a
/// model when built from a [ModelDefinition], or a [Row] map from
/// `DB.table()`.
///
/// Every value goes to the driver as a bound parameter. Table and column
/// names are validated as identifiers; trusted fragments go through
/// [RawSql].
class QueryBuilder<T> {
  QueryBuilder(
    this.connection,
    this.table, {
    required this._hydrate,
    this.definition,
  });

  Connection connection;
  final String table;
  final T Function(Row row) _hydrate;
  final ModelDefinition<T>? definition;

  final List<Object> columns = [];
  bool isDistinct = false;
  final List<JoinClause> joins = [];
  final List<WhereClause> wheres = [];
  final List<String> groups = [];
  final List<WhereClause> havings = [];
  final List<OrderClause> orders = [];
  int? limitValue;
  int? offsetValue;

  final Map<String, RelationConstraint?> eagerLoads = {};
  final Set<String> removedScopes = {};
  bool _scopesApplied = false;

  /// Set by [_has] on an existence subquery whose table would otherwise
  /// shadow the one it correlates against.
  String? _alias;

  /// How many `whereHas` subqueries this builder sits inside; it names the
  /// alias, so two live aliases can never share a name.
  int _hasDepth = 0;

  /// What column references in this query qualify against: the table, or
  /// its alias when [whereHas] had to alias it.
  String get qualifier => _alias ?? table;

  /// The FROM target, `table as alias` when aliased.
  String get fromClause => _alias == null ? table : '$table as $_alias';

  Grammar get grammar => connection.grammar;

  /// A deep copy; the original is untouched by later calls on the copy.
  QueryBuilder<T> clone() =>
      QueryBuilder<T>(
          connection,
          table,
          hydrate: _hydrate,
          definition: definition,
        )
        ..columns.addAll(columns)
        ..isDistinct = isDistinct
        ..joins.addAll(joins)
        ..wheres.addAll(wheres)
        ..groups.addAll(groups)
        ..havings.addAll(havings)
        ..orders.addAll(orders)
        ..limitValue = limitValue
        ..offsetValue = offsetValue
        ..eagerLoads.addAll(eagerLoads)
        ..removedScopes.addAll(removedScopes)
        .._scopesApplied = _scopesApplied
        .._alias = _alias
        .._hasDepth = _hasDepth;

  /// Run this query (and any query derived from it) on [other]; used for
  /// transactions: `User.query().using(tx)`.
  QueryBuilder<T> using(Connection other) {
    connection = other;
    return this;
  }

  // ---------------------------------------------------------------------------
  // Columns
  // ---------------------------------------------------------------------------

  QueryBuilder<T> select(List<Object> selected) {
    columns
      ..clear()
      ..addAll(selected.map(_column));
    return this;
  }

  QueryBuilder<T> addSelect(List<Object> selected) {
    columns.addAll(selected.map(_column));
    return this;
  }

  QueryBuilder<T> selectRaw(String sql, [List<Object?> bindings = const []]) =>
      addSelect([RawSql(sql, bindings)]);

  QueryBuilder<T> distinct([bool value = true]) {
    isDistinct = value;
    return this;
  }

  // ---------------------------------------------------------------------------
  // Joins
  // ---------------------------------------------------------------------------

  QueryBuilder<T> join(
    String table,
    String first, [
    String operator = '=',
    String? second,
    String type = 'inner',
  ]) {
    assertIdentifier(splitAlias(table).$1);
    joins.add(
      JoinClause(
        type,
        table,
        first: _column(first),
        operator: assertOperator(operator),
        second: _column(
          second ?? (throw ArgumentError('join needs both columns')),
        ),
      ),
    );
    return this;
  }

  QueryBuilder<T> leftJoin(
    String table,
    String first, [
    String operator = '=',
    String? second,
  ]) => join(table, first, operator, second, 'left');

  QueryBuilder<T> rightJoin(
    String table,
    String first, [
    String operator = '=',
    String? second,
  ]) => join(table, first, operator, second, 'right');

  QueryBuilder<T> crossJoin(String table) {
    assertIdentifier(splitAlias(table).$1);
    joins.add(JoinClause('cross', table));
    return this;
  }

  // ---------------------------------------------------------------------------
  // Where
  // ---------------------------------------------------------------------------

  /// `where('age', '>', 18)`, `where('active', true)`, `where('x', null)`
  /// (becomes `is null`), or `where((q) => q.where(..).orWhere(..))`.
  QueryBuilder<T> where(
    Object column, [
    Object? operatorOrValue = _absent,
    Object? value = _absent,
  ]) => _where(column, operatorOrValue, value, 'and');

  QueryBuilder<T> orWhere(
    Object column, [
    Object? operatorOrValue = _absent,
    Object? value = _absent,
  ]) => _where(column, operatorOrValue, value, 'or');

  QueryBuilder<T> _where(
    Object column,
    Object? operatorOrValue,
    Object? value,
    String boolean,
  ) {
    if (column is WhereGroup<T>) {
      final nested = _newNested();
      column(nested);
      if (nested.wheres.isNotEmpty) wheres.add(NestedWhere(nested, boolean));
      return this;
    }
    final String operator;
    final Object? bound;
    if (identical(value, _absent)) {
      if (identical(operatorOrValue, _absent)) {
        throw ArgumentError('where() needs a value: where(column, value)');
      }
      operator = '=';
      bound = operatorOrValue;
    } else {
      operator = assertOperator(operatorOrValue as String);
      bound = value;
    }
    final col = _column(column);
    if (bound == null) {
      return _null(col, boolean, not: operator != '=' && operator != 'is');
    }
    if (bound is QueryBuilder) {
      throw ArgumentError('Use whereIn(column, subquery) for subqueries');
    }
    wheres.add(BasicWhere(col, operator, bound, boolean));
    return this;
  }

  QueryBuilder<T> whereNot(Object column, Object? value) =>
      _where(column, '!=', value, 'and');

  QueryBuilder<T> whereNull(String column) =>
      _null(_column(column), 'and', not: false);
  QueryBuilder<T> whereNotNull(String column) =>
      _null(_column(column), 'and', not: true);
  QueryBuilder<T> orWhereNull(String column) =>
      _null(_column(column), 'or', not: false);
  QueryBuilder<T> orWhereNotNull(String column) =>
      _null(_column(column), 'or', not: true);

  QueryBuilder<T> _null(Object column, String boolean, {required bool not}) {
    wheres.add(NullWhere(column, boolean, not: not));
    return this;
  }

  /// `whereIn('id', [1, 2])` or `whereIn('id', subquery)`.
  QueryBuilder<T> whereIn(String column, Object values) =>
      _in(column, values, 'and', not: false);
  QueryBuilder<T> whereNotIn(String column, Object values) =>
      _in(column, values, 'and', not: true);
  QueryBuilder<T> orWhereIn(String column, Object values) =>
      _in(column, values, 'or', not: false);
  QueryBuilder<T> orWhereNotIn(String column, Object values) =>
      _in(column, values, 'or', not: true);

  QueryBuilder<T> _in(
    String column,
    Object values,
    String boolean, {
    required bool not,
  }) {
    final col = _column(column);
    if (values is QueryBuilder) {
      wheres.add(InSubqueryWhere(col, values.prepared(), boolean, not: not));
    } else if (values is Iterable) {
      wheres.add(InWhere(col, values.toList(), boolean, not: not));
    } else {
      throw ArgumentError('whereIn needs a list or a subquery');
    }
    return this;
  }

  QueryBuilder<T> whereBetween(String column, Object? low, Object? high) {
    wheres.add(BetweenWhere(_column(column), low, high, 'and', not: false));
    return this;
  }

  QueryBuilder<T> whereNotBetween(String column, Object? low, Object? high) {
    wheres.add(BetweenWhere(_column(column), low, high, 'and', not: true));
    return this;
  }

  /// `like` with the pattern bound as a parameter. On PostgreSQL `like`
  /// is case-sensitive; pass `caseInsensitive: true` for `ilike`.
  QueryBuilder<T> whereLike(
    String column,
    String pattern, {
    bool caseInsensitive = false,
  }) => _where(column, caseInsensitive ? 'ilike' : 'like', pattern, 'and');

  QueryBuilder<T> orWhereLike(
    String column,
    String pattern, {
    bool caseInsensitive = false,
  }) => _where(column, caseInsensitive ? 'ilike' : 'like', pattern, 'or');

  QueryBuilder<T> whereNotLike(String column, String pattern) =>
      _where(column, 'not like', pattern, 'and');

  /// Compare two columns: `whereColumn('updated_at', '>', 'created_at')`.
  QueryBuilder<T> whereColumn(
    String first,
    String operatorOrSecond, [
    String? second,
  ]) {
    final op = second == null ? '=' : assertOperator(operatorOrSecond);
    wheres.add(
      ColumnWhere(
        _column(first),
        op,
        _column(second ?? operatorOrSecond),
        'and',
      ),
    );
    return this;
  }

  QueryBuilder<T> whereExists(QueryBuilder<Object?> query, {bool not = false}) {
    wheres.add(ExistsWhere(query.prepared(), 'and', not: not));
    return this;
  }

  QueryBuilder<T> whereNotExists(QueryBuilder<Object?> query) =>
      whereExists(query, not: true);

  /// Trusted SQL. Never interpolate user input into [sql]; bind it.
  QueryBuilder<T> whereRaw(String sql, [List<Object?> bindings = const []]) {
    wheres.add(RawWhere(RawSql(sql, bindings), 'and'));
    return this;
  }

  QueryBuilder<T> orWhereRaw(String sql, [List<Object?> bindings = const []]) {
    wheres.add(RawWhere(RawSql(sql, bindings), 'or'));
    return this;
  }

  /// `where primaryKey = id` (or `in` for a list of ids).
  QueryBuilder<T> whereKey(Object id) {
    final key = _qualifiedKey;
    if (id is Iterable) return whereIn(key, id);
    return where(key, id);
  }

  String get _qualifiedKey => '$qualifier.${definition?.primaryKey ?? 'id'}';

  // ---------------------------------------------------------------------------
  // Relations (model queries only)
  // ---------------------------------------------------------------------------

  /// Eager load relations: `with_(['posts', 'posts.comments'])`.
  QueryBuilder<T> with_(List<String> relations) {
    for (final r in relations) {
      eagerLoads.putIfAbsent(r, () => null);
    }
    return this;
  }

  /// Eager load with extra constraints on the related query.
  QueryBuilder<T> withWhere(String relation, RelationConstraint constraint) {
    eagerLoads[relation] = constraint;
    return this;
  }

  /// `whereHas('posts', (q) => q.where('published', true))`.
  QueryBuilder<T> whereHas(String relation, [RelationConstraint? constraint]) =>
      _has(relation, constraint, 'and', not: false);

  QueryBuilder<T> orWhereHas(
    String relation, [
    RelationConstraint? constraint,
  ]) => _has(relation, constraint, 'or', not: false);

  QueryBuilder<T> whereDoesntHave(
    String relation, [
    RelationConstraint? constraint,
  ]) => _has(relation, constraint, 'and', not: true);

  QueryBuilder<T> has(String relation) => whereHas(relation);

  QueryBuilder<T> _has(
    String relation,
    RelationConstraint? constraint,
    String boolean, {
    required bool not,
  }) {
    final rel = _definition.relationFor(relation);
    final sub = rel.related.query(connection: connection)
      .._hasDepth = _hasDepth + 1
      ..select([const RawSql('1')]);
    // A self-referencing relation puts the same name on both sides of the
    // correlation, and the inner one wins; alias the subquery's table so
    // the outer row stays reachable. Everything the subquery qualifies —
    // the relation's own keys, global scopes, the constraint closure —
    // goes through `sub.qualifier`, so it follows the alias.
    if (rel.related.table == qualifier) sub._alias = '__has_$_hasDepth';
    rel.addExistenceConstraint(sub, qualifier);
    constraint?.call(sub);
    wheres.add(ExistsWhere(sub.prepared(), boolean, not: not));
    return this;
  }

  // ---------------------------------------------------------------------------
  // Group / having / order / limit
  // ---------------------------------------------------------------------------

  QueryBuilder<T> groupBy(List<String> columnNames) {
    groups.addAll(columnNames.map(assertColumn));
    return this;
  }

  QueryBuilder<T> having(
    Object column,
    Object operatorOrValue, [
    Object? value = _absent,
  ]) {
    final op = identical(value, _absent)
        ? '='
        : assertOperator(operatorOrValue as String);
    final bound = identical(value, _absent) ? operatorOrValue : value;
    havings.add(BasicWhere(_column(column), op, bound, 'and'));
    return this;
  }

  QueryBuilder<T> havingRaw(String sql, [List<Object?> bindings = const []]) {
    havings.add(RawWhere(RawSql(sql, bindings), 'and'));
    return this;
  }

  /// Direction is a boolean, never a string from the request.
  QueryBuilder<T> orderBy(String column, {bool descending = false}) {
    orders.add(OrderClause(_column(column), descending: descending));
    return this;
  }

  QueryBuilder<T> orderByDesc(String column) =>
      orderBy(column, descending: true);

  QueryBuilder<T> orderByRaw(String sql, [List<Object?> bindings = const []]) {
    orders.add(OrderClause(RawSql(sql, bindings), descending: false));
    return this;
  }

  QueryBuilder<T> latest([String? column]) =>
      orderBy(column ?? _timestampColumn, descending: true);

  QueryBuilder<T> oldest([String? column]) =>
      orderBy(column ?? _timestampColumn);

  String get _timestampColumn => definition?.createdAtColumn ?? 'created_at';

  QueryBuilder<T> reorder() {
    orders.clear();
    return this;
  }

  QueryBuilder<T> limit(int value) {
    limitValue = RangeError.checkNotNegative(value, 'limit');
    return this;
  }

  QueryBuilder<T> offset(int value) {
    offsetValue = RangeError.checkNotNegative(value, 'offset');
    return this;
  }

  QueryBuilder<T> take(int value) => limit(value);
  QueryBuilder<T> skip(int value) => offset(value);

  QueryBuilder<T> forPage(int page, int perPage) =>
      offset((page - 1) * perPage).limit(perPage);

  // ---------------------------------------------------------------------------
  // Scopes
  // ---------------------------------------------------------------------------

  QueryBuilder<T> withoutGlobalScope(String name) {
    removedScopes.add(name);
    return this;
  }

  QueryBuilder<T> withoutGlobalScopes() {
    removedScopes.addAll(definition?.globalScopes.keys ?? const []);
    return this;
  }

  /// Soft deletes: include trashed rows.
  QueryBuilder<T> withTrashed() => withoutGlobalScope(softDeletesScope);

  /// Soft deletes: only trashed rows.
  QueryBuilder<T> onlyTrashed() =>
      withTrashed().whereNotNull('$qualifier.${_definition.deletedAtColumn}');

  /// Applies global scopes once. Called on a clone before compiling.
  QueryBuilder<T> applyScopes() {
    final def = definition;
    if (_scopesApplied || def == null) return this;
    _scopesApplied = true;
    for (final entry in def.globalScopes.entries) {
      if (!removedScopes.contains(entry.key)) entry.value(this);
    }
    return this;
  }

  /// A scoped copy ready to compile.
  QueryBuilder<T> prepared() => clone().applyScopes();

  // ---------------------------------------------------------------------------
  // Compile
  // ---------------------------------------------------------------------------

  /// The SELECT this builder would run, with `?` placeholders.
  String toSql() => compile().$1;

  Compiled compile() => grammar.compileSelect(prepared());

  // ---------------------------------------------------------------------------
  // Read
  // ---------------------------------------------------------------------------

  Future<List<T>> get() async {
    final (sql, bindings) = compile();
    final rows = await connection.select(sql, bindings);
    final results = [for (final r in rows) _hydrateRow(r)];
    final def = definition;
    if (def != null && eagerLoads.isNotEmpty && results.isNotEmpty) {
      await EagerLoader.load(
        def,
        results.cast<Model>(),
        eagerLoads,
        connection,
      );
    }
    return results;
  }

  T _hydrateRow(Row row) {
    final def = definition;
    return def == null
        ? _hydrate(row)
        : def.hydrate(row, connection: connection);
  }

  Future<T?> first() async => (await clone().limit(1).get()).firstOrNull;

  Future<T?> firstOrNull() => first();

  Future<T> firstOrFail() async =>
      await first() ?? (throw ModelNotFoundException(_modelName));

  Future<T?> find(Object id) => clone().whereKey(id).first();

  Future<T> findOrFail(Object id) async =>
      await find(id) ?? (throw ModelNotFoundException(_modelName, id));

  Future<List<T>> findMany(Iterable<Object> ids) =>
      clone().whereKey(ids.toList()).get();

  Future<bool> exists() async {
    final (sql, bindings) = grammar.compileExists(prepared()..reorder());
    final rows = await connection.select(sql, bindings);
    final v = rows.first.values.first;
    return v == true || v == 1;
  }

  Future<bool> doesntExist() async => !await exists();

  Future<int> count([String column = '*']) async =>
      (await _aggregate('count', column) as num?)?.toInt() ?? 0;

  Future<num?> sum(String column) async =>
      await _aggregate('sum', column) as num?;
  Future<num?> avg(String column) async =>
      await _aggregate('avg', column) as num?;
  Future<Object?> min(String column) => _aggregate('min', column);
  Future<Object?> max(String column) => _aggregate('max', column);

  Future<Object?> _aggregate(String function, String column) async {
    final q = prepared()..reorder();
    final wrapped = grammar.wrap(assertColumn(column));
    final String sql;
    final List<Object?> bindings;
    if (q.groups.isNotEmpty || q.isDistinct) {
      // Aggregate over the grouped/distinct result set, not per group.
      final (inner, b) = grammar.compileSelect(q);
      sql =
          'select $function($wrapped) as "aggregate" from ($inner) as "aggregate_table"';
      bindings = b;
    } else {
      q
        ..columns.clear()
        ..columns.add(RawSql('$function($wrapped) as "aggregate"'))
        ..limitValue = null
        ..offsetValue = null;
      (sql, bindings) = grammar.compileSelect(q);
    }
    final rows = await connection.select(sql, bindings);
    return rows.firstOrNull?['aggregate'];
  }

  /// One column as a list, or a `{key: value}` map when [key] is given.
  Future<Object> pluck(String column, [String? key]) async {
    final q = prepared()..select([column, ?key]);
    final (sql, bindings) = grammar.compileSelect(q);
    final rows = await connection.select(sql, bindings);
    final c = _resultKey(column);
    if (key == null) return [for (final r in rows) r[c]];
    final k = _resultKey(key);
    return {for (final r in rows) r[k]: r[c]};
  }

  Future<List<Object?>> pluckList(String column) async =>
      await pluck(column) as List<Object?>;

  /// A single column of the first row.
  Future<Object?> value(String column) async {
    final q = prepared()
      ..select([column])
      ..limit(1);
    final (sql, bindings) = grammar.compileSelect(q);
    final rows = await connection.select(sql, bindings);
    return rows.firstOrNull?[_resultKey(column)];
  }

  static String _resultKey(String column) {
    final (name, alias) = splitAlias(column);
    return alias ?? name.split('.').last;
  }

  Future<Paginator<T>> paginate({int page = 1, int perPage = 15}) async {
    if (page < 1) page = 1;
    final total = await clone().count();
    final data = total == 0
        ? <T>[]
        : await clone().forPage(page, perPage).get();
    return Paginator<T>(
      data: data,
      total: total,
      perPage: perPage,
      currentPage: page,
    );
  }

  /// Processes the table in pages of [size]; return `false` from
  /// [callback] to stop early. Ordered by primary key unless you ordered.
  Future<void> chunk(
    int size,
    FutureOr<bool?> Function(List<T> rows) callback,
  ) async {
    final base = clone();
    if (base.orders.isEmpty) base.orderBy(_qualifiedKey);
    var page = 1;
    while (true) {
      final rows = await base.clone().forPage(page, size).get();
      if (rows.isEmpty) return;
      if (await callback(rows) == false) return;
      if (rows.length < size) return;
      page++;
    }
  }

  /// Streams rows one at a time, fetching [chunkSize] per query.
  Stream<T> lazy({int chunkSize = 100}) async* {
    final base = clone();
    if (base.orders.isEmpty) base.orderBy(_qualifiedKey);
    var page = 1;
    while (true) {
      final rows = await base.clone().forPage(page, chunkSize).get();
      for (final row in rows) {
        yield row;
      }
      if (rows.length < chunkSize) return;
      page++;
    }
  }

  // ---------------------------------------------------------------------------
  // Write
  // ---------------------------------------------------------------------------

  /// Inserts one map or a list of maps. Returns the number of rows.
  Future<int> insert(Object rows) async {
    final list = rows is Map<String, Object?>
        ? [rows]
        : (rows as Iterable).cast<Map<String, Object?>>().toList();
    if (list.isEmpty) return 0;
    final (sql, bindings) = grammar.compileInsert(
      table,
      list.map(_encode).toList(),
    );
    return connection.execute(sql, bindings);
  }

  Future<Object?> insertGetId(Map<String, Object?> row) async {
    final key = definition?.primaryKey ?? 'id';
    final (sql, bindings) = grammar.compileInsertGetId(
      table,
      _encode(row),
      key,
    );
    return connection.insertGetId(sql, bindings, primaryKey: key);
  }

  /// Bulk update of every row matching the query. Returns affected rows.
  Future<int> update(Map<String, Object?> values) async {
    if (values.isEmpty) return 0;
    final (sql, bindings) = grammar.compileUpdate(prepared(), _encode(values));
    return connection.execute(sql, bindings);
  }

  Future<int> increment(
    String column, [
    num amount = 1,
    Map<String, Object?> extra = const {},
  ]) => update({
    column: RawSql('${grammar.wrap(assertColumn(column))} + ?', [amount]),
    ...extra,
  });

  Future<int> decrement(
    String column, [
    num amount = 1,
    Map<String, Object?> extra = const {},
  ]) => update({
    column: RawSql('${grammar.wrap(assertColumn(column))} - ?', [amount]),
    ...extra,
  });

  /// Deletes matching rows, or soft-deletes them when the model uses
  /// soft deletes. Returns affected rows.
  Future<int> delete([Object? id]) async {
    final q = id == null ? this : clone().whereKey(id);
    final def = definition;
    if (def != null && def.softDeletes) {
      final now = DateTime.now().toUtc();
      return q.update({
        def.deletedAtColumn: now,
        if (def.timestamps) def.updatedAtColumn: now,
      });
    }
    return q.forceDelete();
  }

  /// Deletes matching rows for real, even with soft deletes.
  Future<int> forceDelete() async {
    final q = prepared();
    q.removedScopes.add(softDeletesScope);
    final (sql, bindings) = grammar.compileDelete(q);
    return connection.execute(sql, bindings);
  }

  /// Soft deletes: un-trash matching rows.
  Future<int> restore() => clone().withTrashed().update({
    _definition.deletedAtColumn: null,
    if (_definition.timestamps)
      _definition.updatedAtColumn: DateTime.now().toUtc(),
  });

  Future<void> truncate() => connection.execute(grammar.compileTruncate(table));

  // ---------------------------------------------------------------------------
  // Model conveniences
  // ---------------------------------------------------------------------------

  /// Mass-assign and insert; fires model events. Model queries only.
  Future<T> create(Map<String, Object?> attributes) =>
      _definition.create(attributes, connection: connection);

  Future<T> forceCreate(Map<String, Object?> attributes) =>
      _definition.create(attributes, connection: connection, force: true);

  Future<T> firstOrCreate(
    Map<String, Object?> match, [
    Map<String, Object?> extra = const {},
  ]) async {
    final q = clone();
    match.forEach(q.where);
    return await q.first() ?? await create({...match, ...extra});
  }

  Future<T> updateOrCreate(
    Map<String, Object?> match,
    Map<String, Object?> values,
  ) async {
    final q = clone();
    match.forEach(q.where);
    final found = await q.first();
    if (found == null) return create({...match, ...values});
    return (found as Model).update(values) as Future<T>;
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  ModelDefinition<T> get _definition =>
      definition ??
      (throw StateError('This operation needs a model query, not DB.table()'));

  String get _modelName => definition?.modelName ?? table;

  QueryBuilder<T> _newNested() =>
      QueryBuilder<T>(
          connection,
          table,
          hydrate: _hydrate,
          definition: definition,
        )
        .._alias = _alias
        .._hasDepth = _hasDepth;

  Object _column(Object column) {
    if (column is RawSql) return column;
    if (column is String) {
      final (name, alias) = splitAlias(column);
      assertColumn(name);
      if (alias != null) assertIdentifier(alias);
      return column;
    }
    throw ArgumentError.value(column, 'column', 'must be a String or RawSql');
  }

  Map<String, Object?> _encode(Map<String, Object?> values) =>
      definition?.encodeAttributes(values) ?? values;
}
