import '../database/adapters/sqlite_schema_grammar.dart';
import '../database/connection.dart';
import '../database/database.dart';
import '../exceptions/exceptions.dart';
import 'blueprint.dart';
import 'postgres_schema_grammar.dart';
import 'schema_grammar.dart';

final Map<String, SchemaGrammar> _schemaGrammars = {
  'sqlite': const SqliteSchemaGrammar(),
  'postgres': const PostgresSchemaGrammar(),
};

/// Registers [grammar] as the [SchemaGrammar] for connections whose query
/// grammar name is [driver]. Adapters outside this package (a MySQL driver,
/// say) call this once at startup so [schemaGrammarFor] — and therefore
/// [Migrator] — can find them.
void registerSchemaGrammar(String driver, SchemaGrammar grammar) {
  _schemaGrammars[driver] = grammar;
}

/// Picks the schema grammar matching [connection]'s query grammar.
SchemaGrammar schemaGrammarFor(Connection connection) {
  final driver = connection.grammar.name;
  final grammar = _schemaGrammars[driver];
  if (grammar == null) {
    throw DatabaseException(
      "No schema grammar for connection '$driver'. "
      "Call registerSchemaGrammar('$driver', ...) before using it.",
    );
  }
  return grammar;
}

/// Runs DDL on one connection: the Dart spelling of Laravel's
/// `Schema` facade bound to a connection.
class SchemaBuilder {
  SchemaBuilder(this.connection, this.grammar);

  final Connection connection;
  final SchemaGrammar grammar;

  Future<void> create(String table, void Function(Blueprint) build) =>
      _run(grammar.compileCreate(Blueprint(table)..also(build)));

  /// Alters an existing table.
  Future<void> table(String table, void Function(Blueprint) build) =>
      _run(grammar.compileAlter(Blueprint(table)..also(build)));

  Future<void> drop(String table) =>
      connection.execute(grammar.compileDrop(table));

  Future<void> dropIfExists(String table) =>
      connection.execute(grammar.compileDropIfExists(table));

  /// Drops every table in the database, migration-registered or not —
  /// `migrate:fresh`'s real "fresh" behavior. Postgres tables are dropped
  /// `cascade` so foreign keys between dropped tables don't block the drop.
  Future<void> dropAllTables() async {
    final rows = await connection.select(grammar.compileTableListing());
    for (final row in rows) {
      final table = row.values.first as String;
      final cascade = grammar.name == 'postgres' ? ' cascade' : '';
      await connection.execute(
        'drop table if exists ${grammar.wrap(table)}$cascade',
      );
    }
  }

  Future<void> rename(String from, String to) =>
      connection.execute(grammar.compileRename(from, to));

  Future<bool> hasTable(String table) async {
    final (sql, bindings) = grammar.compileTableExists();
    final rows = await connection.select(sql, [...bindings, table]);
    return rows.isNotEmpty;
  }

  Future<bool> hasColumn(String table, String column) async =>
      (await columnListing(table)).contains(column);

  /// Column names of [table] in declaration order (empty when absent).
  Future<List<String>> columnListing(String table) async {
    final (sql, bindings) = grammar.compileColumnListing(table);
    final rows = await connection.select(sql, bindings);
    return [for (final r in rows) r['name'] as String];
  }

  Future<void> _run(List<String> statements) async {
    for (final sql in statements) {
      await connection.execute(sql);
    }
  }
}

extension on Blueprint {
  void also(void Function(Blueprint) build) => build(this);
}

/// Static schema access on the default connection, like Laravel's
/// `Schema` facade. Use [on] for another connection.
class Schema {
  Schema._();

  static SchemaBuilder on(Connection connection) =>
      SchemaBuilder(connection, schemaGrammarFor(connection));

  static SchemaBuilder get _default => on(DB.connection);

  static Future<void> create(String table, void Function(Blueprint) build) =>
      _default.create(table, build);

  static Future<void> table(String table, void Function(Blueprint) build) =>
      _default.table(table, build);

  static Future<void> drop(String table) => _default.drop(table);

  static Future<void> dropIfExists(String table) =>
      _default.dropIfExists(table);

  static Future<void> rename(String from, String to) =>
      _default.rename(from, to);

  static Future<bool> hasTable(String table) => _default.hasTable(table);

  static Future<bool> hasColumn(String table, String column) =>
      _default.hasColumn(table, column);
}
