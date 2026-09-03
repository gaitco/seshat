import '../database/connection.dart';
import '../model/model.dart';
import 'has_one_or_many.dart';
import 'relation.dart';

/// `users.id ← profiles.user_id`: the parent owns one [R].
class HasOne<R> extends HasOneOrMany<R> {
  HasOne(super.related, {required super.foreignKey, super.localKey});

  @override
  HasOne<R> bind(Model model) =>
      HasOne<R>(related, foreignKey: foreignKey, localKey: localKey)
        ..parent = parent
        ..name = name
        ..instance = model;

  /// The eager-loaded row, or `null`. Throws if not loaded.
  R? get value => loaded as R?;

  @override
  Future<void> eagerLoad(
    List<Model> parents,
    Connection connection, {
    RelationConstraint? constraint,
    List<String> nested = const [],
  }) async {
    final grouped = await loadGrouped(parents, connection, constraint, nested);
    for (final p in parents) {
      p.setRelation(name, grouped[p.toMap()[localKey]]?.firstOrNull);
    }
  }
}
