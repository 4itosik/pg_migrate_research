package pgschema

import (
	"errors"
	"strings"
	"testing"

	"github.com/4itosik/pg_migrate_research/pgschema/internal/parse"
	"github.com/4itosik/pg_migrate_research/pgschema/internal/plpgsql"
)

// SQL that does not parse is a *SyntaxError with the position of the error in
// the text that was passed, also when the error is inside a function body.
func TestSyntaxError(t *testing.T) {
	tests := []struct {
		name, sql    string
		line, column int
		msg          string
	}{
		{"a statement", "SELECT 1;\nSELECT FROM FROM", 2, 13, `syntax error at or near "FROM"`},
		{"columns count characters", "SELECT 'é', 'ж' FROM FROM", 1, 22, `syntax error at or near "FROM"`},
		{"the end of the input", "CREATE TABLE users (id int", 1, 27, "syntax error at end of input"},
		{"a byte order mark", "\ufeffSELECT 1", 1, 1, "the input starts with a UTF-8 byte order mark (EF BB BF); remove it"},
		{"a SQL body", "CREATE FUNCTION f() RETURNS int LANGUAGE sql AS $$\nSELECT FROM FROM\n$$", 2, 13, `function f: syntax error at or near "FROM"`},
		{"a SQL body in quotes", "CREATE FUNCTION f() RETURNS int LANGUAGE sql AS 'SELECT FROM FROM'", 1, 62, `function f: syntax error at or near "FROM"`},
		{"a fragment of a PL/pgSQL body", "CREATE FUNCTION f() RETURNS int LANGUAGE plpgsql AS $$\nBEGIN\n  PERFORM 1 FROM FROM;\nEND $$", 3, 18,
			`function f: PL/pgSQL line 3 "SELECT 1 FROM FROM": syntax error at or near "FROM"`},
		{"the structure of a PL/pgSQL body", "DO $$\nBEGIN\n  IF true THEN NULL;\nEND $$", 4, 5, `DO block: PL/pgSQL: syntax error, expected "IF" at end of input`},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			_, _, err := Rewrite(tc.sql, Options{Schema: "auth"})
			var se *SyntaxError
			if !errors.As(err, &se) {
				t.Fatalf("not a *SyntaxError: %#v", err)
			}
			if se.Line != tc.line || se.Column != tc.column || !strings.HasPrefix(se.Msg, tc.msg) {
				t.Errorf("got %d:%d %q, want %d:%d %q", se.Line, se.Column, se.Msg, tc.line, tc.column, tc.msg)
			}
			if !strings.HasPrefix(err.Error(), "line ") || !strings.HasSuffix(err.Error(), se.Msg) {
				t.Errorf("Error() = %q", err.Error())
			}
			if errors.Is(err, ErrNotVerified) {
				t.Error("a syntax error is a verification error")
			}
		})
	}
	// Learn reports it as well
	r := newTestRewriter(t, Options{Schema: "auth"})
	var se *SyntaxError
	if err := r.Learn("SELECT 1;\nSELECT FROM FROM"); !errors.As(err, &se) || se.Line != 2 {
		t.Errorf("Learn: %v", err)
	}
	// other errors are not syntax errors
	_, _, err := Rewrite("SELECT 1", Options{Schema: "it's"})
	if err == nil || errors.As(err, &se) {
		t.Errorf("a bad schema: %v", err)
	}
	if got := (&SyntaxError{Line: 3, Column: 7, Msg: "m"}).Error(); got != "line 3, column 7: m" {
		t.Errorf("Error() = %q", got)
	}
}

// A failed verification wraps ErrNotVerified.
func TestErrNotVerified(t *testing.T) {
	stmts, err := parse.Parse("SELECT 1")
	if err != nil {
		t.Fatal(err)
	}
	for _, out := range []string{"SELECT 2", "SELECT 1; SELECT 1", "SELECT FROM FROM"} {
		err := verify(stmts, out)
		if !errors.Is(err, ErrNotVerified) || !strings.HasPrefix(err.Error(), "verification: ") {
			t.Errorf("%q: %v", out, err)
		}
		var se *SyntaxError
		if errors.As(err, &se) {
			t.Errorf("%q: a verification error is a syntax error", out)
		}
	}
	body := "BEGIN PERFORM 1; END"
	pb, err := plpgsql.Parse(body, nil)
	if err != nil {
		t.Fatal(err)
	}
	for _, out := range []string{"BEGIN PERFORM 1; PERFORM 2; END", "BEGIN END IF; END"} {
		if err := verifyBody(pb, out, plpgsql.Options{}); !errors.Is(err, ErrNotVerified) || !strings.HasPrefix(err.Error(), "verification: ") {
			t.Errorf("%q: %v", out, err)
		}
	}
}
