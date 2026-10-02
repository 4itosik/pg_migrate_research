#!/usr/bin/env bash
# Downloads the PostgreSQL sources the parser is ported from (reference only,
# nothing here is compiled) from raw.githubusercontent.com.
#
#   ./get-pgsrc.sh [dir [branch]]    default: ~/.cache/pgschema/pgsrc REL_17_STABLE
set -euo pipefail
dest=${1:-$HOME/.cache/pgschema/pgsrc}
branch=${2:-REL_17_STABLE}
base=https://raw.githubusercontent.com/postgres/postgres/$branch
mkdir -p "$dest/$branch"
for f in \
	src/backend/parser/gram.y src/backend/parser/scan.l src/backend/parser/parser.c \
	src/include/parser/kwlist.h src/backend/parser/gramparse.h src/include/parser/scanner.h \
	src/include/nodes/parsenodes.h src/include/nodes/primnodes.h src/include/nodes/value.h \
	src/include/nodes/pg_list.h src/include/nodes/nodes.h \
	src/pl/plpgsql/src/pl_gram.y src/pl/plpgsql/src/pl_scanner.c src/pl/plpgsql/src/pl_comp.c \
	src/pl/plpgsql/src/plpgsql.h \
	src/backend/nodes/makefuncs.c src/include/nodes/makefuncs.h src/include/parser/parser.h; do
	mkdir -p "$dest/$branch/$(dirname "$f")"
	curl -fsS -o "$dest/$branch/$f" "$base/$f"
done
wc -l "$dest/$branch/src/backend/parser/gram.y" "$dest/$branch/src/backend/parser/scan.l" "$dest/$branch/src/pl/plpgsql/src/pl_gram.y"
