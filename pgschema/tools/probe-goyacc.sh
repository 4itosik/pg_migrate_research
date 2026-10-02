#!/usr/bin/env bash
# Reproduces the goyacc measurements of ADR 0001: the PostgreSQL 17 grammar
# without actions through goyacc (rules, states, conflicts, generation time)
# and the compile time and memory of the generated tables.
#
#   ./probe-goyacc.sh [workdir]        needs get-data.sh pgsrc and python3
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
. "$here/env.sh"
work=${1:-$(mktemp -d)}
mkdir -p "$work/gp"
GOBIN=$work/bin GOFLAGS=-mod=mod go install golang.org/x/tools/cmd/goyacc@v0.50.0
python3 "$here/strip_actions.py" "$PGSRC/src/backend/parser/gram.y" >"$work/gram_noact.y"
cd "$work"
start=$(date +%s.%N)
bin/goyacc -o gp/gram.go -v gram.output gram_noact.y
echo "goyacc: $(echo "$(date +%s.%N) - $start" | bc) s"
grep -E "terminals|grammar rules|conflicts|table entries" gram.output
cat >gp/lex.go <<'GO'
package gp

type yyLex struct{}

func (yyLex) Lex(lval *yySymType) int { return 0 }
func (yyLex) Error(s string)           {}
GO
printf 'module gp\n\ngo 1.25.1\n' >go.mod
(cd "$here/../../poc/pgquery" && go build -o "$work/maxrss" ./wasm2go/maxrss)
CGO_ENABLED=0 MAXRSS_LOG=$work/maxrss.log go build -a -toolexec="$work/maxrss" ./gp
grep ' gp ' "$work/maxrss.log" || grep 'gp maxrss' "$work/maxrss.log"
