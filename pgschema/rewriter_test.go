package pgschema

import (
	"strings"
	"testing"
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
		{"function and call", "CREATE FUNCTION f(a int) RETURNS int LANGUAGE sql AS 'SELECT a + 1'; SELECT f(1)",
			"CREATE FUNCTION auth.f(a int) RETURNS int LANGUAGE sql AS 'SELECT a + 1'; SELECT auth.f(1)"},
		{"sql function body", "CREATE FUNCTION g() RETURNS bigint LANGUAGE sql AS $$ SELECT count(*) FROM t $$",
			"CREATE FUNCTION auth.g() RETURNS bigint LANGUAGE sql AS $$ SELECT count(*) FROM auth.t $$"},
		{"sql function body in quotes is requoted", "CREATE FUNCTION g() RETURNS bigint LANGUAGE sql AS 'SELECT count(*) FROM t'",
			"CREATE FUNCTION auth.g() RETURNS bigint LANGUAGE sql AS $$SELECT count(*) FROM auth.t$$"},
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
	for _, sql := range []string{"CREATE TABLE (", "SELECT FROM FROM", "CREATE FUNCTION f() RETURNS int LANGUAGE sql AS 'not sql'",
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
