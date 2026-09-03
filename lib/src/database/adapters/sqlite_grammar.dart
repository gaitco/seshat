import '../grammar.dart';

/// SQLite: booleans are integers, timestamps are ISO-8601 text.
class SqliteGrammar extends Grammar {
  const SqliteGrammar();

  @override
  String get name => 'sqlite';

  @override
  Object? encode(Object? value) {
    if (value is bool) return value ? 1 : 0;
    if (value is DateTime) return value.toUtc().toIso8601String();
    return super.encode(value);
  }
}
