# Действия грамматики: соглашения порта C → Go

Статус: порт закончен, в `gram/*.y` не осталось действий `{ /*C … */ }`; деревья совпадают с libpg_query на всех операторах корпуса и регрессионных тестов PostgreSQL 12–16. Документ остаётся справкой по соглашениям: как значения C отображаются на Go и как менять действия при обновлении на следующую версию PostgreSQL. Скрипты `tools/gramskel.py` и `tools/gramapply.py` — история: запуск `gramskel.py` затрёт переведённое.

Грамматика `gram/*.y` — порт `gram.y` PostgreSQL 17 на goyacc. Правила скопированы из `gram.y` без изменений; действия (код в `{ … }`) переведены с C на Go вручную и строят то же дерево с теми же позициями (`location`), что и C-код. Ничего в тексте правил (символы, `|`, `;`, `%prec`) без причины не менять.

Эталон — libpg_query: деревья сравниваются поле за полем, включая позиции.

## Файлы

- `gram/10_rules_NN.y` — правила, по одному файлу на кусок `gram.y`. Номера строк `gram.y` — в первой строке файла. Свой файл правь, чужие не трогай.
- `gram/types.txt` — для каждого символа тип его значения: `qualified_name: node (*RangeVar) [range]`. Смотри сюда, когда нужно понять, что лежит в `$N`.
- `../makefuncs.go`, `../helpers.go`, `../util.go`, `../private.go` — готовые Go-функции: порты `makefuncs.c` и функций из конца `gram.y`. Новые вспомогательные функции кладёшь в свой файл `../helpers_NN.go` (NN — номер куска), не в чужие.
- `../../ast/nodes_gen.go`, `enums_gen.go` — типы узлов и перечислений. Имена полей и констант ищи там.
- C-исходники PostgreSQL 17: `$PGSRC` (`. pgschema/tools/env.sh`): `src/include/nodes/parsenodes.h`, `primnodes.h`, `src/backend/parser/gram.y` и так далее. Недостающие заголовки докачивай с `https://raw.githubusercontent.com/postgres/postgres/REL_17_STABLE/…`.

## Значение символа

`$N`, `$$` — поля структуры `yySymType`; поле выбирает тег из `%type`/`%token`:

| Поле | Go-тип | Что лежит |
|---|---|---|
| `node` | `Node` | любой указатель на узел: `Node *`, `RangeVar *`, `TypeName *`, `DefElem *`, `Alias *`, `RoleSpec *`, `ResTarget *`, `SortBy *`, `IntoClause *`, `WithClause *` и так далее, и закрытые структуры (`*privTarget`, `*selectLimit`, …) |
| `list` | `[]Node` | `List *`. `NIL` — `nil` |
| `str` | `string` | `char *`, `const char *` (ключевые слова — это строка), и `char` как строка из одного символа |
| `ival` | `int32` | `int` и перечисления (`JoinType`, `DropBehavior`, `ObjectType`, …). `$$ = int32(JOIN_INNER)`; читать: `JoinType($2)` |
| `boolean` | `bool` | `bool` |

`NULL` у `char *` — пустая строка `""`. `NULL` у указателя — `nil`.

Чтобы прочитать поле узла, который лежит в `$N` как `Node`, приведи его: `as[*RangeVar]($4).Relname`. `as` не паникует: для `nil` и чужого типа вернёт `nil`-указатель. Поле узла присваивай приведением: `n.Relation = as[*RangeVar]($4)`. Если `$N` — `Node *` и поле тоже `Node`, приведение не нужно: `n.Arg = $3`.

Типизированный `nil` в `Node` — ошибка: `var r *RangeVar; $$ = r` кладёт в `$$` не-`nil` интерфейс с `nil` внутри. Если значение может быть `nil`, оберни: `$$ = nn(r)`. После `n := &X{}` `$$ = n` безопасно.

## Позиции

`@N` — позиция символа `N` (байтовое смещение начала), `@$` — позиция результата. Они работают как в bison: позиция правила — позиция первого символа правой части, для пустого правила — `-1`. Как в C, `@$` можно присваивать: `if @$ < 0 { @$ = @2 }`. Поле `location` в узле заполняй так же, как C: `n.Location = @1`.

Позиция у `String`-узлов — наше расширение (поле `Loc`): `makeString(s, loc)` принимает позицию имени; передавай `@N` символа, из которого взято имя: `makeString($1, @1)`. Где позиции нет, `-1`.

## Соответствие C и Go

| C | Go |
|---|---|
| `makeNode(X)` + присваивания полей | `n := &X{}` и `n.Field = …`, как в C. Нулевые значения те же. Имя поля: C-имя с заглавной первой буквой, подчёркивания убираются: `targetList` → `TargetList`, `is_not_null` → `IsNotNull`, `missing_ok` → `MissingOk`. Сверяй с `nodes_gen.go` |
| `$$ = (Node *) n;` | `$$ = n` |
| `(Node *) $N` для списка в поле `Node` | `listNode($N)` (пустой список — `nil`) |
| `(List *) $N` из значения-узла | `asList($N)` |
| `castNode(X, $N)`, `(X *) $N` | `as[*X]($N)` |
| `IsA(n, X)` | `_, ok := n.(*X)` или `switch n.(type)` |
| `NIL`, `NULL` | `nil` (у `char *` — `""`) |
| `list_make1(a)`, `list_make2(a, b)` | `[]Node{a}`, `[]Node{a, b}`; элемент-список оборачивай `listNode` |
| `lappend(l, x)` | `append(l, x)` |
| `lcons(x, l)` | `append([]Node{x}, l...)` |
| `list_concat(a, b)` | `append(a, b...)` |
| `linitial(l)`, `lsecond(l)`, `llast(l)`, `list_length(l)` | `l[0]`, `l[1]`, `l[len(l)-1]`, `len(l)` |
| `foreach(lc, l)` | `for _, x := range l` |
| `strcmp(a, "b") == 0` | `a == "b"`; `pg_strcasecmp` — `strings.EqualFold` |
| `pstrdup(s)` | `s` |
| `psprintf(...)`, `format` | `fmt.Sprintf`; `fmt` и `strings` в грамматике уже импортированы |
| `makeString(s)` | `makeString(s, loc)` |
| `makeInteger(i)`, `makeFloat(s)`, `makeBoolean(b)` | то же, возвращают `*Integer` и т.д. |
| `makeSimpleA_Expr`, `makeA_Expr`, `makeFuncCall`, `makeTypeName`, `makeRangeVar`, `makeDefElem`, … | те же имена, см. `makefuncs.go`. Аргументы-узлы — `Node`; для `TypeName *`, `RangeVar *` приводи через `as` |
| `SystemFuncName("x")`, `SystemTypeName("x")` | `systemFuncName("x")`, `systemTypeName("x")` |
| `makeColumnRef(c, ind, loc, yyscanner)` | `p.makeColumnRef(c, ind, loc)` |
| `check_func_name(l, yyscanner)`, `check_indirection`, `check_qualified_name` | `p.checkFuncName(l)`, `p.checkIndirection(l)`, `p.checkQualifiedName(l)` |
| `insertSelectOptions(...)`, `makeOrderedSetArgs(...)`, `processCASbits(...)`, `SplitColQualList(...)`, `makeRangeVarFromAnyName(...)`, … | методы `*parser` в `helpers.go`, имена в lowerCamel, `yyscanner` опускается |
| `parser_yyerror("msg")` | `p.yyerror("msg")` (ошибка у последнего токена, «at or near») |
| `ereport(ERROR, …errmsg("text %s", x), parser_errposition(@N))` | `p.fail(@N, fmt.Sprintf("text %s", x))`; без `parser_errposition` позиция `-1`. Подставь все `%s` |
| `elog(ERROR, …)` | `p.fail(-1, "…")` |
| `pg_yyget_extra(yyscanner)->parsetree = x` | уже сделано в `parse_toplevel` |
| `InvalidOid` | `0` |
| `true`, `false` | то же |
| символьные константы `'a'`, `RELPERSISTENCE_TEMP` | поля узлов-«char» в `ast` — строки из одного символа: `"a"`. Для `relpersistence` есть константы `relpersistencePermanent`, `relpersistenceUnlogged`, `relpersistenceTemp` |
| `CAS_*` | константы `casNotDeferrable` … в `private.go` |

`p` — это `*parser`, доступен в каждом действии. Действия — отдельные функции, внутри них можно объявлять переменные и использовать `return`, но не нужно: результат кладётся в `$$`.

Если в C значение поля берётся из значения символа другого типа, чем поле (например `Node *` в поле `RangeVar *`), приводи через `as`. Если для C-макроса или функции нет готового Go-аналога, а он нужен в нескольких местах, напиши его в своём `helpers_NN.go` и назови как в C.

Комментарии C-кода сохраняй как комментарии Go.

## Как проверять

```bash
cd pgschema
go generate ./internal/parse/                      # gram/*.y -> gram_gen.go (7 с)
CGO_ENABLED=0 go build ./internal/parse/           # ошибки в действиях видны здесь
. tools/env.sh                                     # данные: PGSRC, REGRESS_ROOT, …
cd oracle
# деревья против libpg_query на корпусе и регрессионных тестах PostgreSQL 16;
# PARSE_STMT — регулярка на тип узла оператора; расхождения группируются по пути поля
PARSE_STMT='^(CreateStmt|AlterTableStmt)$' CGO_ENABLED=0 go test -count=1 -run TestParseTrees -v .
PARSE_MAX=3 ...                                    # больше примеров на группу
PARSE_VERSIONS="REL_16_STABLE REL_13_STABLE" ...   # другие версии
```

Тип узла оператора — имя узла из `nodes_gen.go`: правило `DropRoleStmt` строит `DropRoleStmt`, `CreateStmt` строит `CreateStmt`; бывают исключения (`ViewStmt`, `SelectStmt` для вложенных `select_no_parens`…). Расхождение «ours nothing», «ours 0 elements» в поле, которое строит правило из чужого куска, — это не твоя ошибка: чужое правило ещё не переведено. Расхождение в самом поле твоего правила — ошибка перевода: сравни с C-кодом.

Проверяй, что ничего не паникует: `go test -run TestParseAcceptance` печатает число паник (должно быть 0) и число операторов, которые библиотека принимает, а libpg_query отвергает: часть из них — ошибки, которые C-действия выдают через `ereport`, и после перевода они должны исчезнуть из этого списка.

## Правила работы

- После любой правки `gram/*.y` запусти `go generate ./internal/parse` и закоммить `gram_gen.go`: `TestGrammarGenerated` сверяет его с грамматикой.
- Пример перевода — правила `CallStmt`, `DropRoleStmt`, `CreateSchemaStmt` в `10_rules_01.y` и `RoleSpec` в `10_rules_12.y`.
