package harness

import (
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// TestOptions configures RunTest.
type TestOptions struct {
	Config
	// Strict fails the test for every failed case that is expected to pass.
	Strict bool
}

// RunTest runs the corpus (CORPUS_DIR, default ../corpus) and writes the
// report to RESULTS_DIR (default ../results). CASE=<substring> limits the run
// to matching cases and skips writing the report.
func RunTest(t *testing.T, opts TestOptions) Report {
	t.Helper()
	ctx := context.Background()
	corpusDir := envOr("CORPUS_DIR", "../corpus")
	resultsDir := envOr("RESULTS_DIR", "../results")
	cases, err := LoadCorpus(corpusDir)
	if err != nil {
		t.Fatal(err)
	}
	filter := os.Getenv("CASE")
	if filter != "" {
		var sel []Case
		for _, c := range cases {
			if strings.Contains(c.Name, filter) {
				sel = append(sel, c)
			}
		}
		cases = sel
	}
	srv, err := StartServer(ctx)
	if err != nil {
		t.Fatal(err)
	}
	defer srv.Stop()

	cfg := opts.Config
	if cfg.Mode == ModeRewrite && cfg.OutputDir == "" {
		cfg.OutputDir = filepath.Join(resultsDir, cfg.Candidate)
		if filter == "" {
			_ = os.RemoveAll(cfg.OutputDir)
		}
	}
	rep := Run(ctx, srv, cases, cfg)
	for _, r := range rep.Results {
		switch {
		case r.Status == "pass":
			t.Logf("PASS %s (%.1f ms)", r.Case, r.RewriteMS)
		default:
			t.Logf("FAIL %s [%s] %s", r.Case, r.Stage, r.Error)
		}
		for _, w := range r.Warnings {
			t.Logf("     warning: %s", w)
		}
		if opts.Strict && r.Status != "pass" && r.Expect == "pass" {
			t.Errorf("%s: %s: %s", r.Case, r.Stage, r.Error)
		}
	}
	t.Logf("%s: %d/%d cases passed on PostgreSQL %s", cfg.Candidate, rep.Passed(), len(rep.Results), rep.Server)
	if filter == "" {
		if err := WriteReport(filepath.Join(resultsDir, cfg.Candidate+".json"), rep); err != nil {
			t.Fatal(err)
		}
	}
	return rep
}

func envOr(k, def string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return def
}
