import 'package:seshat/seshat.dart';

/// A query [Grammar] that quotes identifiers with backticks, the way MySQL
/// does — used to prove the migrator routes its SQL through the
/// connection's grammar instead of hard-coding ANSI double quotes.
class FakeMysqlGrammar extends Grammar {
  const FakeMysqlGrammar();

  @override
  String get name => 'mysql';

  @override
  String wrapValue(String value) => '`$value`';
}

/// A [SchemaGrammar] standing in for a real MySQL adapter in tests: reuses
/// Postgres's DDL shape (it's never executed here) but reports as 'mysql'.
class FakeMysqlSchemaGrammar extends PostgresSchemaGrammar {
  const FakeMysqlSchemaGrammar();

  @override
  String get name => 'mysql';
}

/// A [Connection] that never touches a real database: every statement is
/// recorded and reads return empty results.
class RecordingConnection extends ConnectionBase implements Connection {
  @override
  final Grammar grammar = const FakeMysqlGrammar();

  final List<String> sqlLog = [];

  @override
  Future<List<Row>> select(String sql, [List<Object?> bindings = const []]) {
    sqlLog.add(sql);
    return Future.value(const []);
  }

  @override
  Future<int> execute(String sql, [List<Object?> bindings = const []]) {
    sqlLog.add(sql);
    return Future.value(0);
  }

  @override
  Future<Object?> insertGetId(
    String sql,
    List<Object?> bindings, {
    String? primaryKey,
  }) {
    sqlLog.add(sql);
    return Future.value(0);
  }

  @override
  Future<R> transaction<R>(Future<R> Function(Connection tx) body) =>
      body(this);

  @override
  int get transactionDepth => 0;

  @override
  Future<void> close() => Future.value();
}
