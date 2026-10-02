# pgschema

Go-библиотека, которая добавляет схему к объектам в SQL-миграциях PostgreSQL:

```sql
CREATE TABLE users (...)       -- было
CREATE TABLE auth.users (...)  -- стало
```

Строится на собственном парсере PostgreSQL на чистом Go: без cgo и без WebAssembly. Модуль `github.com/4itosik/pg_migrate_research/pgschema`.

Статус: в разработке. Задача, этапы и пороги приёмки — в [prompts/own-parser-library.md](../prompts/own-parser-library.md). Текущее состояние — в [PROGRESS.md](PROGRESS.md).

Исследование, на котором основана библиотека, лежит в этом же репозитории:
- [README.md](../README.md) — отчёт: правила квалификации, найденные ловушки, ограничения подхода;
- [DATASET.md](../DATASET.md) — корпус миграций, регрессионные тесты PostgreSQL и эталоны;
- [poc/pgquery](../poc/pgquery) — прототип на libpg_query, эталон поведения.

## Запуск

```bash
cd pgschema
CGO_ENABLED=0 go test ./...
```
