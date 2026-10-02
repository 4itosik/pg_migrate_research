package oracle

import (
	"context"
	"fmt"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/golang-migrate/migrate/v4"
	_ "github.com/golang-migrate/migrate/v4/database/pgx/v5"
	_ "github.com/golang-migrate/migrate/v4/source/file"

	"github.com/4itosik/pg_migrate_research/pgschema"
	"github.com/4itosik/pg_migrate_research/pgschema/migratesrc"
	"github.com/4itosik/pg_migrate_research/poc/harness"
	"github.com/golang-migrate/migrate/v4/source"
)

// TestGolangMigrate runs the corpus through golang-migrate on a live
// PostgreSQL, as a service does: the migrations are templates written with
// the placeholder, migratesrc.Wrap gives them the schema, and the migrate
// library applies them with the pgx driver (one Query message per file). The
// schema it produces must be exactly what the directly rewritten migrations
// produce, and the down migrations must leave nothing in the schema.
func TestGolangMigrate(t *testing.T) {
	if !haveServer() {
		skipUnlessCI(t, "no PostgreSQL server: set PG_BIN or PG_DSN (tools/env.sh)")
	}
	if _, err := os.Stat(corpusDir()); err != nil {
		skipUnlessCI(t, "no corpus directory")
	}
	cases, err := harness.LoadCorpus(corpusDir())
	if err != nil {
		t.Fatal(err)
	}
	ctx := context.Background()
	srv, err := harness.StartServer(ctx)
	if err != nil {
		t.Fatal(err)
	}
	defer srv.Stop()

	passed := 0
	for _, c := range cases {
		if c.Meta.Expect == "limitation" || srv.Major() < c.Meta.MinServerVersion {
			continue
		}
		t.Run(c.Name, func(t *testing.T) {
			ok := runGolangMigrateCase(t, ctx, srv, c)
			if ok {
				passed++
			}
		})
	}
	t.Logf("%d cases applied through golang-migrate give the schema of direct rewriting", passed)
}

func runGolangMigrateCase(t *testing.T, ctx context.Context, srv *harness.Server, c harness.Case) bool {
	const schema = "auth"
	dir := t.TempDir()
	direct, err := pgschema.New(pgschema.Options{Schema: schema})
	if err != nil {
		t.Fatal(err)
	}
	tmpl, err := pgschema.New(pgschema.Options{Placeholder: true})
	if err != nil {
		t.Fatal(err)
	}
	for _, m := range c.Migrations {
		if err := direct.Learn(m.Up); err != nil {
			t.Fatal(err)
		}
		if err := tmpl.Learn(m.Up); err != nil {
			t.Fatal(err)
		}
	}
	type files struct{ up, down string }
	rewritten := make([]files, len(c.Migrations))
	for i, m := range c.Migrations {
		for _, f := range []struct {
			name, sql string
			to        *string
			rw        *pgschema.Rewriter
			write     bool
		}{
			{m.UpFile, m.Up, &rewritten[i].up, direct, false},
			{m.DownFile, m.Down, &rewritten[i].down, direct, false},
			{m.UpFile, m.Up, nil, tmpl, true},
			{m.DownFile, m.Down, nil, tmpl, true},
		} {
			out, _, err := f.rw.Rewrite(f.sql)
			if err != nil {
				if strings.Contains(err.Error(), plpgsqlPending) {
					t.Skip("waits for the PL/pgSQL extractor")
				}
				t.Fatalf("%s: %v", f.name, err)
			}
			if f.write {
				if err := os.WriteFile(filepath.Join(dir, f.name), []byte(out), 0o644); err != nil {
					t.Fatal(err)
				}
			} else {
				*f.to = out
			}
		}
	}

	// the schema after direct rewriting, applied with plain Exec
	dbDirect, err := srv.NewDatabase(ctx, "gm_direct_"+shortName(c.Name))
	if err != nil {
		t.Fatal(err)
	}
	defer dbDirect.Drop(ctx)
	prepare := func(db *harness.Database) {
		if err := db.Exec(ctx, "CREATE SCHEMA "+schema+"; CREATE SCHEMA trap"); err != nil {
			t.Fatal(err)
		}
		if c.Setup != "" {
			if err := db.Exec(ctx, c.Setup); err != nil {
				t.Fatalf("setup: %v", err)
			}
		}
	}
	prepare(dbDirect)
	for i, f := range rewritten {
		if err := dbDirect.Exec(ctx, f.up); err != nil {
			t.Fatalf("direct up %s: %v", c.Migrations[i].UpFile, err)
		}
	}
	want, err := dbDirect.DumpSchema(ctx, schema)
	if err != nil {
		t.Fatal(err)
	}
	want = withoutRestrict(want)

	// the same through golang-migrate, from the templates
	dbMigrate, err := srv.NewDatabase(ctx, "gm_migrate_"+shortName(c.Name))
	if err != nil {
		t.Fatal(err)
	}
	defer dbMigrate.Drop(ctx)
	prepare(dbMigrate)
	// the address of the server, as the session sees it
	conn, err := dbMigrate.QueryStrings(ctx, "SELECT current_user UNION ALL SELECT current_database() UNION ALL SELECT current_setting('port') UNION ALL SELECT split_part(current_setting('unix_socket_directories'), ',', 1)")
	if err != nil || len(conn) != 4 {
		t.Fatalf("server address: %v %v", conn, err)
	}
	u := url.URL{Scheme: "pgx5", User: url.User(conn[0]), Path: "/" + conn[1]}
	u.RawQuery = url.Values{"host": {conn[3]}, "port": {conn[2]}, "sslmode": {"disable"}}.Encode()

	src, err := source.Open("file://" + dir)
	if err != nil {
		t.Fatal(err)
	}
	m, err := migrate.NewWithSourceInstance("file", migratesrc.Wrap(src, schema), u.String())
	if err != nil {
		t.Fatal(err)
	}
	defer m.Close()
	if err := m.Up(); err != nil {
		t.Fatalf("migrate up: %v", err)
	}
	got, err := dbMigrate.DumpSchema(ctx, schema)
	if err != nil {
		t.Fatal(err)
	}
	if got = withoutRestrict(got); got != want {
		t.Errorf("the schema differs from the one of direct rewriting:\n%s", firstDiff(want, got))
	}
	if err := m.Down(); err != nil {
		t.Fatalf("migrate down: %v", err)
	}
	left, err := dbMigrate.QueryStrings(ctx, `
		SELECT c.relname FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = '`+schema+`'
		UNION ALL
		SELECT p.proname FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname = '`+schema+`'`)
	if err != nil {
		t.Fatal(err)
	}
	if len(left) > 0 {
		t.Errorf("objects left in %s after down: %s", schema, strings.Join(left, ", "))
	}
	return !t.Failed()
}

func shortName(s string) string {
	if len(s) > 20 {
		s = s[:20]
	}
	return strings.ToLower(s) + fmt.Sprint(time.Now().UnixNano()%100000)
}

// withoutRestrict drops the \restrict and \unrestrict lines of pg_dump: they
// carry a random token.
func withoutRestrict(dump string) string {
	var out []string
	for _, l := range strings.Split(dump, "\n") {
		if !strings.HasPrefix(l, `\restrict `) && !strings.HasPrefix(l, `\unrestrict `) {
			out = append(out, l)
		}
	}
	return strings.Join(out, "\n")
}
