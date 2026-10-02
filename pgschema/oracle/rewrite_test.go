package oracle

import (
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"testing"

	"github.com/4itosik/pg_migrate_research/pgschema"
	"github.com/4itosik/pg_migrate_research/poc/harness"
)

// ours adapts the library's Rewriter to the live PostgreSQL harness.
func ours(schema string) (harness.Rewriter, error) {
	r, err := pgschema.New(pgschema.Options{Schema: schema})
	if err != nil {
		return nil, err
	}
	return HarnessAdapter{Learner: r.Learn, Rewriter: r.Rewrite}, nil
}

// TestRewriteOnHarness runs the corpus on a live PostgreSQL with the library:
// every case but the documented limitation must pass.
func TestRewriteOnHarness(t *testing.T) {
	if !haveServer() {
		skipUnlessCI(t, "no PostgreSQL server: set PG_BIN or PG_DSN (tools/env.sh)")
	}
	if os.Getenv("CORPUS_DIR") == "" || os.Getenv("RESULTS_DIR") == "" {
		skipUnlessCI(t, "CORPUS_DIR and RESULTS_DIR are not set (tools/env.sh)")
	}
	if _, err := os.Stat(filepath.Join(os.Getenv("RESULTS_DIR"), "baseline-schema")); err != nil {
		skipUnlessCI(t, "no baseline schemas in $RESULTS_DIR: run tools/baseline.sh")
	}
	rep := harness.RunTest(t, harness.TestOptions{
		Config: harness.Config{
			Candidate: "pgschema",
			Library:   "pgschema (own parser)",
			Mode:      harness.ModeRewrite,
			Factory:   ours,
		},
		Strict: true,
	})
	if rep.Passed() == 0 {
		t.Fatal("no case passed")
	}
}

// plpgsqlPending is the error of the library for a PL/pgSQL body until the
// extractor of stage 3 is wired in; the comparisons skip it.
const plpgsqlPending = "PL/pgSQL bodies are not supported yet"

// pair holds a prototype and a library rewriter with the same schema.
type pair struct {
	proto *Prototype
	our   *pgschema.Rewriter
}

func newPair(t testing.TB) pair {
	p, err := NewPrototype(PrototypeOptions{Schema: "auth"})
	if err != nil {
		t.Fatal(err)
	}
	o, err := pgschema.New(pgschema.Options{Schema: "auth"})
	if err != nil {
		t.Fatal(err)
	}
	return pair{p, o}
}

// TestRewriteCorpusVsPrototype rewrites every migration of the corpus with
// the prototype and with the library: the output and the warnings must be
// the same, byte for byte.
func TestRewriteCorpusVsPrototype(t *testing.T) {
	cases, err := harness.LoadCorpus(corpusDir())
	if err != nil {
		t.Fatal(err)
	}
	files, same, differ, pending := 0, 0, 0, 0
	for _, c := range cases {
		pr := newPair(t)
		for _, m := range c.Migrations {
			if err := pr.proto.Learn(m.Up); err != nil {
				t.Fatalf("%s: prototype learn: %v", c.Name, err)
			}
			_ = pr.our.Learn(m.Up)
		}
		for _, m := range c.Migrations {
			for _, f := range []struct{ name, sql string }{{m.UpFile, m.Up}, {m.DownFile, m.Down}} {
				files++
				want, wwarn, werr := pr.proto.Rewrite(f.sql)
				got, gwarn, gerr := pr.our.Rewrite(f.sql)
				switch {
				case werr != nil && c.Meta.Expect == "limitation":
					continue
				case werr != nil:
					t.Errorf("%s/%s: the prototype fails: %v", c.Name, f.name, werr)
				case gerr != nil && strings.Contains(gerr.Error(), plpgsqlPending):
					pending++
					t.Logf("%s/%s: waits for the PL/pgSQL extractor", c.Name, f.name)
				case gerr != nil:
					differ++
					t.Errorf("%s/%s: the library fails: %v", c.Name, f.name, gerr)
				case got != want:
					differ++
					t.Errorf("%s/%s: output differs:\n%s", c.Name, f.name, firstDiff(want, got))
				case strings.Join(gwarn, "\n") != strings.Join(wwarn, "\n"):
					differ++
					t.Errorf("%s/%s: warnings differ:\n  prototype: %q\n  library:   %q", c.Name, f.name, wwarn, gwarn)
				default:
					same++
				}
			}
		}
	}
	t.Logf("%d files: %d identical to the prototype, %d differ, %d wait for the PL/pgSQL extractor", files, same, differ, pending)
}

func firstDiff(want, got string) string {
	wl, gl := strings.Split(want, "\n"), strings.Split(got, "\n")
	for i := 0; i < len(wl) && i < len(gl); i++ {
		if wl[i] != gl[i] {
			return fmt.Sprintf("  line %d\n  prototype: %s\n  library:   %s", i+1, wl[i], gl[i])
		}
	}
	return fmt.Sprintf("  prototype has %d lines, library %d", len(wl), len(gl))
}

// TestRewriteRegress rewrites every statement of the regression tests that
// libpg_query accepts with the prototype and with the library (after
// Learn on the whole file, as the research did) and compares the outputs.
// REWRITE_VERSIONS selects the branches (default REL_16_STABLE), REWRITE_MAX
// the number of samples per group.
func TestRewriteRegress(t *testing.T) {
	root := os.Getenv("REGRESS_ROOT")
	if root == "" {
		skipUnlessCI(t, "REGRESS_ROOT is not set; run tools/get-data.sh and source tools/env.sh")
	}
	branches := []string{"REL_16_STABLE"}
	if v := os.Getenv("REWRITE_VERSIONS"); v != "" {
		branches = strings.Fields(v)
	}
	maxSamples := 3
	if v := os.Getenv("REWRITE_MAX"); v != "" {
		fmt.Sscan(v, &maxSamples)
	}
	for _, branch := range branches {
		t.Run(branch, func(t *testing.T) {
			files, err := LoadRegress(filepath.Join(root, branch))
			if err != nil {
				skipUnlessCI(t, err.Error())
			}
			var total, sameChanged, sameUnchanged, differ, onlyProto, onlyOurs, bothFail, pending int
			samples := map[string][]string{}
			note := func(kind, msg string) {
				if len(samples[kind]) < maxSamples {
					samples[kind] = append(samples[kind], msg)
				}
			}
			for _, f := range files {
				var accepted []string
				for _, s := range f.Statements {
					if _, err := Parse(s); err == nil {
						accepted = append(accepted, s)
					}
				}
				pr := newPair(t)
				for _, s := range accepted {
					_ = pr.proto.Learn(s)
					_ = pr.our.Learn(s)
				}
				for _, s := range accepted {
					total++
					want, _, werr := pr.proto.Rewrite(s)
					got, _, gerr := pr.our.Rewrite(s)
					switch {
					case werr != nil && gerr != nil:
						bothFail++
					case werr != nil:
						onlyOurs++
						note("only the library rewrites", fmt.Sprintf("%s: prototype: %.80s\n    %q", f.Name, strings.ReplaceAll(werr.Error(), "\n", " "), truncate(s, 100)))
					case gerr != nil && strings.Contains(gerr.Error(), plpgsqlPending):
						pending++
					case gerr != nil:
						onlyProto++
						note("only the prototype rewrites", fmt.Sprintf("%s: library: %.200s\n    %q", f.Name, strings.ReplaceAll(gerr.Error(), "\n", " "), truncate(s, 100)))
					case got != want:
						differ++
						note("outputs differ", fmt.Sprintf("%s:\n%s\n    %q", f.Name, firstDiff(want, got), truncate(s, 100)))
					case got != s:
						sameChanged++
					default:
						sameUnchanged++
					}
				}
			}
			t.Logf("%d statements: identical output %d (of them rewritten %d), outputs differ %d, only the library rewrites %d, only the prototype rewrites %d, both refuse %d, wait for the PL/pgSQL extractor %d",
				total, sameChanged+sameUnchanged, sameChanged, differ, onlyOurs, onlyProto, bothFail, pending)
			var kinds []string
			for k := range samples {
				kinds = append(kinds, k)
			}
			sort.Strings(kinds)
			for _, k := range kinds {
				for _, s := range samples[k] {
					t.Logf("%s: %s", k, s)
				}
			}
			if differ > 0 || onlyProto > 0 {
				if os.Getenv("CI") != "" {
					t.Errorf("%d outputs differ and %d statements are rewritten only by the prototype", differ, onlyProto)
				}
			}
		})
	}
}
