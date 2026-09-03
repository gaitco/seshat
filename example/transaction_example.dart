// dart run example/transaction_example.dart
import 'package:maat_seshat_core/maat_seshat_core.dart';
import 'package:maat_seshat_core/sqlite.dart';

import 'migrations.dart';
import 'models.dart';

Future<void> main() async {
  final db = SqliteConnection.inMemory();
  DB.use(db);
  await Migrator(db, migrations).run();

  print('commit');
  await db.transaction((tx) async {
    final user = await User.using(
      tx,
    ).create({'name': 'Ann', 'email': 'ann@example.com'});
    await Post.query().using(tx).create({'user_id': user.id, 'title': 'Hi'});
  });
  print(
    '  users=${await User.query().count()} posts=${await Post.query().count()}',
  );

  print('rollback on exception');
  try {
    await db.transaction((tx) async {
      await User.using(tx).create({'name': 'Bob', 'email': 'bob@example.com'});
      throw StateError('payment failed');
    });
  } on StateError catch (e) {
    print('  caught: ${e.message}');
  }
  print('  users=${await User.query().count()}');

  print('nested: inner savepoint rolled back, outer kept');
  await db.transaction((tx) async {
    await User.using(tx).create({'name': 'Cid', 'email': 'cid@example.com'});
    try {
      await tx.transaction((inner) async {
        await User.using(
          inner,
        ).create({'name': 'Dan', 'email': 'dan@example.com'});
        throw StateError('inner');
      });
    } on StateError {
      // only Dan is discarded
    }
  });
  print('  users: ${await User.query().pluck('name')}');

  await db.close();
}
