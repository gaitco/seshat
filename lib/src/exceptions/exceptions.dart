/// Base class for every error seshat raises.
class DatabaseException implements Exception {
  DatabaseException(this.message, {this.sql, this.bindings, this.cause});

  final String message;

  /// The statement that failed, when the error came from the database.
  final String? sql;
  final List<Object?>? bindings;

  /// The driver's own error, when there is one.
  final Object? cause;

  @override
  String toString() {
    final buffer = StringBuffer('$runtimeType: $message');
    if (sql != null) buffer.write('\n  SQL: $sql');
    if (bindings != null && bindings!.isNotEmpty) {
      buffer.write('\n  Bindings: $bindings');
    }
    return buffer.toString();
  }
}

/// The driver rejected a statement (syntax, constraint, type...).
class QueryException extends DatabaseException {
  QueryException(super.message, {super.sql, super.bindings, super.cause});
}

/// A UNIQUE or PRIMARY KEY constraint was violated.
class UniqueConstraintException extends QueryException {
  UniqueConstraintException(
    super.message, {
    super.sql,
    super.bindings,
    super.cause,
  });
}

/// The connection could not be opened, or was lost.
class ConnectionException extends DatabaseException {
  ConnectionException(super.message, {super.cause});
}

/// A table, column or alias name is not a plain identifier. Use [RawSql]
/// for anything else, and only with trusted input.
class InvalidIdentifierException extends DatabaseException {
  InvalidIdentifierException(String identifier)
    : super(
        "Invalid identifier '$identifier': use letters, digits and '_' "
        '(optionally qualified with a dot). Wrap trusted SQL in RawSql.',
      );
}

/// `findOrFail` / `firstOrFail` found nothing.
class ModelNotFoundException extends DatabaseException {
  ModelNotFoundException(this.model, [this.id])
    : super(
        id == null
            ? 'No query results for model [$model]'
            : 'No query results for model [$model] $id',
      );

  final String model;
  final Object? id;
}

/// An attribute was mass-assigned through `create()`/`update()`/`fill()`
/// without being listed in `fillable` (or while being `guarded`).
class MassAssignmentException extends DatabaseException {
  MassAssignmentException(String attribute, String model)
    : super(
        "Add [$attribute] to the fillable list of $model, or use "
        'forceCreate()/forceFill() for trusted data.',
      );
}

/// `relation.value` was read before the relation was eager loaded.
class RelationNotLoadedException extends DatabaseException {
  RelationNotLoadedException(String relation, String model)
    : super(
        "Relation '$relation' on $model is not loaded. Eager load it with "
        ".with_(['$relation']) or query it with .$relation().get().",
      );
}

/// A model method that only makes sense on a persisted row was called on
/// one that was never saved (or was deleted).
class ModelNotPersistedException extends DatabaseException {
  ModelNotPersistedException(String model, String operation)
    : super('Cannot $operation a $model that does not exist in the database.');
}
