// Command buildmetrics measures the build of the library: the peak memory of
// the compiler on every package, the time of a clean build and the size of
// the CLI binary, and writes them to the "build" section of the metrics
// report. The peak memory comes from the -toolexec wrapper of
// poc/pgquery/wasm2go/maxrss, which it builds from the prototype.
//
//	go run ./cmd/buildmetrics -out ../results/metrics.json [-budgets]
package main

import (
	"flag"
	"fmt"
	"log"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/4itosik/pg_migrate_research/pgschema/oracle"
)

const modulePath = "github.com/4itosik/pg_migrate_research/pgschema"

var lineRe = regexp.MustCompile(`^(compile|link) (\S*) maxrss=(\d+)MB wall=([\d.]+)s$`)

func main() {
	out := flag.String("out", "../results/metrics.json", "metrics report")
	lib := flag.String("lib", "..", "library module directory")
	proto := flag.String("proto", "../../poc/pgquery", "prototype module directory, to build the maxrss tool")
	budgets := flag.Bool("budgets", false, "exit with an error when a budget of the task is exceeded")
	flag.Parse()

	tmp, err := os.MkdirTemp("", "buildmetrics")
	if err != nil {
		log.Fatal(err)
	}
	defer os.RemoveAll(tmp)
	tool := filepath.Join(tmp, "maxrss")
	run(*proto, nil, "go", "build", "-o", tool, "./wasm2go/maxrss")

	type step struct {
		pkg  string
		mb   int
		wall float64
	}
	// build runs a clean build (-a rebuilds the standard library too, as in an
	// empty build cache) under the maxrss wrapper and returns its duration, the
	// compile steps and the peak memory of the linker.
	build := func(name string, args ...string) (time.Duration, []step, int) {
		logFile := filepath.Join(tmp, name+".log")
		env := []string{"CGO_ENABLED=0", "MAXRSS_LOG=" + logFile}
		start := time.Now()
		run(*lib, env, "go", append([]string{"build", "-a", "-toolexec=" + tool}, args...)...)
		d := time.Since(start)
		b, err := os.ReadFile(logFile)
		if err != nil {
			log.Fatal(err)
		}
		var steps []step
		linkMB := 0
		for _, l := range regexp.MustCompile(`\n`).Split(string(b), -1) {
			m := lineRe.FindStringSubmatch(l)
			if m == nil {
				continue
			}
			mb, _ := strconv.Atoi(m[3])
			wall, _ := strconv.ParseFloat(m[4], 64)
			if m[1] == "link" {
				linkMB = max(linkMB, mb)
				continue
			}
			steps = append(steps, step{m[2], mb, wall})
		}
		return d, steps, linkMB
	}
	onlyLib := func(steps []step) (out []step) {
		for _, s := range steps {
			if len(s.pkg) >= len(modulePath) && s.pkg[:len(modulePath)] == modulePath {
				out = append(out, s)
			}
		}
		return out
	}
	peak := func(steps []step) (step, bool) {
		if len(steps) == 0 {
			return step{}, false
		}
		sort.Slice(steps, func(i, j int) bool { return steps[i].mb > steps[j].mb })
		return steps[0], true
	}

	clean, allSteps, linkMB := build("all", "./...")
	sec := map[string]any{
		"go_version":          runtimeVersion(),
		"clean_build_seconds": clean.Seconds(),
		"link_peak_mb":        linkMB,
	}
	if p, ok := peak(onlyLib(allSteps)); ok {
		sec["library_compile_peak_mb"] = p.mb
		sec["library_compile_peak_package"] = p.pkg
	}
	if p, ok := peak(allSteps); ok {
		sec["all_compile_peak_mb"] = p.mb
		sec["all_compile_peak_package"] = p.pkg
	}

	// the CLI: a clean build of the binary alone, then its size
	if _, err := os.Stat(filepath.Join(*lib, "cmd", "pgschema")); err == nil {
		bin := filepath.Join(tmp, "pgschema")
		d, steps, _ := build("cli", "-o", bin, "./cmd/pgschema")
		sec["cli_clean_build_seconds"] = d.Seconds()
		if p, ok := peak(steps); ok {
			sec["cli_compile_peak_mb"] = p.mb
			sec["cli_compile_peak_package"] = p.pkg
		}
		if fi, err := os.Stat(bin); err == nil {
			sec["cli_binary_mb"] = float64(fi.Size()) / (1 << 20)
		}
	}
	if *budgets {
		exceeded := false
		check := func(name string, got, max float64) {
			if got > max {
				fmt.Fprintf(os.Stderr, "budget exceeded: %s is %.1f, the budget is %.0f\n", name, got, max)
				exceeded = true
			}
		}
		if v, ok := sec["all_compile_peak_mb"].(int); ok {
			check("compiler peak memory on a package, MB", float64(v), 700)
		}
		if v, ok := sec["cli_clean_build_seconds"].(float64); ok {
			check("clean build of the CLI, s", v, 30)
		}
		if v, ok := sec["cli_binary_mb"].(float64); ok {
			check("CLI binary, MB", v, 15)
		}
		defer func() {
			if exceeded {
				os.Exit(1)
			}
		}()
	}
	if err := oracle.UpdateMetrics(*out, []string{"build"}, sec); err != nil {
		log.Fatal(err)
	}
	fmt.Printf("wrote %s: %v\n", *out, sec)
}

// runtimeVersion is the version of the go command that builds the library.
func runtimeVersion() string {
	out, err := exec.Command("go", "env", "GOVERSION").Output()
	if err != nil {
		return "unknown"
	}
	return strings.TrimSpace(string(out))
}

func run(dir string, env []string, name string, args ...string) {
	cmd := exec.Command(name, args...)
	cmd.Dir = dir
	cmd.Env = append(os.Environ(), env...)
	cmd.Stdout, cmd.Stderr = os.Stderr, os.Stderr
	if err := cmd.Run(); err != nil {
		log.Fatalf("%s %v in %s: %v", name, args, dir, err)
	}
}
