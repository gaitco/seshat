import '../exceptions/exceptions.dart';
import 'raw_sql.dart';

final _identifier = RegExp(
  r'^[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)*$',
);
final _identifierOrStar = RegExp(
  r'^(\*|[A-Za-z_][A-Za-z0-9_]*(\.([A-Za-z_][A-Za-z0-9_]*|\*))*)$',
);
final _alias = RegExp(
  r'^(.+?)\s+as\s+([A-Za-z_][A-Za-z0-9_]*)$',
  caseSensitive: false,
);

/// Throws [InvalidIdentifierException] unless [name] is a plain, optionally
/// dot-qualified identifier. This is the single gate through which every
/// table and column name passes before reaching SQL.
String assertIdentifier(String name) {
  if (!_identifier.hasMatch(name)) throw InvalidIdentifierException(name);
  return name;
}

/// Like [assertIdentifier] but also accepts `*` and `table.*`.
String assertColumn(String name) {
  if (!_identifierOrStar.hasMatch(name)) throw InvalidIdentifierException(name);
  return name;
}

/// Splits `'users.name as author'` into its column and alias parts,
/// validating both. Returns `(column, null)` when there is no alias.
(String, String?) splitAlias(String column) {
  final m = _alias.firstMatch(column.trim());
  if (m == null) return (column.trim(), null);
  return (m[1]!.trim(), m[2]!);
}

/// The SQL comparison operators a query may use. Anything else throws.
const allowedOperators = {
  '=',
  '<',
  '>',
  '<=',
  '>=',
  '<>',
  '!=',
  'like',
  'not like',
  'ilike',
  'not ilike',
  'is',
  'is not',
  '&',
  '|',
  '<<',
  '>>',
};

String assertOperator(String operator) {
  final normalized = operator.trim().toLowerCase();
  if (!allowedOperators.contains(normalized)) {
    throw DatabaseException("Illegal operator '$operator'");
  }
  return normalized;
}

/// A column reference is either a validated identifier or trusted raw SQL.
bool isRaw(Object column) => column is RawSql;
