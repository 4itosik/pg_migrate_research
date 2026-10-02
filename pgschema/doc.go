// Package pgschema qualifies unqualified object names in PostgreSQL
// migrations with a target schema. It is built on its own pure-Go PostgreSQL
// parser: no cgo, no WebAssembly.
//
// The module is under development. The task, stages and acceptance
// thresholds are in ../prompts/own-parser-library.md; the state is in
// PROGRESS.md.
package pgschema
