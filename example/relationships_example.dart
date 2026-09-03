// dart run example/relationships_example.dart
import 'package:seshat/seshat.dart';
import 'package:seshat/sqlite.dart';

import 'migrations.dart';
import 'models.dart';

Future<void> main() async {
  final db = SqliteConnection.inMemory();
  DB.use(db);
  await Migrator(db, migrations).run();

  final ann = await User.create({'name': 'Ann', 'email': 'ann@example.com'});
  final bob = await User.create({'name': 'Bob', 'email': 'bob@example.com'});
  await ann.posts().create({'title': 'Hello', 'published': true});
  await ann.posts().create({'title': 'Draft'});
  await bob.posts().create({'title': 'Bob writes', 'published': true});

  print('lazy: ann.posts().get()');
  for (final p in await ann.posts().get()) {
    print('  ${p.title}');
  }

  print('eager: User.with_(["posts"]) — two queries, not N+1');
  db.enableQueryLog();
  final users = await User.with_(['posts']).get();
  print('  queries: ${db.queryLog.length}');
  for (final u in users) {
    print('  ${u.name}: ${u.posts().value.map((p) => p.title).join(', ')}');
  }

  print('belongsTo from the other side');
  final posts = await Post.query()
      .with_(['user'])
      .where('published', true)
      .get();
  for (final p in posts) {
    print('  ${p.title} by ${p.user().value?.name}');
  }

  print('whereHas');
  final authorsOfDrafts = await User.query()
      .whereHas('posts', (q) => q.where('published', false))
      .pluck('name');
  print('  authors with drafts: $authorsOfDrafts');

  await db.close();
}
