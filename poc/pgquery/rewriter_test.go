package pgqrewrite

import (
	"strings"
	"testing"
)

func rewrite(t *testing.T, schema string, learn []string, sql string) (string, []string) {
	t.Helper()
	r, err := New(Options{Schema: schema})
	if err != nil {
		t.Fatal(err)
	}
	for _, l := range learn {
		if err := r.Learn(l); err != nil {
			t.Fatal(err)
		}
	}
	out, warns, err := r.Rewrite(sql)
	if err != nil {
		t.Fatalf("Rewrite(%q): %v", sql, err)
	}
	return out, warns
}

func TestRewrite(t *testing.T) {
	cases := []struct {
		name, schema string
		learn        []string
		in, want     string
	}{
		{"example from the task", "auth", nil,
			"Create table users (id int)",
			"Create table auth.users (id int)"},
		{"schema that needs quotes", "My Schema", nil,
			"CREATE TABLE t (id int); SELECT nextval('s')",
			`CREATE TABLE "My Schema".t (id int); SELECT nextval('"My Schema".s')`},
		{"schema that is a keyword", "user", nil,
			"DROP TABLE t",
			`DROP TABLE "user".t`},
		{"already qualified and catalogs", "auth", nil,
			"SELECT * FROM auth.a, other.b, pg_class, information_schema.tables",
			"SELECT * FROM auth.a, other.b, pg_class, information_schema.tables"},
		{"unreserved keyword as a table name", "auth", nil,
			"CREATE TABLE data (id int); DROP TABLE data; COMMENT ON TABLE data IS 'x'",
			"CREATE TABLE auth.data (id int); DROP TABLE auth.data; COMMENT ON TABLE auth.data IS 'x'"},
		{"comments between name parts", "auth", nil,
			"COMMENT ON COLUMN t /* x */ . c IS 'y'",
			"COMMENT ON COLUMN auth.t /* x */ . c IS 'y'"},
		{"types and functions only when known", "auth", []string{"CREATE TYPE mood AS ENUM ('ok'); CREATE FUNCTION f() RETURNS int LANGUAGE sql AS 'SELECT 1'"},
			"SELECT f(), g(), 'ok'::mood, 'x'::citext, lower('A')",
			"SELECT auth.f(), g(), 'ok'::auth.mood, 'x'::citext, lower('A')"},
		{"recursive CTE sees itself, alias is not a table", "auth", nil,
			"WITH RECURSIVE r AS (SELECT 1 AS n UNION ALL SELECT n + 1 FROM r WHERE n < 3) SELECT x.n FROM r AS x JOIN t ON true",
			"WITH RECURSIVE r AS (SELECT 1 AS n UNION ALL SELECT n + 1 FROM r WHERE n < 3) SELECT x.n FROM r AS x JOIN auth.t ON true"},
		{"subquery in UPDATE with CTE", "auth", nil,
			"WITH ids AS (SELECT id FROM a) UPDATE b SET x = 1 WHERE id IN (SELECT id FROM ids)",
			"WITH ids AS (SELECT id FROM auth.a) UPDATE auth.b SET x = 1 WHERE id IN (SELECT id FROM ids)"},
		{"MERGE", "auth", nil,
			"MERGE INTO t USING s ON t.id = s.id WHEN MATCHED THEN UPDATE SET v = s.v WHEN NOT MATCHED THEN INSERT VALUES (s.id, s.v)",
			"MERGE INTO auth.t USING auth.s ON t.id = s.id WHEN MATCHED THEN UPDATE SET v = s.v WHEN NOT MATCHED THEN INSERT VALUES (s.id, s.v)"},
		{"policy and trigger names stay, tables are qualified", "auth", nil,
			"DROP POLICY p ON t; DROP TRIGGER IF EXISTS trg ON t2 CASCADE; COMMENT ON TRIGGER trg ON t3 IS 'x'",
			"DROP POLICY p ON auth.t; DROP TRIGGER IF EXISTS trg ON auth.t2 CASCADE; COMMENT ON TRIGGER trg ON auth.t3 IS 'x'"},
		{"function with the same name as a trigger", "auth", []string{"CREATE FUNCTION trg() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RETURN NEW; END $$"},
			"CREATE TRIGGER trg BEFORE INSERT ON t FOR EACH ROW EXECUTE FUNCTION trg()",
			"CREATE TRIGGER trg BEFORE INSERT ON auth.t FOR EACH ROW EXECUTE FUNCTION auth.trg()"},
		{"built-in trigger function is not qualified", "auth", nil,
			"CREATE TRIGGER z BEFORE UPDATE ON t FOR EACH ROW EXECUTE FUNCTION suppress_redundant_updates_trigger()",
			"CREATE TRIGGER z BEFORE UPDATE ON auth.t FOR EACH ROW EXECUTE FUNCTION suppress_redundant_updates_trigger()"},
		{"E-string literal is re-quoted", "auth", nil,
			`SELECT nextval(E'my\_seq')`,
			`SELECT nextval('auth.my_seq')`},
		{"single-quoted SQL body becomes dollar-quoted", "auth", nil,
			"CREATE FUNCTION f() RETURNS bigint LANGUAGE sql AS 'SELECT count(*) FROM t WHERE s = ''$$'''",
			"CREATE FUNCTION auth.f() RETURNS bigint LANGUAGE sql AS $body0$SELECT count(*) FROM auth.t WHERE s = '$$'$body0$"},
		{"PL/pgSQL: variable %TYPE stays, record field %TYPE stays", "auth", nil,
			"CREATE FUNCTION f(r t) RETURNS void LANGUAGE plpgsql AS $$\nDECLARE\n  a t.c%TYPE;\n  b a%TYPE;\n  c r.c%TYPE;\nBEGIN\n  PERFORM 1;\nEND $$",
			"CREATE FUNCTION auth.f(r t) RETURNS void LANGUAGE plpgsql AS $$\nDECLARE\n  a auth.t.c%TYPE;\n  b a%TYPE;\n  c r.c%TYPE;\nBEGIN\n  PERFORM 1;\nEND $$"},
		{"PL/pgSQL: PERFORM, INTO STRICT, RETURN QUERY, FOREACH", "auth", nil,
			"DO $$\nDECLARE x int; ids int[];\nBEGIN\n  PERFORM pg_sleep(0) FROM t;\n  SELECT id INTO STRICT x FROM t LIMIT 1;\n  FOREACH x IN ARRAY (SELECT array_agg(id) FROM t2) LOOP NULL; END LOOP;\nEND $$",
			"DO $$\nDECLARE x int; ids int[];\nBEGIN\n  PERFORM pg_sleep(0) FROM auth.t;\n  SELECT id INTO STRICT x FROM auth.t LIMIT 1;\n  FOREACH x IN ARRAY (SELECT array_agg(id) FROM auth.t2) LOOP NULL; END LOOP;\nEND $$"},
		{"identical statements on one line", "auth", nil,
			"DO $$ BEGIN INSERT INTO t VALUES (1); INSERT INTO t VALUES (1); END $$",
			"DO $$ BEGIN INSERT INTO auth.t VALUES (1); INSERT INTO auth.t VALUES (1); END $$"},
		{"temp table created earlier in the file", "auth", nil,
			"CREATE TEMP TABLE tmp (id int); INSERT INTO tmp SELECT id FROM t; DROP TABLE tmp",
			"CREATE TEMP TABLE tmp (id int); INSERT INTO tmp SELECT id FROM auth.t; DROP TABLE tmp"},
		{"exclusions via registry: types in function signatures", "auth", []string{"CREATE TYPE k AS ENUM ('a')"},
			"DROP FUNCTION f(k, int, text)",
			"DROP FUNCTION auth.f(auth.k, int, text)"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			got, _ := rewrite(t, c.schema, c.learn, c.in)
			if got != c.want {
				t.Errorf("\n got: %s\nwant: %s", got, c.want)
			}
		})
	}
}

func TestWarnings(t *testing.T) {
	cases := map[string]string{
		"DO $$ BEGIN EXECUTE 'DROP TABLE t'; END $$":                     "dynamic SQL",
		"SET search_path TO other":                                       "changes search_path",
		"SELECT set_config('search_path', 'x', true)":                    "changes search_path",
		"CREATE EXTENSION pgcrypto":                                      "CREATE EXTENSION without SCHEMA",
		"SELECT 1 FROM pg_type WHERE typname = 'x'":                      "system catalogs",
		"DO $$ BEGIN PERFORM 1 FROM pg_class WHERE relname = 't'; END $$": "system catalogs",
		"SELECT current_schema()":                                        "current_schema",
		"CREATE FUNCTION f() RETURNS int LANGUAGE plpython3u AS 'return 1'": "LANGUAGE plpython3u",
	}
	for sql, want := range cases {
		_, warns := rewrite(t, "auth", nil, sql)
		if !strings.Contains(strings.Join(warns, "\n"), want) {
			t.Errorf("%s: warnings %q do not mention %q", sql, warns, want)
		}
	}
}

func TestInvalidSQL(t *testing.T) {
	r, _ := New(Options{Schema: "auth"})
	if _, _, err := r.Rewrite("CREATE TABLE (id int"); err == nil {
		t.Fatal("expected a parse error")
	}
}
