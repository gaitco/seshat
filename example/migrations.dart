// Example migrations. Register them in order; the migrator records what
// ran in a `migrations` table.
import 'package:seshat/seshat.dart';

class CreateUsersTable extends Migration {
  @override
  Future<void> up(SchemaBuilder schema) async {
    await schema.create('users', (table) {
      table.id();
      table.string('name');
      table.string('email').unique();
      table.string('role').defaultValue('member');
      table.boolean('active').defaultValue(true);
      table.timestamps();
      table.softDeletes();
    });
  }

  @override
  Future<void> down(SchemaBuilder schema) => schema.dropIfExists('users');
}

class CreatePostsTable extends Migration {
  @override
  Future<void> up(SchemaBuilder schema) async {
    await schema.create('posts', (table) {
      table.id();
      table.foreignId('user_id').constrained().onDelete('cascade');
      table.string('title');
      table.boolean('published').defaultValue(false);
      table.timestamps();
      table.index(['published']);
    });
  }

  @override
  Future<void> down(SchemaBuilder schema) => schema.dropIfExists('posts');
}

/// Every migration, in the order they should run.
final migrations = <Migration>[CreateUsersTable(), CreatePostsTable()];
