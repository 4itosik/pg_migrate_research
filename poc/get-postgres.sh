#!/usr/bin/env bash
# Downloads PostgreSQL server binaries for linux-amd64 from Maven Central:
# the zonky embedded-postgres-binaries builds (initdb, pg_ctl, postgres and
# contrib extensions). pg_dump is not included; the harness uses the newest
# installed pg_dump, which reads older servers (or PG_DUMP).
#
#   ./get-postgres.sh /opt/pg 12 13 14 15 16
#
# Result: /opt/pg/<major>/bin/{initdb,pg_ctl,postgres}.
set -euo pipefail
dest=$1
shift
repo=${MAVEN_REPO:-https://repo1.maven.org/maven2}
declare -A release=([12]=12.22.0 [13]=13.23.0 [14]=14.24.0 [15]=15.19.0 [16]=16.15.0 [17]=17.11.0)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
for major in "$@"; do
	v=${release[$major]:?no release pinned for PostgreSQL $major}
	url=$repo/io/zonky/test/postgres/embedded-postgres-binaries-linux-amd64/$v/embedded-postgres-binaries-linux-amd64-$v.jar
	curl -fsS -o "$tmp/pg.jar" "$url"
	want=$(curl -fsS "$url.sha1" | cut -d' ' -f1)
	got=$(sha1sum "$tmp/pg.jar" | cut -d' ' -f1)
	if [ "$want" != "$got" ]; then
		echo "sha1 mismatch for $v: $got, want $want" >&2
		exit 1
	fi
	rm -rf "$tmp/x" "${dest:?}/$major"
	mkdir -p "$tmp/x" "$dest/$major"
	unzip -q "$tmp/pg.jar" -d "$tmp/x"
	tar -xJf "$tmp"/x/*.txz -C "$dest/$major"
	# The harness runs initdb as the postgres user when started as root.
	chmod -R a+rX "$dest/$major"
	echo "$major: $("$dest/$major/bin/postgres" --version)"
done
