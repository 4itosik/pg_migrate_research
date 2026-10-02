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

### Одна строка: на входе SQL и настройки, на выходе SQL или ошибка

```go
import "github.com/4itosik/pg_migrate_research/pgschema"

sql := `CREATE TABLE users (
    id    serial PRIMARY KEY,
    email text NOT NULL -- login
);
CREATE INDEX users_email_idx ON users (email);
CREATE TABLE public.audit (user_id int REFERENCES users (id));`

out, warnings, err := pgschema.Rewrite(sql, pgschema.Options{Schema: "auth"})
if err != nil {
	// SQL не разобрался (*pgschema.SyntaxError) или результат не прошёл
	// проверку (errors.Is(err, pgschema.ErrNotVerified)): текста нет
	return err
}
// out:
//   CREATE TABLE auth.users (
//       id    serial PRIMARY KEY,
//       email text NOT NULL -- login
//   );
//   CREATE INDEX users_email_idx ON auth.users (email);
//   CREATE TABLE public.audit (user_id int REFERENCES auth.users (id));
// warnings: []pgschema.Warning{Line, Message} — места, которые нельзя переписать
// статически (динамический SQL, search_path); w.String() — "line 3: …"
```

`Rewrite(sql, opts)` берёт текст одной миграции и настройки (`opts.Schema` — имя схемы) и возвращает текст со схемой, список предупреждений и ошибку. С ошибкой текста нет: непроверенный SQL библиотека не отдаёт. Настройки (`Options`):

| Поле | Что делает |
|---|---|
| `Schema` | имя схемы; с пробелом, заглавными буквами или ключевым словом получает кавычки, как у `quote_identifier`. Имя, которое `subst` не подставит (см. ниже), и метка `pgschema_placeholder` — ошибка |
| `Placeholder` | вместо схемы пишет метку, шаблон для `subst.Apply` (см. ниже); вместе с `Schema` — ошибка |
| `ExcludeRelations` | отношения, которые живут в другой схеме и остаются без схемы. Имена — идентификаторы SQL, как в тексте: без кавычек приводятся к нижнему регистру (`Countries` — это `countries`), в двойных кавычках берутся как есть (`"Countries"`). Пустое имя и имя со схемой (`public.countries`) — ошибка |
| `Extensions` | по расширению: в какой схеме оно установлено (`""` — в целевой); вызовы его функций и типы в SQL получают эту схему, `CREATE EXTENSION` без `SCHEMA` тоже (см. «Расширения»). Имя расширения приводится к нижнему регистру; расширение не из contrib без имён в `ExtensionObjects` — ошибка |
| `ExtensionObjects` | имена функций и типов расширений, которых нет в списке contrib; идентификаторы SQL, как в `ExcludeRelations`. Расширение, которого нет в `Extensions`, при выключенном `ExtensionsInSchema` — ошибка: его имена ни на что не повлияли бы |
| `ExtensionsInSchema` | все расширения, которые создают миграции, — в целевую схему |

`New` и `Rewrite` возвращают ошибку на настройки, которые иначе молча ничего не сделали бы: опечатку в имени расширения, имя отношения со схемой, `Schema` вместе с `Placeholder`.

Ошибки и предупреждения — типы пакета, внутренние типы наружу не выходят:
- `*pgschema.SyntaxError{Line, Column, Msg}` — SQL не разбирается, в том числе внутри тела функции или `DO`; строка и колонка (с 1, колонка — в символах) указывают в переданный текст, `Error()` — `line 2, column 13: syntax error at or near "FROM"`. Текст, который начинается с BOM UTF-8, — тоже `SyntaxError` с советом убрать BOM. Достаётся через `errors.As`.
- `pgschema.ErrNotVerified` — проверка результата не прошла (`errors.Is`); это ошибка библиотеки, а не SQL, о ней стоит сообщить.
- `pgschema.Warning{Line, Message}` — предупреждение; `Line` — строка места, о котором оно, если позиция есть (использование имени, `current_schema()`), иначе строка начала оператора; для тел функций — строка в исходном тексте.

Рабочие примеры с проверяемым выводом: [example_test.go](example_test.go) (`go test -run Example -v`): простая миграция, ошибка, предупреждения, настройки, несколько файлов через один `Rewriter`, шаблон и подстановка.

Если миграции зависят друг от друга (тип создан одним файлом, использован другим), нужен один `Rewriter`: сначала `Learn` на всех up-файлах, потом `Rewrite` на каждом (блок «Библиотека» ниже, `ExampleRewriter`). Тип или функция получают схему, только если их создала какая-то миграция.

### При сборке: каталог → каталог

```bash
cd pgschema && CGO_ENABLED=0 go build -o pgschema ./cmd/pgschema

# шаблоны с меткой вместо схемы; их кладут в репозиторий и в образ сервиса
pgschema rewrite -placeholder -src migrations -dst migrations.tmpl

# в CI: каталог шаблонов не устарел (код 1, если файл отличается, не хватает или лишний)
pgschema rewrite -placeholder -src migrations -dst migrations.tmpl -check

# или сразу с именем схемы
pgschema rewrite -schema auth -src migrations -dst migrations.auth

# расширения: где установлено (вызовы и типы получат эту схему), и имена, которых нет в списке contrib
pgschema rewrite -schema auth -extension pgcrypto=ext -extension citext=ext -src migrations -dst migrations.auth
pgschema rewrite -schema auth -extension postgis=ext -extension-objects postgis=geometry,st_distance -src migrations -dst migrations.auth

# все расширения из миграций — в схему сервиса
pgschema rewrite -schema auth -extensions-in-schema -src migrations -dst migrations.auth
```

CLI читает файлы `NNN_имя.up.sql` и `NNN_имя.down.sql` каталога golang-migrate, сначала учит по всем up-файлам, какие типы и функции создают миграции, потом переписывает каждый файл и пишет результат в `-dst` под тем же именем. Предупреждения идут в stderr со строкой (`файл: warning: line 3: …`), `-fail-on-warning` делает их ошибкой, `-exclude a,b` оставляет без схемы отношения других схем, `-extensions-in-schema`, `-extension имя[=схема]` и `-extension-objects имя=a,b` настраивают расширения (см. «Расширения»). Ошибка в любом файле — код 1 и ни одного записанного файла. В режиме записи файлы `NNN_имя.up.sql` и `.down.sql` в `-dst`, которых нет в `-src`, удаляются (каталог `-dst` генерируется); `-src` и `-dst` должны быть разными каталогами.

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

`migratesrc` — отдельный модуль (`github.com/4itosik/pg_migrate_research/pgschema/migratesrc`, каталог `migratesrc/`; пока в репозитории нет выпущенных версий, его `go.mod` ссылается на `pgschema` через `replace`, а внешнему сервису нужны теги `pgschema/vX.Y.Z` и `pgschema/migratesrc/vX.Y.Z`): его `Wrap` принимает и возвращает `source.Driver` golang-migrate, поэтому ему нужна эта зависимость, а основному модулю — нет ([ADR 0005](docs/adr/0005-layout.md)). Недопустимое имя схемы делает ошибкой каждое чтение миграции.

Имя схемы с пробелом, заглавными буквами или ключевым словом получает кавычки, как у `quote_identifier` PostgreSQL (`"my schema"`, `"Auth"`, `"user"`). `subst` отвергает пустое имя, длиннее 63 байт, не в UTF-8, содержащее `'`, `$`, `\`, управляющий символ, `/*`, `*/` или `--` и с пробелом в начале или в конце: метка стоит и внутри строк, и внутри долларовых тел функций, и в комментариях. Отвергаются и имена, которые не могут быть схемой сервиса: начинающиеся с `pg_` (PostgreSQL оставляет их системным схемам, `CREATE SCHEMA` их не принимает) и `information_schema`. Шаблон делается только из текста без метки: `Learn` и `Rewrite` в режиме `Placeholder` отвергают текст, где `pgschema_placeholder` уже есть (в комментарии, в строке), — `subst.Apply` заменил бы и его.

### Библиотека

```go
rw, err := pgschema.New(pgschema.Options{Schema: "auth", ExcludeRelations: []string{"countries"}})
for _, up := range upFiles {
	err = rw.Learn(up) // заранее по всем up-файлам: какие типы и функции созданы миграциями
}
out, warns, err := rw.Rewrite(sql) // вставки "auth." в исходный текст; ошибка вместо непроверенного SQL
```

`Options{Placeholder: true}` вместо `Schema` даёт шаблон; `Options{ExtensionsInSchema: true}` включает схему в `CREATE EXTENSION` (см. «Расширения»). Один `Rewriter` — одна последовательность миграций одной схемы; в нескольких горутинах им пользоваться нельзя. `Learn` и `Rewrite`, которые вернули ошибку, не меняют `Rewriter`: типы, функции и расширения из такого текста не запоминаются.

## Что гарантируется

- **Только вставки.** `Rewrite` вставляет `schema.` в исходный текст. Комментарии, форматирование, регистр и кавычки остаются как в оригинале. Целиком переписывается только то, что нельзя править на месте: тело функции или `DO` в `'…'` или `E'…'` (его меняют декодированным и записывают в долларовых кавычках с тегом, которого нет в теле) и строка с именем отношения, в которой есть экранирование (`nextval(E'\x73')` становится `nextval('auth.s')`). Тело в `$$…$$` и `$tag$…$tag$` остаётся в своих кавычках.
- **Результат проверен.** После правок библиотека разбирает результат и сравнивает его дерево с деревом входа, в которое внесены те же квалификации; тело PL/pgSQL проверяется ещё и структурой (те же фрагменты SQL, режимы, объявления). Не разобралось, дерево расходится или позиция указывает не на то имя — `Rewrite` возвращает ошибку, а не SQL ([ADR 0007](docs/adr/0007-rewriter.md)).
- **Метка и прямое переписывание дают один текст.** `subst.Apply(шаблон, схема)` равен `Rewrite` с этой схемой: проверено для `auth`, `Auth`, `user` и `my schema` на корпусе миграций и на регрессионных тестах PostgreSQL 16 и применением результата на сервере. Условие: миграции не называют целевую схему явно. Шаблон не знает, какая схема целевая, поэтому `CREATE TYPE auth.mood` в нём — тип чужой схемы, который переписыватель не запоминает; с `-schema auth` он запомнил бы его и квалифицировал бы `mood` дальше.
- **Парсер совпадает с PostgreSQL.** Грамматика — порт `gram.y` PostgreSQL 17 на goyacc; деревья вместе с позициями совпали с libpg_query на 188 760 операторах корпуса и регрессионных тестов PostgreSQL 12–16, принятие — на всех. Отличия описаны в [docs/differences.md](docs/differences.md).
- **Не хуже прототипа.** На регрессионных тестах PostgreSQL 12–16 вывод побайтно совпадает с прототипом на libpg_query везде, где переписали оба, кроме трёх намеренных отличий (имена встроенных объектов, вложенные приведения к `regclass`, область временных таблиц; сверка проверяет, что каждое отличие — одно из них, и каждое подтверждено на сервере, [docs/differences.md](docs/differences.md)); отказов 2–3 на версию против 10–11 у прототипа. Корпус на живом сервере: те же сценарии, что у прототипа; не проходит только динамический SQL, ожидаемо (цифры — в [PROGRESS.md](PROGRESS.md)).
- **Ошибка не меняет состояние.** `Learn` или `Rewrite`, вернувшие ошибку, оставляют `Rewriter` таким, каким он был до вызова.

## Что переписывается

Квалифицируются: таблицы, представления, последовательности, индексы во всех операторах, где они стоят как отношения (`FROM`, `JOIN`, `INSERT`/`UPDATE`/`DELETE`/`MERGE`, `ALTER`, `DROP`, `GRANT`, `COMMENT`, триггеры, политики, правила…); имена, которые операторы создают и удаляют (типы, домены, функции, процедуры, агрегаты, статистика, collation, конфигурации текстового поиска); строки, которые называют отношение: `nextval('s')`, `'t'::regclass`, `to_regclass('t')`, `pg_get_serial_sequence('t', …)`, в том числе под вложенными приведениями старого `pg_dump` (`nextval(('s'::text)::regclass)`, `'s'::text::regclass`); таблица в `OWNED BY t.c`; типы и функции, **которые создали миграции** (встроенные типы и функции не трогаются; функции и типы расширений — только если расширение настроено, см. «Расширения»); SQL внутри тел функций на `sql` и `plpgsql` и внутри `DO`: операторы, выражения, присваивания, курсоры, `RETURN QUERY`, объявления `t%ROWTYPE`, `t.c%TYPE` и типов; тело `BEGIN ATOMIC`.

Имя, у которого схема уже указана, не меняется, какой бы она ни была: чужая (`other.t`), целевая (`auth.t`), `pg_temp`, `pg_catalog`, с каталогом (`db.s.t`). Это относится ко всем объектам: таблицам, типам, функциям, строкам `regclass`, `DROP`, `COMMENT`, `GRANT`, объявлениям `%TYPE`. В одном операторе меняются только имена без схемы (`FROM other.a JOIN b` → `FROM other.a JOIN auth.b`); проверено на 33 операторах разных видов (`TestRewriteLeavesQualifiedNamesAlone`).

**Имена встроенных объектов.** Тип или функция миграции с именем типа или функции `pg_catalog` (`CREATE TABLE text`, `CREATE TABLE money`, `CREATE FUNCTION round(…)`) создаётся в целевой схеме, но использования этого имени без схемы не квалифицируются: `pg_catalog` всегда первая в `search_path`, и для типа `text` в `name text` это и есть разрешение PostgreSQL, а для функции так сохраняются вызовы встроенной (иначе `round(price, 2)` по всей миграции ушёл бы в `auth.round`, а тело `SELECT round($1::numeric, $2)` — в бесконечную рекурсию). И создание, и каждое такое использование получают предупреждение: если миграция имеет в виду свой объект, пусть назовёт схему явно. Имена — объединение `pg_type` (с массивами) и `pg_proc` (функции, агрегаты, процедуры) живых серверов PostgreSQL 12–16 и ключевых слов типов грамматики (`int`, `varchar`, …), их собирает `oracle/cmd/genbuiltins` в `builtins_gen.go`.

Не квалифицируются: имена CTE в их области видимости, временные таблицы (в тексте, который передан `Learn` или `Rewrite` и создаёт временную таблицу, начиная с её `CREATE TEMP`; в других файлах имя временной таблицы ничего не скрывает, а `CREATE TABLE` с тем же именем без `TEMP` получает схему и снимает это для следующих операторов), transition tables триггеров (`REFERENCING NEW TABLE AS x`), `pg_*` и `information_schema`, имя в `FOR UPDATE OF t`, отношения из `-exclude`, переменные PL/pgSQL вместо таблицы в `v.c%TYPE`.

Предупреждения (текст не меняется, `Rewrite` их возвращает): динамический SQL (`EXECUTE`) в теле функции; тип или функция миграции с именем встроенного объекта и их использования (см. выше); `SECURITY LABEL` и `ALTER EXTENSION … ADD/DROP` (их объект не переписывается); запросы к системным каталогам по имени (`pg_class`, `pg_type`, `information_schema`…); `current_schema()`; `SET search_path` и `set_config('search_path', …)`; `CREATE EXTENSION` без `SCHEMA`, если расширение не настроено; настроенное расширение с операторами (они не переписываются) и расширение, имён которого библиотека не знает; тела на других языках; операторные классы и семейства и объекты вроде `CREATE OPERATOR`, которые библиотека не переписывает; создание диапазонного типа, collation и объекта текстового поиска (их использование не квалифицируется); `CREATE SCHEMA` с элементами.

## Расширения

Расширение попадает в миграции двумя способами: как оператор `CREATE EXTENSION` и как использование его объектов прямо в SQL (`DEFAULT gen_random_uuid()`, `digest(...)`, `email citext`). Библиотека по умолчанию не трогает ни то, ни другое: расширение создаётся один раз на базу и обычно общее для сервисов (`public`, откуда его видит любой `search_path`). Каждое поведение настраивается.

| Настройка | `CREATE EXTENSION x` | Использование в SQL |
|---|---|---|
| ничего (по умолчанию) | как написан, предупреждение «без `SCHEMA` объекты попадут в первую схему `search_path`» | не меняется |
| `Extensions: {"pgcrypto": "ext"}` (CLI `-extension pgcrypto=ext`) | получает `SCHEMA ext`, если схемы в нём нет | функции и типы расширения без схемы получают `ext.` |
| `Extensions: {"pgcrypto": ""}` (CLI `-extension pgcrypto`) | получает `SCHEMA <целевая>` | они получают целевую схему |
| `ExtensionsInSchema: true` (CLI `-extensions-in-schema`) | каждое расширение из миграций получает `SCHEMA <целевая>` | они получают целевую схему |

Схема, указанная в самом операторе (`CREATE EXTENSION x SCHEMA public`), остаётся при любых настройках, и вызовы функций такого расширения после него получают `public.`, если расширение включено настройкой, даже если `Extensions` называет для него другую схему: оператор говорит, где расширение на самом деле. Функция, которую создала миграция, сильнее одноимённой функции расширения. Имена из `ExtensionObjects` берутся как даны, даже если такое имя есть в `pg_catalog` другой версии (`gen_random_uuid` для PostgreSQL 12, ниже).

Какие имена принадлежат расширению, библиотека знает для 48 расширений из contrib (`extensions_gen.go`, его создаёт `oracle/cmd/genext` по живым серверам PostgreSQL 12–16: функции, агрегаты, типы, таблицы и представления, которыми расширение владеет по `pg_depend`). Имена, которые есть и в ядре, из списка убраны: `gen_random_uuid` в ядре с PostgreSQL 13, ему схема расширения не нужна (в PostgreSQL 12 он принадлежит `pgcrypto`, и там имя надо назвать: `ExtensionObjects: {"pgcrypto": {"gen_random_uuid"}}`; проверено на сервере 12, `TestExtensionUsesOnServer`). Для расширений вне contrib (`postgis`, `vector`, `pg_cron`, …) имена даёт `ExtensionObjects: {"postgis": {"geometry", "st_distance"}}` (CLI `-extension-objects postgis=geometry,st_distance`); для расширения, которое библиотека не знает и имён не получила, `CREATE EXTENSION` под `ExtensionsInSchema` получает предупреждение, а в `Extensions` такое расширение — ошибка `New`.

Пример (миграция, `pgcrypto` и `citext` установлены в схему `ext`, `gen_random_uuid` — ядро):

```sql
CREATE TABLE users (                                  CREATE TABLE auth.users (
    id    uuid DEFAULT gen_random_uuid(),                 id    uuid DEFAULT gen_random_uuid(),
    email citext,                                    →    email ext.citext,
    pwd   text DEFAULT crypt('x', gen_salt('bf'))         pwd   text DEFAULT ext.crypt('x', ext.gen_salt('bf'))
);                                                    );
```

Проверено на сервере с `search_path = trap, public`, где нет ни целевой схемы, ни `ext` (`TestExtensionUsesOnServer`): без настройки миграция падает, с настройкой проходит; то же для расширений, которые создают сами миграции с `ExtensionsInSchema` (они оказываются в целевой схеме).

**Операторы расширений библиотека не переписывает.** Оператор ищется через `search_path`, а схему на него можно поставить только как `OPERATOR(схема.=)`. Если расширение вне `search_path`, а оператор из него не виден, сервер молча берёт оператор ядра: для `citext` сравнение `=` становится сравнением `text` и перестаёт быть нечувствительным к регистру, для `pg_trgm` не работают `%` и `<->`, для `hstore` — `->`. Расширение с операторами (`citext`, `hstore`, `ltree`, `pg_trgm`, `cube`, `isn`, …) оставляйте в схеме, которая есть в `search_path` соединения (обычно `public`), либо не включайте для него переписывание. На `CREATE EXTENSION` такого расширения выдаётся предупреждение. Использование расширения в схеме сервиса через `ExtensionsInSchema` годится для расширений без операторов (`pgcrypto`, `uuid-ossp`).

## Ограничения

- Грамматика PostgreSQL 17. Синтаксис, которого в ней нет, отвергается; миграции для версий 12–16 разбираются (проверено на регрессионных тестах этих версий).
- Динамический SQL (`EXECUTE`, `format(…)`) и тела на языках, кроме `sql` и `plpgsql`, статически не переписываются: только предупреждение.
- Имена, которые создаёт код тела на другом языке или динамический SQL, `Learn` не видит.
- Без предупреждения не квалифицируются (результат совпадает с прототипом, сервер отвергнет миграцию при применении): имена в строках для функций вне списка (`nextval`, `currval`, `setval`, `pg_get_serial_sequence`, `to_regclass`, `pg_relation_size` и родственные — это единственные, которые библиотека знает; `has_table_privilege('t', …)`, `pg_get_viewdef('v')`, `to_regtype('mood')` — нет); функции, которые называют параметры агрегата (`sfunc = f`); `COLLATE` с созданной миграцией collation и объекты текстового поиска (предупреждение при создании есть); конструкторы созданных диапазонных типов (предупреждение при создании есть); цель присваивания PL/pgSQL (`a[(SELECT …)] := …`), квалифицируется только правая часть.
- Приведение к созданному типу в форме вызова функции (`mood('a')`) не квалифицируется: для парсера это вызов функции `mood`, а функции с таким именем миграции нет. Пишите `'a'::mood` или `CAST('a' AS mood)`.
- Строка `U&'…'` с именем отношения (`nextval(U&'\0073')`) не переписывается: `Rewrite` отказывает с ошибкой «cannot locate string literal». Пишите имя обычной строкой.
- `CREATE SCHEMA имя CREATE TABLE …` (элементы схемы) получает целевую схему в именах элементов, и сервер такое отвергает; предупреждение есть.
- Операторы расширений (`citext` `=`, `pg_trgm` `%`, `hstore` `->`) не переписываются: см. «Расширения».
- Миграции одной схемы: `search_path` и `CURRENT_SCHEMA()` в SQL остаются как есть, о них сказано в предупреждениях.
- Входной текст должен быть валидным UTF-8 без нулевых байтов, как для сервера с базой в UTF-8: миграция в другой кодировке (WIN1251, WIN1252) отвергается, даже если сервер в этой кодировке её принял бы, — перекодируйте её. `$1` вместо строковой константы отвергается, как сервером.
- Предел вложенности: цепочка из порядка миллиона операторов в одном выражении переполняет стек Go, а это не перехватывается; сто тысяч уровней разбираются за секунды, сервер такую глубину отвергает (`max_stack_depth`). Метка `pgschema_placeholder` заменяется везде, в том числе внутри идентификатора, который её содержит.
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

Грамматику меняют правкой `internal/parse/gram/*.y` и `go generate ./internal/parse`; `TestGrammarGenerated` проверяет, что `gram_gen.go` не устарел и конфликтов нет. Фаззинг: `cd oracle && go test -run '^$' -fuzz FuzzParse -fuzztime 10m .` (так же `FuzzLex` и `FuzzRewrite`); детерминированные прогоны с мутациями — `TestParseMutations`, `TestRewriteMutations`. CI (`.github/workflows/pgschema.yml`) гоняет всё на PostgreSQL 12–16.

## Лицензии

Грамматика, лексер и PL/pgSQL-разбор — производные от PostgreSQL ([LICENSE.PostgreSQL](LICENSE.PostgreSQL)); дерево сгенерировано по описанию libpg_query ([LICENSE.libpg_query](LICENSE.libpg_query)); форк goyacc — [LICENSE.Go](LICENSE.Go). Подробности — [ADR 0006](docs/adr/0006-licensing.md).
