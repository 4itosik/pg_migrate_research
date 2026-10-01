// Command rewrite qualifies object names in migration files with the
// multigres-based rewriter: rewrite -schema auth migrations/*.up.sql
package main

import (
	"flag"
	"fmt"
	"os"

	mgrewrite "github.com/4itosik/pg_migrate_research/poc/multigres"
)

func main() {
	schema := flag.String("schema", "", "target schema")
	flag.Parse()
	r, err := mgrewrite.New(mgrewrite.Options{Schema: *schema})
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
