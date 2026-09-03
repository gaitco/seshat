// dart run example/crud_example.dart
import 'package:maat_seshat_core/maat_seshat_core.dart';
import 'package:maat_seshat_core/sqlite.dart';

import 'migrations.dart';
import 'models.dart';

Future<void> main() async {
  final db = SqliteConnection.inMemory();
  DB.use(db);
  await Migrator(db, migrations).run();
  db.listen((e) => print('  [sql] $e'));

  print('create');
  final user = await User.create({
    'name': 'Abdullah',
    'email': 'abdullah@example.com',
    'role': Role.admin,
  });
  print('  -> $user');

  print('find / query');
  print('  find(1): ${await User.find(1)}');
  final byEmail = await User.query()
      .where('email', 'abdullah@example.com')
      .first();
  print('  first(): ${byEmail?.name}');

  print('update (returns a new immutable instance)');
  final renamed = await user.update({'name': 'Abdullah Ghanem'});
  print('  -> ${renamed.name}, original still ${user.name}');

  print('bulk update + increment on the builder');
  await User.query().where('id', 1).update({'active': false});

  print('soft delete, restore, force delete');
  await renamed.delete();
  print(
    '  visible: ${await User.query().count()}, '
    'trashed: ${await User.def.onlyTrashed().count()}',
  );
  final back = await renamed.restore();
  print('  restored trashed=${back.trashed}');
  await back.forceDelete();
  print('  rows left: ${await User.def.withTrashed().count()}');

  await db.close();
}
