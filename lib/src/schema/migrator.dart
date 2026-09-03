import '../database/connection.dart';
import '../exceptions/exceptions.dart';
import 'migration.dart';
import 'schema_builder.dart';
import 'schema_grammar.dart';

/// A migration's name and the batch it ran in (`null` = pending).
class MigrationStatus {
  const MigrationStatus(this.name, this.batch);

  final String name;
  final int? batch;

  bool get isPending => batch == null;

  @override
  String toString() => '$name: ${batch ?? 'Pending'}';
}

/// Runs and rolls back [Migration]s, recording each in a repository table
/// the way Laravel's `migrations` table does. Every migration runs inside
/// its own transaction, so a failing `up()` leaves neither its tables nor
/// its repository row behind. On MySQL, DDL statements commit implicitly, so
/// a migration that fails halfway may leave tables behind; the repository
/// row is still not written, so fixing and re-running is safe once you drop
/// what was created. Laravel has the same limitation.
class Migrator {
  Migrator(
    this.connection,
    this.migrations, {
    this.table = 'migrations',
    this.log,
  }) : grammar = schemaGrammarFor(connection) {
    final seen = <String>{};
    for (final m in migrations) {
      if (!seen.add(m.name)) {
        throw DatabaseException("Duplicate migration name '${m.name}'");
      }
    }
  }

  final Connection connection;
  final List<Migration> migrations;
  final String table;
  final SchemaGrammar grammar;

  /// Receives one progress line per migration run or rolled back.
  final void Function(String message)? log;

  /// Runs every pending migration in order as one new batch. Returns the
  /// names that ran.
  Future<List<String>> run() async {
    await _ensureRepository();
    final ran = await _ranBatches();
    final pending = [
      for (final m in migrations)
        if (!ran.containsKey(m.name)) m,
    ];
    if (pending.isEmpty) {
      log?.call('Nothing to migrate.');
      return const [];
    }
    final batch = (ran.values.fold(0, (a, b) => a > b ? a : b)) + 1;
    for (final m in pending) {
      await connection.transaction((tx) async {
        await m.up(SchemaBuilder(tx, grammar));
        await tx.execute(
          'insert into ${_table(tx)} (${_col('migration')}, '
          '${_col('batch')}) values (?, ?)',
          [m.name, batch],
        );
      });
      log?.call('Migrated: ${m.name}');
    }
    return [for (final m in pending) m.name];
  }

  /// Rolls back the last [steps] batches, newest migration first.
  Future<List<String>> rollback({int steps = 1}) async {
    if (steps < 1) throw ArgumentError.value(steps, 'steps', 'Must be >= 1');
    await _ensureRepository();
    final rows = await connection.select(
      'select ${_col('migration')}, ${_col('batch')} '
      'from ${_table(connection)} '
      'order by ${_col('batch')} desc, ${_col('id')} desc',
    );
    final batches = rows.map((r) => r['batch'] as int).toSet().take(steps);
    final cutoff = batches.isEmpty ? null : batches.last;
    return _rollbackRows([
      for (final r in rows)
        if (cutoff != null && (r['batch'] as int) >= cutoff) r,
    ]);
  }

  /// Rolls back every migration that has run.
  Future<List<String>> reset() async {
    await _ensureRepository();
    final rows = await connection.select(
      'select ${_col('migration')}, ${_col('batch')} '
      'from ${_table(connection)} '
      'order by ${_col('batch')} desc, ${_col('id')} desc',
    );
    return _rollbackRows(rows);
  }

  /// [reset] then [run]. Returns the names that ran.
  Future<List<String>> refresh() async {
    await reset();
    return run();
  }

  Future<List<MigrationStatus>> status() async {
    await _ensureRepository();
    final ran = await _ranBatches();
    return [for (final m in migrations) MigrationStatus(m.name, ran[m.name])];
  }

  Future<List<String>> _rollbackRows(List<Row> rows) async {
    final byName = {for (final m in migrations) m.name: m};
    final rolledBack = <String>[];
    for (final row in rows) {
      final name = row['migration'] as String;
      final migration = byName[name];
      if (migration == null) {
        throw DatabaseException(
          "Migration '$name' has run but is not registered with this Migrator",
        );
      }
      await connection.transaction((tx) async {
        await migration.down(SchemaBuilder(tx, grammar));
        await tx.execute(
          'delete from ${_table(tx)} where ${_col('migration')} = ?',
          [name],
        );
      });
      log?.call('Rolled back: $name');
      rolledBack.add(name);
    }
    return rolledBack;
  }

  Future<Map<String, int>> _ranBatches() async {
    final rows = await connection.select(
      'select ${_col('migration')}, ${_col('batch')} '
      'from ${_table(connection)} order by ${_col('id')}',
    );
    return {for (final r in rows) r['migration'] as String: r['batch'] as int};
  }

  Future<void> _ensureRepository() async {
    final schema = SchemaBuilder(connection, grammar);
    if (await schema.hasTable(table)) return;
    await schema.create(table, (t) {
      t.id();
      t.string('migration').unique();
      t.integer('batch');
    });
  }

  String _table(Connection c) => c.grammar.wrapTable(table);

  String _col(String name) => connection.grammar.wrap(name);
}
