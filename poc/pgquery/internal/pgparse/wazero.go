//go:build !wasm2go

// Package pgparse is the libpg_query backend of the rewriter.
//
// By default it is github.com/wasilibs/go-pgquery: libpg_query compiled to
// WebAssembly and run by wazero, which compiles the module on first use
// (about 1.5 s). With the build tag wasm2go it is the same C code translated
// to Go (../libpgquery): nothing is compiled at run time, the results are the
// same bytes.
package pgparse

import (
	pg "github.com/pganalyze/pg_query_go/v6"
	pgquery "github.com/wasilibs/go-pgquery"
)

// Backend names the backend in reports.
const Backend = "go-pgquery"

// Library describes the backend in reports.
const Library = "github.com/wasilibs/go-pgquery (libpg_query 17, WASM)"

func Parse(sql string) (*pg.ParseResult, error)     { return pgquery.Parse(sql) }
func Scan(sql string) (*pg.ScanResult, error)       { return pgquery.Scan(sql) }
func ParsePlPgSqlToJSON(sql string) (string, error) { return pgquery.ParsePlPgSqlToJSON(sql) }
