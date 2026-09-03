import 'dart:async';

import '../exceptions/exceptions.dart';
import '../query/query_builder.dart';
import 'connection.dart';

/// The application's default connection, the Dart spelling of Laravel's
/// `DB` facade. Set it once at startup; models and `DB.table()` use it
/// unless given another connection explicitly.
///
/// ```dart
/// DB.use(SqliteConnection.open('storage/app.sqlite'));
/// final rows = await DB.table('users').where('active', true).get();
/// ```
class DB {
  DB._();

  static Connection? _default;

  static void use(Connection connection) => _default = connection;

  static Connection get connection {
    final c = _default;
    if (c == null) {
      throw ConnectionException(
        'No default connection. Call DB.use(connection) at startup, or pass '
        'a connection explicitly.',
      );
    }
    return c;
  }

  static bool get hasConnection => _default != null;

  /// Forget the default connection (tests).
  static void reset() => _default = null;

  static const _zoneKey = 'seshat.transaction';

  /// The connection pinned by an enclosing [transaction], or null.
  static Connection? get currentTransaction =>
      Zone.current[_zoneKey] as Connection?;

  /// The connection statements should use: the pinned one inside a
  /// transaction, otherwise the configured default.
  static Connection get effectiveConnection => currentTransaction ?? connection;

  /// A row-level query builder on [table]; results are plain maps.
  static QueryBuilder<Row> table(String table, {Connection? connection}) =>
      QueryBuilder<Row>(
        connection ?? effectiveConnection,
        table,
        hydrate: (r) => r,
      );

  static Future<R> transaction<R>(Future<R> Function(Connection tx) body) =>
      effectiveConnection.transaction(
        (tx) => runZoned(() => body(tx), zoneValues: {_zoneKey: tx}),
      );

  static Future<List<Row>> select(
    String sql, [
    List<Object?> bindings = const [],
  ]) => effectiveConnection.select(sql, bindings);

  static Future<int> statement(
    String sql, [
    List<Object?> bindings = const [],
  ]) => effectiveConnection.execute(sql, bindings);
}
