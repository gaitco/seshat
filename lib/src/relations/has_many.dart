import '../database/connection.dart';
import '../model/model.dart';
import 'has_one_or_many.dart';
import 'relation.dart';

/// `users.id ← posts.user_id`: the parent owns many [R].
///
/// ```dart
/// relations: (r) => r.hasMany('posts', Post.def, foreignKey: 'user_id'),
/// HasMany<Post> posts() => relation('posts');
/// final posts = await user.posts().get();
/// final loaded = user.posts().value; // after with_(['posts'])
/// ```
class HasMany<R> extends HasOneOrMany<R> {
  HasMany(super.related, {required super.foreignKey, super.localKey});

  @override
  HasMany<R> bind(Model model) =>
      HasMany<R>(related, foreignKey: foreignKey, localKey: localKey)
        ..parent = parent
        ..name = name
        ..instance = model;

  /// The eager-loaded rows. Throws if the relation was not loaded.
  List<R> get value => (loaded as List).cast<R>();

  @override
  Future<void> eagerLoad(
    List<Model> parents,
    Connection connection, {
    RelationConstraint? constraint,
    List<String> nested = const [],
  }) async {
    final grouped = await loadGrouped(parents, connection, constraint, nested);
    for (final p in parents) {
      p.setRelation(name, grouped[p.toMap()[localKey]] ?? <R>[]);
    }
  }
}
