package oracle

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"testing"
	"time"

	"github.com/4itosik/pg_migrate_research/pgschema/internal/ast"
	"github.com/4itosik/pg_migrate_research/pgschema/internal/parse"
	"github.com/4itosik/pg_migrate_research/poc/harness"
	pg "github.com/pganalyze/pg_query_go/v6"
)

// safeParse parses sql and turns a panic into an error: a panic in the
// parser is a defect to count, not a reason to stop the run.
func safeParse(sql string) (stmts int, err error) {
	defer func() {
		if r := recover(); r != nil {
			err = fmt.Errorf("panic: %v", r)
		}
	}()
	s, err := parse.Parse(sql)
	var ie *parse.InternalError
	if errors.As(err, &ie) {
		err = fmt.Errorf("panic: %v\n%s", ie.Value, ie.Stack)
	}
	return len(s), err
}

// TestParseAcceptance checks that the library parser accepts the statements
// libpg_query accepts and rejects those it rejects, on every statement of
// the regression tests of the versions in REGRESS_ROOT (PARSE_VERSIONS limits
// them, e.g. "REL_16_STABLE"). It does not look at the trees.
func TestParseAcceptance(t *testing.T) {
	root := os.Getenv("REGRESS_ROOT")
	if root == "" {
		skipUnlessCI(t, "REGRESS_ROOT is not set; run tools/get-data.sh and source tools/env.sh")
	}
	branches := []string{"REL_12_STABLE", "REL_13_STABLE", "REL_14_STABLE", "REL_15_STABLE", "REL_16_STABLE"}
	if v := os.Getenv("PARSE_VERSIONS"); v != "" {
		branches = strings.Fields(v)
	}
	report := map[string]any{}
	for _, branch := range branches {
		t.Run(branch, func(t *testing.T) {
			files, err := LoadRegress(filepath.Join(root, branch))
			if err != nil {
				skipUnlessCI(t, err.Error())
			}
			var theirsOK, oursOK, bothOK, onlyOurs, onlyTheirs, panics, bothRejected, errDiffs int
			var errSamples []string
			var samplesTheirs, samplesOurs []string
			byToken := map[string]int{}
			for _, f := range files {
				for i, s := range f.Statements {
					_, werr := Parse(s)
					_, gerr := safeParse(s)
					if gerr != nil && strings.HasPrefix(gerr.Error(), "panic") {
						panics++
					}
					switch {
					case werr != nil && gerr != nil:
						// both reject: the message and the cursor should agree too
						wmsg, wpos := ErrorInfo(werr)
						ge, _ := gerr.(*parse.Error)
						if ge == nil || ge.Msg != wmsg || ge.CursorPos(s) != wpos {
							errDiffs++
							if len(errSamples) < 8 {
								errSamples = append(errSamples, fmt.Sprintf("%s#%d: ours %q at %d, libpg_query %q at %d", f.Name, i, gerr, errPos(gerr, s), wmsg, wpos))
							}
						}
						bothRejected++
					case werr == nil && gerr == nil:
						theirsOK++
						oursOK++
						bothOK++
					case werr == nil:
						theirsOK++
						onlyTheirs++
						byToken[firstWords(gerr.Error())]++
						if len(samplesTheirs) < 15 {
							samplesTheirs = append(samplesTheirs, fmt.Sprintf("%s#%d: %v\n    %q", f.Name, i, gerr, truncate(s, 120)))
						}
					case gerr == nil:
						oursOK++
						onlyOurs++
						if len(samplesOurs) < 15 {
							samplesOurs = append(samplesOurs, fmt.Sprintf("%s#%d: libpg_query: %v\n    %q", f.Name, i, werr, truncate(s, 120)))
						}
					}
				}
			}
			t.Logf("libpg_query accepts %d; library accepts %d of them (%.2f%%), %d it rejects; library accepts %d that libpg_query rejects; panics %d",
				theirsOK, bothOK, 100*float64(bothOK)/float64(max(theirsOK, 1)), onlyTheirs, onlyOurs, panics)
			var keys []string
			for k := range byToken {
				keys = append(keys, k)
			}
			sort.Slice(keys, func(i, j int) bool { return byToken[keys[i]] > byToken[keys[j]] })
			for i, k := range keys {
				if i == 12 {
					break
				}
				t.Logf("  %5d  %s", byToken[k], k)
			}
			for _, s := range samplesTheirs {
				t.Log("rejected by the library: " + s)
			}
			for _, s := range samplesOurs {
				t.Log("accepted by the library: " + s)
			}
			t.Logf("rejected by both: %d, of them with a different message or cursor: %d", bothRejected, errDiffs)
			for _, e := range errSamples {
				t.Log("  error: " + e)
			}
			report[branch] = map[string]any{
				"rejected_by_both": bothRejected, "rejected_with_different_error": errDiffs,
				"accepted_by_libpg_query": theirsOK, "accepted_by_both": bothOK,
				"rejected_by_library": onlyTheirs, "accepted_only_by_library": onlyOurs, "panics": panics,
			}
			if onlyTheirs > 0 || onlyOurs > 0 || panics > 0 {
				t.Errorf("the acceptance differs: rejected by the library %d, accepted only by the library %d, panics %d", onlyTheirs, onlyOurs, panics)
			}
		})
	}
	if out := os.Getenv("METRICS_OUT"); out != "" && !t.Failed() {
		if err := UpdateMetrics(out, []string{"stage2", "parser", "acceptance"}, report); err != nil {
			t.Fatal(err)
		}
	}
	_ = harness.ModeRewrite
}

// firstWords is the message of a syntax error without the quoted text, to
// group the errors.
func firstWords(msg string) string {
	if i := strings.Index(msg, " at or near"); i >= 0 {
		return msg[:i] + " near " + nearToken(msg[i:])
	}
	return msg
}

func nearToken(s string) string {
	i := strings.IndexByte(s, '"')
	if i < 0 {
		return ""
	}
	s = s[i+1:]
	if j := strings.IndexAny(s, " \t\n\"("); j > 0 {
		return s[:j]
	}
	return s
}

// TestParseSpeed times the library parser on the statements of the
// PostgreSQL 16 regression tests that libpg_query accepts, the figure of the
// budget "average parse of a statement", and writes it to the report.
func TestParseSpeed(t *testing.T) {
	root := os.Getenv("REGRESS_ROOT")
	if root == "" {
		skipUnlessCI(t, "REGRESS_ROOT is not set; run tools/get-data.sh and source tools/env.sh")
	}
	files, err := LoadRegress(filepath.Join(root, "REL_16_STABLE"))
	if err != nil {
		skipUnlessCI(t, err.Error())
	}
	var stmts []string
	for _, s := range Accepted(files) {
		stmts = append(stmts, s.SQL)
	}
	// the first parse in the process, then the average of the best of five runs
	start := time.Now()
	if _, err := safeParse(stmts[0]); err != nil {
		t.Logf("first statement: %v", err)
	}
	first := time.Since(start)
	best := time.Duration(1<<63 - 1)
	for run := 0; run < 5; run++ {
		start := time.Now()
		for _, s := range stmts {
			safeParse(s)
		}
		if d := time.Since(start); d < best {
			best = d
		}
	}
	per := float64(best.Nanoseconds()) / float64(len(stmts)) / 1000
	t.Logf("%d statements: %.2f us per statement; the first parse in the process took %s", len(stmts), per, first.Round(time.Microsecond))
	if out := os.Getenv("METRICS_OUT"); out != "" {
		err := UpdateMetrics(out, []string{"stage2", "parser", "speed_pg16"}, map[string]any{
			"statements": len(stmts), "us_per_statement": per, "first_parse_us": float64(first.Nanoseconds()) / 1000,
		})
		if err != nil {
			t.Fatal(err)
		}
	}
}

// TestParseTrees compares the trees of the library parser with those of
// libpg_query, field by field with the locations, on the statements of the
// corpus and of the regression tests that libpg_query accepts. It is the
// measure of how much of the grammar actions is ported: the differences are
// grouped by the statement type and the path of the field that differs.
//
//	PARSE_VERSIONS  regression test branches, default REL_16_STABLE
//	PARSE_STMT      regexp on the node type of the statement, e.g. ^CreateStmt$;
//	                with it the test only reports and does not fail
//
// Any difference fails the test.
//
//	PARSE_MAX       samples to print per group of differences (default 1)
func TestParseTrees(t *testing.T) {
	var sources []Statement
	// the corpus
	cases, err := harness.LoadCorpus(corpusDir())
	if err != nil {
		t.Fatal(err)
	}
	for _, c := range cases {
		var texts []string
		for _, m := range c.Migrations {
			texts = append(texts, m.Up, m.Down)
		}
		texts = append(texts, c.Setup, c.Check)
		for _, text := range texts {
			for _, s := range SplitStatements(text) {
				if tree, err := Parse(s); err == nil {
					sources = append(sources, Statement{File: "corpus/" + c.Name, SQL: s, Tree: tree})
				}
			}
		}
	}
	branchesUsed := []string{}
	root := os.Getenv("REGRESS_ROOT")
	if root == "" {
		skipUnlessCI(t, "REGRESS_ROOT is not set; run tools/get-data.sh and source tools/env.sh")
	}
	if root != "" {
		branches := []string{"REL_16_STABLE"}
		if v := os.Getenv("PARSE_VERSIONS"); v != "" {
			branches = strings.Fields(v)
		}
		branchesUsed = branches
		for _, b := range branches {
			files, err := LoadRegress(filepath.Join(root, b))
			if err != nil {
				skipUnlessCI(t, err.Error())
			}
			for _, s := range Accepted(files) {
				s.File = b + "/" + s.File
				sources = append(sources, s)
			}
		}
	}
	var filter *regexp.Regexp
	if v := os.Getenv("PARSE_STMT"); v != "" {
		filter = regexp.MustCompile(v)
	}
	maxSamples := 1
	if v := os.Getenv("PARSE_MAX"); v != "" {
		fmt.Sscan(v, &maxSamples)
	}

	type group struct {
		count   int
		samples []string
	}
	groups := map[string]*group{}
	total, equal := 0, 0
	indexRe := regexp.MustCompile(`\[\d+\]`)
	for _, s := range sources {
		stmtType := ""
		if len(s.Tree.Stmts) > 0 {
			if st := s.Tree.Stmts[0].Stmt; st != nil {
				stmtType = string(st.ProtoReflect().WhichOneof(st.ProtoReflect().Descriptor().Oneofs().ByName("node")).Message().Name())
			}
		}
		if filter != nil && !filter.MatchString(stmtType) {
			continue
		}
		total++
		stmts, perr := parse.Parse(s.SQL)
		var key, what string
		switch {
		case perr != nil:
			key, what = "error: "+firstWords(perr.Error()), perr.Error()
		default:
			d := safeDiff(stmts, s.Tree)
			if d == nil {
				equal++
				continue
			}
			key = indexRe.ReplaceAllString(d.Path, "[]")
			what = d.String()
		}
		g := groups[key]
		if g == nil {
			g = &group{}
			groups[key] = g
		}
		g.count++
		if len(g.samples) < maxSamples {
			g.samples = append(g.samples, fmt.Sprintf("%s: %s\n        %s", s.File, what, truncate(strings.ReplaceAll(s.SQL, "\n", " "), 140)))
		}
	}
	t.Logf("%d statements compared, %d equal (%.2f%%), %d differ in %d groups", total, equal, 100*float64(equal)/float64(max(total, 1)), total-equal, len(groups))
	keys := make([]string, 0, len(groups))
	for k := range groups {
		keys = append(keys, k)
	}
	sort.Slice(keys, func(i, j int) bool {
		if groups[keys[i]].count != groups[keys[j]].count {
			return groups[keys[i]].count > groups[keys[j]].count
		}
		return keys[i] < keys[j]
	})
	for _, k := range keys {
		g := groups[k]
		t.Logf("%5d  %s", g.count, k)
		for _, s := range g.samples {
			t.Logf("        %s", s)
		}
	}
	if filter == nil && equal != total {
		t.Errorf("%d of %d trees differ", total-equal, total)
	}
	if out := os.Getenv("METRICS_OUT"); out != "" && filter == nil {
		err := UpdateMetrics(out, []string{"stage2", "parser", "trees"}, map[string]any{
			"versions": branchesUsed, "statements": total, "equal": equal, "groups": len(groups),
		})
		if err != nil {
			t.Fatal(err)
		}
	}
}

// safeDiff compares two trees and turns a panic of the comparison, which a
// half-built tree can cause, into a difference.
func safeDiff(ours []*ast.RawStmt, theirs *pg.ParseResult) (d *Diff) {
	defer func() {
		if r := recover(); r != nil {
			d = &Diff{Path: "comparison", Ours: fmt.Sprintf("panic: %v", r), Theirs: ""}
		}
	}()
	return DiffStatements(ours, theirs)
}

func errPos(err error, src string) int {
	if e, ok := err.(*parse.Error); ok {
		return e.CursorPos(src)
	}
	return 0
}
