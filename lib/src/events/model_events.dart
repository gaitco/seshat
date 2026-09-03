import 'dart:async';

/// A hook that may veto the operation by returning `false`.
typedef VetoHook<T> = FutureOr<bool?> Function(T model);

/// A hook that runs after the fact.
typedef AfterHook<T> = FutureOr<void> Function(T model);

/// Lifecycle hooks for one model, registered on its [ModelDefinition].
/// Nothing runs unless you register something, and everything is visible
/// in one place.
///
/// ```dart
/// events: ModelEvents<User>(
///   creating: (u) => u.email.contains('@'),   // false aborts the insert
///   created: (u) async => mailer.welcome(u),
/// )
/// ```
///
/// Models are immutable, so hooks cannot rewrite attributes; do that in
/// your `create`/`update` call sites or in `toMap()`.
class ModelEvents<T> {
  const ModelEvents({
    this.saving,
    this.creating,
    this.updating,
    this.deleting,
    this.restoring,
    this.saved,
    this.created,
    this.updated,
    this.deleted,
    this.restored,
  });

  final VetoHook<T>? saving;
  final VetoHook<T>? creating;
  final VetoHook<T>? updating;
  final VetoHook<T>? deleting;
  final VetoHook<T>? restoring;
  final AfterHook<T>? saved;
  final AfterHook<T>? created;
  final AfterHook<T>? updated;
  final AfterHook<T>? deleted;
  final AfterHook<T>? restored;

  /// Runs a veto hook; `true` means "go ahead".
  Future<bool> before(VetoHook<T>? hook, T model) async =>
      hook == null || (await hook(model)) != false;

  Future<void> after(AfterHook<T>? hook, T model) async {
    if (hook != null) await hook(model);
  }
}
