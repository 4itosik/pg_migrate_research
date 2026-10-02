package oracle

import (
	"context"
	"strings"
	"testing"

	"github.com/4itosik/pg_migrate_research/pgschema"
	"github.com/4itosik/pg_migrate_research/pgschema/internal/parse"
	"github.com/4itosik/pg_migrate_research/poc/harness"
)

// TestParamMarkersRejectedByServer confirms docs/differences.md on a live
// server: libpg_query accepts a parameter marker in the place of a string
// constant, PostgreSQL itself and the library reject it.
func TestParamMarkersRejectedByServer(t *testing.T) {
	if !haveServer() {
		skipUnlessCI(t, "no PostgreSQL server: set PG_BIN or PG_DSN (tools/env.sh)")
	}
	ctx := context.Background()
	srv, err := harness.StartServer(ctx)
	if err != nil {
		t.Fatal(err)
	}
	defer srv.Stop()
	db, err := srv.NewDatabase(ctx, "param_markers")
	if err != nil {
		t.Fatal(err)
	}
	defer db.Drop(ctx)
	for _, sql := range []string{
		"SELECT a $1", "SELECT int $1", "SELECT interval $1", "CREATE ROLE param_marker_role PASSWORD $1",
		"SET search_path TO $1", "SET SCHEMA $1", "SET ROLE $1", "SET SESSION AUTHORIZATION $1",
	} {
		if _, err := Parse(sql); err != nil {
			t.Errorf("%q: libpg_query rejects it (%v): the class of differences is not what docs/differences.md says", sql, err)
		}
		if _, err := parse.Parse(sql); err == nil {
			t.Errorf("%q: the library accepts it", sql)
		}
		err := db.Exec(ctx, sql)
		if err == nil || !strings.Contains(err.Error(), "syntax error") {
			t.Errorf("%q: the server answers %v, want a syntax error", sql, err)
		}
	}
}

// TestRewriteImprovements runs on a live server the migrations that the
// prototype cannot rewrite and the library can (docs/differences.md): the
// rewritten functions must work with a search_path that does not contain the
// schema.
func TestRewriteImprovements(t *testing.T) {
	if !haveServer() {
		skipUnlessCI(t, "no PostgreSQL server: set PG_BIN or PG_DSN (tools/env.sh)")
	}
	ctx := context.Background()
	srv, err := harness.StartServer(ctx)
	if err != nil {
		t.Fatal(err)
	}
	defer srv.Stop()
	tests := []struct {
		name, up, query, want string
		// protoWrong: the prototype rewrites the migration and the result on
		// the server is not want
		protoWrong bool
	}{
		{
			name: "the list of WHEN of a CASE with a selector",
			up: `CREATE TABLE items (id int PRIMARY KEY);
INSERT INTO items VALUES (1), (2);
CREATE FUNCTION kind_of(x int) RETURNS text LANGUAGE plpgsql AS $$
BEGIN
  CASE x
    WHEN (SELECT max(id) FROM items) THEN RETURN 'last';
    ELSE RETURN 'other';
  END CASE;
END $$;`,
			query: "SELECT auth.kind_of(2) || auth.kind_of(1)",
			want:  "lastother",
		},
		{
			name: "a type keyword in a declaration is the type of pg_catalog",
			up: `CREATE DOMAIN varchar AS text;
CREATE FUNCTION f() RETURNS text LANGUAGE plpgsql AS $$
DECLARE c varchar = 'xyz';
BEGIN
  RETURN pg_typeof(c)::text;
END $$;`,
			query:      "SELECT auth.f()",
			want:       "character varying",
			protoWrong: true,
		},
		{
			name: "a variable named like a keyword",
			up: `CREATE TYPE mood AS ENUM ('sad', 'happy');
CREATE FUNCTION f() RETURNS text LANGUAGE plpgsql AS $$
DECLARE int mood := 'happy';
BEGIN
  RETURN int::text;
END $$;`,
			query: "SELECT auth.f()",
			want:  "happy",
		},
		{
			name: "a refcursor parameter",
			up: `CREATE TABLE t (id int);
INSERT INTO t VALUES (7);
CREATE FUNCTION return_refcursor(rc refcursor) RETURNS refcursor LANGUAGE plpgsql AS $$
BEGIN
  OPEN rc FOR SELECT id FROM t;
  RETURN rc;
END $$;`,
			query: "BEGIN; SELECT auth.return_refcursor('c'); FETCH ALL IN c",
			want:  "7",
		},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			proto, err := NewPrototype(PrototypeOptions{Schema: "auth"})
			if err != nil {
				t.Fatal(err)
			}
			if _, _, err := proto.Rewrite(tc.up); err == nil {
				t.Logf("the prototype rewrites this migration too")
			}
			r := newPair(t).our
			if err := r.Learn(tc.up); err != nil {
				t.Fatal(err)
			}
			out, _, err := r.Rewrite(tc.up)
			if err != nil {
				t.Fatalf("the library refuses: %v", err)
			}
			if tc.protoWrong {
				proto, err := NewPrototype(PrototypeOptions{Schema: "auth"})
				if err != nil {
					t.Fatal(err)
				}
				pout, _, err := proto.Rewrite(tc.up)
				if err != nil {
					t.Fatalf("the prototype refuses: %v", err)
				}
				pdb, err := srv.NewDatabase(ctx, "improvement_proto")
				if err != nil {
					t.Fatal(err)
				}
				defer pdb.Drop(ctx)
				if err := pdb.Exec(ctx, "CREATE SCHEMA auth; CREATE SCHEMA trap; SET search_path TO trap"); err != nil {
					t.Fatal(err)
				}
				if err := pdb.Exec(ctx, pout); err != nil {
					t.Fatalf("the prototype's output fails: %v", err)
				}
				if got, err := pdb.QueryStrings(ctx, tc.query); err != nil || len(got) == 0 || got[len(got)-1] == tc.want {
					t.Errorf("the prototype's output gives %v (%v), the point of the case is that it differs from %s", got, err, tc.want)
				}
			}
			db, err := srv.NewDatabase(ctx, "improvement")
			if err != nil {
				t.Fatal(err)
			}
			defer db.Drop(ctx)
			if err := db.Exec(ctx, "CREATE SCHEMA auth; CREATE SCHEMA trap; SET search_path TO trap"); err != nil {
				t.Fatal(err)
			}
			if err := db.Exec(ctx, out); err != nil {
				t.Fatalf("the rewritten migration fails: %v\n%s", err, out)
			}
			got, err := db.QueryStrings(ctx, tc.query)
			if err != nil {
				t.Fatalf("%s: %v", tc.query, err)
			}
			if len(got) == 0 || got[len(got)-1] != tc.want {
				t.Errorf("%s = %v, want %s", tc.query, got, tc.want)
			}
		})
	}
}

// TestExtensionSchemaOnServer shows what the option does to CREATE EXTENSION
// on a live server: without it the extension lands in the first schema of the
// search_path (here "trap", as behind a pooler it would be some schema of the
// connection), with it in the target schema.
func TestExtensionSchemaOnServer(t *testing.T) {
	if !haveServer() {
		skipUnlessCI(t, "no PostgreSQL server: set PG_BIN or PG_DSN (tools/env.sh)")
	}
	ctx := context.Background()
	srv, err := harness.StartServer(ctx)
	if err != nil {
		t.Fatal(err)
	}
	defer srv.Stop()
	for _, tc := range []struct {
		inSchema bool
		want     string
	}{{false, "trap"}, {true, "auth"}} {
		r, err := pgschema.New(pgschema.Options{Schema: "auth", ExtensionsInSchema: tc.inSchema})
		if err != nil {
			t.Fatal(err)
		}
		out, _, err := r.Rewrite("CREATE EXTENSION IF NOT EXISTS pgcrypto;")
		if err != nil {
			t.Fatal(err)
		}
		db, err := srv.NewDatabase(ctx, "extension_schema")
		if err != nil {
			t.Fatal(err)
		}
		if err := db.Exec(ctx, "CREATE SCHEMA auth; CREATE SCHEMA trap; SET search_path TO trap, public"); err != nil {
			t.Fatal(err)
		}
		if err := db.Exec(ctx, out); err != nil {
			t.Fatalf("%s: %v", out, err)
		}
		got, err := db.QueryStrings(ctx, "SELECT extnamespace::regnamespace::text FROM pg_extension WHERE extname = 'pgcrypto'")
		if err != nil || len(got) != 1 || got[0] != tc.want {
			t.Errorf("in schema %v: the extension is in %v (%v), want %s; statement %q", tc.inSchema, got, err, tc.want, out)
		}
		db.Drop(ctx)
	}
}
