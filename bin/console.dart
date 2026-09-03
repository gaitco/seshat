// Migration console for the example app:
//   dart run bin/console.dart migrate
//   dart run bin/console.dart migrate:rollback --step=1
//   dart run bin/console.dart migrate:status
// Uses DATABASE_PATH (SQLite file, default example.sqlite).
import 'dart:io';

import 'package:seshat/seshat.dart';
import 'package:seshat/sqlite.dart';

import '../example/migrations.dart';

Future<void> main(List<String> args) async {
  final path = Platform.environment['DATABASE_PATH'] ?? 'example.sqlite';
  final db = SqliteConnection.open(path);
  final migrator = Migrator(db, migrations);
  final code = await runMigrationConsole(args, migrator);
  await db.close();
  exit(code);
}
