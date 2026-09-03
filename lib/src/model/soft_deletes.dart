import 'model.dart';

/// Instance-side soft delete helpers. The query side (the global scope,
/// `withTrashed()`, `onlyTrashed()`, `restore()`, `forceDelete()`) is
/// switched on by `softDeletes: true` on the [ModelDefinition]; this mixin
/// adds what only makes sense on an instance.
///
/// ```dart
/// class User extends Model<User> with SoftDeletes<User> { ... }
/// await user.delete();      // sets deleted_at, row stays
/// final back = await user.restore();
/// await user.forceDelete(); // really gone
/// ```
mixin SoftDeletes<T extends Model<T>> on Model<T> {
  DateTime? get deletedAt {
    final def = definition;
    if (!def.softDeletes) {
      throw StateError(
        '${def.modelName} mixes in SoftDeletes but its ModelDefinition has '
        'softDeletes: false',
      );
    }
    return toMap()[def.deletedAtColumn] as DateTime?;
  }

  bool get trashed => deletedAt != null;

  /// Clears `deleted_at` and returns the restored instance.
  Future<T> restore() async {
    final events = definition.events;
    if (events != null && !await events.before(events.restoring, this as T)) {
      return this as T;
    }
    await newQuery().whereKey(requireKey('restore')).restore();
    final restored = definition.instantiate(
      {...toMap(), definition.deletedAtColumn: null},
      connection: connection,
      exists: true,
    );
    if (events != null) await events.after(events.restored, restored);
    return restored;
  }
}
