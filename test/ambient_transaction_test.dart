import 'package:seshat/seshat.dart';
import 'package:seshat/sqlite.dart';
import 'package:test/test.dart';

/// A [Connection] test double that mimics a pooled backend (e.g. Postgres):
/// [transaction] hands the body a genuinely different [Connection] object
/// per nesting level, each tracking its own transaction depth independently
/// (`begin` at depth 0, `savepoint` below that), while every wrapper
/// executes against the same underlying SQLite handle so data assertions
/// still work. This is the distinction SQLite's own connection can't make on
/// its own — [SqliteConnection.transaction] just hands back `this`, so
/// "went through the pinned transaction connection" and "went through the
/// default connection" are indistinguishable there. Calling `transaction()`
/// on the wrong wrapper (root instead of the pinned one) issues a second
/// `begin` while one is already open, which SQLite rejects — that's the
/// signal a misrouted nested transaction trips.
class PooledConnection implements Connection {
  PooledConnection(this._inner, [this._depth = 0]);

  final Connection _inner;
  final int _depth;

  @override
  Grammar get grammar => _inner.grammar;

  @override
  Future<List<Row>> select(String sql, [List<Object?> bindings = const []]) =>
      _inner.select(sql, bindings);

  @override
  Future<int> execute(String sql, [List<Object?> bindings = const []]) =>
      _inner.execute(sql, bindings);

  @override
  Future<Object?> insertGetId(
    String sql,
    List<Object?> bindings, {
    String? primaryKey,
  }) => _inner.insertGetId(sql, bindings, primaryKey: primaryKey);

  @override
  int get transactionDepth => _depth;

  @override
  Future<R> transaction<R>(Future<R> Function(Connection tx) body) async {
    final sp = _depth == 0 ? null : 'pooled_sp$_depth';
    await _inner.execute(sp == null ? 'begin' : 'savepoint $sp');
    try {
      final result = await body(PooledConnection(_inner, _depth + 1));
      await _inner.execute(sp == null ? 'commit' : 'release savepoint $sp');
      return result;
    } catch (_) {
      await _inner.execute(
        sp == null ? 'rollback' : 'rollback to savepoint $sp',
      );
      rethrow;
    }
  }

  @override
  Future<void> close() => _inner.close();

  @override
  void listen(void Function(QueryEvent event) listener) =>
      _inner.listen(listener);

  @override
  void enableQueryLog() => _inner.enableQueryLog();

  @override
  void disableQueryLog() => _inner.disableQueryLog();

  @override
  List<QueryEvent> get queryLog => _inner.queryLog;

  @override
  void flushQueryLog() => _inner.flushQueryLog();
}

void main() {
  setUp(() async {
    DB.use(SqliteConnection.open(':memory:'));
    await DB.statement(
      'create table users (id integer primary key autoincrement, email text)',
    );
  });

  tearDown(() async {
    await DB.connection.close();
    DB.reset();
  });

  test(
    'a nested call that never sees the handle joins the transaction',
    () async {
      // Exactly how a repository or service would write, with no handle threaded.
      Future<void> nestedInsert() =>
          DB.table('users').insert({'email': 'nested@x.y'});

      await expectLater(
        () => DB.transaction((tx) async {
          await nestedInsert();
          throw StateError('nope');
        }),
        throwsA(isA<StateError>()),
      );

      expect(await DB.table('users').count(), 0);
    },
  );

  test('a nested call commits with the transaction', () async {
    Future<void> nestedInsert() =>
        DB.table('users').insert({'email': 'nested@x.y'});

    await DB.transaction((tx) async => nestedInsert());

    expect(await DB.table('users').count(), 1);
  });

  test('exposes the pinned connection inside, and nothing outside', () async {
    expect(DB.currentTransaction, isNull);

    await DB.transaction((tx) async {
      expect(DB.currentTransaction, isNotNull);
      expect(identical(DB.currentTransaction, tx), isTrue);
    });

    expect(DB.currentTransaction, isNull);
  });

  test('DB.select and DB.statement also join', () async {
    await expectLater(
      () => DB.transaction((tx) async {
        await DB.statement("insert into users (email) values ('raw@x.y')");
        final rows = await DB.select('select count(*) as c from users');
        expect(rows.single['c'], 1);
        throw StateError('nope');
      }),
      throwsA(isA<StateError>()),
    );

    expect(await DB.table('users').count(), 0);
  });

  test('an explicit connection still wins over the ambient one', () async {
    final other = SqliteConnection.open(':memory:');
    addTearDown(other.close);
    await other.execute(
      'create table users (id integer primary key, email text)',
    );

    await DB
        .transaction<void>((tx) async {
          await DB.table('users', connection: other).insert({
            'id': 1,
            'email': 'other@x.y',
          });
          throw StateError('nope');
        })
        .catchError((_) {});

    // The other connection was never part of the transaction, so its row stands.
    expect(await DB.table('users', connection: other).count(), 1);
  });

  test('a nested call inside DB.transaction reaches the pinned connection, '
      'not the default one', () async {
    // Swap in a pooled-style default: transaction() hands back a
    // distinct object from the default, unlike SQLite's own connection.
    await DB.connection.close();
    DB.use(PooledConnection(SqliteConnection.open(':memory:')));
    await DB.statement('create table t (id integer primary key)');

    await DB.transaction((tx) async {
      final builder = DB.table('t');
      expect(identical(builder.connection, tx), isTrue);
      expect(identical(builder.connection, DB.connection), isFalse);
    });
  });

  test(
    'a nested DB.transaction() nests on the pinned connection, not the root',
    () async {
      // Regression test for routing DB.transaction's own body through
      // `connection` (the root) instead of `effectiveConnection` (the
      // pinned one): on a pooled-style connection this issues a second
      // `begin` on an already-open transaction, which SQLite rejects.
      await DB.connection.close();
      DB.use(PooledConnection(SqliteConnection.open(':memory:')));
      await DB.statement('create table t (id integer primary key, v text)');

      await DB.transaction((tx) async {
        await DB.transaction((_) async {
          await DB.table('t').insert({'v': 'nested'});
        });
      });

      expect(await DB.table('t').count(), 1);
    },
  );
}
