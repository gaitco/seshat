import 'dart:async';

import '../database/connection.dart';
import '../exceptions/exceptions.dart';
import '../model/model.dart';
import '../model/model_definition.dart';
import '../query/query_builder.dart';

/// Extra constraints for an eager load: `withWhere('posts', (q) => ...)`.
typedef RelationConstraint = void Function(QueryBuilder<Object?> query);

/// A relationship between a parent model and [R].
///
/// Relations are declared once on the parent's [ModelDefinition] (inside
/// a closure, so definitions may reference each other), which gives the
/// query builder static knowledge for `with_()` and `whereHas()`. An
/// instance binds to one with [Model.relation]:
///
/// ```dart
/// HasMany<Post> posts() => relation('posts');
/// ```
abstract class Relation<R> {
  Relation(this.related);

  final ModelDefinition<R> related;

  /// Set by the parent definition when the relation is registered.
  late final ModelDefinition<Object?> parent;
  late final String name;

  /// The parent instance this relation is bound to, `null` on the
  /// definition-level relation.
  Model? instance;

  /// A copy bound to [model].
  Relation<R> bind(Model model);

  Model get _instance {
    final i = instance;
    if (i == null) {
      throw StateError(
        "Relation '$name' is not bound to a model; call model.$name()",
      );
    }
    return i;
  }

  Model get boundInstance => _instance;

  Connection? get connection => instance?.connection;

  /// Query for the related rows of the bound instance.
  QueryBuilder<R> query();

  /// Loads [name] for every model in [parents] with one query and stores
  /// the result on each via [Model.setRelation].
  Future<void> eagerLoad(
    List<Model> parents,
    Connection connection, {
    RelationConstraint? constraint,
    List<String> nested = const [],
  });

  /// Adds `related.fk = parent.pk` style constraints to [query] so it can
  /// serve as an EXISTS subquery for `whereHas`.
  ///
  /// The related side qualifies against `query.qualifier` (the subquery's
  /// alias when there is one) and the parent side against
  /// [parentQualifier] — never the bare table names, which collide when
  /// the relation is self-referencing.
  void addExistenceConstraint(QueryBuilder<R> query, String parentQualifier);

  /// The eager-loaded result on the bound instance. Throws
  /// [RelationNotLoadedException] rather than silently querying.
  Object? get loaded {
    final i = _instance;
    if (!i.relationLoaded(name)) {
      throw RelationNotLoadedException(name, i.definition.modelName);
    }
    return i.getRelation(name);
  }

  bool get isLoaded => instance?.relationLoaded(name) ?? false;

  /// Applies eager loads and constraints to a related query.
  QueryBuilder<R> prepareEagerQuery(
    QueryBuilder<R> query,
    RelationConstraint? constraint,
    List<String> nested,
  ) {
    constraint?.call(query);
    if (nested.isNotEmpty) query.with_(nested);
    return query;
  }
}
