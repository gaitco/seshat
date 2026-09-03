import 'dart:async';

import '../exceptions/exceptions.dart';
import 'grammar.dart';

/// One result row, keyed by column name (or alias).
typedef Row = Map<String, Object?>;

/// Emitted for every statement a connection runs. Subscribe with
/// [Connection.listen] or turn on [Connection.enableQueryLog].
class QueryEvent {
  QueryEvent(this.sql, this.bindings, this.duration);

  final String sql;
  final List<Object?> bindings;
  final Duration duration;

  @override
  String toString() =>
      '[${duration.inMicroseconds / 1000}ms] $sql ${bindings.isEmpty ? '' : bindings}';
}

/// A database connection. Adapters implement the four primitive
/// operations; everything else (query builder, models) is built on them.
///
/// The object passed to a [transaction] callback is also a [Connection];
/// run statements through it to keep them inside the transaction.
abstract class Connection {
  Grammar get grammar;

  /// Runs a SELECT and returns every row. Prefer the query builder's
  /// `chunk()`/`lazy()` for large tables.
  Future<List<Row>> select(String sql, [List<Object?> bindings = const []]);

  /// Runs INSERT/UPDATE/DELETE/DDL and returns the number of affected rows.
  Future<int> execute(String sql, [List<Object?> bindings = const []]);

  /// Runs an INSERT and returns the generated primary key.
  Future<Object?> insertGetId(
    String sql,
    List<Object?> bindings, {
    String? primaryKey,
  });

  /// Runs [body] inside a transaction: commits when it returns, rolls back
  /// and rethrows when it throws. Nested calls use savepoints.
  Future<R> transaction<R>(Future<R> Function(Connection tx) body);

  int get transactionDepth;

  Future<void> close();

  /// Observe every statement (for logging, tracing, slow-query alerts).
  void listen(void Function(QueryEvent event) listener);

  /// Start recording statements into [queryLog]. Useful in tests to assert
  /// how many queries a code path issued.
  void enableQueryLog();
  void disableQueryLog();
  List<QueryEvent> get queryLog;
  void flushQueryLog();
}

/// Shared plumbing for adapters: listeners, query log, error wrapping.
abstract class ConnectionBase implements Connection {
  final _listeners = <void Function(QueryEvent)>[];
  List<QueryEvent>? _log;

  @override
  void listen(void Function(QueryEvent event) listener) =>
      _listeners.add(listener);

  @override
  void enableQueryLog() => _log ??= [];

  @override
  void disableQueryLog() => _log = null;

  @override
  List<QueryEvent> get queryLog => List.unmodifiable(_log ?? const []);

  @override
  void flushQueryLog() => _log?.clear();

  /// Times [run], publishes a [QueryEvent], and converts driver errors into
  /// [QueryException] carrying the SQL and bindings.
  Future<R> logged<R>(
    String sql,
    List<Object?> bindings,
    FutureOr<R> Function() run,
  ) async {
    final watch = Stopwatch()..start();
    try {
      return await run();
    } on DatabaseException {
      rethrow;
    } catch (e) {
      throw wrapError(e, sql, bindings);
    } finally {
      final event = QueryEvent(sql, bindings, watch.elapsed);
      _log?.add(event);
      for (final l in _listeners) {
        l(event);
      }
    }
  }

  /// Adapters override to map driver errors (unique violations, ...).
  QueryException wrapError(Object error, String sql, List<Object?> bindings) =>
      QueryException(
        error.toString(),
        sql: sql,
        bindings: bindings,
        cause: error,
      );
}
