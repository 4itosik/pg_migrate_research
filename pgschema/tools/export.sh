#!/usr/bin/env bash
# Copies the library, the shipping part of pgschema/, into an empty directory
# outside this repository and checks that the copy stands on its own:
#
#   - the main module: go vet and go test offline (GOPROXY=off), no cgo,
#     standard library only;
#   - migratesrc: go vet and go test with golang-migrate from the module
#     proxy and the copied library through its replace ../;
#   - no relative link in the copy leads out of it or to a missing file, and
#     no Go file names poc/.
#
#   tools/export.sh DEST
#
# The tracked files (git ls-files) are copied as they are in the working tree,
# except what belongs to the research only: oracle/ (the reference checks
# against libpg_query, the prototype and live PostgreSQL), results/,
# PROGRESS.md, NOTES.md and the tools that download data, use poc/ or are kept
# for the history of the port (baseline.sh, env.sh, get-data.sh,
# get-pgsrc.sh, probe-*.sh, gramskel.py, gramapply.py, gramdecls.py,
# strip_actions.py). tools/gengram.sh and internal/tools/goyacc stay: go
# generate ./internal/parse and TestGrammarGenerated need them.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
lib=$(cd "$here/.." && pwd -P)
repo=$(git -C "$lib" rev-parse --show-toplevel)
dest=${1:?usage: tools/export.sh DEST}

fail() {
	echo "export.sh: $*" >&2
	exit 1
}

if [ -e "$dest" ] && [ -n "$(ls -A "$dest")" ]; then
	fail "$dest is not empty"
fi
created=0
[ -e "$dest" ] || created=1
mkdir -p "$dest"
dest=$(cd "$dest" && pwd -P)
case "$dest/" in
"$repo"/*)
	[ "$created" = 0 ] || rmdir "$dest"
	fail "$dest is inside the repository $repo; the copy must be checked outside it"
	;;
esac
if [ -n "$(git -C "$lib" status --porcelain -- .)" ]; then
	echo "export.sh: warning: pgschema/ has uncommitted changes, they are copied as they are" >&2
fi

research='^(oracle/|results/|PROGRESS\.md$|NOTES\.md$|tools/(baseline\.sh|env\.sh|get-data\.sh|get-pgsrc\.sh|probe-[^/]*\.sh|gramskel\.py|gramapply\.py|gramdecls\.py|strip_actions\.py)$)'
n=0
while IFS= read -r -d '' f; do
	if [[ $f =~ $research ]]; then
		continue
	fi
	mkdir -p "$dest/$(dirname "$f")"
	cp -p "$lib/$f" "$dest/$f"
	n=$((n + 1))
done < <(git -C "$lib" ls-files -z)
echo "copied $n files to $dest"

# Links. In Markdown, a relative link (outside code spans) must name a file of
# the copy; in Go, a reference to a file outside the package ("see
# ../../LICENSE.PostgreSQL", "../x.md") must too.
broken=0
check_target() { # file target
	local dir target
	dir=$(dirname "$1")
	target=${2%%#*}
	[ -n "$target" ] || return 0
	if [ ! -e "$dir/$target" ]; then
		echo "$1: link to $2: no such file in the copy" >&2
		broken=1
		return 0
	fi
	local abs
	abs=$(cd "$(dirname "$dir/$target")" && pwd -P)
	case "$abs/" in
	"$dest"/*) ;;
	*)
		echo "$1: link to $2 leads out of the copy" >&2
		broken=1
		;;
	esac
}
cd "$dest"
while IFS= read -r -d '' f; do
	while IFS= read -r target; do
		case $target in
		http://* | https://* | mailto:* | '#'*) continue ;;
		esac
		check_target "$f" "$target"
	done < <(sed 's/`[^`]*`//g' "$f" | grep -o '\]([^) ]*)' | sed 's/^](//; s/)$//')
done < <(find . -name '*.md' -print0)
while IFS= read -r -d '' f; do
	while IFS= read -r target; do
		check_target "$f" "$target"
	done < <(grep -oE 'see (\.\./)+[^ )]+|(\.\./)+[^ )`]+\.md' "$f" | sed 's/^see //; s/[.,;:]$//')
done < <(find . -name '*.go' -print0)
if grep -rn --include='*.go' 'poc/' .; then
	echo "export.sh: Go files of the copy name poc/" >&2
	broken=1
fi
[ "$broken" = 0 ] || fail "broken links in the copy"
echo "links: ok"

# The main module: offline, standard library only.
(
	cd "$dest"
	export CGO_ENABLED=0 GOFLAGS=-mod=mod GOPROXY=off GOWORK=off
	go vet ./...
	go test -count=1 ./...
) || fail "the main module of the copy does not pass go vet and go test offline"

# migratesrc: golang-migrate from the proxy, the library of the copy.
(
	cd "$dest/migratesrc"
	export GOWORK=off
	[ "$(go list -m -f '{{.Replace.Dir}}' github.com/4itosik/pg_migrate_research/pgschema)" = "$dest" ] ||
		fail "migratesrc does not use the library of the copy"
	go vet ./...
	go test -count=1 ./...
) || fail "migratesrc of the copy does not pass go vet and go test"

echo "export.sh: $dest is ready"
