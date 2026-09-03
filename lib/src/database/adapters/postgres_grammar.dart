import '../grammar.dart';

/// PostgreSQL: native booleans and timestamps; `ilike` available.
class PostgresGrammar extends Grammar {
  const PostgresGrammar();

  @override
  String get name => 'postgres';

  @override
  Object? encode(Object? value) {
    if (value is DateTime) return value.toUtc();
    return super.encode(value);
  }

  /// `TRUNCATE` resets sequences and is much faster than `DELETE`.
  @override
  String compileTruncate(String table) =>
      'truncate ${wrapTable(table)} restart identity cascade';
}
