// Rough throughput numbers for the hot paths against in-memory SQLite.
// Run: dart run benchmark/orm_benchmark.dart
import 'package:maat_seshat_core/maat_seshat_core.dart';
import 'package:maat_seshat_core/sqlite.dart';

class Item extends Model<Item> {
  Item({this.id, required this.name, required this.price, this.active = true});

  static final def = ModelDefinition<Item>(
    table: 'items',
    fromMap: (m) => Item(
      id: m['id'] as int?,
      name: m['name'] as String,
      price: m['price'] as num,
      active: m['active'] as bool? ?? true,
    ),
    fillable: ['name', 'price', 'active'],
    casts: {'active': Cast.boolean},
    timestamps: false,
  );

  @override
  ModelDefinition<Item> get definition => def;
  static QueryBuilder<Item> query() => def.query();

  final int? id;
  final String name;
  final num price;
  final bool active;

  @override
  Map<String, Object?> toMap() => {
    'id': id,
    'name': name,
    'price': price,
    'active': active,
  };
}

Future<void> main() async {
  final db = SqliteConnection.inMemory();
  DB.use(db);
  await db.execute(
    'create table items (id integer primary key autoincrement, '
    'name text, price real, active integer)',
  );

  Future<void> bench(String label, int n, Future<void> Function() body) async {
    await body(); // warm-up
    final watch = Stopwatch()..start();
    for (var i = 0; i < n; i++) {
      await body();
    }
    final us = watch.elapsedMicroseconds / n;
    print('${label.padRight(44)} ${us.toStringAsFixed(1).padLeft(9)} us/op');
  }

  await bench('compile: 3 wheres + order + limit', 20000, () async {
    Item.query()
        .where('active', true)
        .where('price', '>', 5)
        .whereIn('id', [1, 2, 3])
        .orderBy('name')
        .limit(10)
        .toSql();
  });
  await bench('create()', 5000, () async {
    await Item.query().create({'name': 'x', 'price': 9.5});
  });
  await bench('find() by primary key', 5000, () async {
    await Item.query().find(1);
  });
  await bench('get() 100 rows hydrated', 1000, () async {
    await Item.query().limit(100).get();
  });
  await bench('DB.table get() 100 rows as maps', 1000, () async {
    await DB.table('items').limit(100).get();
  });
  await bench('paginate() 20 per page', 1000, () async {
    await Item.query().paginate(page: 3, perPage: 20);
  });
  await bench('update() one dirty column', 2000, () async {
    final item = await Item.query().findOrFail(1);
    await item.update({'price': item.price + 1});
  });
  await db.close();
}
