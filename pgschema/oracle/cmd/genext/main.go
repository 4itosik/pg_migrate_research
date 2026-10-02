// Command genext writes ../extensions_gen.go: the names of the functions,
// types and relations that the extensions of PostgreSQL's contrib provide,
// read from live servers. The rewriter uses them to put a schema on the uses
// of an extension in SQL.
//
// Every extension that the server offers is installed in a database of its
// own, and what pg_depend says it owns is recorded. Names that exist in
// pg_catalog on some server are left out: a function that was in pgcrypto
// until PostgreSQL 12 and is in the core since 13 (gen_random_uuid) must not
// get the schema of the extension. The names are the union over the servers.
//
//	. ../tools/env.sh && go run ./cmd/genext -versions "12 13 14 15 16" -out ../extensions_gen.go
package main

import (
	"bytes"
	"context"
	"flag"
	"fmt"
	"go/format"
	"log"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"github.com/4itosik/pg_migrate_research/poc/harness"
)

type objects struct {
	funcs, types, rels map[string]bool
	ops                bool // the extension has operators
}

func newObjects() *objects {
	return &objects{funcs: map[string]bool{}, types: map[string]bool{}, rels: map[string]bool{}}
}

func main() {
	out := flag.String("out", "../extensions_gen.go", "output file")
	versions := flag.String("versions", "12 13 14 15 16", "PostgreSQL major versions, their servers are under $PG_ROOT/<major>")
	flag.Parse()
	root := os.Getenv("PG_ROOT")
	if root == "" {
		log.Fatal("PG_ROOT is not set: . tools/env.sh")
	}
	ctx := context.Background()
	core := newObjects()
	byExt := map[string]*objects{}
	for _, v := range strings.Fields(*versions) {
		if err := os.Setenv("PG_BIN", filepath.Join(root, v, "bin")); err != nil {
			log.Fatal(err)
		}
		collect(ctx, v, core, byExt)
	}
	b := render(core, byExt)
	src, err := format.Source(b)
	if err != nil {
		log.Fatalf("%v\n%s", err, b)
	}
	if err := os.WriteFile(*out, src, 0o644); err != nil {
		log.Fatal(err)
	}
	log.Printf("wrote %s: %d extensions", *out, len(byExt))
}

func collect(ctx context.Context, version string, core *objects, byExt map[string]*objects) {
	srv, err := harness.StartServer(ctx)
	if err != nil {
		log.Fatal(err)
	}
	defer srv.Stop()

	db, err := srv.NewDatabase(ctx, "genext_core")
	if err != nil {
		log.Fatal(err)
	}
	// what the core provides, before any extension is installed
	add(core, rows(ctx, db, `
		SELECT 'f|' || proname FROM pg_proc WHERE pronamespace = 'pg_catalog'::regnamespace
		UNION SELECT 't|' || typname FROM pg_type WHERE typnamespace = 'pg_catalog'::regnamespace
		UNION SELECT 'r|' || relname FROM pg_class WHERE relnamespace = 'pg_catalog'::regnamespace`))
	names := rows(ctx, db, "SELECT name FROM pg_available_extensions ORDER BY name")
	db.Drop(ctx)

	installed := 0
	for _, name := range names {
		ext, err := srv.NewDatabase(ctx, "genext_x")
		if err != nil {
			log.Fatal(err)
		}
		if err := ext.Exec(ctx, "CREATE EXTENSION "+quote(name)+" CASCADE"); err != nil {
			// the procedural languages and the like are not installed here
			ext.Drop(ctx)
			continue
		}
		installed++
		o := byExt[name]
		if o == nil {
			o = newObjects()
			byExt[name] = o
		}
		add(o, rows(ctx, ext, fmt.Sprintf(`
			SELECT 'f|' || p.proname FROM pg_depend d
			  JOIN pg_extension e ON e.oid = d.refobjid AND d.refclassid = 'pg_extension'::regclass
			  JOIN pg_proc p ON d.classid = 'pg_proc'::regclass AND d.objid = p.oid
			 WHERE e.extname = %[1]s AND d.deptype = 'e'
			UNION
			SELECT 't|' || t.typname FROM pg_depend d
			  JOIN pg_extension e ON e.oid = d.refobjid AND d.refclassid = 'pg_extension'::regclass
			  JOIN pg_type t ON d.classid = 'pg_type'::regclass AND d.objid = t.oid
			 WHERE e.extname = %[1]s AND d.deptype = 'e' AND t.typcategory <> 'A'
			   AND (t.typrelid = 0 OR (SELECT relkind FROM pg_class WHERE oid = t.typrelid) = 'c')
			UNION
			SELECT 'r|' || c.relname FROM pg_depend d
			  JOIN pg_extension e ON e.oid = d.refobjid AND d.refclassid = 'pg_extension'::regclass
			  JOIN pg_class c ON d.classid = 'pg_class'::regclass AND d.objid = c.oid
			 WHERE e.extname = %[1]s AND d.deptype = 'e' AND c.relkind IN ('r', 'v', 'm', 'f', 'S')
			UNION
			SELECT 'o|' || o.oprname FROM pg_depend d
			  JOIN pg_extension e ON e.oid = d.refobjid AND d.refclassid = 'pg_extension'::regclass
			  JOIN pg_operator o ON d.classid = 'pg_operator'::regclass AND d.objid = o.oid
			 WHERE e.extname = %[1]s AND d.deptype = 'e'`, literal(name))))
		ext.Drop(ctx)
	}
	log.Printf("PostgreSQL %s: %d of %d extensions installed", version, installed, len(names))
}

func rows(ctx context.Context, db *harness.Database, q string) []string {
	r, err := db.QueryStrings(ctx, q)
	if err != nil {
		log.Fatalf("%v\n%s", err, q)
	}
	return r
}

func add(o *objects, rows []string) {
	for _, r := range rows {
		kind, name, ok := strings.Cut(r, "|")
		if !ok {
			continue
		}
		switch kind {
		case "f":
			o.funcs[name] = true
		case "t":
			o.types[name] = true
		case "r":
			o.rels[name] = true
		case "o":
			o.ops = true
		}
	}
}

func quote(s string) string   { return `"` + strings.ReplaceAll(s, `"`, `""`) + `"` }
func literal(s string) string { return `'` + strings.ReplaceAll(s, `'`, `''`) + `'` }

func sorted(m map[string]bool, drop map[string]bool) []string {
	var out []string
	for k := range m {
		if !drop[k] {
			out = append(out, k)
		}
	}
	sort.Strings(out)
	return out
}

func render(core *objects, byExt map[string]*objects) []byte {
	var exts []string
	for e := range byExt {
		exts = append(exts, e)
	}
	sort.Strings(exts)
	var b bytes.Buffer
	b.WriteString(`// Code generated by oracle/cmd/genext; DO NOT EDIT.

// This file lists what the extensions of PostgreSQL's contrib provide, as the
// servers of PostgreSQL 12-16 report it (pg_depend).
//
// Portions Copyright (c) 1996-2024, PostgreSQL Global Development Group
// Portions Copyright (c) 1994, Regents of the University of California
//
// PostgreSQL License: see LICENSE.PostgreSQL.

package pgschema

// contribObjects are the names of the functions (and aggregates), types and
// relations of every contrib extension that could be installed, without the
// names that the core has in pg_catalog, and whether it has operators.
var contribObjects = map[string]extensionObjects{
`)
	empty := 0
	for _, e := range exts {
		o := byExt[e]
		f, t, r := sorted(o.funcs, core.funcs), sorted(o.types, core.types), sorted(o.rels, core.rels)
		if len(f)+len(t)+len(r) == 0 && !o.ops {
			empty++
			continue
		}
		fmt.Fprintf(&b, "\t%q: {\n", e)
		if o.ops {
			b.WriteString("\t\tops: true,\n")
		}
		for _, f := range []struct {
			name string
			v    []string
		}{{"funcs", f}, {"types", t}, {"rels", r}} {
			if len(f.v) == 0 {
				continue
			}
			fmt.Fprintf(&b, "\t\t%s: []string{", f.name)
			for i, n := range f.v {
				if i > 0 {
					b.WriteString(", ")
				}
				fmt.Fprintf(&b, "%q", n)
			}
			b.WriteString("},\n")
		}
		b.WriteString("\t},\n")
	}
	b.WriteString("}\n")
	return b.Bytes()
}
