// dart run example/pagination_example.dart
import 'dart:convert';

import 'package:seshat/seshat.dart';
import 'package:seshat/sqlite.dart';

import 'migrations.dart';
import 'models.dart';

Future<void> main() async {
  final db = SqliteConnection.inMemory();
  DB.use(db);
  await Migrator(db, migrations).run();
  for (var i = 1; i <= 23; i++) {
    await User.create({
      'name': 'User $i',
      'email': 'u$i@example.com',
      'active': i % 4 != 0,
    });
  }

  final page = await User.query()
      .active()
      .orderBy('id')
      .paginate(page: 2, perPage: 5);
  print(
    'page ${page.currentPage}/${page.lastPage}, total ${page.total}, '
    'showing ${page.from}-${page.to}, more: ${page.hasMorePages}',
  );
  for (final u in page.data) {
    print('  ${u.id} ${u.name}');
  }

  print('as JSON for an API response:');
  print(jsonEncode(page.toJson()));

  print('streaming the whole table without loading it at once:');
  var seen = 0;
  await for (final _ in User.query().lazy(chunkSize: 10)) {
    seen++;
  }
  print('  streamed $seen rows');

  await db.close();
}
