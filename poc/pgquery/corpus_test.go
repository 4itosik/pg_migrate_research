package pgqrewrite_test

import (
	"testing"

	"github.com/4itosik/pg_migrate_research/poc/harness"
	pgqrewrite "github.com/4itosik/pg_migrate_research/poc/pgquery"
)

type adapter struct{ r *pgqrewrite.Rewriter }

func (a adapter) Learn(sql string) error { return a.r.Learn(sql) }

func (a adapter) Rewrite(sql string) (harness.Result, error) {
	out, warns, err := a.r.Rewrite(sql)
	return harness.Result{SQL: out, Warnings: warns}, err
}

func factory(schema string) (harness.Rewriter, error) {
	r, err := pgqrewrite.New(pgqrewrite.Options{Schema: schema})
	return adapter{r}, err
}

// TestCorpus runs the shared corpus on PostgreSQL. Every case except the
// documented limitations must pass.
func TestCorpus(t *testing.T) {
	harness.RunTest(t, harness.TestOptions{
		Config: harness.Config{
			Candidate: "go-pgquery",
			Library:   "github.com/wasilibs/go-pgquery (libpg_query 17, WASM)",
			Mode:      harness.ModeRewrite,
			Factory:   factory,
		},
		Strict: true,
	})
}
