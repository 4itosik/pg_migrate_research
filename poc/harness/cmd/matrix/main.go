// Command matrix renders harness reports as Markdown tables.
//
//	go run ./cmd/matrix ../results/go-pgquery.json ../results/multigres.json ...
//	go run ./cmd/matrix -versions ../results/pg12 ../results/pg13 ...
//
// With -versions every directory holds the reports of one PostgreSQL version
// and the table shows the totals of each run per version.
package main

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/4itosik/pg_migrate_research/poc/harness"
)

func main() {
	if len(os.Args) > 1 && os.Args[1] == "-versions" {
		versions(os.Args[2:])
		return
	}
	var reps []harness.Report
	for _, p := range os.Args[1:] {
		r, err := harness.ReadReport(p)
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
		reps = append(reps, r)
	}
	if len(reps) == 0 {
		fmt.Fprintln(os.Stderr, "usage: matrix report.json...")
		os.Exit(2)
	}
	var b strings.Builder
	b.WriteString("| Сценарий |")
	for _, r := range reps {
		b.WriteString(" " + r.Candidate + " |")
	}
	b.WriteString("\n|---|")
	for range reps {
		b.WriteString("---|")
	}
	b.WriteString("\n")
	for i, c := range reps[0].Results {
		title := c.Case
		if c.Expect == "limitation" {
			title += " ⚠️"
		}
		b.WriteString("| " + title + " |")
		for _, r := range reps {
			b.WriteString(" " + cell(r.Results[i]) + " |")
		}
		b.WriteString("\n")
	}
	b.WriteString("| **Итого** |")
	for _, r := range reps {
		b.WriteString(" **" + total(r) + "** |")
	}
	b.WriteString("\n")
	fmt.Print(b.String())

	if len(os.Args) > 1 && os.Getenv("DETAILS") != "" {
		for _, r := range reps {
			fmt.Printf("\n### %s\n\n", r.Candidate)
			for _, c := range r.Results {
				if c.Status != "pass" {
					fmt.Printf("- `%s` [%s]: %s\n", c.Case, c.Stage, firstLine(c.Error))
				}
			}
		}
	}
}

// runs are the reports of one version directory, in table order.
var runs = []string{"baseline", "noop", "go-pgquery", "multigres", "bytebase-antlr"}

func versions(dirs []string) {
	var b strings.Builder
	b.WriteString("| Прогон |")
	reps := make([][]harness.Report, len(dirs))
	for i, d := range dirs {
		for _, name := range runs {
			r, err := harness.ReadReport(filepath.Join(d, name+".json"))
			if err != nil {
				fmt.Fprintln(os.Stderr, err)
				os.Exit(1)
			}
			reps[i] = append(reps[i], r)
		}
		b.WriteString(" PostgreSQL " + reps[i][0].Server + " |")
	}
	b.WriteString("\n|---|")
	for range dirs {
		b.WriteString("---|")
	}
	b.WriteString("\n")
	for k, name := range runs {
		b.WriteString("| " + name + " |")
		for i := range dirs {
			b.WriteString(" " + total(reps[i][k]) + " |")
		}
		b.WriteString("\n")
	}
	fmt.Print(b.String())
	for i, d := range dirs {
		fmt.Printf("\n%s (PostgreSQL %s):\n", d, reps[i][0].Server)
		for k, name := range runs {
			if name == "noop" {
				continue
			}
			for _, c := range reps[i][k].Results {
				if c.Status != "pass" {
					fmt.Printf("- %s `%s` [%s]: %s\n", name, c.Case, c.Stage, firstLine(c.Error))
				}
			}
		}
	}
}

// total is "passed/run", with the number of cases skipped on this version.
func total(r harness.Report) string {
	s := fmt.Sprintf("%d/%d", r.Passed(), len(r.Results)-r.Skipped())
	if n := r.Skipped(); n > 0 {
		s += fmt.Sprintf(" (+%d пропущено)", n)
	}
	return s
}

func cell(c harness.CaseResult) string {
	switch c.Status {
	case "pass":
		return "✅"
	case "skip":
		return "—"
	}
	stage := c.Stage
	if i := strings.IndexByte(stage, ' '); i > 0 {
		stage = stage[:i]
	}
	return "❌ " + stage
}

func firstLine(s string) string {
	if i := strings.IndexByte(s, '\n'); i >= 0 {
		return s[:i]
	}
	return s
}
