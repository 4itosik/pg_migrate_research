package main

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func write(t *testing.T, dir, name, text string) {
	t.Helper()
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, name), []byte(text), 0o644); err != nil {
		t.Fatal(err)
	}
}

func TestRewriteAndCheck(t *testing.T) {
	root := t.TempDir()
	src, dst := filepath.Join(root, "src"), filepath.Join(root, "dst")
	write(t, src, "001_users.up.sql", "CREATE TYPE mood AS ENUM ('a');\nCREATE TABLE users (id int, m mood); -- keep\n")
	write(t, src, "001_users.down.sql", "DROP TABLE users;\nDROP TYPE mood;\n")
	write(t, src, "010_more.up.sql", "ALTER TABLE users ADD COLUMN n text;\n")
	write(t, src, "README.md", "not a migration")

	var out, errb bytes.Buffer
	if code := run([]string{"rewrite", "-schema", "auth", "-src", src, "-dst", dst}, &out, &errb); code != 0 {
		t.Fatalf("exit %d: %s", code, errb.String())
	}
	b, err := os.ReadFile(filepath.Join(dst, "001_users.up.sql"))
	if err != nil {
		t.Fatal(err)
	}
	if want := "CREATE TYPE auth.mood AS ENUM ('a');\nCREATE TABLE auth.users (id int, m auth.mood); -- keep\n"; string(b) != want {
		t.Errorf("up file:\n%s\nwant\n%s", b, want)
	}
	if _, err := os.Stat(filepath.Join(dst, "README.md")); err == nil {
		t.Error("a file that is not a migration was copied")
	}

	// check: up to date
	out.Reset()
	errb.Reset()
	if code := run([]string{"rewrite", "-schema", "auth", "-src", src, "-dst", dst, "-check"}, &out, &errb); code != 0 {
		t.Fatalf("check of up-to-date files: exit %d: %s", code, errb.String())
	}
	// check: a changed source, a missing file, a stale file
	write(t, src, "010_more.up.sql", "ALTER TABLE users ADD COLUMN n text, ADD COLUMN k int;\n")
	write(t, dst, "020_old.up.sql", "SELECT 1;\n")
	if err := os.Remove(filepath.Join(dst, "001_users.down.sql")); err != nil {
		t.Fatal(err)
	}
	errb.Reset()
	if code := run([]string{"rewrite", "-schema", "auth", "-src", src, "-dst", dst, "-check"}, &out, &errb); code != 3 {
		t.Fatalf("check of stale files: exit %d, want 3 (out of date)", code)
	}
	for _, want := range []string{"010_more.up.sql: differs", "001_users.down.sql: missing", "020_old.up.sql: stale"} {
		if !strings.Contains(errb.String(), want) {
			t.Errorf("no %q in %q", want, errb.String())
		}
	}
}

func TestPlaceholderTemplates(t *testing.T) {
	root := t.TempDir()
	src, dst := filepath.Join(root, "src"), filepath.Join(root, "dst")
	write(t, src, "001_t.up.sql", "CREATE TABLE t (id serial);\nSELECT nextval('t_id_seq');\n")
	var out, errb bytes.Buffer
	if code := run([]string{"rewrite", "-placeholder", "-src", src, "-dst", dst}, &out, &errb); code != 0 {
		t.Fatalf("exit %d: %s", code, errb.String())
	}
	b, _ := os.ReadFile(filepath.Join(dst, "001_t.up.sql"))
	if !strings.Contains(string(b), "CREATE TABLE pgschema_placeholder.t") {
		t.Errorf("template: %s", b)
	}
}

func TestUsageAndErrors(t *testing.T) {
	var out, errb bytes.Buffer
	if code := run(nil, &out, &errb); code != 2 {
		t.Errorf("no arguments: exit %d", code)
	}
	if code := run([]string{"rewrite", "-src", "x", "-dst", "y"}, &out, &errb); code != 2 {
		t.Errorf("no schema: exit %d", code)
	}
	root := t.TempDir()
	write(t, root, "001_bad.up.sql", "CREATE TABLE (\n")
	errb.Reset()
	if code := run([]string{"rewrite", "-schema", "auth", "-src", root, "-dst", filepath.Join(t.TempDir(), "out")}, &out, &errb); code != 1 || !strings.Contains(errb.String(), "001_bad.up.sql") {
		t.Errorf("a syntax error: exit %d, %q", code, errb.String())
	}
}

func TestStaleFilesAreRemoved(t *testing.T) {
	root := t.TempDir()
	src, dst := filepath.Join(root, "src"), filepath.Join(root, "dst")
	write(t, src, "001_a.up.sql", "CREATE TABLE a (id int);\n")
	write(t, dst, "002_gone.up.sql", "SELECT 1;\n")
	write(t, dst, "notes.txt", "not a migration, stays")
	var out, errb bytes.Buffer
	if code := run([]string{"rewrite", "-schema", "auth", "-src", src, "-dst", dst, "-prune"}, &out, &errb); code != 0 {
		t.Fatalf("exit %d: %s", code, errb.String())
	}
	if _, err := os.Stat(filepath.Join(dst, "002_gone.up.sql")); err == nil {
		t.Error("the stale migration is still there")
	}
	if _, err := os.Stat(filepath.Join(dst, "notes.txt")); err != nil {
		t.Error("a file that is not a migration was removed")
	}
	if !strings.Contains(out.String(), "1 stale removed") {
		t.Errorf("output %q", out.String())
	}
}

func TestFailOnWarningWritesNothing(t *testing.T) {
	root := t.TempDir()
	src, dst := filepath.Join(root, "src"), filepath.Join(root, "dst")
	write(t, src, "001_a.up.sql", "SET search_path TO public;\n")
	var out, errb bytes.Buffer
	if code := run([]string{"rewrite", "-schema", "auth", "-src", src, "-dst", dst, "-fail-on-warning"}, &out, &errb); code != 1 {
		t.Fatalf("exit %d: %s", code, errb.String())
	}
	if _, err := os.Stat(dst); err == nil {
		t.Error("files were written although the command failed")
	}
	if !strings.Contains(errb.String(), "warning") {
		t.Errorf("no warning in %q", errb.String())
	}
}

func TestSameDirectoryAndHelpAndExclude(t *testing.T) {
	root := t.TempDir()
	write(t, root, "001_a.up.sql", "SELECT * FROM countries JOIN users ON true;\n")
	var out, errb bytes.Buffer
	if code := run([]string{"rewrite", "-schema", "auth", "-src", root, "-dst", root}, &out, &errb); code != 2 {
		t.Errorf("-src equal to -dst: exit %d", code)
	}
	if b, _ := os.ReadFile(filepath.Join(root, "001_a.up.sql")); string(b) != "SELECT * FROM countries JOIN users ON true;\n" {
		t.Errorf("the source was overwritten: %s", b)
	}
	if code := run([]string{"rewrite", "-h"}, &out, &errb); code != 0 {
		t.Errorf("-h: exit %d", code)
	}
	dst := filepath.Join(t.TempDir(), "out")
	if code := run([]string{"rewrite", "-schema", "auth", "-exclude", "countries, other", "-src", root, "-dst", dst}, &out, &errb); code != 0 {
		t.Fatalf("exit %d: %s", code, errb.String())
	}
	if b, _ := os.ReadFile(filepath.Join(dst, "001_a.up.sql")); string(b) != "SELECT * FROM countries JOIN auth.users ON true;\n" {
		t.Errorf("got %s", b)
	}
}

func TestExtensionsInSchemaFlag(t *testing.T) {
	root := t.TempDir()
	src := filepath.Join(root, "src")
	write(t, src, "001_ext.up.sql", "CREATE EXTENSION IF NOT EXISTS pgcrypto;\n")
	var out, errb bytes.Buffer
	for flagArgs, want := range map[string]string{
		"":                      "CREATE EXTENSION IF NOT EXISTS pgcrypto;\n",
		"-extensions-in-schema": "CREATE EXTENSION IF NOT EXISTS pgcrypto SCHEMA auth;\n",
	} {
		dst := filepath.Join(root, "dst"+flagArgs)
		args := []string{"rewrite", "-schema", "auth", "-src", src, "-dst", dst}
		if flagArgs != "" {
			args = append(args, flagArgs)
		}
		if code := run(args, &out, &errb); code != 0 {
			t.Fatalf("%q: exit %d: %s", flagArgs, code, errb.String())
		}
		if b, _ := os.ReadFile(filepath.Join(dst, "001_ext.up.sql")); string(b) != want {
			t.Errorf("%q: got %q, want %q", flagArgs, b, want)
		}
	}
}

func TestExtensionFlags(t *testing.T) {
	root := t.TempDir()
	src, dst := filepath.Join(root, "src"), filepath.Join(root, "dst")
	write(t, src, "001_a.up.sql", "CREATE EXTENSION pgcrypto;\nCREATE TABLE t (g geometry, h bytea DEFAULT digest('x', 'md5'), c citext, d float DEFAULT st_area(g));\n")
	var out, errb bytes.Buffer
	args := []string{"rewrite", "-schema", "auth", "-src", src, "-dst", dst,
		"-extension", "pgcrypto", "-extension", "citext=ext", "-extension", "postgis=ext", "-extension-objects", "postgis=geometry, st_area"}
	if code := run(args, &out, &errb); code != 0 {
		t.Fatalf("exit %d: %s", code, errb.String())
	}
	want := "CREATE EXTENSION pgcrypto SCHEMA auth;\nCREATE TABLE auth.t (g ext.geometry, h bytea DEFAULT auth.digest('x', 'md5'), c ext.citext, d float DEFAULT ext.st_area(g));\n"
	if b, _ := os.ReadFile(filepath.Join(dst, "001_a.up.sql")); string(b) != want {
		t.Errorf("got %q, want %q", b, want)
	}
	if code := run([]string{"rewrite", "-schema", "auth", "-src", src, "-dst", dst, "-extension", "=x"}, &out, &errb); code != 2 {
		t.Errorf("an empty extension name: exit %d", code)
	}
}

// TestStrayArgument: flag parsing stops at the first argument that is not a
// flag, so "-placeholder true -check" would silently drop -check and write.
func TestStrayArgument(t *testing.T) {
	root := t.TempDir()
	src, dst := filepath.Join(root, "s"), filepath.Join(root, "d")
	write(t, src, "001_a.up.sql", "CREATE TABLE a (id int);\n")
	var out, errb bytes.Buffer
	if code := run([]string{"rewrite", "-src", src, "-dst", dst, "-placeholder", "true", "-check"}, &out, &errb); code != 2 {
		t.Errorf("exit %d, want 2: %s", code, errb.String())
	}
	if !strings.Contains(errb.String(), `"true"`) {
		t.Errorf("the argument is not named: %q", errb.String())
	}
	if _, err := os.Stat(dst); err == nil {
		t.Error("files were written")
	}
}

// TestForeignFilesInDestination: a migration in -dst that -src does not
// produce may be written by hand; it is removed only with -prune.
func TestForeignFilesInDestination(t *testing.T) {
	root := t.TempDir()
	dst := filepath.Join(root, "d8")
	src := filepath.Join(root, "s8")
	write(t, src, "001_a.up.sql", "CREATE TABLE a (id int);\n")
	write(t, dst, "001_a.up.sql", "old\n")
	write(t, dst, "005_hand.up.sql", "SELECT 1;\n")
	write(t, dst, "006_hand.down.pgsql", "SELECT 2;\n") // golang-migrate reads it too
	var out, errb bytes.Buffer
	if code := run([]string{"rewrite", "-schema", "auth", "-src", src, "-dst", dst}, &out, &errb); code != 1 {
		t.Fatalf("exit %d, want 1: %s", code, errb.String())
	}
	for _, want := range []string{"005_hand.up.sql", "006_hand.down.pgsql", "-prune"} {
		if !strings.Contains(errb.String(), want) {
			t.Errorf("no %q in %q", want, errb.String())
		}
	}
	for name, want := range map[string]string{"001_a.up.sql": "old\n", "005_hand.up.sql": "SELECT 1;\n"} {
		if b, err := os.ReadFile(filepath.Join(dst, name)); err != nil || string(b) != want {
			t.Errorf("%s changed: %q, %v", name, b, err)
		}
	}
	errb.Reset()
	if code := run([]string{"rewrite", "-schema", "auth", "-src", src, "-dst", dst, "-prune"}, &out, &errb); code != 0 {
		t.Fatalf("-prune: exit %d: %s", code, errb.String())
	}
	for _, name := range []string{"005_hand.up.sql", "006_hand.down.pgsql"} {
		if _, err := os.Stat(filepath.Join(dst, name)); err == nil {
			t.Errorf("-prune left %s", name)
		}
	}
}

// TestNestedDirectories: -src inside -dst (or the reverse) is refused, also
// through a symbolic link.
func TestNestedDirectories(t *testing.T) {
	root := t.TempDir()
	d8 := filepath.Join(root, "d8")
	write(t, filepath.Join(d8, "raw"), "001_a.up.sql", "CREATE TABLE a (id int);\n")
	write(t, d8, "005_hand.up.sql", "SELECT 1;\n")
	link := filepath.Join(root, "link")
	if err := os.Symlink(d8, link); err != nil {
		t.Fatal(err)
	}
	var out, errb bytes.Buffer
	for _, c := range [][2]string{
		{filepath.Join(d8, "raw"), d8},                                      // -src inside -dst
		{d8, filepath.Join(d8, "out")},                                      // -dst inside -src, not created yet
		{filepath.Join(link, "raw"), d8},                                    // through a link
		{filepath.Join(d8, "raw"), link},                                    // through a link
		{filepath.Join(d8, "raw"), link + string(filepath.Separator) + "."}, // the same, spelled otherwise
	} {
		errb.Reset()
		if code := run([]string{"rewrite", "-schema", "auth", "-src", c[0], "-dst", c[1]}, &out, &errb); code != 2 {
			t.Errorf("-src %s -dst %s: exit %d, want 2: %s", c[0], c[1], code, errb.String())
		}
	}
	if _, err := os.Stat(filepath.Join(d8, "005_hand.up.sql")); err != nil {
		t.Error("the hand-written migration is gone")
	}
	if _, err := os.Stat(filepath.Join(d8, "out")); err == nil {
		t.Error("a directory was created")
	}
}

// TestSymlinkIsReplaced: a link in -dst is replaced by the file, the file it
// points to stays as it was.
func TestSymlinkIsReplaced(t *testing.T) {
	root := t.TempDir()
	s2, d2 := filepath.Join(root, "s2"), filepath.Join(root, "d2")
	write(t, s2, "001_a.up.sql", "CREATE TABLE a (id int);\n")
	if err := os.MkdirAll(d2, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink("../s2/001_a.up.sql", filepath.Join(d2, "001_a.up.sql")); err != nil {
		t.Fatal(err)
	}
	var out, errb bytes.Buffer
	if code := run([]string{"rewrite", "-schema", "auth", "-src", s2, "-dst", d2}, &out, &errb); code != 0 {
		t.Fatalf("exit %d: %s", code, errb.String())
	}
	if b, _ := os.ReadFile(filepath.Join(s2, "001_a.up.sql")); string(b) != "CREATE TABLE a (id int);\n" {
		t.Errorf("the source was overwritten through the link: %q", b)
	}
	fi, err := os.Lstat(filepath.Join(d2, "001_a.up.sql"))
	if err != nil || !fi.Mode().IsRegular() {
		t.Fatalf("not a regular file: %v, %v", fi, err)
	}
	if b, _ := os.ReadFile(filepath.Join(d2, "001_a.up.sql")); string(b) != "CREATE TABLE auth.a (id int);\n" {
		t.Errorf("got %q", b)
	}
}

// TestWriteAllOrNothing: a target that cannot be written leaves every file
// of -dst as it was, and no temporary files.
func TestWriteAllOrNothing(t *testing.T) {
	root := t.TempDir()
	src, d1 := filepath.Join(root, "s1"), filepath.Join(root, "d1")
	write(t, src, "001_a.up.sql", "CREATE TABLE a (id int);\n")
	write(t, src, "002_b.up.sql", "CREATE TABLE b (id int);\n")
	write(t, d1, "001_a.up.sql", "old\n")
	if err := os.MkdirAll(filepath.Join(d1, "002_b.up.sql"), 0o755); err != nil {
		t.Fatal(err)
	}
	var out, errb bytes.Buffer
	if code := run([]string{"rewrite", "-schema", "auth", "-src", src, "-dst", d1}, &out, &errb); code != 1 {
		t.Fatalf("exit %d, want 1: %s", code, errb.String())
	}
	if !strings.Contains(errb.String(), "002_b.up.sql") {
		t.Errorf("the file is not named: %q", errb.String())
	}
	if b, _ := os.ReadFile(filepath.Join(d1, "001_a.up.sql")); string(b) != "old\n" {
		t.Errorf("001_a.up.sql was written: %q", b)
	}
	entries, _ := os.ReadDir(d1)
	if len(entries) != 2 {
		t.Errorf("files left in -dst: %v", entries)
	}
	// -check calls such a target an error, not a stale directory
	errb.Reset()
	if code := run([]string{"rewrite", "-schema", "auth", "-src", src, "-dst", d1, "-check"}, &out, &errb); code != 1 {
		t.Errorf("-check: exit %d, want 1: %s", code, errb.String())
	}
}

// TestOtherExtensions: golang-migrate reads a migration with any extension;
// the CLI handles .sql only and must not skip the others silently.
func TestOtherExtensions(t *testing.T) {
	for _, name := range []string{"002_b.up.pgsql", "003_c.up.SQL", "004_d.down.sql.bak"} {
		root := t.TempDir()
		src := filepath.Join(root, "src")
		write(t, src, "001_a.up.sql", "CREATE TABLE a (id int);\n")
		write(t, src, name, "CREATE TABLE b (id int);\n")
		var out, errb bytes.Buffer
		if code := run([]string{"rewrite", "-schema", "auth", "-src", src, "-dst", filepath.Join(root, "dst")}, &out, &errb); code != 1 || !strings.Contains(errb.String(), name) {
			t.Errorf("%s: exit %d, %q", name, code, errb.String())
		}
	}
}

// TestVersionClashes: golang-migrate refuses two up (or two down) files of
// one version and skips a version that does not fit in 64 bits.
func TestVersionClashes(t *testing.T) {
	for _, names := range [][]string{
		{"1_a.up.sql", "001_b.up.sql"},
		{"2_a.down.sql", "02_a.down.sql"},
		{"99999999999999999999999_c.up.sql"},
	} {
		root := t.TempDir()
		src := filepath.Join(root, "src")
		write(t, src, "0003_x.up.sql", "CREATE TABLE x (id int);\n")
		for _, n := range names {
			write(t, src, n, "SELECT 1;\n")
		}
		var out, errb bytes.Buffer
		code := run([]string{"rewrite", "-schema", "auth", "-src", src, "-dst", filepath.Join(root, "dst")}, &out, &errb)
		if code != 1 {
			t.Errorf("%v: exit %d, want 1", names, code)
		}
		for _, n := range names {
			if !strings.Contains(errb.String(), n) {
				t.Errorf("%v: %s is not named in %q", names, n, errb.String())
			}
		}
	}
	// an up and a down file of one version are a pair, not a clash
	root := t.TempDir()
	src := filepath.Join(root, "src")
	write(t, src, "1_a.up.sql", "CREATE TABLE a (id int);\n")
	write(t, src, "001_a.down.sql", "DROP TABLE a;\n")
	var out, errb bytes.Buffer
	if code := run([]string{"rewrite", "-schema", "auth", "-src", src, "-dst", filepath.Join(root, "dst")}, &out, &errb); code != 0 {
		t.Errorf("up and down: exit %d: %s", code, errb.String())
	}
}

func TestByteOrderMark(t *testing.T) {
	root := t.TempDir()
	src := filepath.Join(root, "src")
	write(t, src, "001_bom.up.sql", "\xef\xbb\xbfCREATE TABLE a (id int);\n")
	var out, errb bytes.Buffer
	if code := run([]string{"rewrite", "-schema", "auth", "-src", src, "-dst", filepath.Join(root, "dst")}, &out, &errb); code != 1 {
		t.Fatalf("exit %d", code)
	}
	if !strings.Contains(errb.String(), "001_bom.up.sql: line 1, column 1:") || !strings.Contains(errb.String(), "byte order mark") {
		t.Errorf("got %q", errb.String())
	}
}

// TestCheckExitCodes: 0 up to date, 3 out of date, 1 an error, 2 usage.
func TestCheckExitCodes(t *testing.T) {
	root := t.TempDir()
	src, dst := filepath.Join(root, "src"), filepath.Join(root, "dst")
	write(t, src, "001_a.up.sql", "CREATE TABLE a (id int);\n")
	var out, errb bytes.Buffer
	if code := run([]string{"rewrite", "-schema", "auth", "-src", src, "-dst", dst, "-check"}, &out, &errb); code != 3 {
		t.Errorf("no -dst: exit %d, want 3", code)
	}
	write(t, src, "002_bad.up.sql", "CREATE TABLE (\n")
	if code := run([]string{"rewrite", "-schema", "auth", "-src", src, "-dst", dst, "-check"}, &out, &errb); code != 1 {
		t.Errorf("a syntax error: exit %d, want 1", code)
	}
	errb.Reset()
	if code := run([]string{"rewrite", "-h"}, &out, &errb); code != 0 || !strings.Contains(errb.String(), "exit status") {
		t.Errorf("-h: exit %d, %q", code, errb.String())
	}
}
