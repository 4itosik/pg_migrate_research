#!/usr/bin/env bash
# Runs the corpus on several PostgreSQL versions: baseline, noop and the
# three rewriters. Server binaries come from $PG_ROOT/<major>/bin (see
# get-postgres.sh), reports go to results/pg<major>.
#
#   PG_ROOT=/opt/pg ./run-versions.sh 12 13 14 15 16
set -uo pipefail
cd "$(dirname "$0")"
root=$PWD
status=0
dirs=()
for major in "$@"; do
	export PG_BIN=${PG_ROOT:-/opt/pg}/$major/bin RESULTS_DIR=$root/results/pg$major SAVE_SQL=0 CGO_ENABLED=0
	mkdir -p "$RESULTS_DIR"
	dirs+=("../results/pg$major")
	echo "== PostgreSQL $major"
	(cd harness && go test -count=1 -run 'TestBaseline|TestNoop' .) || status=1
	for m in pgquery multigres antlr; do
		(cd "$m" && go test -count=1 -run TestCorpus .) || status=1
	done
done
(cd harness && go run ./cmd/matrix -versions "${dirs[@]}")
exit $status
