# PoC: схема в SQL-миграциях

Код к исследованию из [README в корне](../README.md). Три реализации одного и того же переписывания на трёх библиотеках и общий стенд проверки на живом PostgreSQL.

## Состав

| Каталог | Что внутри |
|---|---|
| `corpus/` | 21 сценарий миграций в формате golang-migrate: `NNN_name.up.sql` / `.down.sql`, `setup.sql`, `check.sql`, `case.json` |
| `harness/` | Стенд: временный PostgreSQL, накат, проверки, сравнение схем, откат |
| `pgquery/` | Реализация на `github.com/wasilibs/go-pgquery`, утилита `cmd/pgschema-rewrite` |
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
- `TestBaseline`: оригинал с `search_path = auth` проходит 21 из 21.
- `TestNoop`: оригинал без схемы в пути падает 21 из 21.

## Запуск

Нужны Go 1.25+ и бинарники PostgreSQL: `initdb`, `pg_ctl`, `pg_dump`. Их ищет `PG_BIN`, затем `PATH`, затем `/usr/lib/postgresql/*/bin`. Вместо локального кластера можно передать `PG_DSN` с правами на создание БД и ролей. Модулю multigres нужен Go 1.26; при `GOTOOLCHAIN=auto` (по умолчанию) он скачается сам.

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

Стресс-тест и замеры на регрессионных тестах PostgreSQL. Нужен каталог с `*.sql` из `src/test/regress/sql`. В прогонах использована копия из `github.com/bytebase/parser/postgresql/examples`: 212 файлов, из них 7 — примеры PL/pgSQL из документации.

```bash
cd poc/pgquery    && REGRESS_DIR=/path/to/sql go test -run TestRegress -v .
cd poc/coverage   && go run . -regress /path/to/sql -out ../results/coverage-regress.json
cd poc/crosscheck && go run . -regress /path/to/sql -out ../results/crosscheck-regress.json -diffs /tmp/diffs.jsonl
```

`-diffs` пишет каждое расхождение и каждую ошибку отдельной строкой JSON. У multigres расхождение помечено: `deparse`, если дерево меняет уже deparse исходного оператора, иначе `rewrite`.

## Утилита

```bash
cd poc/pgquery
CGO_ENABLED=0 go build ./cmd/pgschema-rewrite
./pgschema-rewrite -schema auth ../corpus/09_plpgsql_trigger/001_documents.up.sql
```

Файлы обрабатываются по порядку: объекты из ранних файлов известны при переписывании поздних. Результат печатается в stdout, предупреждения — в stderr.
