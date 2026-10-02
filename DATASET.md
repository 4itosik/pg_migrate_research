# Датасет

Данные, на которых проверялись все реализации переписывания. Отчёт — [README.md](README.md), запуск стенда — [poc/README.md](poc/README.md).

Три части:

| Часть | Где | В git |
|---|---|---|
| Корпус миграций: 23 сценария с проверками | [`poc/corpus/`](poc/corpus) | да |
| Регрессионные тесты PostgreSQL 12–16: 32–43 тыс. операторов на версию | скачиваются [`poc/get-regress.sh`](poc/get-regress.sh) в любой каталог | нет |
| Эталоны и результаты прогонов | [`poc/results/`](poc/results) | да, кроме эталонов по версиям |

## 1. Корпус миграций

Каждый сценарий — отдельный каталог `poc/corpus/NN_имя/`. Миграции написаны так, как их пишут разработчики: без схемы. Целевая схема на стенде — `auth`.

### Файлы сценария

| Файл | Обязателен | Что это |
|---|---|---|
| `NNN_имя.up.sql` | да | миграция в формате golang-migrate. Номер задаёт порядок, файлов может быть несколько |
| `NNN_имя.down.sql` | да | откат той же версии: после отката схема должна остаться пустой |
| `case.json` | нет, но есть во всех сценариях | `title`, `description`, `expect` и, если нужно, `min_server_version` |
| `setup.sql` | нет | выполняется до миграций: объекты вне целевой схемы (другие схемы, расширения, роли) |
| `check.sql` | нет | выполняется после up-миграций: вставки, вызовы функций, срабатывание триггеров. Любая ошибка — провал сценария |

Поля `case.json`:
- `expect`: `pass` (по умолчанию) или `limitation` — сценарий, который статически не переписать. Сейчас это только 12, динамический SQL.
- `min_server_version`: самая старая версия PostgreSQL, на которой работает синтаксис сценария. На более старых сервер сценарий пропускает (`skip`).

При прогоне реализаций `check.sql` выполняется с `search_path = trap, public`. Поэтому обращаться к объектам миграций в нём нужно явно: `auth.tasks`.

### Как стенд прогоняет сценарий

[`poc/harness`](poc/harness), для каждой реализации:
1. `Learn` по всем up-файлам, затем `Rewrite` каждого up- и down-файла.
2. Новая БД, схемы `auth` и `trap`, затем `setup.sql`.
3. Up-миграции с `search_path = trap, public`. Схемы `auth` в пути нет, как за pgbouncer: имя без схемы либо не найдётся, либо создаст объект в `trap`.
4. `pg_dump --schema-only` схемы `auth` сравнивается с эталоном. Тела функций и сама схема в именах при сравнении убираются: текст тел законно отличается.
5. `check.sql`.
6. Поиск объектов, созданных в `trap` и `public`.
7. Down-миграции в обратном порядке, затем проверка, что `auth` пуста.

Этап падения пишется в отчёт: `rewrite`, `up`, `schema`, `check`, `leak`, `down`.

Контроль самого корпуса (`poc/harness`):
- `TestBaseline`: оригинал с `search_path = auth, public` проходит все сценарии. Этот же прогон пишет эталонные схемы.
- `TestNoop`: оригинал без схемы в пути падает во всех сценариях. Если сценарий проходит без переписывания, он ничего не проверяет.

### Сценарии

| Сценарий | Что покрывает |
|---|---|
| 01_tables_basic | таблицы, FK, индексы, `IF NOT EXISTS`, `DROP INDEX/TABLE` |
| 02_alter_rename_comment | `ALTER TABLE/INDEX`, переименования, `COMMENT ON` таблицы, колонки, индекса и ограничения |
| 03_sequences_defaults | последовательности, `OWNED BY`, `nextval('seq')`, `'seq'::regclass`, `setval`, `pg_get_serial_sequence`, `IDENTITY` |
| 04_types_enums_domains | enum, domain, composite, типы колонок и массивов, касты, `ALTER`/`COMMENT ON`/`DROP` типов |
| 05_views_matviews | представления и матпредставления, `REFRESH`, `ALTER VIEW RENAME`, `DROP VIEW` со списком |
| 06_dml_data_migration | `INSERT … ON CONFLICT`, `INSERT … SELECT` с JOIN, `UPDATE … FROM`, `DELETE … USING`, `RETURNING` |
| 07_cte_scoping | `WITH RECURSIVE`, CTE с именем реальной таблицы, видимость CTE, data-modifying CTE |
| 08_functions_sql | SQL-функции с телом в `$$` и в `'…'`, `RETURNS SETOF`, `CALL`, функции в `DEFAULT`/`CHECK`/`GENERATED`/индексе |
| 09_plpgsql_trigger | триггерная функция: `%TYPE`, `%ROWTYPE`, `SELECT INTO`, `NEW.*`, `CREATE TRIGGER … EXECUTE FUNCTION` |
| 10_plpgsql_advanced | `DECLARE` с курсором, `PERFORM`, `IF`/`CASE`, `FOR … IN SELECT`, `RETURNING INTO`, `RETURN QUERY` |
| 11_do_blocks | DO-блоки: `CREATE TYPE` с `EXCEPTION`, проверка по `pg_type`, свой тег долларовых кавычек |
| 12_dynamic_sql | `EXECUTE` строки и `format('%I')`. `expect: limitation`: ожидается предупреждение, а не переписывание |
| 13_partitions_inheritance | `PARTITION BY/OF`, `ATTACH/DETACH PARTITION`, `LIKE … INCLUDING ALL`, `INHERITS`, `[NO] INHERIT` |
| 14_grants_policies | RLS, `CREATE/ALTER/DROP POLICY`, `GRANT` на таблицу, колонку и последовательность, `REVOKE` |
| 15_quoting_and_qualified | `"CamelCase"`, зарезервированные слова в кавычках, ссылки на другую схему (`shared.*`), уже квалифицированные имена |
| 16_extensions_catalogs_temp | функции и типы расширений, `pg_*` и `information_schema`, temp-таблицы |
| 17_misc_ddl | частичный индекс с `INCLUDE`, `REINDEX`, `CREATE STATISTICS`, `CLUSTER`, `RULE`, `OWNER TO`, `LOCK`, `TRUNCATE` |
| 18_concurrent_index | `CREATE INDEX CONCURRENTLY` отдельной миграцией из одного оператора, как требует golang-migrate |
| 19_triggers_transition_tables | `REFERENCING NEW TABLE AS`, `INSTEAD OF` на view, `CONSTRAINT TRIGGER … DEFERRABLE` |
| 20_lexical_traps | имена таблиц в комментариях и строках (`'…'`, `E'…'`, `$q$…$q$`), алиас с именем таблицы |
| 21_cross_file_registry | тип и функция из 001 используются в 002, `ALTER TYPE RENAME` и новое имя дальше |
| 22_sql_standard_body | SQL-функции с телом `RETURN` и `BEGIN ATOMIC`, PostgreSQL 14+ |
| 23_statistics_target | `ALTER STATISTICS … SET STATISTICS`, PostgreSQL 13+ |

Полные описания — в `case.json` каждого сценария.

### Пример: 21_cross_file_registry

`001_types.up.sql` создаёт тип и функцию:

```sql
CREATE TYPE priority AS ENUM ('low', 'high');
CREATE FUNCTION normalize_code(code text) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $$ SELECT lower(btrim(code)) $$;
```

`002_tasks.up.sql` использует их в другом файле:

```sql
CREATE TABLE tasks (
    id   int PRIMARY KEY,
    prio priority NOT NULL DEFAULT 'low',
    code text NOT NULL CHECK (code = normalize_code(code))
);
INSERT INTO tasks VALUES (1, 'high'::priority, normalize_code('  AbC '));
ALTER TYPE priority RENAME VALUE 'high' TO 'urgent';
ALTER TYPE priority RENAME TO task_priority;
ALTER TABLE tasks ADD COLUMN backup_prio task_priority;
```

`check.sql` проверяет результат, обращаясь к схеме явно:

```sql
DO $$ BEGIN
    IF (SELECT prio::text FROM auth.tasks WHERE id = 1) <> 'urgent' THEN RAISE EXCEPTION 'enum rename broken'; END IF;
    IF (SELECT code FROM auth.tasks WHERE id = 1) <> 'abc' THEN RAISE EXCEPTION 'function in CHECK broken'; END IF;
END $$;
```

Переписанный go-pgquery файл, [`poc/results/go-pgquery/21_cross_file_registry/002_tasks.up.sql`](poc/results/go-pgquery/21_cross_file_registry/002_tasks.up.sql):

```sql
CREATE TABLE auth.tasks (
    id   int PRIMARY KEY,
    prio auth.priority NOT NULL DEFAULT 'low',
    code text NOT NULL CHECK (code = auth.normalize_code(code))
);
INSERT INTO auth.tasks VALUES (1, 'high'::auth.priority, auth.normalize_code('  AbC '));
ALTER TYPE auth.priority RENAME VALUE 'high' TO 'urgent';
ALTER TYPE auth.priority RENAME TO task_priority;
ALTER TABLE auth.tasks ADD COLUMN backup_prio auth.task_priority;
```

`setup.sql` нужен, когда миграция ссылается на чужую схему. Например, в 15_quoting_and_qualified:

```sql
CREATE SCHEMA IF NOT EXISTS shared;
CREATE TABLE IF NOT EXISTS shared.countries (code char(2) PRIMARY KEY);
INSERT INTO shared.countries VALUES ('RU'), ('US') ON CONFLICT DO NOTHING;
```

### Как добавить сценарий

1. Создать каталог `poc/corpus/NN_имя/` с up- и down-файлами, `case.json` и, если нужно, `setup.sql` и `check.sql`.
2. `cd poc/harness && go test -run TestBaseline ./...` — оригинал с `auth` в пути должен пройти. Прогон пишет эталон `poc/results/baseline-schema/NN_имя.sql`.
3. `go test -run TestNoop ./...` — без схемы в пути сценарий должен падать.
4. Прогнать реализации: `cd poc/pgquery && CGO_ENABLED=0 go test -run TestCorpus ./...`, то же в `poc/multigres` и `poc/antlr`.
5. На всех версиях: `cd poc && PG_ROOT=/opt/pg ./run-versions.sh 12 13 14 15 16`.

Реальные миграции лучше обезличивать: стенду нужна структура SQL, а не данные.

## 2. Регрессионные тесты PostgreSQL

Это файлы `src/test/regress/sql/*.sql` из веток `REL_12_STABLE` … `REL_16_STABLE`. Список тестов берётся из `parallel_schedule`. В репозитории их нет: скрипт качает их с raw.githubusercontent.com.

```bash
cd poc
./get-regress.sh /tmp/regress REL_12_STABLE REL_13_STABLE REL_14_STABLE REL_15_STABLE REL_16_STABLE
# результат: /tmp/regress/REL_16_STABLE/*.sql и т. д.
```

| | 12 | 13 | 14 | 15 | 16 |
|---|---|---|---|---|---|
| Файлов | 189 | 197 | 206 | 217 | 220 |
| Операторов, которые принимает парсер PostgreSQL | 32 024 | 34 733 | 37 777 | 41 116 | 42 798 |

Как из файлов получаются операторы:
- вырезаются команды psql (`\…`) и данные `COPY … FROM stdin`;
- текст делится сканером PostgreSQL по `;` верхнего уровня, тела `BEGIN ATOMIC … END` остаются целыми;
- строка с токеном, который сканер не принимает, выбрасывается. Тесты проверяют и такие ошибки;
- в замерах считаются только операторы, которые принимает libpg_query.

Где используются:

| Что | Как передать каталог |
|---|---|
| `TestRegress`, `TestWasm2goSameBytes`, `TestPlaceholder` в `poc/pgquery` | `REGRESS_DIR=/tmp/regress/REL_16_STABLE` |
| `poc/coverage`, `poc/crosscheck` | флаг `-regress /tmp/regress/REL_16_STABLE` |

Первый замер делался на копии этих тестов из bytebase/parser. Она неполная, её отчёты лежат как `poc/results/*-bytebase.json`.

## 3. Эталоны и результаты

| Путь | Что |
|---|---|
| `poc/results/baseline-schema/<сценарий>.sql` | эталон для PostgreSQL 16: схема `auth` после оригинальных миграций с `auth` в пути |
| `poc/results/pgNN/baseline-schema/` | эталоны для версий 12–16. Не в git, их пересоздаёт `run-versions.sh` |
| `poc/results/<реализация>.json`, `poc/results/pgNN/<реализация>.json` | отчёты по корпусу. Для каждого сценария: `status` (`pass`, `fail`, `skip`), `stage`, `error`, `warnings`, `rewrite_ms` |
| `poc/results/baseline.json`, `noop.json` | контроль корпуса: оригинал с `auth` проходит всё, без схемы падает всё |
| `poc/results/<реализация>/<сценарий>/<файл>` | переписанные файлы go-pgquery, multigres и bytebase ANTLR |
| `poc/results/go-pgquery-wasm2go.json` | корпус на сборке через wasm2go |
| `poc/results/coverage-regress-pgNN.json` | покрытие грамматики, точность deparse и скорость парсеров на регрессионных тестах |
| `poc/results/crosscheck-regress-pgNN.json` | сверка трёх реализаций на регрессионных тестах |
| `poc/results/coverage-corpus.json` | те же замеры парсеров на операторах корпуса |
