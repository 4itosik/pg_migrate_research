package oracle

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/4itosik/pg_migrate_research/pgschema"
	"github.com/4itosik/pg_migrate_research/pgschema/subst"
	"github.com/4itosik/pg_migrate_research/poc/harness"
)

// TestPlaceholder checks the build-time variant: migrations are rewritten
// once with the placeholder, and the service only replaces the placeholder
// with the schema, without a parser. The result must be exactly the output
// of rewriting with the schema itself, for the corpus (up and down files) and
// for the statements of the regression tests of PostgreSQL 16, with a plain
// schema, a mixed-case one, a keyword and a name with a space. The extensions
// option is on, so that SCHEMA is quoted the same way too.
func TestPlaceholder(t *testing.T) {
	type group struct {
		name  string
		learn []string // up migrations, or the statements of a regression file
		units []string // texts rewritten one by one
	}
	var groups []group
	cases, err := harness.LoadCorpus(corpusDir())
	if err != nil {
		t.Fatal(err)
	}
	for _, c := range cases {
		g := group{name: c.Name}
		for _, m := range c.Migrations {
			g.learn = append(g.learn, m.Up)
			g.units = append(g.units, m.Up, m.Down)
		}
		groups = append(groups, g)
	}
	if root := os.Getenv("REGRESS_ROOT"); root != "" {
		files, err := LoadRegress(filepath.Join(root, "REL_16_STABLE"))
		if err != nil {
			skipUnlessCI(t, err.Error())
		}
		for _, f := range files {
			var accepted []string
			for _, s := range f.Statements {
				if _, err := Parse(s); err == nil {
					accepted = append(accepted, s)
				}
			}
			groups = append(groups, group{name: f.Name, learn: accepted, units: accepted})
		}
	} else {
		skipUnlessCI(t, "REGRESS_ROOT is not set; the regression tests are not checked")
	}

	perSchema := map[string]any{}
	for _, schema := range []string{"auth", "Auth", "user", "my schema"} {
		var same, changed, refused, diffs int
		for _, g := range groups {
			direct, err := pgschema.New(pgschema.Options{Schema: schema, ExtensionsInSchema: true})
			if err != nil {
				t.Fatal(err)
			}
			tmpl, err := pgschema.New(pgschema.Options{Placeholder: true, ExtensionsInSchema: true})
			if err != nil {
				t.Fatal(err)
			}
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
					got, err := subst.Apply(out, schema)
					if err != nil {
						t.Fatal(err)
					}
					if got != want {
						diffs++
						t.Errorf("%s [%s]: differs\n%s", g.name, schema, firstDiff(want, got))
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
		perSchema[schema] = map[string]any{"identical": same, "rewritten": changed, "refused_by_both": refused, "different": diffs}
	}
	writeMetrics(t, []string{"stage5", "placeholder"}, perSchema)
}

// TestSubstRejects checks the schema names the substitution refuses.
func TestSubstRejects(t *testing.T) {
	for _, bad := range []string{"a'b", "a$b"} {
		if _, err := subst.Apply("pgschema_placeholder.t", bad); err == nil {
			t.Errorf("schema %q accepted", bad)
		}
	}
}
