# Source this file: . pgschema/tools/env.sh [pg-major]
# Points the tests, the oracle and the poc harness at the data that
# get-data.sh downloaded. pg-major selects the server (default 16).
_here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
export PGSCHEMA_CACHE=${PGSCHEMA_CACHE:-$HOME/.cache/pgschema}
export PGSRC=$PGSCHEMA_CACHE/pgsrc/REL_17_STABLE
export REGRESS_ROOT=$PGSCHEMA_CACHE/regress
export REGRESS_DIR=$REGRESS_ROOT/REL_${1:-16}_STABLE
export PG_ROOT=$PGSCHEMA_CACHE/pg
export PG_BIN=$PG_ROOT/${1:-16}/bin
if [ -x "$PGSCHEMA_CACHE/pgclient/usr/lib/postgresql/16/bin/pg_dump" ]; then
	export PG_DUMP=$PGSCHEMA_CACHE/pgclient/usr/lib/postgresql/16/bin/pg_dump
	export LD_LIBRARY_PATH=$PGSCHEMA_CACHE/pgclient/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
fi
export CORPUS_DIR=$_here/../../poc/corpus
export RESULTS_DIR=$_here/../results/pg${1:-16}
unset _here
