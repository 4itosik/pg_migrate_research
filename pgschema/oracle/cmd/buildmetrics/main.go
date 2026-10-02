// Command buildmetrics measures the build of the library: the peak memory of
// the compiler on every package, the time of a clean build and the size of
// the CLI binary, and writes them to the "build" section of the metrics
// report. The peak memory comes from the -toolexec wrapper of
// poc/pgquery/wasm2go/maxrss, which it builds from the prototype.
//
//	go run ./cmd/buildmetrics -out ../results/metrics.json
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
	"time"

	"github.com/4itosik/pg_migrate_research/pgschema/oracle"
)

const modulePath = "github.com/4itosik/pg_migrate_research/pgschema"

var lineRe = regexp.MustCompile(`^(compile|link) (\S*) maxrss=(\d+)MB wall=([\d.]+)s$`)

func main() {
	out := flag.String("out", "../results/metrics.json", "metrics report")
	lib := flag.String("lib", "..", "library module directory")
	proto := flag.String("proto", "../../poc/pgquery", "prototype module directory, to build the maxrss tool")
	flag.Parse()

	tmp, err := os.MkdirTemp("", "buildmetrics")
	if err != nil {
		log.Fatal(err)
	}
	defer os.RemoveAll(tmp)
	tool := filepath.Join(tmp, "maxrss")
	run(*proto, nil, "go", "build", "-o", tool, "./wasm2go/maxrss")

	logFile := filepath.Join(tmp, "maxrss.log")
	env := []string{"CGO_ENABLED=0", "MAXRSS_LOG=" + logFile}
	start := time.Now()
	// -a rebuilds the standard library too, as in an empty build cache
	run(*lib, env, "go", "build", "-a", "-toolexec="+tool, "./...")
	clean := time.Since(start)

	b, err := os.ReadFile(logFile)
	if err != nil {
		log.Fatal(err)
	}
	type step struct {
		pkg  string
		mb   int
		wall float64
	}
	var libSteps, allSteps []step
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
		s := step{m[2], mb, wall}
		allSteps = append(allSteps, s)
		if len(s.pkg) >= len(modulePath) && s.pkg[:len(modulePath)] == modulePath {
			libSteps = append(libSteps, s)
		}
	}
	peak := func(steps []step) (step, bool) {
		if len(steps) == 0 {
			return step{}, false
		}
		sort.Slice(steps, func(i, j int) bool { return steps[i].mb > steps[j].mb })
		return steps[0], true
	}
	sec := map[string]any{
		"clean_build_seconds": clean.Seconds(),
		"link_peak_mb":        linkMB,
	}
	if p, ok := peak(libSteps); ok {
		sec["library_compile_peak_mb"] = p.mb
		sec["library_compile_peak_package"] = p.pkg
	}
	if p, ok := peak(allSteps); ok {
		sec["all_compile_peak_mb"] = p.mb
		sec["all_compile_peak_package"] = p.pkg
	}

	// the CLI, when it exists
	if _, err := os.Stat(filepath.Join(*lib, "cmd", "pgschema")); err == nil {
		bin := filepath.Join(tmp, "pgschema")
		run(*lib, []string{"CGO_ENABLED=0"}, "go", "build", "-o", bin, "./cmd/pgschema")
		if fi, err := os.Stat(bin); err == nil {
			sec["cli_binary_mb"] = float64(fi.Size()) / (1 << 20)
		}
	}
	if err := oracle.UpdateMetrics(*out, []string{"build"}, sec); err != nil {
		log.Fatal(err)
	}
	fmt.Printf("wrote %s: %v\n", *out, sec)
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
