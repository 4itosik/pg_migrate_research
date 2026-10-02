// Command coldstart measures the first call of the libpg_query backend in a
// fresh process: go-pgquery compiles its WebAssembly module with wazero on
// first use, the wasm2go build (-tags wasm2go) compiles nothing at run time.
package main

import (
	"fmt"
	"os"
	"time"

	pgqrewrite "github.com/4itosik/pg_migrate_research/poc/pgquery"
	pgquery "github.com/4itosik/pg_migrate_research/poc/pgquery/internal/pgparse"
)

func main() {
	t0 := time.Now()
	if _, err := pgquery.Parse("SELECT 1"); err != nil {
		panic(err)
	}
	first := time.Since(t0)
	t1 := time.Now()
	for i := 0; i < 100; i++ {
		_, _ = pgquery.Parse("CREATE TABLE users (id bigserial PRIMARY KEY, email text NOT NULL UNIQUE)")
	}
	steady := time.Since(t1) / 100
	r, _ := pgqrewrite.New(pgqrewrite.Options{Schema: "auth"})
	b, _ := os.ReadFile(os.Args[1])
	t2 := time.Now()
	if _, _, err := r.Rewrite(string(b)); err != nil {
		panic(err)
	}
	fmt.Printf("backend %s\nfirst Parse: %v\nsteady Parse: %v\nRewrite of %s (%d bytes): %v\n", pgquery.Backend, first, steady, os.Args[1], len(b), time.Since(t2))
}
