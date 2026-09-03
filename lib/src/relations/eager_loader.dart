import '../database/connection.dart';
import '../model/model.dart';
import '../model/model_definition.dart';
import 'relation.dart';

/// Resolves `with_(['posts', 'posts.comments', 'author'])` into one query
/// per relation level, so N parents never cost N queries.
class EagerLoader {
  EagerLoader._();

  static Future<void> load(
    ModelDefinition<Object?> definition,
    List<Model> models,
    Map<String, RelationConstraint?> eagerLoads,
    Connection connection,
  ) async {
    if (models.isEmpty) return;
    // Group "posts.comments.author" under "posts" → ["comments.author"].
    final byRoot = <String, List<String>>{};
    final constraints = <String, RelationConstraint?>{};
    for (final entry in eagerLoads.entries) {
      final dot = entry.key.indexOf('.');
      final root = dot < 0 ? entry.key : entry.key.substring(0, dot);
      final children = byRoot.putIfAbsent(root, () => []);
      if (dot >= 0) {
        children.add(entry.key.substring(dot + 1));
      } else {
        constraints[root] = entry.value;
      }
    }
    for (final entry in byRoot.entries) {
      final relation = definition.relationFor(entry.key);
      await relation.eagerLoad(
        models,
        connection,
        constraint: constraints[entry.key],
        nested: entry.value,
      );
    }
  }
}
