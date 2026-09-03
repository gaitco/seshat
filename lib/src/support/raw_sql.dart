/// A fragment of SQL that is written into the statement verbatim.
///
/// This is the escape hatch. Everything passed to it is **trusted code**:
/// never build a [RawSql] from request input. Values still belong in
/// [bindings], never inside the [sql] string.
///
/// ```dart
/// query.select([RawSql('count(*) as total')]);
/// query.whereRaw(RawSql('json_extract(meta, ?) = ?', ['\$.plan', 'pro']));
/// ```
class RawSql {
  const RawSql(this.sql, [this.bindings = const []]);

  /// Alias for the constructor, reads well at call sites:
  /// `RawSql.expression('lower(email)')`.
  const RawSql.expression(this.sql, [this.bindings = const []]);

  final String sql;
  final List<Object?> bindings;

  @override
  String toString() => sql;
}
