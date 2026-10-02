# Handoff

Состояние на 2 октября 2026. Ветка `claude/sql-parser-schema-golang-55m2uj`.

- Постановка задачи: [TASK.md](TASK.md).
- Полный отчёт: [README.md](README.md).
- Запуск PoC и стенда: [poc/README.md](poc/README.md).
- Датасет — где лежат корпус, регрессионные тесты и эталоны: [DATASET.md](DATASET.md).
- Промпт для Claude Sonnet 5.5: библиотека с нуля на собственном парсере, libpg_query только эталон в тестах: [prompts/own-parser-library.md](prompts/own-parser-library.md). Агент запускается в корне репозитория и работает в каталоге [`pgschema/`](pgschema/README.md), модуль `github.com/4itosik/pg_migrate_research/pgschema`.

## Итог на сейчас

Рекомендация: [`github.com/wasilibs/go-pgquery`](https://github.com/wasilibs/go-pgquery). Это libpg_query (парсер PostgreSQL 17) в WebAssembly, рантайм wazero на чистом Go.

Запасной вариант без WASM — ANTLR-грамматика [bytebase/parser](https://github.com/bytebase/parser). [multigres](https://github.com/multigres/multigres) пока не годится: его генератор SQL меняет смысл миграций.

Холодный старт go-pgquery (~1,5 с) убирается без смены парсера: сборка с тегом `wasm2go` переводит тот же libpg_query в обычный Go ([README §10](README.md#10-без-wasm-рантайма-wasm2go)). Ответы побайтно те же, старт ~1 мс. Цена — тяжёлая компиляция одного пакета: ~1,2 ГБ памяти, с флагами 0,7–0,8 ГБ.

Для десятков сервисов предложено переписывать миграции при сборке с меткой вместо схемы, а в сервисе только подставлять схему ([README §11](README.md#11-десятки-сервисов-переписывание-при-сборке)). Результат побайтно совпадает с прямым переписыванием.

## Что сделано

1. Обзор 11 Go-библиотек разбора PostgreSQL: README, раздел 3.
2. Корпус: 23 сценария миграций в формате golang-migrate с проверками, [`poc/corpus`](poc/corpus).
3. Стенд на живом PostgreSQL, [`poc/harness`](poc/harness):
   - накат без целевой схемы в `search_path`, как за pgbouncer;
   - сравнение `pg_dump` с эталоном;
   - проверки данных, функций и триггеров;
   - поиск объектов, созданных вне целевой схемы;
   - откат down-миграций.
4. Три реализации одного переписывания:
   - [`poc/pgquery`](poc/pgquery) — go-pgquery: вставка `schema.` по позициям в тексте и проверка результата по дереву. CLI `cmd/pgschema-rewrite`.
   - [`poc/multigres`](poc/multigres) — изменение AST и генерация SQL заново.
   - [`poc/antlr`](poc/antlr) — bytebase ANTLR, правка токенов.
5. Замеры на регрессионных тестах PostgreSQL 12–16, 32–43 тыс. операторов на версию:
   - покрытие грамматики, точность deparse и скорость пяти парсеров, [`poc/coverage`](poc/coverage);
   - стресс-тест go-pgquery, `TestRegress`;
   - сверка трёх реализаций, [`poc/crosscheck`](poc/crosscheck).
6. Отчёт `README.md` с рекомендацией, плюсами и минусами.
7. Проверка корпуса на PostgreSQL 12, 13, 14, 15, 16: [`poc/run-versions.sh`](poc/run-versions.sh), отчёты в `poc/results/pg12` … `pg16`.
8. Сборка libpg_query без WASM-рантайма, README §10:
   - [`poc/pgquery/wasm2go/build.sh`](poc/pgquery/wasm2go/build.sh) генерирует [`poc/pgquery/internal/libpgquery`](poc/pgquery/internal/libpgquery) через wasm2go;
   - [`split_gram.py`](poc/pgquery/wasm2go/split_gram.py) разрезает действия грамматики, чтобы компилятору Go хватало ~1,2 ГБ вместо 2,8 ГБ;
   - бэкенд выбирает `internal/pgparse`: по умолчанию go-pgquery, с `-tags wasm2go` — сгенерированный пакет;
   - `TestWasm2goSameBytes` — побайтная сверка с go-pgquery;
   - замеры памяти компиляции ([`wasm2go/maxrss`](poc/pgquery/wasm2go/maxrss/main.go)) и сборка под жёстким лимитом памяти.
9. Переписывание при сборке с меткой вместо схемы, README §11: [`TestPlaceholder`](poc/pgquery/placeholder_test.go).
10. Описание датасета: [DATASET.md](DATASET.md).
11. Промпт для разработки библиотеки с нуля на собственном парсере: [prompts/own-parser-library.md](prompts/own-parser-library.md). Этапы с порогами приёмки, бюджеты сборки и скорости, эталоны — libpg_query и этот PoC.
12. Каталог [`pgschema/`](pgschema/README.md) для этой библиотеки: свой `go.mod`, `README.md`, `PROGRESS.md` с этапами. Сверка с libpg_query и прототипом по промпту живёт в отдельном модуле `pgschema/oracle/`, чтобы модуль библиотеки не зависел от WASM.
13. Библиотека `pgschema` выпущена как v0.1.0 (теги `pgschema/v0.1.0`, `pgschema/migratesrc/v0.1.0`) для переноса в закрытый контур: ревью, исправления (встроенные имена, вложенные касты, временные таблицы, типизированные ошибки и предупреждения, защита метки, безопасная запись в CLI, `migratesrc.New`) и `pgschema/tools/export.sh` — копия только библиотеки с проверкой без сети. Подробности — [`pgschema/PROGRESS.md`](pgschema/PROGRESS.md), разделы «Финализация v0.1.0», и [`pgschema/README.md`](pgschema/README.md), раздел «Перенос и встраивание».

## Результаты

| | go-pgquery | multigres | bytebase ANTLR |
|---|---|---|---|
| Корпус на PostgreSQL 16, 23 сценария | 22/23 | 21/23 | 21/23 |
| Корпус на PostgreSQL 12–15 | те же падения, что на 16 | те же | те же |
| Регрессионные тесты PostgreSQL 16, 42 798 операторов | 11 отказов (0,026%), неверного SQL нет | то же дерево, что у go-pgquery: 90,66% | байт в байт с go-pgquery: 98,70%, 444 отказа грамматики |
| Регрессионные тесты PostgreSQL 12–15 | 10–11 отказов на версию | то же дерево: 90,4–90,9% | байт в байт: 98,9–99,5%, 100–361 отказ |
| Первый вызов | ~1,45 с | ~0 | 15–150 мс |
| Размер CLI | 15 МБ | 12 МБ | 23 МБ |

Сборка go-pgquery через wasm2go (`-tags wasm2go`), PostgreSQL 16:
- побайтная сверка с go-pgquery: 81 файл корпуса и 43 323 оператора, расхождений 0;
- корпус 22/23, `TestRegress` — те же 11 отказов;
- первый вызов ~1 мс вместо ~1,45 с, CLI на всём корпусе 0,07 с и 17–25 МБ против 1,5 с и 283 МБ;
- компиляция пакета: 1,16–1,27 ГБ и 9–10 с по умолчанию. С `-gcflags=<пакет>=-c=1` и `GOGC=50` — 0,82 ГБ. Чистая сборка CLI проходит при лимите 1,5 ГБ без флагов, 1 ГБ и 768 МБ с флагами. go-pgquery собирается при 512 МБ.

`TestPlaceholder`: метка и подстановка дают тот же текст, что прямое переписывание, на 42 841 тексте для схем `auth`, `Auth`, `user`, `my schema`.

Сценарий 12 (динамический SQL в `EXECUTE`) не проходит ни у кого. Это ожидаемое ограничение. multigres падает на сценарии 19: deparse меняет `INITIALLY DEFERRED`. ANTLR падает на сценарии 22: грамматика не знает тело функции `RETURN выражение`. На PostgreSQL 12 и 13 сценарии с более новым синтаксисом пропускаются.

Регрессионные тесты взяты из исходников PostgreSQL каждой версии ([`poc/get-regress.sh`](poc/get-regress.sh)). Первая копия из bytebase/parser оказалась неполной (старые версии файлов, нет тел функций `RETURN` и `BEGIN ATOMIC`) и завышала покрытие ANTLR: 99,97% против 98,93% на тестах PostgreSQL 16. Её отчёты оставлены как `poc/results/*-bytebase.json`.

Бинарники PostgreSQL берутся из Maven Central (zonky embedded-postgres-binaries): `apt.postgresql.org`, `ftp.postgresql.org`, codeload и API GitHub закрыты прокси окружения.

## В работе

Ничего.

## Решения пользователя

- PR не нужен: работа пушится прямо в ветку `claude/sql-parser-schema-golang-55m2uj`. Она же ветка по умолчанию в репозитории.
- В закрытый контур переносится только библиотека (без `oracle/` и данных), путь модуля остаётся `github.com/4itosik/pg_migrate_research/pgschema`; библиотеку импортируют в форк golang-migrate.

## Известные проблемы

- go-pgquery: libpg_query разбирает PL/pgSQL без каталога. Переписывание отказывает на параметрах `refcursor`, `$0` в полиморфных функциях и элементе массива как цели `GET DIAGNOSTICS`.
- ANTLR: грамматика отстаёт от PostgreSQL 14–16 (`MERGE`, `CREATE OR REPLACE TRIGGER`, тело функции `RETURN`, `COMPRESSION` и другое), на регрессионных тестах PostgreSQL 16 не разбирает 1,07% операторов. Переписывание на них отказывает.
- ANTLR-PoC, не исправлено:
  - самоссылка в `CREATE RECURSIVE VIEW` получает схему;
  - встроенные функции в классах операторов и `CREATE TRANSFORM` получают схему;
  - грамматика разбирает `FROM unnest((SELECT …))` как таблицу `unnest`;
  - грамматика не принимает `PERFORM FROM …`.
- multigres:
  - deparse теряет комментарии;
  - меняет `INITIALLY DEFERRED` на `IMMEDIATE`;
  - теряет `NO INHERIT` и `RECURSIVE`;
  - для `COMMENT ON RULE` даёт SQL, который не разбирается.
- Общее для всех: динамический SQL, поиск в каталогах по имени, `current_schema()`, `CREATE EXTENSION` без `SCHEMA` — только предупреждения.
- wasm2go-сборка:
  - пакет `internal/libpgquery` тяжело компилировать: ~1,2 ГБ памяти и ~10 с при каждом промахе кэша Go;
  - `-cover` раздувает его до 1,73 ГБ, пакет надо исключать из покрытия;
  - сборочный конвейер (wasi-sdk, binaryen, wasm2go, патчи) — свой, пока go-pgquery не перейдёт на wasm2go сам.
- Подстановка схемы по метке не поддерживает имена схем с `'` и `$`.
- Вне скоупа, проверить до внедрения:
  - golang-migrate берёт `pg_advisory_lock`. Это блокировка уровня сессии, за pgbouncer в transaction mode она ненадёжна.
  - Схему для `schema_migrations` golang-migrate берёт из `CURRENT_SCHEMA()`.

## Ключевые решения

- Только pure Go, поэтому go-pgquery (WASM), а не `pg_query_go` (cgo). API у них одинаковый.
- Текст правится точечными вставками по позициям, а не генерацией SQL заново. Так сохраняются комментарии и форматирование, а ошибки deparse не влияют на результат.
- Результат go-pgquery проверяется повторным разбором и сравнением дерева. Если сравнение не сошлось, возвращается ошибка.
- Типы и функции квалифицируются, только если их создали миграции. Реестр заполняет `Learn(sql)` по всем up-файлам.
- wasm2go-бэкенд включается тегом сборки, по умолчанию остаётся go-pgquery. Сгенерированный код лежит в репозитории, сгенерированные файлы помечены тем же тегом. Обычная сборка и `./...` его не компилируют.
- Генерация детерминирована: `build.sh` даёт те же байты. Действия грамматики режутся скриптом, который сам проверяет, что действия не используют `goto`, `return`, `YYABORT` и `YYERROR`.

## Как продолжить

```bash
cd poc/harness   && go test ./...                 # эталон и контроль корпуса
cd poc/pgquery   && CGO_ENABLED=0 go test ./...   # go-pgquery на корпусе
cd poc/multigres && CGO_ENABLED=0 go test ./...
cd poc/antlr     && CGO_ENABLED=0 go test ./...

# то же на сборке через wasm2go: без WASM-рантайма
cd poc/pgquery   && CGO_ENABLED=0 go test -tags wasm2go ./...
REGRESS_DIR=/tmp/regress/REL_16_STABLE go test -tags wasm2go -run 'TestWasm2goSameBytes|TestPlaceholder|TestRegress' -v .

# перегенерировать internal/libpgquery (скачает wasi-sdk и binaryen)
cd poc/pgquery/wasm2go && ./build.sh

# PostgreSQL 12–16: скачать серверы и прогнать всё на каждой версии
cd poc && ./get-postgres.sh /opt/pg 12 13 14 15 16
PG_ROOT=/opt/pg ./run-versions.sh 12 13 14 15 16
```

## Следующие шаги

1. Прогнать `pgschema-rewrite` на реальных миграциях, разобрать отказы и предупреждения.
2. Добавить реальные миграции в корпус и гонять стенд в CI на нужных версиях PostgreSQL (`poc/run-versions.sh`).
3. Встраивание в golang-migrate (вне скоупа): обёртка над `source.Driver`, которая переписывает `ReadUp` и `ReadDown`.
4. Решить, как подключать десятки сервисов (README §11):
   - переписывание при сборке с меткой — нужны режим метки в `pgschema-rewrite` и подстановщик для обёртки `source.Driver`;
   - или общий образ мигратора.
5. Предложить авторам go-pgquery сборку через wasm2go: go-re2 из той же организации уже собирается через wasm2go.
