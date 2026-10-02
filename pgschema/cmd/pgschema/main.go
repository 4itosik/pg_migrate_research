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
// write and exits with status 3 when a file is missing, different or not
// produced from the source, which is the check for CI that the generated files
// are up to date.
//
// The destination is written all or nothing as far as a file system allows:
// every file is rewritten in memory and written to a temporary file in the
// destination before the first one replaces its target by a rename, so a
// failure leaves the destination as it was. Each rename is atomic; the set of
// them is not, if the process dies in the middle. A rename replaces a symbolic
// link instead of writing through it. A migration in the destination that the
// source does not produce is an error, unless -prune removes it.
//
// The source must hold the migrations as .sql files: golang-migrate reads a
// migration with any extension, and such a file, or two files of one version
// and direction, is an error rather than a file the command skips.
//
// Names that already have a schema are left as they are. CREATE EXTENSION
// stays as written unless -extensions-in-schema adds SCHEMA to it. The uses of
// what an extension provides (digest(), uuid_generate_v4(), the type citext)
// get a schema only for the extensions named with -extension.
//
// Warnings (dynamic SQL, lookups in the system catalogs, SET search_path, ...)
// go to stderr; -fail-on-warning turns them into a failure.
//
// Exit status: 0 done, 1 an error, 2 wrong usage, 3 the destination is out
// of date (-check).
package main

import (
	"errors"
	"flag"
	"fmt"
	"io"
	"io/fs"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"

	"github.com/4itosik/pg_migrate_research/pgschema"
)

func main() { os.Exit(run(os.Args[1:], os.Stdout, os.Stderr)) }

// migrationFile is the pattern golang-migrate reads migrations by
// (source.Regex): version, name, direction, extension.
var migrationFile = regexp.MustCompile(`^([0-9]+)_(.*)\.(down|up)\.(.*)$`)

const usage = `usage: pgschema rewrite (-schema NAME | -placeholder) -src DIR -dst DIR [-exclude a,b] [-extensions-in-schema] [-extension name[=schema]] [-extension-objects name=a,b] [-check] [-prune] [-fail-on-warning]

exit status:
  0  done; with -check, -dst is up to date
  1  an error: a migration that does not parse, a warning with -fail-on-warning,
     a file that cannot be read or written, a migration in -src that is not
     NNN_name.up.sql or .down.sql or clashes with another one's version, a
     migration in -dst that -src does not produce (without -prune)
  2  wrong usage
  3  with -check: -dst is out of date (a file differs, is missing or is not
     produced from -src)

flags:
`

func run(args []string, stdout, stderr io.Writer) int {
	if len(args) == 0 || args[0] != "rewrite" {
		fmt.Fprint(stderr, strings.TrimSuffix(usage, "\nflags:\n"))
		return 2
	}
	fs := flag.NewFlagSet("rewrite", flag.ContinueOnError)
	fs.SetOutput(stderr)
	fs.Usage = func() {
		fmt.Fprint(stderr, usage)
		fs.PrintDefaults()
	}
	schema := fs.String("schema", "", "target schema")
	placeholder := fs.Bool("placeholder", false, "write templates with the placeholder instead of a schema")
	src := fs.String("src", "", "directory with the migrations")
	dst := fs.String("dst", "", "directory for the rewritten migrations")
	exclude := fs.String("exclude", "", "comma-separated relation names, as PostgreSQL stores them, that stay unqualified (they live in other schemas)")
	extensions := fs.Bool("extensions-in-schema", false, "add SCHEMA <schema> to CREATE EXTENSION statements that have none (by default they stay as written, with a warning)")
	extensionSchemas := map[string]string{}
	fs.Func("extension", "an extension and the schema it is installed in, name[=schema]; without a schema the target one. The uses of its functions and types in the migrations get that schema. Repeatable", func(v string) error {
		name, schema, _ := strings.Cut(v, "=")
		if name == "" {
			return errors.New("the extension name is empty")
		}
		extensionSchemas[name] = schema
		return nil
	})
	extensionObjects := map[string][]string{}
	fs.Func("extension-objects", "names of functions and types of an extension that the library does not know, name=a,b,c. Repeatable", func(v string) error {
		name, list, ok := strings.Cut(v, "=")
		if !ok || name == "" || list == "" {
			return errors.New("want name=a,b,c")
		}
		for _, n := range strings.Split(list, ",") {
			extensionObjects[name] = append(extensionObjects[name], strings.TrimSpace(n))
		}
		return nil
	})
	check := fs.Bool("check", false, "write nothing; exit with status 3 if the destination is not what the command would write")
	prune := fs.Bool("prune", false, "remove the migrations in the destination that the source does not produce (without it they are an error)")
	failOnWarning := fs.Bool("fail-on-warning", false, "exit with status 1 when there are warnings")
	if err := fs.Parse(args[1:]); err != nil {
		if errors.Is(err, flag.ErrHelp) {
			return 0
		}
		return 2
	}
	if fs.NArg() > 0 {
		fmt.Fprintf(stderr, "pgschema rewrite: unexpected argument %q: a boolean flag takes no separate value (-flag or -flag=true, not -flag true), and nothing follows the flags\n", fs.Arg(0))
		return 2
	}
	if *src == "" || *dst == "" || (*schema == "") == !*placeholder {
		fmt.Fprintln(stderr, "pgschema rewrite: -src, -dst and exactly one of -schema and -placeholder are required")
		return 2
	}
	if err := checkDirs(*src, *dst); err != nil {
		fmt.Fprintln(stderr, "pgschema rewrite:", err)
		return 2
	}
	var ex []string
	if *exclude != "" {
		for _, name := range strings.Split(*exclude, ",") {
			ex = append(ex, strings.TrimSpace(name))
		}
	}
	r, err := pgschema.New(pgschema.Options{Schema: *schema, Placeholder: *placeholder, ExcludeRelations: ex, ExtensionsInSchema: *extensions,
		Extensions: extensionSchemas, ExtensionObjects: extensionObjects})
	if err != nil {
		fmt.Fprintln(stderr, "pgschema:", err)
		return 2
	}
	files, problems, err := listMigrations(*src)
	if err != nil {
		fmt.Fprintln(stderr, "pgschema:", err)
		return 1
	}
	if len(problems) > 0 {
		for _, p := range problems {
			fmt.Fprintln(stderr, p)
		}
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
	if failed || (warned && *failOnWarning) {
		return 1
	}
	if *check {
		drift, ok := compareDir(*dst, out, stderr)
		switch {
		case !ok:
			return 1
		case drift:
			return 3
		}
		return 0
	}
	// the destination is generated, but a migration in it that the source
	// does not produce may be written by hand: it goes only with -prune
	foreign := staleFiles(*dst, out)
	if len(foreign) > 0 && !*prune {
		for _, f := range foreign {
			fmt.Fprintf(stderr, "%s: a migration in %s that %s does not produce\n", f, *dst, *src)
		}
		fmt.Fprintln(stderr, "pgschema: nothing written; -prune removes such files")
		return 1
	}
	if err := writeAll(*dst, files, out); err != nil {
		fmt.Fprintln(stderr, "pgschema:", err)
		return 1
	}
	for _, name := range foreign {
		if err := os.Remove(filepath.Join(*dst, name)); err != nil {
			fmt.Fprintln(stderr, "pgschema:", err)
			return 1
		}
	}
	fmt.Fprintf(stdout, "%d files written to %s", len(files), *dst)
	if len(foreign) > 0 {
		fmt.Fprintf(stdout, ", %d stale removed", len(foreign))
	}
	fmt.Fprintln(stdout)
	return 0
}

// writeAll writes the files to dir, all or nothing as far as a file system
// allows: every target is checked and every file is written to a temporary
// file in dir before the first one replaces its target by a rename. A failure
// before the renames removes the temporary files and leaves dir as it was. A
// rename replaces a symbolic link instead of writing through it.
func writeAll(dir string, names []string, out map[string]string) (err error) {
	for _, f := range names {
		fi, err := os.Lstat(filepath.Join(dir, f))
		switch {
		case err == nil && fi.IsDir():
			return fmt.Errorf("%s: a directory stands in %s where the file goes", f, dir)
		case err != nil && !errors.Is(err, fs.ErrNotExist):
			return err
		}
	}
	_, statErr := os.Stat(dir)
	created := errors.Is(statErr, fs.ErrNotExist)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return err
	}
	var temps []string
	defer func() {
		if err != nil {
			for _, t := range temps {
				os.Remove(t) // gone already if it was renamed
			}
			if created {
				os.Remove(dir) // only if nothing was renamed into it
			}
		}
	}()
	for _, f := range names {
		tmp, err := os.CreateTemp(dir, "."+f+".*.tmp")
		if err != nil {
			return err
		}
		temps = append(temps, tmp.Name())
		_, werr := tmp.WriteString(out[f])
		if err := errors.Join(werr, tmp.Close()); err != nil {
			return fmt.Errorf("%s: %w", f, err)
		}
		if err := os.Chmod(tmp.Name(), 0o644); err != nil {
			return fmt.Errorf("%s: %w", f, err)
		}
	}
	for i, f := range names {
		if err := os.Rename(temps[i], filepath.Join(dir, f)); err != nil {
			return fmt.Errorf("%s: %w (%d of %d files of %s are new, the others as they were)", f, err, i, len(names), dir)
		}
	}
	return nil
}

// checkDirs refuses a source and destination that are the same directory or
// one inside the other, after resolving symbolic links.
func checkDirs(src, dst string) error {
	if same, err := sameDir(src, dst); err == nil && same {
		return errors.New("-src and -dst must be different directories")
	}
	s, err := resolve(src)
	if err != nil {
		return err
	}
	d, err := resolve(dst)
	if err != nil {
		return err
	}
	switch {
	case s == d:
		return errors.New("-src and -dst must be different directories")
	case within(s, d):
		return fmt.Errorf("-src %s is inside -dst %s", src, dst)
	case within(d, s):
		return fmt.Errorf("-dst %s is inside -src %s", dst, src)
	}
	return nil
}

// resolve returns the absolute path of p with symbolic links resolved; the
// part of p that does not exist yet is kept as written.
func resolve(p string) (string, error) {
	p, err := filepath.Abs(p)
	if err != nil {
		return "", err
	}
	rest := ""
	for {
		r, err := filepath.EvalSymlinks(p)
		if err == nil {
			return filepath.Join(r, rest), nil
		}
		parent := filepath.Dir(p)
		if !errors.Is(err, fs.ErrNotExist) || parent == p {
			return "", err
		}
		rest = filepath.Join(filepath.Base(p), rest)
		p = parent
	}
}

// within reports whether path a is inside directory b; both are clean and
// absolute.
func within(a, b string) bool {
	rel, err := filepath.Rel(b, a)
	return err == nil && rel != "." && rel != ".." && !strings.HasPrefix(rel, ".."+string(filepath.Separator))
}

// sameDir reports whether two paths are the same existing directory.
func sameDir(a, b string) (bool, error) {
	ia, err := os.Stat(a)
	if err != nil {
		return false, err
	}
	ib, err := os.Stat(b)
	if err != nil {
		return false, err
	}
	return os.SameFile(ia, ib), nil
}

// listMigrations returns the migration files of dir ordered by version, and
// the files golang-migrate would read differently from this command: a
// migration that is not .sql, two migrations of one version and direction
// (golang-migrate refuses them), a version that does not fit in 64 bits
// (golang-migrate skips it).
func listMigrations(dir string) (files, problems []string, err error) {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return nil, nil, err
	}
	type key struct {
		version   uint64
		direction string
	}
	seen := map[key]string{}
	version := map[string]uint64{}
	for _, e := range entries {
		m := migrationFile.FindStringSubmatch(e.Name())
		if e.IsDir() || m == nil {
			continue
		}
		name := e.Name()
		if m[4] != "sql" {
			problems = append(problems, fmt.Sprintf("%s: golang-migrate reads it as a migration, but pgschema handles NNN_name.up.sql and .down.sql only: rename it or move it out of %s", name, dir))
			continue
		}
		v, err := strconv.ParseUint(m[1], 10, 64)
		if err != nil {
			problems = append(problems, fmt.Sprintf("%s: the version %s does not fit in 64 bits; golang-migrate skips such a file", name, m[1]))
			continue
		}
		k := key{v, m[3]}
		if other, dup := seen[k]; dup {
			problems = append(problems, fmt.Sprintf("%s: version %d has another %s migration, %s; golang-migrate refuses the directory", name, v, m[3], other))
			continue
		}
		seen[k] = name
		version[name] = v
		files = append(files, name)
	}
	sort.Slice(files, func(i, j int) bool {
		if vi, vj := version[files[i]], version[files[j]]; vi != vj {
			return vi < vj
		}
		return files[i] < files[j]
	})
	if len(files) == 0 && len(problems) == 0 {
		return nil, nil, fmt.Errorf("no migration files (NNN_name.up.sql, NNN_name.down.sql) in %s", dir)
	}
	return files, problems, nil
}

// compareDir reports the differences between the files of dir and want. drift
// is true when there are any; ok is false when a file could not be compared.
func compareDir(dir string, want map[string]string, stderr io.Writer) (drift, ok bool) {
	ok = true
	names := make([]string, 0, len(want))
	for f := range want {
		names = append(names, f)
	}
	sort.Strings(names)
	for _, f := range names {
		got, err := os.ReadFile(filepath.Join(dir, f))
		switch {
		case errors.Is(err, fs.ErrNotExist):
			fmt.Fprintf(stderr, "%s: missing in %s\n", f, dir)
			drift = true
		case err != nil:
			fmt.Fprintf(stderr, "%s: %v\n", f, err)
			ok = false
		case string(got) != want[f]:
			fmt.Fprintf(stderr, "%s: differs from what the command writes\n", f)
			drift = true
		}
	}
	for _, f := range staleFiles(dir, want) {
		fmt.Fprintf(stderr, "%s: stale, there is no such migration in the source\n", f)
		drift = true
	}
	return drift, ok
}

// staleFiles lists the files of dir that golang-migrate reads as migrations
// and that are not in want.
func staleFiles(dir string, want map[string]string) []string {
	var stale []string
	entries, _ := os.ReadDir(dir)
	for _, e := range entries {
		if _, in := want[e.Name()]; !e.IsDir() && migrationFile.MatchString(e.Name()) && !in {
			stale = append(stale, e.Name())
		}
	}
	return stale
}
