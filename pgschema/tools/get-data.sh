#!/usr/bin/env bash
# Downloads what the tests and the oracle need into $PGSCHEMA_CACHE
# (default ~/.cache/pgschema). Every step is skipped when its result exists.
#
#   ./get-data.sh [pgsrc] [regress] [servers] [pgdump]    default: all four
#
#   pgsrc    PostgreSQL 17 sources the parser is ported from (reference only)
#   regress  regression tests of PostgreSQL 12-16 (src/test/regress/sql)
#   servers  PostgreSQL 12-16 server binaries (Maven Central, zonky);
#            PG_MAJORS="16" limits the versions
#   pgdump   pg_dump 16 from the Ubuntu package, unpacked without root
#
# Then: source env.sh
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
poc=$here/../../poc
cache=${PGSCHEMA_CACHE:-$HOME/.cache/pgschema}
steps=("$@")
[ ${#steps[@]} -gt 0 ] || steps=(pgsrc regress servers pgdump)
mkdir -p "$cache"

# get-postgres.sh needs unzip; some environments only have python3.
shim=$(mktemp -d)
trap 'rm -rf "$shim"' EXIT
if ! command -v unzip >/dev/null; then
	cat >"$shim/unzip" <<'PY'
#!/usr/bin/env python3
import sys, zipfile
a = [x for x in sys.argv[1:] if x != "-q"]
zipfile.ZipFile(a[0]).extractall(a[a.index("-d") + 1])
PY
	chmod +x "$shim/unzip"
	export PATH=$shim:$PATH
fi

for step in "${steps[@]}"; do
	case $step in
	pgsrc)
		# the last file get-pgsrc.sh fetches: a partial download is retried
		[ -s "$cache/pgsrc/REL_17_STABLE/src/pl/plpgsql/src/plpgsql.h" ] || "$here/get-pgsrc.sh" "$cache/pgsrc" REL_17_STABLE
		;;
	regress)
		for b in REL_12_STABLE REL_13_STABLE REL_14_STABLE REL_15_STABLE REL_16_STABLE; do
			ls "$cache/regress/$b"/*.sql >/dev/null 2>&1 || "$poc/get-regress.sh" "$cache/regress" "$b"
		done
		;;
	servers)
		for v in ${PG_MAJORS:-12 13 14 15 16}; do
			[ -x "$cache/pg/$v/bin/postgres" ] || "$poc/get-postgres.sh" "$cache/pg" "$v"
		done
		;;
	pgdump)
		# a pg_dump of version 16 or newer on the machine (GitHub runners have
		# one) is found by the harness itself and needs no download
		have=0
		for p in "$(command -v pg_dump || true)" /usr/lib/postgresql/*/bin/pg_dump; do
			[ -x "$p" ] || continue
			v=$("$p" --version | sed -n 's/^pg_dump (PostgreSQL) \([0-9][0-9]*\).*/\1/p')
			[ "${v:-0}" -ge 16 ] && have=1
		done
		if [ $have = 0 ] && [ ! -x "$cache/pgclient/usr/lib/postgresql/16/bin/pg_dump" ]; then
			mkdir -p "$cache/debs" "$cache/pgclient"
			(cd "$cache/debs" && apt-get download postgresql-client-16 libpq5)
			for d in "$cache"/debs/*.deb; do dpkg -x "$d" "$cache/pgclient"; done
		fi
		;;
	*)
		echo "unknown step: $step" >&2
		exit 2
		;;
	esac
done
