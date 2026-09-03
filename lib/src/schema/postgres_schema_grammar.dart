import '../database/grammar.dart' show Compiled;
import 'blueprint.dart';
import 'schema_grammar.dart';

/// PostgreSQL DDL.
class PostgresSchemaGrammar extends SchemaGrammar {
  const PostgresSchemaGrammar();

  @override
  String get name => 'postgres';

  @override
  String typeFor(ColumnDefinition column) => switch (column.type) {
    ColumnType.id => 'bigserial primary key',
    ColumnType.string => 'varchar(${column.length ?? 255})',
    ColumnType.text => 'text',
    ColumnType.integer => 'integer',
    ColumnType.bigInteger || ColumnType.unsignedBigInteger => 'bigint',
    ColumnType.boolean => 'boolean',
    ColumnType.double_ => 'double precision',
    ColumnType.decimal =>
      'numeric(${column.precision ?? 8}, ${column.scale ?? 2})',
    ColumnType.date => 'date',
    ColumnType.dateTime || ColumnType.timestamp => 'timestamp',
    ColumnType.json => 'jsonb',
    ColumnType.uuid => 'uuid',
  };

  @override
  String boolLiteral(bool value) => value ? 'true' : 'false';

  @override
  Compiled compileTableExists() => (
    'select tablename from pg_tables '
        'where schemaname = current_schema() and tablename = ?',
    const [],
  );

  @override
  Compiled compileColumnListing(String table) => (
    'select column_name as name from information_schema.columns '
        'where table_schema = current_schema() and table_name = ? '
        'order by ordinal_position',
    [table],
  );

  @override
  String compileTableListing() =>
      'select tablename from pg_tables where schemaname = current_schema()';
}
