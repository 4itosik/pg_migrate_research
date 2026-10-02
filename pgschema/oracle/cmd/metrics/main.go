// Command metrics writes the dataset and environment sections of the JSON
// metrics report. Stage tests add their own sections to the same file with
// oracle.UpdateMetrics.
//
//	go run ./cmd/metrics -out ../results/metrics.json
package main

import (
	"flag"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"runtime"
	"sort"
	"time"

	"github.com/4itosik/pg_migrate_research/pgschema/oracle"
	"github.com/4itosik/pg_migrate_research/poc/harness"
)

func main() {
	out := flag.String("out", "../results/metrics.json", "report path")
	corpus := flag.String("corpus", envOr("CORPUS_DIR", "../../poc/corpus"), "corpus directory")
	regress := flag.String("regress", os.Getenv("REGRESS_ROOT"), "directory with REL_NN_STABLE subdirectories")
	flag.Parse()

	if err := oracle.UpdateMetrics(*out, []string{"environment"}, map[string]any{
		"go":        runtime.Version(),
		"goos":      runtime.GOOS,
		"goarch":    runtime.GOARCH,
		"cpus":      runtime.NumCPU(),
		"generated": time.Now().UTC().Format(time.RFC3339),
	}); err != nil {
		log.Fatal(err)
	}

	cases, err := harness.LoadCorpus(*corpus)
	if err != nil {
		log.Fatal(err)
	}
	var files, bytes int
	for _, c := range cases {
		for _, m := range c.Migrations {
			files += 2
			bytes += len(m.Up) + len(m.Down)
		}
	}
	if err := oracle.UpdateMetrics(*out, []string{"dataset", "corpus"},
		map[string]any{"cases": len(cases), "migration_files": files, "bytes": bytes}); err != nil {
		log.Fatal(err)
	}

	// Without -regress the regress sections of an earlier run stay as they are.
	if *regress != "" {
		dirs, _ := filepath.Glob(filepath.Join(*regress, "REL_*_STABLE"))
		sort.Strings(dirs)
		for _, d := range dirs {
			rf, err := oracle.LoadRegress(d)
			if err != nil {
				log.Fatal(err)
			}
			stmts := 0
			for _, f := range rf {
				stmts += len(f.Statements)
			}
			acc := oracle.Accepted(rf)
			sec := map[string]any{"files": len(rf), "statements": stmts, "accepted_by_libpgq": len(acc)}
			if n := len(acc); n > 0 {
				nodes := make([]int, n)
				sum := 0
				for i, s := range acc {
					nodes[i] = oracle.CountNodes(s.Tree)
					sum += nodes[i]
				}
				sort.Ints(nodes)
				sec["nodes_per_statement"] = map[string]any{
					"mean": float64(sum) / float64(n), "median": nodes[n/2],
					"p90": nodes[n*9/10], "p99": nodes[n*99/100], "max": nodes[n-1],
				}
			}
			if err := oracle.UpdateMetrics(*out, []string{"dataset", "regress", filepath.Base(d)}, sec); err != nil {
				log.Fatal(err)
			}
		}
	}
	fmt.Println("wrote", *out)
}

func envOr(k, def string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return def
}
