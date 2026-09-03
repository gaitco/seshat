import '../database/grammar.dart' show Compiled;
import '../exceptions/exceptions.dart';
import '../support/identifiers.dart';
import '../support/raw_sql.dart';
import 'blueprint.dart';

/// Turns a [Blueprint] into DDL for one dialect. The defaults here are the
/// ANSI-ish subset SQLite and PostgreSQL share; adapters override type
/// names, literals and the catalogue queries.
abstract class SchemaGrammar {
  const SchemaGrammar();

  String get name;

  /// Double-quotes an identifier (each dotted segment separately).
  String wrap(String identifier) => assertIdentifier(
    identifier,
  ).split('.').map((s) => '"${s.replaceAll('"', '""')}"').join('.');

  /// The SQL type for [column].
  String typeFor(ColumnDefinition column);

  /// How a `bool` default is written.
  String boolLiteral(bool value);

  /// `(sql, bindings)` selecting one row when the bound table name exists.
  Compiled compileTableExists();

  /// `(sql, bindings)` returning a `name` column per column of [table].
  Compiled compileColumnListing(String table);

  /// SQL selecting every user table name in the database (one column, no
  /// bindings) — used by `Schema.dropAllTables`.
  String compileTableListing();

  // ---------------------------------------------------------------------------
  // Tables
  // ---------------------------------------------------------------------------

  /// One CREATE TABLE followed by a CREATE INDEX per index.
  List<String> compileCreate(Blueprint blueprint) {
    final body = [for (final c in blueprint.columns) compileColumn(c)];
    final indexes = [...blueprint.columnIndexes];
    for (final command in blueprint.commands) {
      switch (command) {
        case PrimaryCommand():
          body.add('primary key (${_columnList(command.columns)})');
        case IndexCommand():
          indexes.add(command);
        default:
          throw DatabaseException(
            '${command.runtimeType} is not allowed while creating a table',
          );
      }
    }
    return [
      'create table ${wrap(blueprint.table)} (${body.join(', ')})',
      for (final i in indexes) compileIndex(blueprint.table, i),
    ];
  }

  /// One statement per added column, column index and command.
  List<String> compileAlter(Blueprint blueprint) {
    final table = wrap(blueprint.table);
    return [
      for (final c in blueprint.columns)
        'alter table $table add column ${compileColumn(c)}',
      for (final i in blueprint.columnIndexes) compileIndex(blueprint.table, i),
      for (final command in blueprint.commands)
        compileCommand(blueprint.table, command),
    ];
  }

  String compileDrop(String table) => 'drop table ${wrap(table)}';

  String compileDropIfExists(String table) =>
      'drop table if exists ${wrap(table)}';

  String compileRename(String from, String to) =>
      'alter table ${wrap(from)} rename to ${wrap(to)}';

  // ---------------------------------------------------------------------------
  // Pieces
  // ---------------------------------------------------------------------------

  String compileCommand(String table, SchemaCommand command) {
    final wrapped = wrap(table);
    return switch (command) {
      IndexCommand() => compileIndex(table, command),
      PrimaryCommand() =>
        'alter table $wrapped add primary key (${_columnList(command.columns)})',
      DropColumnCommand() =>
        'alter table $wrapped drop column ${wrap(command.name)}',
      DropIndexCommand() => 'drop index ${wrap(command.name)}',
      RenameColumnCommand() =>
        'alter table $wrapped rename column ${wrap(command.from)} '
            'to ${wrap(command.to)}',
    };
  }

  String compileIndex(String table, IndexCommand index) =>
      'create ${index.unique ? 'unique ' : ''}index ${wrap(index.name)} '
      'on ${wrap(table)} (${_columnList(index.columns)})';

  String compileColumn(ColumnDefinition column) {
    final parts = [
      wrap(column.name),
      typeFor(column),
      column.isNullable ? 'null' : 'not null',
    ];
    if (column.hasDefault) {
      parts.add('default ${compileDefault(column.defaultVal)}');
    } else if (column.isUseCurrent) {
      parts.add('default current_timestamp');
    }
    if (column.isPrimary) parts.add('primary key');
    if (column is ForeignIdDefinition && column.referencesTable != null) {
      parts.add(_foreignKey(column));
    }
    return parts.join(' ');
  }

  String compileDefault(Object? value) => switch (value) {
    null => 'null',
    bool b => boolLiteral(b),
    num n => '$n',
    String s => "'${s.replaceAll("'", "''")}'",
    RawSql raw => raw.sql,
    _ => throw ArgumentError.value(value, 'value', 'Unsupported default'),
  };

  String _foreignKey(ForeignIdDefinition column) {
    final buffer = StringBuffer(
      'references ${wrap(column.referencesTable!)} '
      '(${wrap(column.referencesColumn)})',
    );
    if (column.onDeleteAction != null) {
      buffer.write(' on delete ${column.onDeleteAction}');
    }
    if (column.onUpdateAction != null) {
      buffer.write(' on update ${column.onUpdateAction}');
    }
    return buffer.toString();
  }

  String _columnList(List<String> columns) => columns.map(wrap).join(', ');
}
