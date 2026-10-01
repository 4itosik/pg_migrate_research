package antlrrewrite_test

import (
	"testing"

	antlrrewrite "github.com/4itosik/pg_migrate_research/poc/antlr"
	"github.com/4itosik/pg_migrate_research/poc/harness"
)

type adapter struct{ r *antlrrewrite.Rewriter }

func (a adapter) Learn(sql string) error { return a.r.Learn(sql) }

func (a adapter) Rewrite(sql string) (harness.Result, error) {
	out, warns, err := a.r.Rewrite(sql)
	return harness.Result{SQL: out, Warnings: warns}, err
}

func TestCorpus(t *testing.T) {
	harness.RunTest(t, harness.TestOptions{Config: harness.Config{
		Candidate: "bytebase-antlr",
		Library:   "github.com/bytebase/parser/postgresql (ANTLR4 grammar, pure Go)",
		Mode:      harness.ModeRewrite,
		Factory: func(schema string) (harness.Rewriter, error) {
			r, err := antlrrewrite.New(antlrrewrite.Options{Schema: schema})
			return adapter{r}, err
		},
	}})
}
