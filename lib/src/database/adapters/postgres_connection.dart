import 'dart:async';

import 'package:postgres/postgres.dart' as pg;

import '../../exceptions/exceptions.dart';
import '../connection.dart';
import '../grammar.dart';
import 'postgres_grammar.dart';

/// A connection to PostgreSQL via `package:postgres` (pure Dart).
///
/// ```dart
/// final db = await PostgresConnection.open(
///   host: 'localhost', database: 'app', username: 'app', password: '...',
/// );
/// DB.use(db);
/// ```
///
/// Transactions run on the driver's transaction session, so the object
/// handed to [transaction] callbacks is a distinct [Connection]; use it
/// (`User.using(tx)`) for every statement that must be inside the
/// transaction. Statements sent to the root connection while a
/// transaction is open wait until it finishes.
class PostgresConnection extends _PostgresSession {
  PostgresConnection._(this._pool) : super(_pool, null);

  static Future<PostgresConnection> open({
    String host = 'localhost',
    int port = 5432,
    required String database,
    String? username,
    String? password,
    bool ssl = false,
    int maxConnections = 5,
  }) async {
    final pool = pg.Pool<void>.withEndpoints(
      [
        pg.Endpoint(
          host: host,
          port: port,
          database: database,
          username: username,
          password: password,
        ),
      ],
      settings: pg.PoolSettings(
        maxConnectionCount: maxConnections,
        sslMode: ssl ? pg.SslMode.require : pg.SslMode.disable,
      ),
    );
    try {
      await pool.execute('select 1');
      return PostgresConnection._(pool);
    } catch (e) {
      await pool.close(force: true);
      throw ConnectionException(
        'Cannot connect to PostgreSQL at $host:$port/$database: $e',
        cause: e,
      );
    }
  }

  final pg.Pool<void> _pool;

  @override
  int get transactionDepth => 0;

  @override
  Future<R> transaction<R>(Future<R> Function(Connection tx) body) =>
      _pool.runTx((session) => body(_PostgresTransaction(session, this)));

  @override
  Future<void> close() => _pool.close();
}

/// Inside `runTx`: nested calls become savepoints on the same session.
class _PostgresTransaction extends _PostgresSession {
  _PostgresTransaction(super.session, super.root, [this._depth = 1]);

  final int _depth;

  @override
  int get transactionDepth => _depth;

  @override
  Future<R> transaction<R>(Future<R> Function(Connection tx) body) async {
    final savepoint = 'sp$_depth';
    await execute('savepoint $savepoint');
    try {
      final result = await body(
        _PostgresTransaction(session, root!, _depth + 1),
      );
      await execute('release savepoint $savepoint');
      return result;
    } catch (_) {
      await execute('rollback to savepoint $savepoint');
      rethrow;
    }
  }

  @override
  Future<void> close() async {}
}

/// Shared statement execution for the root connection and transactions.
/// Listeners and the query log live on the root; transactions forward.
abstract class _PostgresSession extends ConnectionBase {
  _PostgresSession(this.session, this.root);

  final pg.Session session;
  final _PostgresSession? root;

  @override
  Grammar get grammar => const PostgresGrammar();

  Future<R> _run<R>(
    String sql,
    List<Object?> bindings,
    FutureOr<R> Function() fn,
  ) => (root ?? this).logged(sql, bindings, fn);

  Future<pg.Result> _execute(String sql, List<Object?> bindings) => session
      .execute(pg.Sql.indexed(sql, substitution: '?'), parameters: bindings);

  @override
  Future<List<Row>> select(String sql, [List<Object?> bindings = const []]) =>
      _run(sql, bindings, () async {
        final result = await _execute(sql, bindings);
        return [for (final row in result) row.toColumnMap()];
      });

  @override
  Future<int> execute(String sql, [List<Object?> bindings = const []]) => _run(
    sql,
    bindings,
    () async => (await _execute(sql, bindings)).affectedRows,
  );

  @override
  Future<Object?> insertGetId(
    String sql,
    List<Object?> bindings, {
    String? primaryKey,
  }) => _run(sql, bindings, () async {
    final result = await _execute(sql, bindings);
    return result.isEmpty ? null : result.first.first;
  });

  @override
  void listen(void Function(QueryEvent event) listener) =>
      root == null ? super.listen(listener) : root!.listen(listener);

  @override
  void enableQueryLog() =>
      root == null ? super.enableQueryLog() : root!.enableQueryLog();

  @override
  List<QueryEvent> get queryLog =>
      root == null ? super.queryLog : root!.queryLog;

  @override
  QueryException wrapError(Object error, String sql, List<Object?> bindings) {
    if (error is pg.ServerException && error.code == '23505') {
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
