import '../support/identifiers.dart';
import '../support/raw_sql.dart';

/// The dialect-neutral column types a [Blueprint] can declare. Each schema
/// grammar maps them to its own SQL type names.
enum ColumnType {
  id,
  string,
  text,
  integer,
  bigInteger,
  unsignedBigInteger,
  boolean,
  double_,
  decimal,
  date,
  dateTime,
  timestamp,
  json,
  uuid,
}

const _referentialActions = {'cascade', 'set null', 'restrict', 'no action'};

/// One column in a [Blueprint], with its fluent modifiers.
class ColumnDefinition {
  ColumnDefinition(
    String name,
    this.type, {
    this.length,
    this.precision,
    this.scale,
  }) : name = assertIdentifier(name);

  final String name;
  final ColumnType type;

  /// `string` length; `decimal` precision/scale.
  final int? length;
  final int? precision;
  final int? scale;

  bool isNullable = false;
  bool hasDefault = false;
  Object? defaultVal;
  bool isUnique = false;
  bool isIndex = false;
  bool isPrimary = false;
  bool isUnsigned = false;
  bool isUseCurrent = false;

  /// Allows NULL (`nullable(false)` makes the column NOT NULL again).
  ColumnDefinition nullable([bool value = true]) {
    isNullable = value;
    return this;
  }

  /// A literal default. Accepts `bool`, `num`, `String`, [RawSql] or `null`;
  /// anything else throws [ArgumentError].
  ColumnDefinition defaultValue(Object? value) {
    if (value != null &&
        value is! bool &&
        value is! num &&
        value is! String &&
        value is! RawSql) {
      throw ArgumentError.value(
        value,
        'value',
        'Defaults must be bool, num, String, RawSql or null',
      );
    }
    hasDefault = true;
    defaultVal = value;
    return this;
  }

  /// Adds a unique index on this column.
  ColumnDefinition unique() {
    isUnique = true;
    return this;
  }

  /// Adds an index on this column.
  ColumnDefinition index() {
    isIndex = true;
    return this;
  }

  /// Makes this column the primary key (use [Blueprint.id] for the usual
  /// auto-increment key).
  ColumnDefinition primary() {
    isPrimary = true;
    return this;
  }

  /// Marks the column unsigned. Neither SQLite nor PostgreSQL has unsigned
  /// integers, so the grammars record it but emit nothing.
  ColumnDefinition unsigned() {
    isUnsigned = true;
    return this;
  }

  /// Defaults the column to `current_timestamp`.
  ColumnDefinition useCurrent() {
    isUseCurrent = true;
    return this;
  }
}

/// A `foreignId` column that can declare its foreign key inline.
class ForeignIdDefinition extends ColumnDefinition {
  ForeignIdDefinition(super.name, super.type);

  String? referencesTable;
  String referencesColumn = 'id';
  String? onDeleteAction;
  String? onUpdateAction;

  /// Adds the foreign key. [table] defaults to the plural of the column
  /// name without `_id` (`team_id` → `teams`).
  ForeignIdDefinition constrained([String? table, String column = 'id']) {
    referencesTable = assertIdentifier(table ?? _guessTable());
    referencesColumn = assertIdentifier(column);
    return this;
  }

  /// One of `cascade`, `set null`, `restrict`, `no action`.
  ForeignIdDefinition onDelete(String action) {
    onDeleteAction = _assertAction(action);
    return this;
  }

  /// One of `cascade`, `set null`, `restrict`, `no action`.
  ForeignIdDefinition onUpdate(String action) {
    onUpdateAction = _assertAction(action);
    return this;
  }

  String _guessTable() {
    final base = name.endsWith('_id')
        ? name.substring(0, name.length - 3)
        : name;
    return '${base}s';
  }

  static String _assertAction(String action) {
    final normalized = action.trim().toLowerCase();
    if (!_referentialActions.contains(normalized)) {
      throw ArgumentError.value(
        action,
        'action',
        'Expected one of ${_referentialActions.join(', ')}',
      );
    }
    return normalized;
  }
}

/// A table-level command collected by a [Blueprint].
sealed class SchemaCommand {
  const SchemaCommand();
}

class IndexCommand extends SchemaCommand {
  const IndexCommand(this.columns, this.name, {this.unique = false});

  final List<String> columns;
  final String name;
  final bool unique;
}

class PrimaryCommand extends SchemaCommand {
  const PrimaryCommand(this.columns);

  final List<String> columns;
}

class DropColumnCommand extends SchemaCommand {
  const DropColumnCommand(this.name);

  final String name;
}

class DropIndexCommand extends SchemaCommand {
  const DropIndexCommand(this.name);

  final String name;
}

class RenameColumnCommand extends SchemaCommand {
  const RenameColumnCommand(this.from, this.to);

  final String from;
  final String to;
}

/// Collects the columns and commands for one table. The schema grammar
/// turns a blueprint into DDL for its dialect.
///
/// ```dart
/// await schema.create('posts', (t) {
///   t.id();
///   t.string('title');
///   t.foreignId('user_id').constrained().onDelete('cascade');
///   t.timestamps();
/// });
/// ```
class Blueprint {
  Blueprint(String table) : table = assertIdentifier(table);

  final String table;
  final List<ColumnDefinition> columns = [];
  final List<SchemaCommand> commands = [];

  /// Indexes requested through column modifiers (`unique()`, `index()`).
  List<IndexCommand> get columnIndexes => [
    for (final c in columns)
      if (c.isUnique)
        IndexCommand([c.name], indexName([c.name], 'unique'), unique: true)
      else if (c.isIndex)
        IndexCommand([c.name], indexName([c.name], 'index')),
  ];

  /// Laravel's naming scheme: `users_email_unique`.
  String indexName(List<String> columns, String suffix) =>
      '${table}_${columns.join('_')}_$suffix';

  // ---------------------------------------------------------------------------
  // Columns
  // ---------------------------------------------------------------------------

  ColumnDefinition _add(ColumnDefinition column) {
    columns.add(column);
    return column;
  }

  /// Auto-incrementing big integer primary key.
  ColumnDefinition id([String name = 'id']) =>
      _add(ColumnDefinition(name, ColumnType.id));

  ColumnDefinition string(String name, [int length = 255]) =>
      _add(ColumnDefinition(name, ColumnType.string, length: length));

  ColumnDefinition text(String name) =>
      _add(ColumnDefinition(name, ColumnType.text));

  ColumnDefinition integer(String name) =>
      _add(ColumnDefinition(name, ColumnType.integer));

  ColumnDefinition bigInteger(String name) =>
      _add(ColumnDefinition(name, ColumnType.bigInteger));

  ColumnDefinition unsignedBigInteger(String name) =>
      _add(ColumnDefinition(name, ColumnType.unsignedBigInteger)..unsigned());

  ColumnDefinition boolean(String name) =>
      _add(ColumnDefinition(name, ColumnType.boolean));

  ColumnDefinition double_(String name) =>
      _add(ColumnDefinition(name, ColumnType.double_));

  /// Alias of [double_].
  ColumnDefinition float(String name) => double_(name);

  ColumnDefinition decimal(String name, {int precision = 8, int scale = 2}) =>
      _add(
        ColumnDefinition(
          name,
          ColumnType.decimal,
          precision: precision,
          scale: scale,
        ),
      );

  ColumnDefinition date(String name) =>
      _add(ColumnDefinition(name, ColumnType.date));

  ColumnDefinition dateTime(String name) =>
      _add(ColumnDefinition(name, ColumnType.dateTime));

  ColumnDefinition timestamp(String name) =>
      _add(ColumnDefinition(name, ColumnType.timestamp));

  ColumnDefinition json(String name) =>
      _add(ColumnDefinition(name, ColumnType.json));

  ColumnDefinition uuid(String name) =>
      _add(ColumnDefinition(name, ColumnType.uuid));

  /// An unsigned big integer meant to reference another table's `id`.
  ForeignIdDefinition foreignId(String name) {
    final column = ForeignIdDefinition(name, ColumnType.unsignedBigInteger)
      ..unsigned();
    columns.add(column);
    return column;
  }

  /// Nullable `created_at` and `updated_at` timestamps.
  void timestamps() {
    timestamp('created_at').nullable();
    timestamp('updated_at').nullable();
  }

  /// Nullable `deleted_at` timestamp for soft deletes.
  ColumnDefinition softDeletes([String name = 'deleted_at']) =>
      timestamp(name).nullable();

  // ---------------------------------------------------------------------------
  // Table-level commands
  // ---------------------------------------------------------------------------

  void unique(List<String> columns, [String? name]) => commands.add(
    IndexCommand(
      _assertAll(columns),
      assertIdentifier(name ?? indexName(columns, 'unique')),
      unique: true,
    ),
  );

  void index(List<String> columns, [String? name]) => commands.add(
    IndexCommand(
      _assertAll(columns),
      assertIdentifier(name ?? indexName(columns, 'index')),
    ),
  );

  /// A composite primary key.
  void primary(List<String> columns) =>
      commands.add(PrimaryCommand(_assertAll(columns)));

  void dropColumn(String name) =>
      commands.add(DropColumnCommand(assertIdentifier(name)));

  void dropIndex(String name) =>
      commands.add(DropIndexCommand(assertIdentifier(name)));

  void renameColumn(String from, String to) => commands.add(
    RenameColumnCommand(assertIdentifier(from), assertIdentifier(to)),
  );

  static List<String> _assertAll(List<String> names) {
    if (names.isEmpty) throw ArgumentError('At least one column is required');
    return [for (final n in names) assertIdentifier(n)];
  }
}
