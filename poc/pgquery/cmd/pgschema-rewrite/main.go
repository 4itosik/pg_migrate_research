// Command pgschema-rewrite qualifies object names in migration files.
//
//	pgschema-rewrite -schema auth migrations/*.up.sql
//
// Files are processed in the given order; objects created by earlier files
// are known when later files are rewritten. The output goes to stdout,
// warnings to stderr.
package main

import (
	"flag"
	"fmt"
	"os"
	"strings"

	pgqrewrite "github.com/4itosik/pg_migrate_research/poc/pgquery"
)

func main() {
	schema := flag.String("schema", "", "target schema")
	exclude := flag.String("exclude", "", "comma-separated relations that must stay unqualified")
	flag.Parse()
	var ex []string
	if *exclude != "" {
		ex = strings.Split(*exclude, ",")
	}
	r, err := pgqrewrite.New(pgqrewrite.Options{Schema: *schema, ExcludeRelations: ex})
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(2)
	}
	for _, f := range flag.Args() {
		b, err := os.ReadFile(f)
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
		out, warns, err := r.Rewrite(string(b))
		if err != nil {
			fmt.Fprintf(os.Stderr, "%s: %v\n", f, err)
			os.Exit(1)
		}
		for _, w := range warns {
			fmt.Fprintf(os.Stderr, "%s: warning: %s\n", f, w)
		}
		fmt.Printf("-- %s\n%s\n", f, out)
	}
}
