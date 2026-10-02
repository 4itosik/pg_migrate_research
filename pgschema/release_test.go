package pgschema

import (
	"strings"
	"testing"
)

// rewriteOne learns sql and rewrites it with a new Rewriter.
func rewriteOne(t *testing.T, opts Options, sql string) (string, string) {
	t.Helper()
	r := newTestRewriter(t, opts)
	if err := r.Learn(sql); err != nil {
		t.Fatal(err)
	}
	out, warns, err := r.Rewrite(sql)
	if err != nil {
		t.Fatal(err)
	}
	return out, warningText(warns)
}

// A type or a function that a migration creates with the name of a built-in
// of pg_catalog: pg_catalog comes first in the search_path, so an unqualified
// use means the built-in and stays unqualified (with a warning); the CREATE
// itself gets the schema, also with a warning.
func TestRewriteBuiltinNames(t *testing.T) {
	tests := []struct{ name, sql, want string }{
		{"a function named like a built-in",
			"CREATE FUNCTION round(double precision, int) RETURNS numeric LANGUAGE sql AS 'SELECT round($1::numeric, $2)'; SELECT round(price, 2) FROM items",
			"CREATE FUNCTION auth.round(double precision, int) RETURNS numeric LANGUAGE sql AS 'SELECT round($1::numeric, $2)'; SELECT round(price, 2) FROM auth.items"},
		{"a table named like a built-in type",
			"CREATE TABLE text (a int); CREATE TABLE p (name text); SELECT 'x'::text, 'text'::regtype FROM text",
			"CREATE TABLE auth.text (a int); CREATE TABLE auth.p (name text); SELECT 'x'::text, 'text'::regtype FROM auth.text"},
		{"a table named money",
			"CREATE TABLE money (a int); CREATE TABLE p (m money); INSERT INTO money VALUES (1)",
			"CREATE TABLE auth.money (a int); CREATE TABLE auth.p (m money); INSERT INTO auth.money VALUES (1)"},
		{"a domain named like a type keyword",
			"CREATE DOMAIN int AS bigint; CREATE TABLE p (a int)",
			"CREATE DOMAIN auth.int AS bigint; CREATE TABLE auth.p (a int)"},
		{"declarations, triggers and regproc",
			"CREATE TABLE text (a int);\nCREATE FUNCTION lower() RETURNS trigger LANGUAGE plpgsql AS $$ DECLARE v text; BEGIN RETURN NEW; END $$;\nCREATE TRIGGER tg BEFORE INSERT ON t FOR EACH ROW EXECUTE FUNCTION lower(); SELECT 'lower'::regproc",
			"CREATE TABLE auth.text (a int);\nCREATE FUNCTION auth.lower() RETURNS trigger LANGUAGE plpgsql AS $$ DECLARE v text; BEGIN RETURN NEW; END $$;\nCREATE TRIGGER tg BEFORE INSERT ON auth.t FOR EACH ROW EXECUTE FUNCTION lower(); SELECT 'lower'::regproc"},
		{"other names are still qualified",
			"CREATE TYPE mood AS ENUM ('a'); CREATE FUNCTION f() RETURNS mood LANGUAGE sql AS 'SELECT ''a''::mood'; SELECT f()",
			"CREATE TYPE auth.mood AS ENUM ('a'); CREATE FUNCTION auth.f() RETURNS auth.mood LANGUAGE sql AS $$SELECT 'a'::auth.mood$$; SELECT auth.f()"},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got, warns := rewriteOne(t, Options{Schema: "auth"}, tc.sql)
			if got != tc.want {
				t.Errorf("got\n%s\nwant\n%s", got, tc.want)
			}
			if tc.name != "other names are still qualified" {
				if !strings.Contains(warns, "built-in") || !strings.Contains(warns, "qualify it explicitly") {
					t.Errorf("no warning about the built-in name: %s", warns)
				}
			} else if strings.Contains(warns, "built-in") {
				t.Errorf("a warning about a built-in name: %s", warns)
			}
		})
	}
}

// Nested casts of the old pg_dump style: nextval(('s'::text)::regclass).
func TestRewriteNestedRegclassCasts(t *testing.T) {
	got, _ := rewriteOne(t, Options{Schema: "auth"},
		"SELECT nextval(('s'::text)::regclass), 's'::text::regclass, 's'::varchar::regclass, 's'::character varying::regclass, (('s'::text)::regclass)::regclass")
	want := "SELECT nextval(('auth.s'::text)::regclass), 'auth.s'::text::regclass, 'auth.s'::varchar::regclass, 'auth.s'::character varying::regclass, (('auth.s'::text)::regclass)::regclass"
	if got != want {
		t.Errorf("got\n%s\nwant\n%s", got, want)
	}
	// other casts are not looked through
	got, _ = rewriteOne(t, Options{Schema: "auth"}, "SELECT ('s'::name)::regclass, nextval(lower('s')::regclass)")
	if want := "SELECT ('s'::name)::regclass, nextval(lower('s')::regclass)"; got != want {
		t.Errorf("got %s", got)
	}
}

// A temporary table hides a relation of the same name only in the text that
// creates it, from its CREATE onward, until a permanent CREATE of the name.
func TestRewriteTempScope(t *testing.T) {
	r := newTestRewriter(t, Options{Schema: "auth"})
	if err := r.Learn("CREATE TEMP TABLE users AS SELECT 1"); err != nil {
		t.Fatal(err)
	}
	got, _, err := r.Rewrite("CREATE TABLE users (id int); INSERT INTO users VALUES (1)")
	if err != nil || got != "CREATE TABLE auth.users (id int); INSERT INTO auth.users VALUES (1)" {
		t.Errorf("a temp name of Learn: %q, %v", got, err)
	}
	tests := []struct{ name, sql, want string }{
		{"in the same text from the CREATE onward",
			"INSERT INTO tmp VALUES (0); CREATE TEMP TABLE tmp (id int); INSERT INTO tmp VALUES (1)",
			"INSERT INTO auth.tmp VALUES (0); CREATE TEMP TABLE tmp (id int); INSERT INTO tmp VALUES (1)"},
		{"a permanent CREATE ends it for the statements after it",
			"CREATE TEMP TABLE tmp (id int); CREATE TABLE tmp AS SELECT * FROM tmp; INSERT INTO tmp VALUES (2)",
			"CREATE TEMP TABLE tmp (id int); CREATE TABLE auth.tmp AS SELECT * FROM tmp; INSERT INTO auth.tmp VALUES (2)"},
		{"in a body of the same text",
			"DO $$ BEGIN CREATE TEMP TABLE x (a int); INSERT INTO x VALUES (1); END $$; INSERT INTO x VALUES (2)",
			"DO $$ BEGIN CREATE TEMP TABLE x (a int); INSERT INTO x VALUES (1); END $$; INSERT INTO x VALUES (2)"},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			r := newTestRewriter(t, Options{Schema: "auth"})
			got, _, err := r.Rewrite(tc.sql)
			if err != nil || got != tc.want {
				t.Errorf("got\n%s (%v)\nwant\n%s", got, err, tc.want)
			}
			// and nothing is left for the next text
			got, _, err = r.Rewrite("INSERT INTO tmp VALUES (3); INSERT INTO x VALUES (3)")
			if err != nil || got != "INSERT INTO auth.tmp VALUES (3); INSERT INTO auth.x VALUES (3)" {
				t.Errorf("the next text: %q, %v", got, err)
			}
		})
	}
}

// A failed Rewrite or Learn leaves the Rewriter as it was.
func TestFailedCallsLeaveNoState(t *testing.T) {
	r := newTestRewriter(t, Options{Schema: "auth", ExtensionsInSchema: true})
	broken := "CREATE TYPE mood AS ENUM ('a'); CREATE EXTENSION citext; CREATE FUNCTION f() RETURNS int LANGUAGE plpgsql AS $$ BEGIN RETURN INTO x; END $$"
	if _, _, err := r.Rewrite(broken); err == nil {
		t.Fatal("no error")
	}
	got, _, err := r.Rewrite("SELECT 'a'::mood, 'x'::citext")
	if err != nil || got != "SELECT 'a'::mood, 'x'::citext" {
		t.Errorf("after a failed Rewrite: %q, %v", got, err)
	}
	if err := r.Learn("CREATE TYPE mood AS ENUM ('a'); SELECT FROM FROM"); err == nil {
		t.Fatal("no error")
	}
	got, _, err = r.Rewrite("SELECT 'a'::mood")
	if err != nil || got != "SELECT 'a'::mood" {
		t.Errorf("after a failed Learn: %q, %v", got, err)
	}
}

func warningText(warns []string) string { return strings.Join(warns, "\n") }
