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
	if code := run([]string{"rewrite", "-schema", "auth", "-src", src, "-dst", dst, "-check"}, &out, &errb); code != 1 {
		t.Fatalf("check of stale files: exit %d", code)
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
	if code := run([]string{"rewrite", "-schema", "auth", "-src", root, "-dst", filepath.Join(root, "out")}, &out, &errb); code != 1 || !strings.Contains(errb.String(), "001_bad.up.sql") {
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
	if code := run([]string{"rewrite", "-schema", "auth", "-src", src, "-dst", dst}, &out, &errb); code != 0 {
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
