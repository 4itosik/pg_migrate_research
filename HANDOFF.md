# Handoff

Состояние на 1 октября 2026. Ветка `claude/sql-parser-schema-golang-55m2uj`.

- Постановка задачи: [TASK.md](TASK.md).
- Полный отчёт: [README.md](README.md).
- Запуск PoC и стенда: [poc/README.md](poc/README.md).

## Итог на сейчас

Рекомендация: [`github.com/wasilibs/go-pgquery`](https://github.com/wasilibs/go-pgquery). Это libpg_query (парсер PostgreSQL 17) в WebAssembly, рантайм wazero на чистом Go.

Запасной вариант без WASM — ANTLR-грамматика [bytebase/parser](https://github.com/bytebase/parser). [multigres](https://github.com/multigres/multigres) пока не годится: его генератор SQL меняет смысл миграций.

## Что сделано

1. Обзор 11 Go-библиотек разбора PostgreSQL: README, раздел 3.
2. Корпус: 21 сценарий миграций в формате golang-migrate с проверками, [`poc/corpus`](poc/corpus).
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
5. Замеры на 32 029 операторах регрессионных тестов PostgreSQL:
   - покрытие грамматики, точность deparse и скорость пяти парсеров, [`poc/coverage`](poc/coverage);
   - стресс-тест go-pgquery, `TestRegress`;
   - сверка трёх реализаций, [`poc/crosscheck`](poc/crosscheck).
6. Отчёт `README.md` с рекомендацией, плюсами и минусами.

## Результаты на PostgreSQL 16

| | go-pgquery | multigres | bytebase ANTLR |
|---|---|---|---|
| Корпус, 21 сценарий | 20/21 | 19/21 | 20/21 |
| Регрессионные тесты, 32 029 операторов | 16 отказов (0,05%), неверного SQL нет | то же дерево, что у go-pgquery: 90,46% | байт в байт с go-pgquery: 99,74% |
| Первый вызов | ~1,45 с | ~0 | 7–16 мс |
| Размер CLI | 15 МБ | 12 МБ | 23 МБ |

Сценарий 12 (динамический SQL в `EXECUTE`) не проходит ни у кого. Это ожидаемое ограничение.

## В работе

Проверка на PostgreSQL 12, 13, 14, 15 (на 16 сделана). Бинарники PostgreSQL берутся из Maven Central (zonky embedded-postgres-binaries): `apt.postgresql.org` и `ftp.postgresql.org` закрыты прокси окружения.

## Открытые вопросы

- Draft PR не создан. Репозиторий был пуст, и ветка `claude/sql-parser-schema-golang-55m2uj` стала веткой по умолчанию, базовой ветки для PR нет. Варианты:
  1. пустая `main` и перенос ветки поверх неё (force push);
  2. `main` из первого коммита;
  3. без PR.

  Ждёт решения пользователя.

## Известные проблемы

- go-pgquery: libpg_query разбирает PL/pgSQL без каталога. Переписывание отказывает на параметрах `refcursor`, `$0` в полиморфных функциях и элементе массива как цели `GET DIAGNOSTICS`.
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
- Вне скоупа, проверить до внедрения:
  - golang-migrate берёт `pg_advisory_lock`. Это блокировка уровня сессии, за pgbouncer в transaction mode она ненадёжна.
  - Схему для `schema_migrations` golang-migrate берёт из `CURRENT_SCHEMA()`.

## Ключевые решения

- Только pure Go, поэтому go-pgquery (WASM), а не `pg_query_go` (cgo). API у них одинаковый.
- Текст правится точечными вставками по позициям, а не генерацией SQL заново. Так сохраняются комментарии и форматирование, а ошибки deparse не влияют на результат.
- Результат go-pgquery проверяется повторным разбором и сравнением дерева. Если сравнение не сошлось, возвращается ошибка.
- Типы и функции квалифицируются, только если их создали миграции. Реестр заполняет `Learn(sql)` по всем up-файлам.

## Как продолжить

```bash
cd poc/harness   && go test ./...                 # эталон и контроль корпуса
cd poc/pgquery   && CGO_ENABLED=0 go test ./...   # go-pgquery на корпусе
cd poc/multigres && CGO_ENABLED=0 go test ./...
cd poc/antlr     && CGO_ENABLED=0 go test ./...

# другая версия PostgreSQL: свой каталог бинарников и свой каталог результатов
PG_BIN=/path/to/pg/bin RESULTS_DIR=../results/pg12 go test ./...
```

## Следующие шаги

1. Завершить проверку на PostgreSQL 12–15 и вписать результаты в отчёт.
2. Прогнать `pgschema-rewrite` на реальных миграциях, разобрать отказы и предупреждения.
3. Добавить реальные миграции в корпус и гонять стенд в CI.
4. Встраивание в golang-migrate (вне скоупа): обёртка над `source.Driver`, которая переписывает `ReadUp` и `ReadDown`.
