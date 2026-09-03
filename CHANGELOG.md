## 0.1.0

Initial release.

- Parameterized query builder: where family, joins, grouping, ordering,
  limits, aggregates, `pluck`/`value`, `paginate`, `chunk`, `lazy`,
  insert/update/delete/increment/decrement/truncate, `RawSql` escape hatch.
- Typed models with `ModelDefinition`: fillable/guarded, casts, timestamps,
  dirty tracking, `create`/`save`/`update`/`delete`/`refresh`,
  `firstOrCreate`/`updateOrCreate`, model events.
- Relations: `hasOne`, `hasMany`, `belongsTo`, `belongsToMany` (pivot
  columns, `attach`/`detach`/`sync`), eager loading with dot notation and
  constraints, `whereHas`/`whereDoesntHave`.
- Local scopes (extensions), named global scopes, soft deletes.
- Transactions with savepoints on SQLite and PostgreSQL.
- Schema builder, migrations, migrator, migration console.
- Adapters: SQLite (`package:sqlite3`) and PostgreSQL (`package:postgres`).
