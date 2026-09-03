/// `inner|left|right|cross join table on first op second`.
class JoinClause {
  const JoinClause(
    this.type,
    this.table, {
    this.first,
    this.operator,
    this.second,
  });

  final String type;
  final String table;
  final Object? first;
  final String? operator;
  final Object? second;
}
