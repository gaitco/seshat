import '../../exceptions/exceptions.dart';
import '../../schema/blueprint.dart';
import '../../schema/schema_grammar.dart';
import '../grammar.dart' show Compiled;

/// SQLite DDL. Types are loose: everything textual is `text`, booleans and
/// dates travel as integers/ISO-8601 text, matching `SqliteGrammar.encode`.
class SqliteSchemaGrammar extends SchemaGrammar {
  const SqliteSchemaGrammar();

  @override
  String get name => 'sqlite';

  @override
  String typeFor(ColumnDefinition column) => switch (column.type) {
    ColumnType.id => 'integer primary key autoincrement',
    ColumnType.string ||
    ColumnType.text ||
    ColumnType.uuid ||
    ColumnType.json ||
    ColumnType.date ||
    ColumnType.dateTime ||
    ColumnType.timestamp => 'text',
    ColumnType.integer ||
    ColumnType.bigInteger ||
    ColumnType.unsignedBigInteger ||
    ColumnType.boolean => 'integer',
    ColumnType.double_ => 'real',
    ColumnType.decimal => 'numeric',
  };

  @override
  String boolLiteral(bool value) => value ? '1' : '0';

  @override
  Compiled compileTableExists() => (
    "select name from sqlite_master where type = 'table' and name = ?",
    const [],
  );

  @override
  Compiled compileColumnListing(String table) =>
      ('pragma table_info(${wrap(table)})', const []);

  @override
  String compileTableListing() =>
      "select name from sqlite_master where type='table' and name not like 'sqlite_%'";

  /// SQLite cannot add a primary key to an existing table.
  @override
  String compileCommand(String table, SchemaCommand command) {
    if (command is PrimaryCommand) {
      throw DatabaseException(
        'SQLite cannot add a primary key to an existing table; declare it '
        'when creating the table.',
      );
    }
    return super.compileCommand(table, command);
  }
}
