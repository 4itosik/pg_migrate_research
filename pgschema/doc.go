// Package pgschema qualifies unqualified object names in PostgreSQL
// migrations with a target schema. It is built on its own pure-Go PostgreSQL
// parser: no cgo, no WebAssembly, only the standard library.
//
//	rw, err := pgschema.New(pgschema.Options{Schema: "auth"})
//	for _, up := range upFiles {
//		err = rw.Learn(up) // which types and functions the migrations create
//	}
//	out, warnings, err := rw.Rewrite(sql)
//
// Rewrite only inserts "auth." into the text of the migration: comments,
// formatting and quoting stay as they are. It parses the result again and
// compares its tree with the input's; if anything differs it returns an error
// instead of unverified SQL. With Options.Placeholder the result is a
// template that package subst turns into the same text for any schema without
// a parser.
//
// The README of the module describes the rules, the guarantees and the
// limits; ../prompts/own-parser-library.md is the task and PROGRESS.md the
// state.
package pgschema
