// Package oracle checks pgschema against libpg_query, the parser of
// PostgreSQL itself, and against the rewriting prototype in poc/pgquery.
//
// libpg_query comes from github.com/wasilibs/go-pgquery (WebAssembly run by
// wazero). The library module never imports this package or anything it
// depends on.
package oracle

import (
	pg "github.com/pganalyze/pg_query_go/v6"
	pgquery "github.com/wasilibs/go-pgquery"
)

// Parse returns the libpg_query parse tree of sql.
func Parse(sql string) (*pg.ParseResult, error) { return pgquery.Parse(sql) }

// Scan returns the libpg_query scanner tokens of sql. The scanner reports
// tokens as the core lexer produces them, before the parser's one-token
// lookahead replaces NOT, NULLS, WITH, WITHOUT and FORMAT.
func Scan(sql string) (*pg.ScanResult, error) { return pgquery.Scan(sql) }

// ParsePlPgSQL returns the libpg_query PL/pgSQL parse tree of a CREATE
// FUNCTION or DO statement as JSON.
func ParsePlPgSQL(sql string) (string, error) { return pgquery.ParsePlPgSqlToJSON(sql) }
