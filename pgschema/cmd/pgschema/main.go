// Command pgschema qualifies the object names of PostgreSQL migrations with a
// schema.
//
//	pgschema rewrite -schema auth -src migrations -dst migrations.auth
//	pgschema rewrite -placeholder -src migrations -dst migrations.tmpl
//	pgschema rewrite -schema auth -src migrations -dst migrations.auth -check
//
// It reads the files NNN_name.up.sql and NNN_name.down.sql of a golang-migrate
// source directory, learns the objects the up migrations create, rewrites every
// file by inserting the schema into the text and writes the results to the
// destination directory under the same names. Nothing but the schema is
// inserted: comments, formatting and quoting stay as written.
//
// With -placeholder the files are templates: the placeholder
// "pgschema_placeholder" stands where the schema goes, and a service puts the
// schema in when it reads a migration (package subst). With -check nothing is
// written: the command compares the destination directory with what it would
// write and exits with status 1 when a file is missing, different or stale,
// which is the check for CI that the generated files are up to date.
//
// Warnings (dynamic SQL, lookups in the system catalogs, SET search_path, ...)
// go to stderr; -fail-on-warning turns them into a failure.
package main

import (
	"flag"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"

	"github.com/4itosik/pg_migrate_research/pgschema"
)

func main() { os.Exit(run(os.Args[1:], os.Stdout, os.Stderr)) }

var migrationFile = regexp.MustCompile(`^(\d+)_.*\.(up|down)\.sql$`)

func run(args []string, stdout, stderr io.Writer) int {
	if len(args) == 0 || args[0] != "rewrite" {
		fmt.Fprintln(stderr, "usage: pgschema rewrite (-schema NAME | -placeholder) -src DIR -dst DIR [-exclude a,b] [-check] [-fail-on-warning]")
		return 2
	}
	fs := flag.NewFlagSet("rewrite", flag.ContinueOnError)
	fs.SetOutput(stderr)
	schema := fs.String("schema", "", "target schema")
	placeholder := fs.Bool("placeholder", false, "write templates with the placeholder instead of a schema")
	src := fs.String("src", "", "directory with the migrations")
	dst := fs.String("dst", "", "directory for the rewritten migrations")
	exclude := fs.String("exclude", "", "comma-separated relations that stay unqualified (they live in other schemas)")
	check := fs.Bool("check", false, "write nothing; fail if the destination is not what the command would write")
	failOnWarning := fs.Bool("fail-on-warning", false, "exit with status 1 when there are warnings")
	if err := fs.Parse(args[1:]); err != nil {
		return 2
	}
	if *src == "" || *dst == "" || (*schema == "") == !*placeholder {
		fmt.Fprintln(stderr, "pgschema rewrite: -src, -dst and exactly one of -schema and -placeholder are required")
		return 2
	}
	var ex []string
	if *exclude != "" {
		ex = strings.Split(*exclude, ",")
	}
	r, err := pgschema.New(pgschema.Options{Schema: *schema, Placeholder: *placeholder, ExcludeRelations: ex})
	if err != nil {
		fmt.Fprintln(stderr, "pgschema:", err)
		return 2
	}
	files, err := listMigrations(*src)
	if err != nil {
		fmt.Fprintln(stderr, "pgschema:", err)
		return 1
	}
	texts := map[string]string{}
	for _, f := range files {
		b, err := os.ReadFile(filepath.Join(*src, f))
		if err != nil {
			fmt.Fprintln(stderr, "pgschema:", err)
			return 1
		}
		texts[f] = string(b)
	}
	// the objects of all up migrations are known before any file is rewritten
	for _, f := range files {
		if strings.HasSuffix(f, ".up.sql") {
			if err := r.Learn(texts[f]); err != nil {
				fmt.Fprintf(stderr, "%s: %v\n", f, err)
				return 1
			}
		}
	}
	failed, warned := false, false
	out := map[string]string{}
	for _, f := range files {
		res, warns, err := r.Rewrite(texts[f])
		if err != nil {
			fmt.Fprintf(stderr, "%s: %v\n", f, err)
			failed = true
			continue
		}
		for _, w := range warns {
			fmt.Fprintf(stderr, "%s: warning: %s\n", f, w)
			warned = true
		}
		out[f] = res
	}
	if failed {
		return 1
	}
	if *check {
		if !compareDir(*dst, out, stderr) {
			return 1
		}
	} else {
		if err := os.MkdirAll(*dst, 0o755); err != nil {
			fmt.Fprintln(stderr, "pgschema:", err)
			return 1
		}
		for _, f := range files {
			if err := os.WriteFile(filepath.Join(*dst, f), []byte(out[f]), 0o644); err != nil {
				fmt.Fprintln(stderr, "pgschema:", err)
				return 1
			}
		}
		fmt.Fprintf(stdout, "%d files written to %s\n", len(files), *dst)
	}
	if warned && *failOnWarning {
		return 1
	}
	return 0
}

// listMigrations returns the migration files of dir ordered by version.
func listMigrations(dir string) ([]string, error) {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return nil, err
	}
	var files []string
	for _, e := range entries {
		if !e.IsDir() && migrationFile.MatchString(e.Name()) {
			files = append(files, e.Name())
		}
	}
	version := func(name string) uint64 {
		v, _ := strconv.ParseUint(migrationFile.FindStringSubmatch(name)[1], 10, 64)
		return v
	}
	sort.Slice(files, func(i, j int) bool {
		if vi, vj := version(files[i]), version(files[j]); vi != vj {
			return vi < vj
		}
		return files[i] < files[j]
	})
	if len(files) == 0 {
		return nil, fmt.Errorf("no migration files (NNN_name.up.sql, NNN_name.down.sql) in %s", dir)
	}
	return files, nil
}

// compareDir reports the differences between the files of dir and want, and
// returns true when there are none.
func compareDir(dir string, want map[string]string, stderr io.Writer) bool {
	ok := true
	for f, text := range want {
		got, err := os.ReadFile(filepath.Join(dir, f))
		switch {
		case err != nil:
			fmt.Fprintf(stderr, "%s: missing in %s\n", f, dir)
			ok = false
		case string(got) != text:
			fmt.Fprintf(stderr, "%s: differs from what the command writes\n", f)
			ok = false
		}
	}
	entries, _ := os.ReadDir(dir)
	for _, e := range entries {
		if _, in := want[e.Name()]; !e.IsDir() && migrationFile.MatchString(e.Name()) && !in {
			fmt.Fprintf(stderr, "%s: stale, there is no such migration in the source\n", e.Name())
			ok = false
		}
	}
	return ok
}
