import 'schema_builder.dart';

/// One reversible schema change. Subclass it, implement [up] and [down],
/// and hand instances to a `Migrator` in the order they should run.
///
/// ```dart
/// class CreateUsersTable extends Migration {
///   @override
///   Future<void> up(SchemaBuilder schema) => schema.create('users', (t) {
///     t.id();
///     t.string('email').unique();
///     t.timestamps();
///   });
///
///   @override
///   Future<void> down(SchemaBuilder schema) => schema.dropIfExists('users');
/// }
/// ```
abstract class Migration {
  /// Recorded in the migrations table; must be unique. Defaults to the
  /// class name.
  String get name => runtimeType.toString();

  Future<void> up(SchemaBuilder schema);

  Future<void> down(SchemaBuilder schema);
}
