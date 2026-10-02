# pgschema

Go-библиотека, которая добавляет схему к объектам в SQL-миграциях PostgreSQL:

```sql
CREATE TABLE users (...)       -- было
CREATE TABLE auth.users (...)  -- стало
```

Строится на собственном парсере PostgreSQL на чистом Go: без cgo и без WebAssembly. Модуль `github.com/4itosik/pg_migrate_research/pgschema`.

Статус: в разработке, этап 0 готов. Задача, этапы и пороги приёмки — в [prompts/own-parser-library.md](../prompts/own-parser-library.md). Текущее состояние — в [PROGRESS.md](PROGRESS.md), решения — в [docs/adr](docs/adr/README.md), отличия от прототипа — в [docs/differences.md](docs/differences.md).

Исследование, на котором основана библиотека, лежит в этом же репозитории:
- [README.md](../README.md) — отчёт: правила квалификации, найденные ловушки, ограничения подхода;
- [DATASET.md](../DATASET.md) — корпус миграций, регрессионные тесты PostgreSQL и эталоны;
- [poc/pgquery](../poc/pgquery) — прототип на libpg_query, эталон поведения.

## Запуск

Библиотека, только стандартная библиотека:

```bash
cd pgschema
CGO_ENABLED=0 go test ./...
```

Сверка с libpg_query и прототипом, стенд на живом PostgreSQL — отдельный модуль `oracle/`. Данные скачиваются один раз в `~/.cache/pgschema`:

```bash
pgschema/tools/get-data.sh                   # исходники PostgreSQL 17, регрессионные тесты и серверы 12–16, pg_dump
pgschema/tools/baseline.sh 16                # эталонные схемы и контроль корпуса на PostgreSQL 16
. pgschema/tools/env.sh 16                   # переменные для тестов
cd pgschema/oracle && go test ./...          # сверка; без переменных живые тесты пропускаются
go run ./cmd/metrics -out ../results/metrics.json
```
