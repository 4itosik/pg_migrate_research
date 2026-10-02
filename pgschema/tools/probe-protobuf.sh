#!/usr/bin/env bash
# Reproduces the pg_query_go measurements of ADR 0002: compile time and
# memory of the generated protobuf types without cgo, the binary size, and
# the start-up cost of the protobuf registry.
#
#   ./probe-protobuf.sh [workdir]
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
work=${1:-$(mktemp -d)}
mkdir -p "$work"
cd "$work"
cat >go.mod <<'MOD'
module pbprobe

go 1.25.1

require (
	github.com/pganalyze/pg_query_go/v6 v6.2.2
	google.golang.org/protobuf v1.36.12
)
MOD
cat >main.go <<'GO'
package main

import (
	"fmt"

	pg "github.com/pganalyze/pg_query_go/v6"
)

func main() { fmt.Println(pg.MakeSimpleRangeVarNode("t", 0) != nil) }
GO
cp "$here/../../poc/pgquery/go.sum" .
GOFLAGS=-mod=mod go mod tidy
(cd "$here/../../poc/pgquery" && go build -o "$work/maxrss" ./wasm2go/maxrss)
CGO_ENABLED=0 MAXRSS_LOG=$work/maxrss.log go build -a -toolexec="$work/maxrss" -o pbprobe .
grep 'pg_query_go' "$work/maxrss.log"
ls -l pbprobe | awk '{print "binary:", $5, "bytes"}'
for i in 1 2 3; do GODEBUG=inittrace=1 ./pbprobe 2>&1 | grep 'init github.com/pganalyze/pg_query_go'; done
