# pgschema

Go-библиотека, которая добавляет схему к объектам в SQL-миграциях PostgreSQL:

```sql
CREATE TABLE users (...)       -- было
CREATE TABLE auth.users (...)  -- стало
```

Нужна, когда миграции накатываются через golang-migrate за pgbouncer в transaction mode: `search_path` там задать нельзя, а схема сервиса отдельная. Строится на собственном парсере PostgreSQL на чистом Go: без cgo, без WebAssembly, только стандартная библиотека в рантайме. Модуль `github.com/4itosik/pg_migrate_research/pgschema`.

Исследование, на котором основана библиотека, лежит в этом же репозитории: [README.md](../README.md) (правила квалификации, ловушки), [DATASET.md](../DATASET.md) (корпус миграций и регрессионные тесты PostgreSQL), [poc/pgquery](../poc/pgquery) — прототип на libpg_query, эталон поведения. Задача, этапы и пороги приёмки — в [prompts/own-parser-library.md](../prompts/own-parser-library.md). Состояние и цифры — в [PROGRESS.md](PROGRESS.md), решения — в [docs/adr](docs/adr/README.md), отличия от прототипа и libpg_query — в [docs/differences.md](docs/differences.md).

## Как этим пользоваться

Два способа: переписывать миграции при сборке (рекомендуется для десятков сервисов: в сервисе нет парсера) или прямо в сервисе.

### При сборке: каталог → каталог

```bash
cd pgschema && CGO_ENABLED=0 go build -o pgschema ./cmd/pgschema

# шаблоны с меткой вместо схемы; их кладут в репозиторий и в образ сервиса
pgschema rewrite -placeholder -src migrations -dst migrations.tmpl

# в CI: каталог шаблонов не устарел (код 1, если файл отличается, не хватает или лишний)
pgschema rewrite -placeholder -src migrations -dst migrations.tmpl -check

# или сразу с именем схемы
pgschema rewrite -schema auth -src migrations -dst migrations.auth
```

CLI читает файлы `NNN_имя.up.sql` и `NNN_имя.down.sql` каталога golang-migrate, сначала учит по всем up-файлам, какие типы и функции создают миграции, потом переписывает каждый файл и пишет результат в `-dst` под тем же именем. Предупреждения идут в stderr, `-fail-on-warning` делает их ошибкой, `-exclude a,b` оставляет без схемы отношения других схем. Ошибка в любом файле — код 1 и ни одного записанного файла.

Пример (`migrations/002_touch.up.sql` из каталога с двумя миграциями, `-schema auth`):

```sql
ALTER TABLE auth.users ADD COLUMN touched_at timestamptz;

CREATE FUNCTION auth.users_touch() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    NEW.touched_at := now();
    PERFORM 1 FROM auth.users WHERE id = NEW.id;
    RETURN NEW;
END $$;

CREATE TRIGGER users_touch BEFORE UPDATE ON auth.users
    FOR EACH ROW EXECUTE FUNCTION auth.users_touch();
```

### В сервисе: подстановка без парсера

Пакет `subst` и вложенный модуль `migratesrc` не тянут парсер:

```go
import (
	"github.com/golang-migrate/migrate/v4"
	"github.com/golang-migrate/migrate/v4/source"
	_ "github.com/golang-migrate/migrate/v4/source/file"

	"github.com/4itosik/pg_migrate_research/pgschema/migratesrc"
	"github.com/4itosik/pg_migrate_research/pgschema/subst"
)

// golang-migrate: шаблоны читаются как есть, схема подставляется при чтении
src, err := source.Open("file://migrations.tmpl")
m, err := migrate.NewWithSourceInstance("file", migratesrc.Wrap(src, "auth"), dbURL)

// или руками
sql, err := subst.Apply(tmpl, "auth") // метка pgschema_placeholder -> auth
```

`migratesrc` — отдельный модуль (`github.com/4itosik/pg_migrate_research/pgschema/migratesrc`, каталог `migratesrc/`): его `Wrap` принимает и возвращает `source.Driver` golang-migrate, поэтому ему нужна эта зависимость, а основному модулю — нет ([ADR 0005](docs/adr/0005-layout.md)). Недопустимое имя схемы делает ошибкой каждое чтение миграции.

Имя схемы с пробелом, заглавными буквами или ключевым словом получает кавычки, как у `quote_identifier` PostgreSQL (`"my schema"`, `"Auth"`, `"user"`). `subst` отвергает пустое имя, длиннее 63 байт и содержащее `'`, `$`, `\` или управляющий символ: метка стоит и внутри строк, и внутри долларовых тел функций.

### Библиотека

```go
rw, err := pgschema.New(pgschema.Options{Schema: "auth", ExcludeRelations: []string{"countries"}})
for _, up := range upFiles {
	err = rw.Learn(up) // заранее по всем up-файлам: какие типы и функции созданы миграциями
}
out, warns, err := rw.Rewrite(sql) // вставки "auth." в исходный текст; ошибка вместо непроверенного SQL
```

`Options{Placeholder: true}` вместо `Schema` даёт шаблон. Один `Rewriter` — одна последовательность миграций одной схемы; в нескольких горутинах им пользоваться нельзя.

## Что гарантируется

- **Только вставки.** `Rewrite` вставляет `schema.` в исходный текст. Комментарии, форматирование, регистр и кавычки остаются как в оригинале. Единственное, что переписывается целиком, — тело функции или `DO` в `'…'` или `E'…'`: его меняют декодированным и записывают в долларовых кавычках с тегом, которого нет в теле. Тело в `$$…$$` и `$tag$…$tag$` остаётся в своих кавычках.
- **Результат проверен.** После правок библиотека разбирает результат и сравнивает его дерево с деревом входа, в которое внесены те же квалификации; тело PL/pgSQL проверяется ещё и структурой (те же фрагменты SQL, режимы, объявления). Не разобралось, дерево расходится или позиция указывает не на то имя — `Rewrite` возвращает ошибку, а не SQL ([ADR 0007](docs/adr/0007-rewriter.md)).
- **Метка и прямое переписывание дают один текст.** `subst.Apply(шаблон, схема)` равен `Rewrite` с этой схемой: проверено для `auth`, `Auth`, `user` и `my schema` на корпусе миграций и на регрессионных тестах PostgreSQL 16.
- **Парсер совпадает с PostgreSQL.** Грамматика — порт `gram.y` PostgreSQL 17 на goyacc; деревья вместе с позициями совпали с libpg_query на 188 760 операторах корпуса и регрессионных тестов PostgreSQL 12–16, принятие — на всех. Отличия описаны в [docs/differences.md](docs/differences.md).
- **Не хуже прототипа.** На регрессионных тестах PostgreSQL 12–16 вывод побайтно совпадает с прототипом на libpg_query везде, где переписали оба; отказов 2–3 на версию против 10–11 у прототипа. Корпус на живом сервере: те же сценарии, что у прототипа; не проходит только динамический SQL, ожидаемо (цифры — в [PROGRESS.md](PROGRESS.md)).

## Что переписывается

Квалифицируются: таблицы, представления, последовательности, индексы во всех операторах, где они стоят как отношения (`FROM`, `JOIN`, `INSERT`/`UPDATE`/`DELETE`/`MERGE`, `ALTER`, `DROP`, `GRANT`, `COMMENT`, триггеры, политики, правила…); имена, которые операторы создают и удаляют (типы, домены, функции, процедуры, агрегаты, статистика, collation, конфигурации текстового поиска); строки, которые называют отношение: `nextval('s')`, `'t'::regclass`, `to_regclass('t')`, `pg_get_serial_sequence('t', …)`, `OWNED BY t.c`; типы и функции, **которые создали миграции** (встроенные типы и функции расширений не трогаются); SQL внутри тел функций на `sql` и `plpgsql` и внутри `DO`: операторы, выражения, присваивания, курсоры, `RETURN QUERY`, объявления `t%ROWTYPE`, `t.c%TYPE` и типов; тело `BEGIN ATOMIC`.

Не квалифицируются: имена CTE в их области видимости, временные таблицы, transition tables триггеров (`REFERENCING NEW TABLE AS x`), `pg_*` и `information_schema`, имя в `FOR UPDATE OF t`, отношения из `-exclude`, переменные PL/pgSQL вместо таблицы в `v.c%TYPE`.

Предупреждения (текст не меняется, `Rewrite` их возвращает): динамический SQL (`EXECUTE`) в теле функции; запросы к системным каталогам по имени (`pg_class`, `pg_type`, `information_schema`…); `current_schema()`; `SET search_path` и `set_config('search_path', …)`; `CREATE EXTENSION` без `SCHEMA`; тела на других языках; операторные классы и семейства и объекты вроде `CREATE OPERATOR`, которые библиотека не переписывает.

## Ограничения

- Грамматика PostgreSQL 17. Синтаксис, которого в ней нет, отвергается; миграции для версий 12–16 разбираются (проверено на регрессионных тестах этих версий).
- Динамический SQL (`EXECUTE`, `format(…)`) и тела на языках, кроме `sql` и `plpgsql`, статически не переписываются: только предупреждение.
- Имена, которые создаёт код тела на другом языке или динамический SQL, `Learn` не видит.
- Миграции одной схемы: `search_path` и `CURRENT_SCHEMA()` в SQL остаются как есть, о них сказано в предупреждениях.
- Входной текст должен быть валидным UTF-8 (как для сервера); `$1` вместо строковой константы отвергается, как сервером.
- Паника внутри парсера не доходит до вызывающего: `Rewrite` отказывает с ошибкой «internal error of the SQL parser». Такой отказ — ошибка библиотеки, о нём стоит сообщить.

## Вне скоупа

Описано, но не исправляется:
- golang-migrate берёт `pg_advisory_lock` — блокировку уровня сессии, ненадёжную за pgbouncer в transaction mode;
- схему таблицы `schema_migrations` golang-migrate берёт из `CURRENT_SCHEMA()`, то есть из `search_path` соединения, а не из имени схемы миграций.

## Цифры

Go 1.25.11, 4 ядра, linux/amd64 ([results/metrics.json](results/metrics.json)):

| | Бюджет | Замер |
|---|---|---|
| Первый разбор в процессе | ≤ 5 мс | 0,8 мс |
| Средний разбор оператора, регрессионные тесты PostgreSQL 16 | ≤ 20 мкс | 10,0 мкс |
| Переписывание корпуса (54 файла) в одном процессе | ≤ 0,1 с | 29 мс с первого вызова, 23 мс в прогретом процессе |
| Память компилятора на пакет | ≤ 700 МБ | 172 МБ (`internal/parse`) |
| Чистая сборка CLI | ≤ 30 с | 13 с |
| Бинарник CLI | ≤ 15 МБ | 5,7 МБ |

## Устройство

| Пакет | Назначение |
|---|---|
| `pgschema` | `New`, `Learn`, `Rewrite`: правила квалификации (`walker.go`, `functions.go`, `registry.go`), проверка (`rewriter.go`) |
| `subst` | подстановка схемы в шаблоны, кавычки идентификаторов |
| `cmd/pgschema` | CLI |
| `migratesrc` | обёртка над `source.Driver` golang-migrate (отдельный модуль) |
| `internal/lex` | лексер, порт `scan.l` |
| `internal/parse` | парсер: порт `gram.y` на goyacc (форк в `internal/tools/goyacc`), правила в `gram/*.y`, `gram_gen.go` сгенерирован |
| `internal/ast` | дерево, сгенерированное по описанию libpg_query |
| `internal/plpgsql` | извлечение SQL из тел PL/pgSQL |
| `oracle` | отдельный модуль сверки: libpg_query, прототип, живой PostgreSQL; сервисы его не импортируют |

## Разработка

Библиотека, только стандартная библиотека:

```bash
cd pgschema
CGO_ENABLED=0 go test ./...
(cd migratesrc && go test ./...)
```

Сверка с libpg_query и прототипом, стенд на живом PostgreSQL — модуль `oracle/`. Данные скачиваются один раз в `~/.cache/pgschema`:

```bash
pgschema/tools/get-data.sh                   # исходники PostgreSQL 17, регрессионные тесты и серверы 12–16, pg_dump
pgschema/tools/baseline.sh 16                # эталонные схемы и контроль корпуса на PostgreSQL 16
. pgschema/tools/env.sh 16                   # переменные для тестов
cd pgschema/oracle && go test ./...          # сверка; без переменных живые тесты пропускаются, в CI они падают
go run ./cmd/metrics -out ../results/metrics.json
```

Грамматику меняют правкой `internal/parse/gram/*.y` и `go generate ./internal/parse`; `TestGrammarGenerated` проверяет, что `gram_gen.go` не устарел и конфликтов нет. Фаззинг: `go test -run '^$' -fuzz FuzzParse -fuzztime 10m ./oracle` (и `FuzzRewrite`); детерминированные прогоны с мутациями — `TestParseMutations`, `TestRewriteMutations`. CI (`.github/workflows/pgschema.yml`) гоняет всё на PostgreSQL 12–16.

## Лицензии

Грамматика, лексер и PL/pgSQL-разбор — производные от PostgreSQL ([LICENSE.PostgreSQL](LICENSE.PostgreSQL)); дерево сгенерировано по описанию libpg_query ([LICENSE.libpg_query](LICENSE.libpg_query)); форк goyacc — [LICENSE.Go](LICENSE.Go). Подробности — [ADR 0006](docs/adr/0006-licensing.md).
