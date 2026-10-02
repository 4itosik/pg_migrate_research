# 0006. Лицензии и атрибуция

Статус: принято, этап 0.

## Контекст

Грамматика и сканер PostgreSQL распространяются под лицензией PostgreSQL. Промпт требует сохранять атрибуцию в портированных файлах и запрещает «код, переведённый из C», а чужие Go-порты (pgplex/pgparser, multigres) разрешает читать как справку, но не копировать.

## Решение

Как понимается запрет: в библиотеке нет машинного перевода C (wasm2go, c2go, транспиляторы действий `gram.y`) и нет WebAssembly. Порт `scan.l`, `gram.y` и `pl_gram.y` пишется на Go вручную: исходники PostgreSQL читаются как спецификация, чужие Go-порты не копируются.

Какие файлы несут какие уведомления:

| Файлы | Происхождение | Уведомление |
|---|---|---|
| `internal/lex` (сканер), `internal/parse/gram.y` и действия, `internal/plpgsql` | порт файлов PostgreSQL | заголовок «Portions Copyright … PostgreSQL Global Development Group, … Regents of the University of California», ссылка на `LICENSE.PostgreSQL` |
| `internal/lex/tokens_gen.go`, `keywords_gen.go` | номера токенов libpg_query, `kwlist.h` | то же |
| `internal/ast/nodes_gen.go` | структуры повторяют `parsenodes.h` и `primnodes.h`, сгенерированы по описанию сообщений libpg_query (BSD-3-Clause, pganalyze) | то же и пометка о libpg_query |
| `internal/tools/goyacc` | копия `golang.org/x/tools/cmd/goyacc` с доработками | лицензия BSD-3 авторов Go, текст в `LICENSE.Go` рядом с кодом |
| `oracle` | использует libpg_query через go-pgquery (MIT, libpg_query — BSD-3-Clause) | библиотека от неё не зависит |

Тексты лицензий лежат в корне модуля: `LICENSE.PostgreSQL` — сейчас, `LICENSE.Go` — когда появится копия goyacc (этап 2).

## Последствия

- Каждый новый портированный файл начинается с заголовка по образцу `internal/lex/token.go`.
- Генераторы пишут заголовок в выходные файлы сами.
