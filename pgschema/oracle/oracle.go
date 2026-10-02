// Package oracle checks pgschema against libpg_query, the parser of
// PostgreSQL itself, and against the rewriting prototype in poc/pgquery.
//
// libpg_query comes from github.com/wasilibs/go-pgquery (WebAssembly run by
// wazero). The library module never imports this package or anything it
// depends on.
package oracle

import (
	"reflect"

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

// ErrorInfo returns the message and the 1-based character cursor position of
// an error from libpg_query, or the text of err and 0 for other errors.
func ErrorInfo(err error) (msg string, cursorPos int) {
	v := reflect.ValueOf(err)
	if v.Kind() == reflect.Pointer && v.Elem().Kind() == reflect.Struct {
		m, p := v.Elem().FieldByName("Message"), v.Elem().FieldByName("Cursorpos")
		if m.IsValid() && p.IsValid() {
			return m.String(), int(p.Int())
		}
	}
	return err.Error(), 0
}
