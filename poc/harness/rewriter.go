// Package harness runs schema-qualifying SQL rewriters against a corpus of
// golang-migrate style migrations and validates the output on a real
// PostgreSQL server.
package harness

// Result is the output of a single rewrite.
type Result struct {
	SQL      string
	Warnings []string
}

// Rewriter qualifies unqualified object names in migration SQL with a schema.
//
// Learn registers objects declared by a migration (types, functions, ...)
// without producing output. The harness calls Learn for every up migration of
// a case before rewriting, the same way an integration into golang-migrate
// could pre-scan the migration source.
type Rewriter interface {
	Learn(sql string) error
	Rewrite(sql string) (Result, error)
}

// Factory creates a rewriter for the given target schema.
type Factory func(schema string) (Rewriter, error)
