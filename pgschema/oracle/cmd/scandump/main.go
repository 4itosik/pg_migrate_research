// Command scandump prints the libpg_query scanner tokens of its arguments
// (or of stdin): a tool for studying what the oracle reports.
//
//	go run ./cmd/scandump "SELECT 1 -- c" 'N'"'"'abc'"'"
package main

import (
	"fmt"
	"io"
	"os"

	"github.com/4itosik/pg_migrate_research/pgschema/oracle"
)

func main() {
	inputs := os.Args[1:]
	if len(inputs) == 0 {
		b, _ := io.ReadAll(os.Stdin)
		inputs = []string{string(b)}
	}
	for _, in := range inputs {
		fmt.Printf("%q\n", in)
		res, err := oracle.Scan(in)
		if err != nil {
			fmt.Printf("  error: %v (%#v)\n", err, err)
			continue
		}
		for _, t := range res.Tokens {
			fmt.Printf("  %-14s %3d..%-3d %-22s %q\n", t.Token, t.Start, t.End, t.KeywordKind, in[t.Start:t.End])
		}
	}
}
