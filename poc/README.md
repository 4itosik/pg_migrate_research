# PoC: схема в SQL-миграциях

Код к исследованию из [README в корне](../README.md). Три реализации одного и того же переписывания на трёх библиотеках и общий стенд проверки на живом PostgreSQL. Устройство датасета — [DATASET.md](../DATASET.md).

## Состав

| Каталог | Что внутри |
|---|---|
| `corpus/` | 23 сценария миграций в формате golang-migrate: `NNN_name.up.sql` / `.down.sql`, `setup.sql`, `check.sql`, `case.json` (в нём можно указать `min_server_version`) |
| `harness/` | Стенд: временный PostgreSQL, накат, проверки, сравнение схем, откат |
| `pgquery/` | Реализация на `github.com/wasilibs/go-pgquery`, утилита `cmd/pgschema-rewrite` |
| `pgquery/internal/libpgquery` | Тот же libpg_query, переведённый в Go через wasm2go: бэкенд сборки с тегом `wasm2go`, без WASM-рантайма |
| `pgquery/wasm2go/` | Генерация `internal/libpgquery` (`build.sh`), разрезание грамматики (`split_gram.py`), замер памяти компилятора (`maxrss`) |
| `multigres/` | Реализация на парсере multigres (изменение AST + генерация SQL) |
| `antlr/` | Реализация на ANTLR-грамматике bytebase (правка токенов) |
| `coverage/` | Замер покрытия грамматики, точности deparse и скорости пяти парсеров |
| `crosscheck/` | Сверка трёх реализаций на 32 тыс. операторов регрессионных тестов PostgreSQL |
| `results/` | JSON-отчёты прогонов и переписанные файлы каждой реализации |

Модули разделены намеренно. Каждый тянет только свою библиотеку, поэтому видны её реальные требования: версия Go, `replace` в `go.mod`, размер бинарника.

## Что проверяет стенд

Для каждого сценария и каждой реализации стенд делает следующее:

1. Вызывает `Learn` для всех up-миграций, затем `Rewrite` для каждого файла.
2. Создаёт пустую БД со схемами `auth` и `trap`.
3. Накатывает up-миграции с `search_path = trap, public`. Схемы `auth` в пути нет, как за pgbouncer. Любое имя без схемы либо не найдётся, либо создаст объект в `trap`.
4. Снимает `pg_dump --schema-only --schema=auth` и сравнивает с эталоном. Эталон — оригинальный SQL, выполненный с `search_path = auth, public`. Тела функций из сравнения исключены: их текст законно отличается.
5. Выполняет `check.sql`: вставки, вызовы функций, срабатывание триггеров, проверки результатов.
6. Ищет объекты, созданные вне `auth`, кроме объектов расширений.
7. Откатывает down-миграции и проверяет, что `auth` пуста.

Контроль самого корпуса:
- `TestBaseline`: оригинал с `search_path = auth` проходит все сценарии.
- `TestNoop`: оригинал без схемы в пути падает во всех сценариях.

Сценарий с `min_server_version` новее сервера пропускается (статус `skip`).

## Запуск

Нужны Go 1.25+ и бинарники PostgreSQL: `initdb`, `pg_ctl`, `postgres`, `pg_dump`. Серверные ищутся в `PG_BIN`, затем в `PATH`, затем в `/usr/lib/postgresql/*/bin`. `pg_dump` ищется отдельно: `PG_DUMP`, рядом с серверными, `PATH`, самый новый в `/usr/lib/postgresql/*/bin`. Он читает серверы своей и более старых версий. Вместо локального кластера можно передать `PG_DSN` с правами на создание БД и ролей. Модулю multigres нужен Go 1.26; при `GOTOOLCHAIN=auto` (по умолчанию) он скачается сам.

```bash
cd poc/harness   && go test ./...      # эталон (пишет results/baseline-schema) и контроль
cd poc/pgquery   && CGO_ENABLED=0 go test ./...
cd poc/multigres && CGO_ENABLED=0 go test ./...
cd poc/antlr     && CGO_ENABLED=0 go test ./...

# сводная таблица
cd poc/harness && go run ./cmd/matrix ../results/go-pgquery.json ../results/multigres.json ../results/bytebase-antlr.json

# один сценарий
CASE=07 go test -run TestCorpus -v .
```

Версии PostgreSQL 12–16. `get-postgres.sh` скачивает серверные сборки zonky embedded-postgres-binaries из Maven Central (`MAVEN_REPO` меняет зеркало). `run-versions.sh` гоняет эталон, контроль и три реализации на каждой версии и печатает сводную таблицу:

```bash
cd poc
./get-postgres.sh /opt/pg 12 13 14 15 16
PG_ROOT=/opt/pg ./run-versions.sh 12 13 14 15 16   # отчёты в results/pg12 … pg16
```

Стресс-тест и замеры на регрессионных тестах PostgreSQL. `get-regress.sh` скачивает `src/test/regress/sql/*.sql` нужных веток с raw.githubusercontent.com (список тестов берётся из `parallel_schedule`):

```bash
cd poc
./get-regress.sh /tmp/regress REL_12_STABLE REL_13_STABLE REL_14_STABLE REL_15_STABLE REL_16_STABLE
R=/tmp/regress/REL_16_STABLE
cd pgquery    && REGRESS_DIR=$R go test -run TestRegress -v .
cd coverage   && go run . -regress $R -out ../results/coverage-regress-pg16.json
cd crosscheck && go run . -regress $R -out ../results/crosscheck-regress-pg16.json -diffs /tmp/diffs.jsonl
```

Инструменты вырезают команды psql и данные `COPY … FROM stdin`. Если сканер не принимает токен (тесты проверяют и такие ошибки), выбрасывается только строка с этим токеном.

`-diffs` пишет каждое расхождение и каждую ошибку отдельной строкой JSON. У multigres расхождение помечено: `deparse`, если дерево меняет уже deparse исходного оператора, иначе `rewrite`.

## Сборка без WASM-рантайма

Тег `wasm2go` подменяет go-pgquery на `internal/libpgquery`: тот же libpg_query, переведённый в обычный Go. Код переписывания тот же. Подробности и замеры — README §10 и §11.

```bash
cd poc/pgquery
CGO_ENABLED=0 SAVE_SQL=0 go test -tags wasm2go ./...    # отчёт корпуса: results/go-pgquery-wasm2go.json
REGRESS_DIR=$R go test -tags wasm2go -run 'TestWasm2goSameBytes|TestPlaceholder|TestRegress' -v .
CGO_ENABLED=0 go build -tags wasm2go ./cmd/pgschema-rewrite

# мало памяти: компилятор обрабатывает функции пакета по одной (~0,8 ГБ вместо ~1,2 ГБ)
GOGC=50 go build -tags wasm2go -gcflags=github.com/4itosik/pg_migrate_research/poc/pgquery/internal/libpgquery=-c=1 ./cmd/pgschema-rewrite

# пик памяти компилятора и линковщика по пакетам; -a пересобирает и то, что уже в кэше
go build -o /tmp/maxrss ./wasm2go/maxrss
MAXRSS_LOG=/tmp/maxrss.log go build -a -tags wasm2go -toolexec=/tmp/maxrss -o /dev/null ./cmd/pgschema-rewrite
sort -t= -k2 -rn /tmp/maxrss.log | head

# перегенерировать internal/libpgquery; wasi-sdk и binaryen скачиваются в ~/.cache/pgquery-wasm2go
cd wasm2go && ./build.sh
```

`TestWasm2goSameBytes` сверяет с go-pgquery байты дерева разбора, токенов сканера, PL/pgSQL и все поля ошибок. `TestPlaceholder` проверяет переписывание при сборке: текст с меткой `pgschema_placeholder` после подстановки схемы должен совпасть с прямым переписыванием. `SAVE_SQL=0` не пишет переписанные файлы: они те же, что у go-pgquery.

## Утилита

```bash
cd poc/pgquery
CGO_ENABLED=0 go build ./cmd/pgschema-rewrite
./pgschema-rewrite -schema auth ../corpus/09_plpgsql_trigger/001_documents.up.sql
```

Файлы обрабатываются по порядку: объекты из ранних файлов известны при переписывании поздних. Результат печатается в stdout, предупреждения — в stderr.
