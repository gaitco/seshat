import '../support/raw_sql.dart';
import 'query_builder.dart';

/// One entry in a WHERE (or HAVING) list. [boolean] is `and` or `or`.
sealed class WhereClause {
  const WhereClause(this.boolean);
  final String boolean;
}

/// `column op ?`
class BasicWhere extends WhereClause {
  const BasicWhere(this.column, this.operator, this.value, super.boolean);
  final Object column; // String identifier or RawSql
  final String operator;
  final Object? value;
}

/// `column is [not] null`
class NullWhere extends WhereClause {
  const NullWhere(this.column, super.boolean, {required this.not});
  final Object column;
  final bool not;
}

/// `column [not] in (?, ?, ...)`
class InWhere extends WhereClause {
  const InWhere(this.column, this.values, super.boolean, {required this.not});
  final Object column;
  final List<Object?> values;
  final bool not;
}

/// `column [not] in (select ...)`
class InSubqueryWhere extends WhereClause {
  const InSubqueryWhere(
    this.column,
    this.query,
    super.boolean, {
    required this.not,
  });
  final Object column;
  final QueryBuilder<Object?> query;
  final bool not;
}

/// `column [not] between ? and ?`
class BetweenWhere extends WhereClause {
  const BetweenWhere(
    this.column,
    this.low,
    this.high,
    super.boolean, {
    required this.not,
  });
  final Object column;
  final Object? low;
  final Object? high;
  final bool not;
}

/// `first op second` where both sides are columns.
class ColumnWhere extends WhereClause {
  const ColumnWhere(this.first, this.operator, this.second, super.boolean);
  final Object first;
  final String operator;
  final Object second;
}

/// `( ...nested wheres... )`
class NestedWhere extends WhereClause {
  const NestedWhere(this.query, super.boolean);
  final QueryBuilder<Object?> query;
}

/// `[not] exists (select ...)`
class ExistsWhere extends WhereClause {
  const ExistsWhere(this.query, super.boolean, {required this.not});
  final QueryBuilder<Object?> query;
  final bool not;
}

/// Trusted SQL with its own bindings.
class RawWhere extends WhereClause {
  const RawWhere(this.raw, super.boolean);
  final RawSql raw;
}

/// `order by column asc|desc` or raw.
class OrderClause {
  const OrderClause(this.column, {required this.descending});
  final Object column; // String identifier or RawSql
  final bool descending;
}
