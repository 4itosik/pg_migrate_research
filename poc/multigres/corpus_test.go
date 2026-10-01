package mgrewrite_test

import (
	"testing"

	"github.com/4itosik/pg_migrate_research/poc/harness"
	mgrewrite "github.com/4itosik/pg_migrate_research/poc/multigres"
)

type adapter struct{ r *mgrewrite.Rewriter }

func (a adapter) Learn(sql string) error { return a.r.Learn(sql) }

func (a adapter) Rewrite(sql string) (harness.Result, error) {
	out, warns, err := a.r.Rewrite(sql)
	return harness.Result{SQL: out, Warnings: warns}, err
}

func TestCorpus(t *testing.T) {
	harness.RunTest(t, harness.TestOptions{Config: harness.Config{
		Candidate: "multigres",
		Library:   "github.com/multigres/multigres/go/common/parser (pure Go, main 2026-10-01)",
		Mode:      harness.ModeRewrite,
		Factory: func(schema string) (harness.Rewriter, error) {
			r, err := mgrewrite.New(mgrewrite.Options{Schema: schema})
			return adapter{r}, err
		},
	}})
}
