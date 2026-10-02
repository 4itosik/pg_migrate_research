package oracle

import (
	"github.com/4itosik/pg_migrate_research/poc/harness"
	pgqrewrite "github.com/4itosik/pg_migrate_research/poc/pgquery"
)

// PrototypeOptions are the options of the prototype rewriter. They mirror
// the library options that matter for a comparison.
type PrototypeOptions struct {
	Schema           string
	ExcludeRelations []string
}

// Prototype is the rewriter of poc/pgquery, the reference for rewriting.
// Its behaviour is the specification: pgschema must produce the same bytes
// wherever both rewrite, and differences are listed in docs/differences.md.
type Prototype struct{ r *pgqrewrite.Rewriter }

// NewPrototype creates a prototype rewriter.
func NewPrototype(opts PrototypeOptions) (*Prototype, error) {
	r, err := pgqrewrite.New(pgqrewrite.Options{Schema: opts.Schema, ExcludeRelations: opts.ExcludeRelations})
	if err != nil {
		return nil, err
	}
	return &Prototype{r}, nil
}

// Learn registers the objects created by sql.
func (p *Prototype) Learn(sql string) error { return p.r.Learn(sql) }

// Rewrite qualifies the names in sql.
func (p *Prototype) Rewrite(sql string) (out string, warnings []string, err error) {
	return p.r.Rewrite(sql)
}

// HarnessAdapter adapts a rewriter with Learn and Rewrite to the live
// PostgreSQL harness (poc/harness).
type HarnessAdapter struct {
	Learner  func(sql string) error
	Rewriter func(sql string) (string, []string, error)
}

func (a HarnessAdapter) Learn(sql string) error { return a.Learner(sql) }

func (a HarnessAdapter) Rewrite(sql string) (harness.Result, error) {
	out, warns, err := a.Rewriter(sql)
	return harness.Result{SQL: out, Warnings: warns}, err
}

// PrototypeFactory is the harness factory of the prototype.
func PrototypeFactory(schema string) (harness.Rewriter, error) {
	p, err := NewPrototype(PrototypeOptions{Schema: schema})
	if err != nil {
		return nil, err
	}
	return HarnessAdapter{Learner: p.Learn, Rewriter: p.Rewrite}, nil
}
