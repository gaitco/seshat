import 'dart:io';

import 'migrator.dart';

const _usage = '''
Usage: <command> [options]

  migrate                    Run pending migrations
  migrate:rollback [--step=N] Roll back the last N batches (default 1)
  migrate:reset              Roll back every migration
  migrate:refresh            Roll back everything, then migrate
  migrate:status             Show each migration and its batch
  help                       Show this message
''';

/// A tiny `maat migrate`-style dispatcher. Returns the process exit
/// code: 0 on success, 1 for `help` or an unknown command.
///
/// ```dart
/// void main(List<String> args) async {
///   exit(await runMigrationConsole(args, Migrator(db, migrations)));
/// }
/// ```
Future<int> runMigrationConsole(
  List<String> args,
  Migrator migrator, {
  StringSink? out,
  StringSink? err,
}) async {
  out ??= stdout;
  err ??= stderr;
  final command = args.isEmpty ? 'help' : args.first;
  switch (command) {
    case 'migrate':
      _report(out, 'Migrated', await migrator.run(), 'Nothing to migrate.');
    case 'migrate:rollback':
      final ran = await migrator.rollback(steps: _step(args));
      _report(out, 'Rolled back', ran, 'Nothing to roll back.');
    case 'migrate:reset':
      _report(out, 'Rolled back', await migrator.reset(), 'Nothing to reset.');
    case 'migrate:refresh':
      _report(out, 'Migrated', await migrator.refresh(), 'Nothing to migrate.');
    case 'migrate:status':
      for (final s in await migrator.status()) {
        out.writeln('${s.name.padRight(50)} ${s.batch ?? 'Pending'}');
      }
    default:
      err.writeln(_usage);
      return 1;
  }
  return 0;
}

int _step(List<String> args) {
  final option = args.skip(1).where((a) => a.startsWith('--step=')).lastOrNull;
  if (option == null) return 1;
  return int.tryParse(option.substring('--step='.length)) ??
      (throw ArgumentError('Invalid --step value: $option'));
}

void _report(StringSink out, String verb, List<String> names, String empty) {
  if (names.isEmpty) {
    out.writeln(empty);
    return;
  }
  for (final n in names) {
    out.writeln('$verb: $n');
  }
}
