package oracle

import (
	"os"
	"os/exec"
	"path/filepath"
	"testing"

	"github.com/4itosik/pg_migrate_research/poc/harness"
)

func haveServer() bool {
	if os.Getenv("PG_DSN") != "" || os.Getenv("PG_BIN") != "" {
		return true
	}
	if _, err := exec.LookPath("initdb"); err == nil {
		return true
	}
	m, _ := filepath.Glob("/usr/lib/postgresql/*/bin/initdb")
	return len(m) > 0
}

// TestPrototypeOnHarness wires the live PostgreSQL harness to the oracle: the
// prototype must pass the corpus the same way as in poc/pgquery. The harness
// takes CORPUS_DIR and RESULTS_DIR from the environment and needs the
// baseline schemas in $RESULTS_DIR/baseline-schema (TestBaseline in
// poc/harness writes them).
func TestPrototypeOnHarness(t *testing.T) {
	if !haveServer() {
		t.Skip("no PostgreSQL server: set PG_BIN or PG_DSN (tools/env.sh)")
	}
	if os.Getenv("CORPUS_DIR") == "" || os.Getenv("RESULTS_DIR") == "" {
		t.Skip("CORPUS_DIR and RESULTS_DIR are not set (tools/env.sh)")
	}
	if _, err := os.Stat(filepath.Join(os.Getenv("RESULTS_DIR"), "baseline-schema")); err != nil {
		t.Skip("no baseline schemas in $RESULTS_DIR: run tools/baseline.sh")
	}
	rep := harness.RunTest(t, harness.TestOptions{
		Config: harness.Config{
			Candidate: "oracle-prototype",
			Library:   "poc/pgquery (libpg_query via go-pgquery)",
			Mode:      harness.ModeRewrite,
			Factory:   PrototypeFactory,
		},
		Strict: true,
	})
	if rep.Passed() == 0 {
		t.Fatal("no case passed")
	}
}
