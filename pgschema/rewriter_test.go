package pgschema

import (
	"fmt"
	"strings"
	"testing"
	"time"
)

func newTestRewriter(t *testing.T, opts Options) *Rewriter {
	t.Helper()
	r, err := New(opts)
	if err != nil {
		t.Fatal(err)
	}
	return r
}

// TestRewrite checks the rules on small migrations. Every expectation is the
// input with "auth." inserted: nothing else may change.
func TestRewrite(t *testing.T) {
	tests := []struct {
		name string
		sql  string
		want string
	}{
		{"create table and index", "CREATE TABLE users (id serial PRIMARY KEY, email text);\nCREATE INDEX users_email ON users (email);",
			"CREATE TABLE auth.users (id serial PRIMARY KEY, email text);\nCREATE INDEX users_email ON auth.users (email);"},
		{"foreign key and references", "CREATE TABLE a (id int PRIMARY KEY); CREATE TABLE b (a_id int REFERENCES a (id));",
			"CREATE TABLE auth.a (id int PRIMARY KEY); CREATE TABLE auth.b (a_id int REFERENCES auth.a (id));"},
		{"already qualified", "CREATE TABLE public.t (id int); SELECT * FROM other.t",
			"CREATE TABLE public.t (id int); SELECT * FROM other.t"},
		{"alter, drop, comment", "ALTER TABLE t ADD COLUMN c int; COMMENT ON TABLE t IS 'x'; DROP TABLE IF EXISTS t, u CASCADE",
			"ALTER TABLE auth.t ADD COLUMN c int; COMMENT ON TABLE auth.t IS 'x'; DROP TABLE IF EXISTS auth.t, auth.u CASCADE"},
		{"select with joins and subquery", "SELECT * FROM a JOIN b USING (id) WHERE a.id IN (SELECT id FROM c)",
			"SELECT * FROM auth.a JOIN auth.b USING (id) WHERE a.id IN (SELECT id FROM auth.c)"},
		{"alias and quoted", `SELECT * FROM "Users" u, t AS x`, `SELECT * FROM auth."Users" u, auth.t AS x`},
		{"cte is not a table", "WITH c AS (SELECT * FROM t) SELECT * FROM c, d",
			"WITH c AS (SELECT * FROM auth.t) SELECT * FROM c, auth.d"},
		{"recursive cte", "WITH RECURSIVE r AS (SELECT 1 AS n UNION ALL SELECT n + 1 FROM r WHERE n < 3) SELECT * FROM r",
			"WITH RECURSIVE r AS (SELECT 1 AS n UNION ALL SELECT n + 1 FROM r WHERE n < 3) SELECT * FROM r"},
		{"cte hides a table only after its definition", "WITH t AS (SELECT * FROM t) SELECT * FROM t",
			"WITH t AS (SELECT * FROM auth.t) SELECT * FROM t"},
		{"insert update delete", "INSERT INTO t (a) SELECT a FROM s; UPDATE t SET a = 1 FROM s WHERE t.id = s.id; DELETE FROM t USING s WHERE t.id = s.id",
			"INSERT INTO auth.t (a) SELECT a FROM auth.s; UPDATE auth.t SET a = 1 FROM auth.s WHERE t.id = s.id; DELETE FROM auth.t USING auth.s WHERE t.id = s.id"},
		{"for update of names a from item", "SELECT * FROM t FOR UPDATE OF t", "SELECT * FROM auth.t FOR UPDATE OF t"},
		{"temp table stays", "CREATE TEMP TABLE tmp (id int); INSERT INTO tmp SELECT id FROM t",
			"CREATE TEMP TABLE tmp (id int); INSERT INTO tmp SELECT id FROM auth.t"},
		{"pg_ relations stay", "SELECT * FROM pg_class JOIN t ON true", "SELECT * FROM pg_class JOIN auth.t ON true"},
		{"types are qualified once created", "CREATE TYPE mood AS ENUM ('a'); CREATE TABLE p (m mood, n int)",
			"CREATE TYPE auth.mood AS ENUM ('a'); CREATE TABLE auth.p (m auth.mood, n int)"},
		{"domain and cast", "CREATE DOMAIN pos AS int CHECK (VALUE > 0); SELECT 1::pos; SELECT CAST(2 AS pos)",
			"CREATE DOMAIN auth.pos AS int CHECK (VALUE > 0); SELECT 1::auth.pos; SELECT CAST(2 AS auth.pos)"},
		{"builtin types stay", "CREATE TABLE q (a int, b text, c timestamptz, d numeric(10, 2), e int[])",
			"CREATE TABLE auth.q (a int, b text, c timestamptz, d numeric(10, 2), e int[])"},
		{"sequence and defaults", "CREATE SEQUENCE s; CREATE TABLE r (id int DEFAULT nextval('s'), v int); ALTER SEQUENCE s OWNED BY r.id",
			"CREATE SEQUENCE auth.s; CREATE TABLE auth.r (id int DEFAULT nextval('auth.s'), v int); ALTER SEQUENCE auth.s OWNED BY auth.r.id"},
		{"regclass literal", "SELECT 'users'::regclass, to_regclass('users'), pg_get_serial_sequence('users', 'id')",
			"SELECT 'auth.users'::regclass, to_regclass('auth.users'), pg_get_serial_sequence('auth.users', 'id')"},
		{"regclass literals are edited in place", "SELECT nextval(' s '), nextval(E's'), $$s$$::regclass, 's'::regclass, '\"My S\"'::regclass",
			"SELECT nextval(' auth.s '), nextval(E'auth.s'), $$auth.s$$::regclass, 'auth.s'::regclass, 'auth.\"My S\"'::regclass"},
		{"a literal that needs requoting", `SELECT '"a""b"'::regclass, E'\x74'::regclass`, `SELECT 'auth."a""b"'::regclass, 'auth.t'::regclass`},
		{"function and call", "CREATE FUNCTION f(a int) RETURNS int LANGUAGE sql AS 'SELECT a + 1'; SELECT f(1)",
			"CREATE FUNCTION auth.f(a int) RETURNS int LANGUAGE sql AS 'SELECT a + 1'; SELECT auth.f(1)"},
		{"sql function body", "CREATE FUNCTION g() RETURNS bigint LANGUAGE sql AS $$ SELECT count(*) FROM t $$",
			"CREATE FUNCTION auth.g() RETURNS bigint LANGUAGE sql AS $$ SELECT count(*) FROM auth.t $$"},
		{"sql function body in quotes is requoted", "CREATE FUNCTION g() RETURNS bigint LANGUAGE sql AS 'SELECT count(*) FROM t'",
			"CREATE FUNCTION auth.g() RETURNS bigint LANGUAGE sql AS $$SELECT count(*) FROM auth.t$$"},
		{"a quoted body that ends with a dollar sign", "CREATE FUNCTION g() RETURNS bigint LANGUAGE sql AS 'SELECT count(*) FROM t -- $'",
			"CREATE FUNCTION auth.g() RETURNS bigint LANGUAGE sql AS $body0$SELECT count(*) FROM auth.t -- $$body0$"},
		{"a table function with one column of a created type", "CREATE TYPE mood AS ENUM ('a'); CREATE FUNCTION f() RETURNS TABLE (m mood) LANGUAGE sql AS 'SELECT NULL::mood'",
			"CREATE TYPE auth.mood AS ENUM ('a'); CREATE FUNCTION auth.f() RETURNS TABLE (m auth.mood) LANGUAGE sql AS $$SELECT NULL::auth.mood$$"},
		{"a table function with several columns", "CREATE TYPE mood AS ENUM ('a'); CREATE FUNCTION f() RETURNS TABLE (a int, m mood) LANGUAGE sql AS 'SELECT 1, NULL::mood'",
			"CREATE TYPE auth.mood AS ENUM ('a'); CREATE FUNCTION auth.f() RETURNS TABLE (a int, m auth.mood) LANGUAGE sql AS $$SELECT 1, NULL::auth.mood$$"},
		{"sql standard body", "CREATE FUNCTION h() RETURNS int LANGUAGE sql BEGIN ATOMIC SELECT 1 FROM t; END",
			"CREATE FUNCTION auth.h() RETURNS int LANGUAGE sql BEGIN ATOMIC SELECT 1 FROM auth.t; END"},
		{"trigger", "CREATE FUNCTION tf() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RETURN NEW; END $$; CREATE TRIGGER tg BEFORE INSERT ON t FOR EACH ROW EXECUTE FUNCTION tf()",
			"CREATE FUNCTION auth.tf() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RETURN NEW; END $$; CREATE TRIGGER tg BEFORE INSERT ON auth.t FOR EACH ROW EXECUTE FUNCTION auth.tf()"},
		{"view and grant", "CREATE VIEW v AS SELECT * FROM t; GRANT SELECT ON v TO bob; GRANT ALL ON ALL TABLES IN SCHEMA public TO bob",
			"CREATE VIEW auth.v AS SELECT * FROM auth.t; GRANT SELECT ON auth.v TO bob; GRANT ALL ON ALL TABLES IN SCHEMA public TO bob"},
		{"drop policy and trigger", "DROP POLICY p ON t; DROP TRIGGER tg ON t", "DROP POLICY p ON auth.t; DROP TRIGGER tg ON auth.t"},
		{"rename", "ALTER TABLE t RENAME TO u; ALTER TABLE u RENAME COLUMN a TO b", "ALTER TABLE auth.t RENAME TO u; ALTER TABLE auth.u RENAME COLUMN a TO b"},
		{"comments and strings are not touched", "-- t\nSELECT 't', $$ from t $$ /* from t */ FROM t",
			"-- t\nSELECT 't', $$ from t $$ /* from t */ FROM auth.t"},
		{"add constraint is not a column", "ALTER TABLE t ADD CONSTRAINT c CHECK (a > 0)", "ALTER TABLE auth.t ADD CONSTRAINT c CHECK (a > 0)"},
		{"unnest of a subquery is a function", "SELECT * FROM unnest((SELECT arr FROM t))", "SELECT * FROM unnest((SELECT arr FROM auth.t))"},
		{"transition tables stay in the body",
			"CREATE FUNCTION tf() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN INSERT INTO audit SELECT * FROM newrows; RETURN NULL; END $$;\nCREATE TRIGGER tg AFTER INSERT ON t REFERENCING NEW TABLE AS newrows FOR EACH STATEMENT EXECUTE FUNCTION tf()",
			"CREATE FUNCTION auth.tf() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN INSERT INTO auth.audit SELECT * FROM newrows; RETURN NULL; END $$;\nCREATE TRIGGER tg AFTER INSERT ON auth.t REFERENCING NEW TABLE AS newrows FOR EACH STATEMENT EXECUTE FUNCTION auth.tf()"},
		{"functions of extensions and built-ins stay", "SELECT gen_random_uuid(), crypt('x', gen_salt('bf')), now(), lower(name) FROM t",
			"SELECT gen_random_uuid(), crypt('x', gen_salt('bf')), now(), lower(name) FROM auth.t"},
		{"an escape string body is requoted", `CREATE FUNCTION e() RETURNS bigint LANGUAGE sql AS E'SELECT count(*) FROM t WHERE x = \'a\''`,
			"CREATE FUNCTION auth.e() RETURNS bigint LANGUAGE sql AS $$SELECT count(*) FROM auth.t WHERE x = 'a'$$"},
		{"information_schema is left alone", "SELECT * FROM information_schema.tables JOIN t ON true",
			"SELECT * FROM information_schema.tables JOIN auth.t ON true"},
		{"a name with Unicode escapes", `CREATE TABLE U&"d\0061t" (id int); SELECT * FROM U&"d!0061t" UESCAPE '!'`,
			`CREATE TABLE auth.U&"d\0061t" (id int); SELECT * FROM auth.U&"d!0061t" UESCAPE '!'`},
		{"no sql", "-- nothing here\n", "-- nothing here\n"},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			r := newTestRewriter(t, Options{Schema: "auth"})
			if err := r.Learn(tc.sql); err != nil {
				t.Fatal(err)
			}
			got, _, err := r.Rewrite(tc.sql)
			if err != nil {
				t.Fatal(err)
			}
			if got != tc.want {
				t.Errorf("got\n%s\nwant\n%s", got, tc.want)
			}
			// the output is a fixed point of nothing: rewriting it again
			// adds no schema where there already is one
			again, _, err := r.Rewrite(got)
			if err != nil {
				t.Fatalf("the output cannot be rewritten: %v", err)
			}
			if again != got {
				t.Errorf("a second rewriting changes the output:\n%s", again)
			}
		})
	}
}

func TestRewritePLpgSQL(t *testing.T) {
	tests := []struct {
		name string
		sql  string
		want string
	}{
		{"statements and expressions",
			"CREATE FUNCTION f() RETURNS int LANGUAGE plpgsql AS $$\nDECLARE n int;\nBEGIN\n  SELECT count(*) INTO n FROM t;\n  IF n > (SELECT max(x) FROM u) THEN RETURN 1; END IF;\n  RETURN 0;\nEND $$",
			"CREATE FUNCTION auth.f() RETURNS int LANGUAGE plpgsql AS $$\nDECLARE n int;\nBEGIN\n  SELECT count(*) INTO n FROM auth.t;\n  IF n > (SELECT max(x) FROM auth.u) THEN RETURN 1; END IF;\n  RETURN 0;\nEND $$"},
		{"perform insert update",
			"CREATE FUNCTION f() RETURNS void LANGUAGE plpgsql AS $$ BEGIN PERFORM 1 FROM t; INSERT INTO t VALUES (1); UPDATE u SET a = 1; END $$",
			"CREATE FUNCTION auth.f() RETURNS void LANGUAGE plpgsql AS $$ BEGIN PERFORM 1 FROM auth.t; INSERT INTO auth.t VALUES (1); UPDATE auth.u SET a = 1; END $$"},
		{"assignment and loops",
			"CREATE FUNCTION f() RETURNS void LANGUAGE plpgsql AS $$\nDECLARE v int; r record;\nBEGIN\n  v := (SELECT count(*) FROM t);\n  FOR r IN SELECT * FROM u LOOP v := v + 1; END LOOP;\nEND $$",
			"CREATE FUNCTION auth.f() RETURNS void LANGUAGE plpgsql AS $$\nDECLARE v int; r record;\nBEGIN\n  v := (SELECT count(*) FROM auth.t);\n  FOR r IN SELECT * FROM auth.u LOOP v := v + 1; END LOOP;\nEND $$"},
		{"declarations",
			"CREATE TYPE mood AS ENUM ('a'); CREATE TABLE t (id int, c int);\nCREATE FUNCTION f() RETURNS void LANGUAGE plpgsql AS $$\nDECLARE a t%ROWTYPE; b t.c%TYPE; m mood; i int;\nBEGIN NULL; END $$",
			"CREATE TYPE auth.mood AS ENUM ('a'); CREATE TABLE auth.t (id int, c int);\nCREATE FUNCTION auth.f() RETURNS void LANGUAGE plpgsql AS $$\nDECLARE a auth.t%ROWTYPE; b auth.t.c%TYPE; m auth.mood; i int;\nBEGIN NULL; END $$"},
		{"array of a column type",
			"CREATE TABLE t (c int);\nCREATE FUNCTION f() RETURNS void LANGUAGE plpgsql AS $$ DECLARE b t.c%TYPE[]; a t%ROWTYPE; BEGIN NULL; END $$",
			"CREATE TABLE auth.t (c int);\nCREATE FUNCTION auth.f() RETURNS void LANGUAGE plpgsql AS $$ DECLARE b auth.t.c%TYPE[]; a auth.t%ROWTYPE; BEGIN NULL; END $$"},
		{"a variable shadows a table in %TYPE",
			"CREATE TABLE t (c int);\nCREATE FUNCTION f(t record) RETURNS void LANGUAGE plpgsql AS $$ DECLARE b t.c%TYPE; BEGIN NULL; END $$",
			"CREATE TABLE auth.t (c int);\nCREATE FUNCTION auth.f(t record) RETURNS void LANGUAGE plpgsql AS $$ DECLARE b t.c%TYPE; BEGIN NULL; END $$"},
		{"trigger variables",
			"CREATE TABLE t (c int);\nCREATE FUNCTION f() RETURNS trigger LANGUAGE plpgsql AS $$ DECLARE b new.c%TYPE; BEGIN RETURN NEW; END $$",
			"CREATE TABLE auth.t (c int);\nCREATE FUNCTION auth.f() RETURNS trigger LANGUAGE plpgsql AS $$ DECLARE b new.c%TYPE; BEGIN RETURN NEW; END $$"},
		{"case with a selector",
			"CREATE FUNCTION f(x int) RETURNS text LANGUAGE plpgsql AS $$ BEGIN CASE x WHEN (SELECT max(id) FROM t) THEN RETURN 'a'; ELSE RETURN 'b'; END CASE; END $$",
			"CREATE FUNCTION auth.f(x int) RETURNS text LANGUAGE plpgsql AS $$ BEGIN CASE x WHEN (SELECT max(id) FROM auth.t) THEN RETURN 'a'; ELSE RETURN 'b'; END CASE; END $$"},
		{"cursor",
			"CREATE FUNCTION f() RETURNS void LANGUAGE plpgsql AS $$ DECLARE c CURSOR FOR SELECT * FROM t; r record; BEGIN OPEN c; FETCH c INTO r; CLOSE c; END $$",
			"CREATE FUNCTION auth.f() RETURNS void LANGUAGE plpgsql AS $$ DECLARE c CURSOR FOR SELECT * FROM auth.t; r record; BEGIN OPEN c; FETCH c INTO r; CLOSE c; END $$"},
		{"do block",
			"DO $$ BEGIN DELETE FROM t WHERE id = 1; END $$",
			"DO $$ BEGIN DELETE FROM auth.t WHERE id = 1; END $$"},
		{"body in quotes is requoted",
			"CREATE FUNCTION f() RETURNS void LANGUAGE plpgsql AS 'BEGIN DELETE FROM t; END'",
			"CREATE FUNCTION auth.f() RETURNS void LANGUAGE plpgsql AS $$BEGIN DELETE FROM auth.t; END$$"},
		{"nested body keeps its tag",
			"CREATE FUNCTION f() RETURNS void LANGUAGE plpgsql AS $body$ BEGIN EXECUTE $$ select 1 $$; DELETE FROM t; END $body$",
			"CREATE FUNCTION auth.f() RETURNS void LANGUAGE plpgsql AS $body$ BEGIN EXECUTE $$ select 1 $$; DELETE FROM auth.t; END $body$"},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			r := newTestRewriter(t, Options{Schema: "auth"})
			if err := r.Learn(tc.sql); err != nil {
				t.Fatal(err)
			}
			got, _, err := r.Rewrite(tc.sql)
			if err != nil {
				t.Fatal(err)
			}
			if got != tc.want {
				t.Errorf("got\n%s\nwant\n%s", got, tc.want)
			}
		})
	}
}

func TestRewriteWarnings(t *testing.T) {
	tests := []struct {
		name, sql, warning string
	}{
		{"dynamic sql", "DO $$ BEGIN EXECUTE 'SELECT 1'; END $$", "dynamic SQL"},
		{"search_path", "SET search_path TO public", "search_path"},
		{"extension", "CREATE EXTENSION pgcrypto", "CREATE EXTENSION without SCHEMA"},
		{"catalog lookup", "SELECT * FROM pg_class WHERE relname = 't'", "system catalogs"},
		{"current_schema", "SELECT current_schema()", "current_schema"},
		{"range type", "CREATE TYPE r AS RANGE (subtype = int)", "constructor functions of a range type"},
		{"collation", "CREATE COLLATION c (provider = libc, locale = 'C')", "collation created by a migration is not qualified"},
		{"text search configuration", "CREATE TEXT SEARCH CONFIGURATION c (COPY = simple)", "text search configuration created by a migration is not qualified"},
		{"schema elements", "CREATE SCHEMA s CREATE TABLE a (id int)", "elements of CREATE SCHEMA"},
		{"other language", "CREATE FUNCTION f() RETURNS int LANGUAGE plpython3u AS $$ return 1 $$", "LANGUAGE plpython3u"},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			r := newTestRewriter(t, Options{Schema: "auth"})
			_, warns, err := r.Rewrite(tc.sql)
			if err != nil {
				t.Fatal(err)
			}
			if !strings.Contains(strings.Join(warns, "\n"), tc.warning) {
				t.Errorf("warnings %q do not mention %q", warns, tc.warning)
			}
		})
	}
}

func TestRewriteSchemaNames(t *testing.T) {
	for schema, prefix := range map[string]string{"auth": "auth.", "Auth": `"Auth".`, "user": `"user".`, "my schema": `"my schema".`, `a"b`: `"a""b".`} {
		r := newTestRewriter(t, Options{Schema: schema})
		got, _, err := r.Rewrite("CREATE TABLE t (id int)")
		if err != nil {
			t.Fatal(err)
		}
		if want := "CREATE TABLE " + prefix + "t (id int)"; got != want {
			t.Errorf("schema %q: got %q, want %q", schema, got, want)
		}
	}
	for _, bad := range []string{"", "a'b", "a$b"} {
		if _, err := New(Options{Schema: bad}); err == nil {
			t.Errorf("schema %q accepted", bad)
		}
	}
}

func TestRewriteExclude(t *testing.T) {
	r := newTestRewriter(t, Options{Schema: "auth", ExcludeRelations: []string{"countries"}})
	got, _, err := r.Rewrite("SELECT * FROM countries c JOIN users u ON u.country = c.code")
	if err != nil {
		t.Fatal(err)
	}
	if want := "SELECT * FROM countries c JOIN auth.users u ON u.country = c.code"; got != want {
		t.Errorf("got %q, want %q", got, want)
	}
}

// TestRewriteLearnAcrossFiles: a type created by an earlier migration is
// qualified in a later one only after Learn has seen the earlier.
func TestRewriteLearnAcrossFiles(t *testing.T) {
	up1 := "CREATE TYPE status AS ENUM ('a', 'b'); CREATE FUNCTION is_a(s status) RETURNS boolean LANGUAGE sql AS 'SELECT s = ''a'''"
	up2 := "ALTER TABLE orders ADD COLUMN st status; SELECT is_a('a')"
	r := newTestRewriter(t, Options{Schema: "auth"})
	got, _, err := r.Rewrite(up2)
	if err != nil {
		t.Fatal(err)
	}
	if got != "ALTER TABLE auth.orders ADD COLUMN st status; SELECT is_a('a')" {
		t.Errorf("without Learn: %s", got)
	}
	if err := r.Learn(up1); err != nil {
		t.Fatal(err)
	}
	got, _, err = r.Rewrite(up2)
	if err != nil {
		t.Fatal(err)
	}
	if want := "ALTER TABLE auth.orders ADD COLUMN st auth.status; SELECT auth.is_a('a')"; got != want {
		t.Errorf("after Learn: got %q, want %q", got, want)
	}
}

func TestRewriteRefusesInvalidSQL(t *testing.T) {
	r := newTestRewriter(t, Options{Schema: "auth"})
	if err := r.Learn("CREATE TYPE mood AS ENUM ('a'); CREATE TABLE t (c int)"); err != nil {
		t.Fatal(err)
	}
	for _, sql := range []string{
		// a declaration whose type text is not a type name
		"CREATE FUNCTION f() RETURNS void LANGUAGE plpgsql AS $$ DECLARE m mood int; BEGIN NULL; END $$",
		"CREATE FUNCTION f() RETURNS void LANGUAGE plpgsql AS $$ DECLARE m t%ROWTYPE ROWTYPE; BEGIN NULL; END $$", "CREATE TABLE (", "SELECT FROM FROM", "CREATE FUNCTION f() RETURNS int LANGUAGE sql AS 'not sql'",
		"DO $$ BEGIN SELECT FROM FROM; END $$", "SELECT 'a\xffb'"} {
		if out, _, err := r.Rewrite(sql); err == nil {
			t.Errorf("%q: no error, output %q", sql, out)
		}
	}
}

func TestPlaceholder(t *testing.T) {
	r := newTestRewriter(t, Options{Placeholder: true})
	got, _, err := r.Rewrite("CREATE TABLE t (id serial); SELECT nextval('t_id_seq'), 't'::regclass")
	if err != nil {
		t.Fatal(err)
	}
	want := "CREATE TABLE pgschema_placeholder.t (id serial); SELECT nextval('pgschema_placeholder.t_id_seq'), 'pgschema_placeholder.t'::regclass"
	if got != want {
		t.Errorf("got %q, want %q", got, want)
	}
}

// A fragment of a PL/pgSQL body must parse in its own mode: "RETURN INTO x" is
// not SELECT INTO x, which would create a table.
func TestRewriteRefusesFragmentsOutsideTheirMode(t *testing.T) {
	r := newTestRewriter(t, Options{Schema: "auth"})
	for _, body := range []string{"BEGIN RETURN INTO x; END", "DECLARE v int; BEGIN v := INTO x; END", "BEGIN PERFORM 1; IF INTO x THEN NULL; END IF; END"} {
		sql := "CREATE FUNCTION f() RETURNS int LANGUAGE plpgsql AS $$ " + body + " $$"
		if out, _, err := r.Rewrite(sql); err == nil {
			t.Errorf("%q: no error, output %q", body, out)
		}
	}
	// and nothing is learned from the refused body
	if _, _, err := r.Rewrite("CREATE FUNCTION g() RETURNS int LANGUAGE plpgsql AS $$ BEGIN RETURN INTO t; END $$"); err == nil {
		t.Fatal("no error")
	}
	got, _, err := r.Rewrite("SELECT * FROM t")
	if err != nil || got != "SELECT * FROM auth.t" {
		t.Errorf("got %q, %v", got, err)
	}
}

// Verification must stay linear in the size of the statement: a data migration
// is often one huge INSERT ... SELECT ... UNION ALL, or a long expression.
func TestRewriteLargeStatements(t *testing.T) {
	var rows, terms []string
	for i := 0; i < 6000; i++ {
		rows = append(rows, fmt.Sprintf("SELECT %d, 'name%d'", i, i))
	}
	for i := 0; i < 20000; i++ {
		terms = append(terms, "1")
	}
	inputs := map[string]string{
		"union all rows": "INSERT INTO users (id, name) " + strings.Join(rows, " UNION ALL ") + ";",
		"long sum":       "SELECT " + strings.Join(terms, " + ") + " FROM users;",
		"deep parens":    "SELECT " + strings.Repeat("(", 5000) + "1" + strings.Repeat(")", 5000) + " FROM users;",
	}
	for name, sql := range inputs {
		start := time.Now()
		r := newTestRewriter(t, Options{Schema: "auth"})
		out, _, err := r.Rewrite(sql)
		if err != nil {
			t.Fatalf("%s: %v", name, err)
		}
		if d := time.Since(start); d > 10*time.Second {
			t.Errorf("%s: %d bytes took %s", name, len(sql), d)
		}
		if !strings.Contains(out, "auth.users") {
			t.Errorf("%s: users is not qualified", name)
		}
	}
}

// The template does not know the target schema, so a migration that names it
// ("auth.users") is not the same to the rewriter in the two modes: with the
// schema it recognizes the objects the migration creates, with the placeholder
// they belong to another schema. The README says that placeholder and direct
// rewriting agree for migrations that do not spell the target schema.
func TestPlaceholderDoesNotKnowTheTargetSchema(t *testing.T) {
	sql := "CREATE TYPE auth.mood AS ENUM ('a'); CREATE TABLE auth.t (m mood)"
	direct := newTestRewriter(t, Options{Schema: "auth"})
	tmpl := newTestRewriter(t, Options{Placeholder: true})
	want, _, err := direct.Rewrite(sql)
	if err != nil {
		t.Fatal(err)
	}
	got, _, err := tmpl.Rewrite(sql)
	if err != nil {
		t.Fatal(err)
	}
	if want != "CREATE TYPE auth.mood AS ENUM ('a'); CREATE TABLE auth.t (m auth.mood)" || got != sql {
		t.Errorf("direct %q, template %q", want, got)
	}
}

// A name that already has a schema is left alone, whatever the schema is:
// another one, the target one, a catalog.
const explicitSchemaMigration = `CREATE TYPE other.mood AS ENUM ('a');
CREATE DOMAIN other.pos AS int CHECK (VALUE > 0);
CREATE TABLE other.t (id serial PRIMARY KEY, m other.mood, p other.pos, n int REFERENCES other.parent (id));
CREATE SEQUENCE other.s OWNED BY other.t.id;
CREATE INDEX t_idx ON other.t (id);
CREATE VIEW other.v AS SELECT * FROM other.t JOIN other.parent USING (id);
CREATE FUNCTION other.f(a other.mood) RETURNS other.mood LANGUAGE sql AS 'SELECT a';
CREATE FUNCTION other.g() RETURNS trigger LANGUAGE plpgsql AS $$ DECLARE r other.t%ROWTYPE; c other.t.id%TYPE; BEGIN INSERT INTO other.log SELECT * FROM other.t; RETURN NEW; END $$;
CREATE TRIGGER tg BEFORE INSERT ON other.t FOR EACH ROW EXECUTE FUNCTION other.g();
ALTER TABLE other.t ADD COLUMN x other.pos;
ALTER TABLE other.t RENAME TO t2;
ALTER TABLE other.t2 RENAME COLUMN x TO y;
COMMENT ON TABLE other.t IS 'x';
COMMENT ON COLUMN other.t.id IS 'y';
DROP TABLE IF EXISTS other.a, other.b CASCADE;
DROP FUNCTION other.f(other.mood);
DROP TYPE other.mood;
GRANT SELECT ON other.t TO bob;
GRANT EXECUTE ON FUNCTION other.f(other.mood) TO bob;
INSERT INTO other.t (id) SELECT id FROM other.parent;
UPDATE other.t SET id = 1 FROM other.parent WHERE true;
DELETE FROM other.t USING other.parent WHERE true;
SELECT nextval('other.s'), 'other.t'::regclass, other.f('a'), 'other.mood'::regtype, to_regclass('other.t'), pg_get_serial_sequence('other.t', 'id');
CREATE POLICY p ON other.t USING (true);
DROP POLICY p ON other.t;
DROP TRIGGER tg ON other.t;
TRUNCATE other.t;
LOCK TABLE other.t;
VACUUM other.t;
CREATE TABLE other.c (LIKE other.t) INHERITS (other.t);
CREATE TABLE other.pt PARTITION OF other.parent FOR VALUES IN (1);
ALTER TABLE other.t SET SCHEMA elsewhere;
SELECT * FROM db.other.t, pg_temp.tmp, information_schema.tables;
`

func TestRewriteLeavesQualifiedNamesAlone(t *testing.T) {
	for _, schema := range []string{"other", "auth"} {
		sql := strings.ReplaceAll(explicitSchemaMigration, "other.", schema+".")
		r := newTestRewriter(t, Options{Schema: "auth"})
		if err := r.Learn(sql); err != nil {
			t.Fatal(err)
		}
		got, _, err := r.Rewrite(sql)
		if err != nil {
			t.Fatalf("schema %s: %v", schema, err)
		}
		if got != sql {
			t.Errorf("schema %s: the text changed:\n%s", schema, firstLineDiff(sql, got))
		}
	}
	// next to unqualified names only those are changed
	r := newTestRewriter(t, Options{Schema: "auth"})
	got, _, err := r.Rewrite("SELECT * FROM other.a JOIN b ON true JOIN auth.c ON true; DROP TABLE public.x, y; COMMENT ON TABLE other.t IS 'x'")
	if err != nil {
		t.Fatal(err)
	}
	if want := "SELECT * FROM other.a JOIN auth.b ON true JOIN auth.c ON true; DROP TABLE public.x, auth.y; COMMENT ON TABLE other.t IS 'x'"; got != want {
		t.Errorf("got %q, want %q", got, want)
	}
}

func firstLineDiff(want, got string) string {
	wl, gl := strings.Split(want, "\n"), strings.Split(got, "\n")
	for i := 0; i < len(wl) && i < len(gl); i++ {
		if wl[i] != gl[i] {
			return fmt.Sprintf("line %d\n  was: %s\n  now: %s", i+1, wl[i], gl[i])
		}
	}
	return "different length"
}

func TestRewriteExtensions(t *testing.T) {
	const warning = "CREATE EXTENSION without SCHEMA"
	// by default the statement stays as written and gets a warning
	r := newTestRewriter(t, Options{Schema: "auth"})
	got, warns, err := r.Rewrite("CREATE EXTENSION IF NOT EXISTS pgcrypto;")
	if err != nil || got != "CREATE EXTENSION IF NOT EXISTS pgcrypto;" || !strings.Contains(strings.Join(warns, "\n"), warning) {
		t.Errorf("default: %q, %q, %v", got, warns, err)
	}
	// with the option the schema is added at the end, before the semicolon
	tests := []struct{ name, sql, want string }{
		{"plain", "CREATE EXTENSION pgcrypto;", "CREATE EXTENSION pgcrypto SCHEMA auth;"},
		{"if not exists", "CREATE EXTENSION IF NOT EXISTS pgcrypto", "CREATE EXTENSION IF NOT EXISTS pgcrypto SCHEMA auth"},
		{"other options", "CREATE EXTENSION hstore WITH VERSION '1.8' CASCADE;", "CREATE EXTENSION hstore WITH VERSION '1.8' CASCADE SCHEMA auth;"},
		{"a comment after", "CREATE EXTENSION citext -- case-insensitive text", "CREATE EXTENSION citext SCHEMA auth -- case-insensitive text"},
		{"a quoted name", `CREATE EXTENSION "uuid-ossp";`, `CREATE EXTENSION "uuid-ossp" SCHEMA auth;`},
		{"with and nothing else", "CREATE EXTENSION ltree WITH;", "CREATE EXTENSION ltree WITH SCHEMA auth;"},
		{"several statements", "CREATE EXTENSION a; CREATE EXTENSION b", "CREATE EXTENSION a SCHEMA auth; CREATE EXTENSION b SCHEMA auth"},
		// a schema in the statement stays, whatever it is
		{"a schema is given", "CREATE EXTENSION pgcrypto SCHEMA public;", "CREATE EXTENSION pgcrypto SCHEMA public;"},
		{"the target schema is given", "CREATE EXTENSION pgcrypto WITH SCHEMA auth VERSION '1.3'", "CREATE EXTENSION pgcrypto WITH SCHEMA auth VERSION '1.3'"},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			r := newTestRewriter(t, Options{Schema: "auth", ExtensionsInSchema: true})
			got, warns, err := r.Rewrite(tc.sql)
			if err != nil {
				t.Fatal(err)
			}
			if got != tc.want {
				t.Errorf("got %q, want %q", got, tc.want)
			}
			if strings.Contains(strings.Join(warns, "\n"), warning) {
				t.Errorf("the old warning is still given: %q", warns)
			}
		})
	}
	// an extension whose objects the library knows needs no warning, one it
	// does not know does: its uses are not rewritten
	r = newTestRewriter(t, Options{Schema: "auth", ExtensionsInSchema: true})
	if _, warns, err := r.Rewrite("CREATE EXTENSION pgcrypto"); err != nil || len(warns) != 0 {
		t.Errorf("a known extension: warnings %q, %v", warns, err)
	}
	if _, warns, err := r.Rewrite("CREATE EXTENSION postgis"); err != nil || !strings.Contains(strings.Join(warns, "\n"), "not known to the library") {
		t.Errorf("an unknown extension: warnings %q, %v", warns, err)
	}
	// a template: the placeholder goes where the schema does
	r = newTestRewriter(t, Options{Placeholder: true, ExtensionsInSchema: true})
	if got, _, err := r.Rewrite("CREATE EXTENSION pgcrypto;"); err != nil || got != "CREATE EXTENSION pgcrypto SCHEMA pgschema_placeholder;" {
		t.Errorf("template: %q, %v", got, err)
	}
	// a schema that needs quotes
	r = newTestRewriter(t, Options{Schema: "my schema", ExtensionsInSchema: true})
	if got, _, err := r.Rewrite("CREATE EXTENSION pgcrypto;"); err != nil || got != `CREATE EXTENSION pgcrypto SCHEMA "my schema";` {
		t.Errorf("quoted: %q, %v", got, err)
	}
	// Learn does not change the text and does not fail
	if err := r.Learn("CREATE EXTENSION pgcrypto"); err != nil {
		t.Fatal(err)
	}
}

// The uses of an extension in SQL: a function such as digest() or a type such
// as citext get the schema where the extension is installed, if the caller says
// where.
func TestRewriteExtensionUses(t *testing.T) {
	const migration = `CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email citext NOT NULL,
    pwd text DEFAULT crypt('x', gen_salt('bf')),
    h text GENERATED ALWAYS AS (encode(digest(email::text, 'sha256'), 'hex')) STORED
);
CREATE FUNCTION fp(k text) RETURNS text LANGUAGE plpgsql AS $$
DECLARE c citext := k;
BEGIN
  RETURN encode(hmac(c::text, 'k', 'sha1'), 'hex') || uuid_generate_v4()::text;
END $$;
CREATE TRIGGER touch BEFORE UPDATE ON users FOR EACH ROW EXECUTE FUNCTION moddatetime(updated_at);
SELECT public.digest('a', 'md5'), now(), lower('A')`
	t.Run("nothing configured: as before", func(t *testing.T) {
		r := newTestRewriter(t, Options{Schema: "auth"})
		got, _, err := r.Rewrite(migration)
		if err != nil {
			t.Fatal(err)
		}
		if strings.Contains(got, "ext.") || strings.Contains(got, "auth.citext") || strings.Contains(got, "auth.digest") {
			t.Errorf("an extension object got a schema:\n%s", got)
		}
	})
	t.Run("installed in another schema", func(t *testing.T) {
		r := newTestRewriter(t, Options{Schema: "auth", Extensions: map[string]string{"pgcrypto": "ext", "citext": "ext", "uuid-ossp": "ext", "moddatetime": "ext"}})
		got, _, err := r.Rewrite(migration)
		if err != nil {
			t.Fatal(err)
		}
		want := strings.NewReplacer(
			"CREATE TABLE users", "CREATE TABLE auth.users",
			"gen_random_uuid()", "gen_random_uuid()", // the core has it: no schema
			"email citext", "email ext.citext",
			"crypt('x', gen_salt('bf'))", "ext.crypt('x', ext.gen_salt('bf'))",
			"digest(email::text", "ext.digest(email::text",
			"CREATE FUNCTION fp", "CREATE FUNCTION auth.fp",
			"c citext", "c ext.citext",
			"hmac(", "ext.hmac(",
			"uuid_generate_v4()", "ext.uuid_generate_v4()",
			"ON users FOR EACH ROW EXECUTE FUNCTION moddatetime", "ON auth.users FOR EACH ROW EXECUTE FUNCTION ext.moddatetime",
		).Replace(migration)
		if got != want {
			t.Errorf("got\n%s\nwant\n%s", got, want)
		}
	})
	t.Run("installed in the target schema", func(t *testing.T) {
		r := newTestRewriter(t, Options{Schema: "auth", Extensions: map[string]string{"pgcrypto": ""}})
		got, _, err := r.Rewrite("SELECT digest('a', 'md5'), gen_random_uuid()")
		if err != nil || got != "SELECT auth.digest('a', 'md5'), gen_random_uuid()" {
			t.Errorf("got %q, %v", got, err)
		}
	})
	t.Run("a function of a migration wins over an extension's", func(t *testing.T) {
		r := newTestRewriter(t, Options{Schema: "auth", Extensions: map[string]string{"pgcrypto": "ext"}})
		got, _, err := r.Rewrite("CREATE FUNCTION digest(a text) RETURNS text LANGUAGE sql AS 'SELECT a'; SELECT digest('x')")
		if err != nil || got != "CREATE FUNCTION auth.digest(a text) RETURNS text LANGUAGE sql AS 'SELECT a'; SELECT auth.digest('x')" {
			t.Errorf("got %q, %v", got, err)
		}
	})
	t.Run("a name outside the extension and a name with a schema stay", func(t *testing.T) {
		r := newTestRewriter(t, Options{Schema: "auth", Extensions: map[string]string{"pgcrypto": "ext"}})
		got, _, err := r.Rewrite("SELECT lower('A'), public.digest('a', 'md5'), ext.digest('a', 'md5'), pg_catalog.now()")
		if err != nil || got != "SELECT lower('A'), public.digest('a', 'md5'), ext.digest('a', 'md5'), pg_catalog.now()" {
			t.Errorf("got %q, %v", got, err)
		}
	})
	t.Run("names the caller adds", func(t *testing.T) {
		r := newTestRewriter(t, Options{Schema: "auth", Extensions: map[string]string{"postgis": "ext"}, ExtensionObjects: map[string][]string{"postgis": {"st_distance", "geometry"}}})
		got, _, err := r.Rewrite("CREATE TABLE p (g geometry); SELECT st_distance(a, b) FROM p")
		if err != nil || got != "CREATE TABLE auth.p (g ext.geometry); SELECT ext.st_distance(a, b) FROM auth.p" {
			t.Errorf("got %q, %v", got, err)
		}
	})
	t.Run("an extension that the migrations create", func(t *testing.T) {
		r := newTestRewriter(t, Options{Schema: "auth", ExtensionsInSchema: true})
		up := "CREATE EXTENSION IF NOT EXISTS citext;\nCREATE TABLE t (e citext, h bytea DEFAULT digest('x', 'md5'))"
		if err := r.Learn(up); err != nil {
			t.Fatal(err)
		}
		got, _, err := r.Rewrite(up)
		want := "CREATE EXTENSION IF NOT EXISTS citext SCHEMA auth;\nCREATE TABLE auth.t (e auth.citext, h bytea DEFAULT digest('x', 'md5'))"
		if err != nil || got != want { // digest belongs to pgcrypto, which the migrations do not create
			t.Errorf("got %q, %v", got, err)
		}
	})
	t.Run("an extension created in a schema the statement names", func(t *testing.T) {
		r := newTestRewriter(t, Options{Schema: "auth", ExtensionsInSchema: true})
		up := "CREATE EXTENSION citext SCHEMA public; CREATE TABLE t (e citext)"
		got, _, err := r.Rewrite(up)
		if err != nil || got != "CREATE EXTENSION citext SCHEMA public; CREATE TABLE auth.t (e public.citext)" {
			t.Errorf("got %q, %v", got, err)
		}
	})
	t.Run("a template", func(t *testing.T) {
		r := newTestRewriter(t, Options{Placeholder: true, Extensions: map[string]string{"pgcrypto": "", "citext": "ext"}})
		got, _, err := r.Rewrite("CREATE EXTENSION pgcrypto; CREATE EXTENSION citext; SELECT digest('a', 'md5'), 'x'::citext")
		want := "CREATE EXTENSION pgcrypto SCHEMA pgschema_placeholder; CREATE EXTENSION citext SCHEMA ext; SELECT pgschema_placeholder.digest('a', 'md5'), 'x'::ext.citext"
		if err != nil || got != want {
			t.Errorf("got %q, %v", got, err)
		}
	})
	t.Run("a schema that cannot be used", func(t *testing.T) {
		if _, err := New(Options{Schema: "auth", Extensions: map[string]string{"pgcrypto": "a'b"}}); err == nil {
			t.Error("the schema a'b was accepted")
		}
	})
}
