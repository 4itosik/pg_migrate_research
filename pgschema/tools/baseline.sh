#!/usr/bin/env bash
# Runs the poc harness control on one PostgreSQL major version: TestBaseline
# (the original migrations pass with search_path = auth and write the
# baseline schemas) and TestNoop (they fail without the schema). Reports go
# to pgschema/results/pg<major>; poc/ is not touched.
#
#   ./baseline.sh [major]    default 16, needs get-data.sh
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
major=${1:-16}
. "$here/env.sh" "$major"
mkdir -p "$RESULTS_DIR"
cd "$here/../../poc/harness"
CGO_ENABLED=0 go test -count=1 -run 'TestBaseline|TestNoop' ./...
