package pgqrewrite

import (
	"os"
	"path/filepath"
	"sort"
	"strings"
	"testing"
)

// TestPlaceholder checks the build-time variant of the rewriter: migrations
// are rewritten once with a placeholder schema, and the service later only
// replaces the placeholder with the real schema, without a parser. The result
// must be exactly the output of rewriting with the real schema.
//
// The corpus always runs; REGRESS_DIR adds the PostgreSQL regression suite.
func TestPlaceholder(t *testing.T) {
	const placeholder = "pgschema_placeholder"
	type group struct {
		name  string
		learn []string // up migrations, or the statements of a regression file
		units []string // texts rewritten one by one
	}
	var groups []group
	corpus := os.Getenv("CORPUS_DIR")
	if corpus == "" {
		corpus = "../corpus"
	}
	cases, _ := filepath.Glob(filepath.Join(corpus, "*"))
	sort.Strings(cases)
	for _, c := range cases {
		files, _ := filepath.Glob(filepath.Join(c, "*.sql"))
		sort.Strings(files)
		g := group{name: filepath.Base(c)}
		for _, f := range files {
			b, err := os.ReadFile(f)
			if err != nil {
				t.Fatal(err)
			}
			switch {
			case strings.HasSuffix(f, ".up.sql"):
				g.learn = append(g.learn, string(b))
				g.units = append(g.units, string(b))
			case strings.HasSuffix(f, ".down.sql"):
				g.units = append(g.units, string(b))
			}
		}
		groups = append(groups, g)
	}
	if dir := os.Getenv("REGRESS_DIR"); dir != "" {
		files, _ := filepath.Glob(filepath.Join(dir, "*.sql"))
		sort.Strings(files)
		for _, f := range files {
			b, err := os.ReadFile(f)
			if err != nil {
				t.Fatal(err)
			}
			stmts := splitStatements(stripPsql(string(b)))
			groups = append(groups, group{name: filepath.Base(f), learn: stmts, units: stmts})
		}
	}

	// A keyword, mixed case and a space need quotes. Names with ' or $ are
	// not supported: the placeholder also sits inside string literals and
	// dollar-quoted function bodies.
	for _, schema := range []string{"auth", "Auth", "user", "my schema"} {
		var same, changed, refused, diffs int
		for _, g := range groups {
			direct, _ := New(Options{Schema: schema})
			tmpl, _ := New(Options{Schema: placeholder})
			for _, s := range g.learn {
				_ = direct.Learn(s)
				_ = tmpl.Learn(s)
			}
			for _, u := range g.units {
				want, _, errD := direct.Rewrite(u)
				out, _, errT := tmpl.Rewrite(u)
				switch {
				case errD != nil && errT != nil:
					refused++
				case errD != nil || errT != nil:
					diffs++
					t.Errorf("%s [%s]: direct error %v, placeholder error %v", g.name, schema, errD, errT)
				default:
					if got := strings.ReplaceAll(out, placeholder, quoteIdent(schema)); got != want {
						diffs++
						t.Errorf("%s [%s]: differs\nwant %q\ngot  %q", g.name, schema, want, got)
						continue
					}
					same++
					if want != u {
						changed++
					}
				}
			}
		}
		t.Logf("schema %-12q identical %d (rewritten %d), refused by both %d, different %d", schema, same, changed, refused, diffs)
	}
}
