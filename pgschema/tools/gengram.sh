#!/usr/bin/env bash
# Assembles internal/parse/gram/*.y into gram.y and generates gram_gen.go
# with the goyacc of internal/tools/goyacc. Run through go generate.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
cd "$here/../internal/parse"
cat gram/*.y >gram.y
# -v "" writes no state listing; -recv gives the actions the *parser
go run ../tools/goyacc -o gram_gen.go -v "" -recv "p *parser" gram.y
gofmt -w gram_gen.go
rm -f gram.y
