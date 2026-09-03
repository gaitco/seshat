import 'dart:convert';

import '../query/conditions.dart';
import '../query/joins.dart';
import '../query/query_builder.dart';
import '../support/identifiers.dart';
import '../support/raw_sql.dart';

/// Compiled SQL plus its bindings, in placeholder order.
typedef Compiled = (String sql, List<Object?> bindings);

/// Turns a [QueryBuilder] into SQL for one dialect. The ANSI defaults here
/// cover SQLite and PostgreSQL; adapters override what differs.
///
/// Every identifier is validated before wrapping and every value becomes a
/// `?` placeholder, so the only way to put text into a statement verbatim
/// is through [RawSql].
abstract class Grammar {
  const Grammar();

  String get name;

  /// Wraps `table.column`, `table.*`, `column as alias`, or passes
  /// [RawSql] through.
  String wrap(Object identifier) {
    if (identifier is RawSql) return identifier.sql;
    final (column, alias) = splitAlias(identifier as String);
    assertColumn(column);
    final wrapped = column
        .split('.')
        .map((s) => s == '*' ? '*' : wrapValue(s))
        .join('.');
    return alias == null ? wrapped : '$wrapped as ${wrapValue(alias)}';
  }

  String wrapTable(String table) {
    final (name, alias) = splitAlias(table);
    assertIdentifier(name);
    final wrapped = name.split('.').map(wrapValue).join('.');
    return alias == null ? wrapped : '$wrapped as ${wrapValue(alias)}';
  }

  String wrapValue(String value) => '"${value.replaceAll('"', '""')}"';

  /// How a Dart value travels to the driver. Overridden per dialect
  /// (SQLite has no bool or DateTime type).
  Object? encode(Object? value) {
    if (value is Enum) return value.name;
    if (value is Map || value is List) return jsonEncode(value);
    return value;
  }

  List<Object?> encodeAll(Iterable<Object?> values) => [
    for (final v in values) encode(v),
  ];

  // ---------------------------------------------------------------------------
  // SELECT
  // ---------------------------------------------------------------------------

  Compiled compileSelect(QueryBuilder<Object?> q) {
    final bindings = <Object?>[];
    final parts = <String>[
      'select ${q.isDistinct ? 'distinct ' : ''}${_columns(q, bindings)}',
      'from ${wrapTable(q.fromClause)}',
    ];
    for (final j in q.joins) {
      parts.add(_join(j));
    }
    final where = compileWheres(q.wheres, bindings);
    if (where.isNotEmpty) parts.add('where $where');
    if (q.groups.isNotEmpty) {
      parts.add('group by ${q.groups.map(wrap).join(', ')}');
    }
    final having = compileWheres(q.havings, bindings);
    if (having.isNotEmpty) parts.add('having $having');
    if (q.orders.isNotEmpty) {
      parts.add(
        'order by ${q.orders.map((o) => _order(o, bindings)).join(', ')}',
      );
    }
    if (q.limitValue != null) parts.add('limit ${q.limitValue}');
    if (q.offsetValue != null) parts.add('offset ${q.offsetValue}');
    return (parts.join(' '), bindings);
  }

  String _order(OrderClause o, List<Object?> bindings) {
    final column = o.column;
    if (column is RawSql) return _raw(column, bindings);
    return '${wrap(column)} ${o.descending ? 'desc' : 'asc'}';
  }

  String _columns(QueryBuilder<Object?> q, List<Object?> bindings) {
    if (q.columns.isEmpty) return '*';
    return q.columns
        .map((c) => c is RawSql ? _raw(c, bindings) : wrap(c))
        .join(', ');
  }

  String _raw(RawSql raw, List<Object?> bindings) {
    bindings.addAll(encodeAll(raw.bindings));
    return raw.sql;
  }

  String _join(JoinClause j) {
    final table = wrapTable(j.table);
    if (j.type == 'cross') return 'cross join $table';
    return '${j.type} join $table on ${wrap(j.first!)} ${j.operator} ${wrap(j.second!)}';
  }

  String compileWheres(List<WhereClause> wheres, List<Object?> bindings) {
    final buffer = StringBuffer();
    for (final w in wheres) {
      if (buffer.isNotEmpty) buffer.write(' ${w.boolean} ');
      buffer.write(_where(w, bindings));
    }
    return buffer.toString();
  }

  String _where(WhereClause w, List<Object?> bindings) {
    switch (w) {
      case BasicWhere():
        bindings.add(encode(w.value));
        return '${wrap(w.column)} ${w.operator} ?';
      case NullWhere():
        return '${wrap(w.column)} is ${w.not ? 'not ' : ''}null';
      case InWhere():
        if (w.values.isEmpty) return w.not ? '1 = 1' : '0 = 1';
        bindings.addAll(encodeAll(w.values));
        final marks = List.filled(w.values.length, '?').join(', ');
        return '${wrap(w.column)} ${w.not ? 'not ' : ''}in ($marks)';
      case InSubqueryWhere():
        final (sql, b) = compileSelect(w.query);
        bindings.addAll(b);
        return '${wrap(w.column)} ${w.not ? 'not ' : ''}in ($sql)';
      case BetweenWhere():
        bindings
          ..add(encode(w.low))
          ..add(encode(w.high));
        return '${wrap(w.column)} ${w.not ? 'not ' : ''}between ? and ?';
      case ColumnWhere():
        return '${wrap(w.first)} ${w.operator} ${wrap(w.second)}';
      case NestedWhere():
        return '(${compileWheres(w.query.wheres, bindings)})';
      case ExistsWhere():
        final (sql, b) = compileSelect(w.query);
        bindings.addAll(b);
        return '${w.not ? 'not ' : ''}exists ($sql)';
      case RawWhere():
        return _raw(w.raw, bindings);
    }
  }

  // ---------------------------------------------------------------------------
  // Writes
  // ---------------------------------------------------------------------------

  Compiled compileInsert(String table, List<Map<String, Object?>> rows) {
    final columns = rows.first.keys.toList();
    for (final c in columns) {
      assertIdentifier(c);
    }
    final bindings = <Object?>[];
    final marks = '(${List.filled(columns.length, '?').join(', ')})';
    final values = <String>[];
    for (final row in rows) {
      bindings.addAll(encodeAll(columns.map((c) => row[c])));
      values.add(marks);
    }
    return (
      'insert into ${wrapTable(table)} (${columns.map(wrapValue).join(', ')}) '
          'values ${values.join(', ')}',
      bindings,
    );
  }

  /// Insert with the generated key returned. Both SQLite (3.35+) and
  /// PostgreSQL understand RETURNING.
  Compiled compileInsertGetId(
    String table,
    Map<String, Object?> row,
    String primaryKey,
  ) {
    final (sql, bindings) = compileInsert(table, [row]);
    return (
      '$sql returning ${wrapValue(assertIdentifier(primaryKey))}',
      bindings,
    );
  }

  Compiled compileUpdate(QueryBuilder<Object?> q, Map<String, Object?> values) {
    final bindings = <Object?>[];
    final sets = values.entries
        .map((e) {
          final column = wrapValue(assertIdentifier(e.key));
          final value = e.value;
          if (value is RawSql) return '$column = ${_raw(value, bindings)}';
          bindings.add(encode(value));
          return '$column = ?';
        })
        .join(', ');
    final where = compileWheres(q.wheres, bindings);
    return (
      'update ${wrapTable(q.table)} set $sets'
          '${where.isEmpty ? '' : ' where $where'}',
      bindings,
    );
  }

  Compiled compileDelete(QueryBuilder<Object?> q) {
    final bindings = <Object?>[];
    final where = compileWheres(q.wheres, bindings);
    return (
      'delete from ${wrapTable(q.table)}${where.isEmpty ? '' : ' where $where'}',
      bindings,
    );
  }

  String compileTruncate(String table) => 'delete from ${wrapTable(table)}';

  Compiled compileExists(QueryBuilder<Object?> q) {
    final (sql, bindings) = compileSelect(q);
    return ('select exists($sql) as ${wrapValue('exists')}', bindings);
  }
}
