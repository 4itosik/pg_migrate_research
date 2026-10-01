#!/usr/bin/env bash
# Downloads the SQL files of the PostgreSQL regression suite for the given
# branches from raw.githubusercontent.com. Test names come from
# parallel_schedule; tests generated from input/*.source have no sql file
# and are skipped.
#
#   ./get-regress.sh /tmp/regress REL_12_STABLE REL_16_STABLE
#
# Result: /tmp/regress/REL_12_STABLE/*.sql, ...
set -euo pipefail
dest=$1
shift
base=https://raw.githubusercontent.com/postgres/postgres
for branch in "$@"; do
	dir=$dest/$branch
	mkdir -p "$dir"
	curl -fsS "$base/$branch/src/test/regress/parallel_schedule" |
		sed -n 's/^test: *//p' | tr ' ' '\n' | sed '/^$/d' | sort -u |
		xargs -P 8 -I{} sh -c 'curl -fsS -o "$1/$2.sql" "$3/$4/src/test/regress/sql/$2.sql" 2>/dev/null || rm -f "$1/$2.sql"' _ "$dir" {} "$base" "$branch"
	echo "$branch: $(find "$dir" -name '*.sql' | wc -l) files"
done
