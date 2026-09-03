import 'package:sqlite3/sqlite3.dart' as sq;

import '../../exceptions/exceptions.dart';
import '../connection.dart';
import '../grammar.dart';
import 'sqlite_grammar.dart';

/// A connection to one SQLite database via `package:sqlite3` (FFI).
///
/// SQLite is single-writer, so keep one connection per isolate. Because
/// the driver is synchronous, the object handed to [transaction] callbacks
/// is this same connection: statements issued elsewhere in the isolate
/// while a transaction is open run inside it, exactly as with Laravel's
/// single PDO handle.
class SqliteConnection extends ConnectionBase {
  SqliteConnection._(this._db);

  /// Opens (creating if needed) the database file at [path].
  factory SqliteConnection.open(String path) {
    try {
      final db = sq.sqlite3.open(path)..execute('pragma foreign_keys = on');
      return SqliteConnection._(db);
    } catch (e) {
      throw ConnectionException(
        "Cannot open SQLite database '$path': $e",
        cause: e,
      );
    }
  }

  /// A fresh in-memory database. Ideal for tests: real SQL, no server.
  factory SqliteConnection.inMemory() => SqliteConnection.open(':memory:');

  final sq.Database _db;
  int _depth = 0;

  @override
  Grammar get grammar => const SqliteGrammar();

  @override
  int get transactionDepth => _depth;

  @override
  Future<List<Row>> select(String sql, [List<Object?> bindings = const []]) =>
      logged(sql, bindings, () {
        final result = _db.select(sql, bindings);
        return [for (final row in result) Map<String, Object?>.of(row)];
      });

  @override
  Future<int> execute(String sql, [List<Object?> bindings = const []]) =>
      logged(sql, bindings, () {
        _db.execute(sql, bindings);
        return _db.updatedRows;
      });

  @override
  Future<Object?> insertGetId(
    String sql,
    List<Object?> bindings, {
    String? primaryKey,
  }) => logged(sql, bindings, () {
    final result = _db.select(sql, bindings);
    return result.isEmpty ? _db.lastInsertRowId : result.first.values.first;
  });

  @override
  Future<R> transaction<R>(Future<R> Function(Connection tx) body) async {
    final savepoint = _depth == 0 ? null : 'sp$_depth';
    await execute(savepoint == null ? 'begin' : 'savepoint $savepoint');
    _depth++;
    try {
      final result = await body(this);
      _depth--;
      await execute(
        savepoint == null ? 'commit' : 'release savepoint $savepoint',
      );
      return result;
    } catch (_) {
      _depth--;
      await execute(
        savepoint == null ? 'rollback' : 'rollback to savepoint $savepoint',
      );
      rethrow;
    }
  }

  @override
  Future<void> close() async => _db.close();

  @override
  QueryException wrapError(Object error, String sql, List<Object?> bindings) {
    if (error is sq.SqliteException &&
        (error.extendedResultCode == 2067 ||
            error.extendedResultCode == 1555)) {
      return UniqueConstraintException(
        error.message,
        sql: sql,
        bindings: bindings,
        cause: error,
      );
    }
    return super.wrapError(error, sql, bindings);
  }
}
