// Command matrix renders harness reports as a Markdown table.
//
//	go run ./cmd/matrix ../results/go-pgquery.json ../results/multigres.json ...
package main

import (
	"fmt"
	"os"
	"strings"

	"github.com/4itosik/pg_migrate_research/poc/harness"
)

func main() {
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
		b.WriteString(fmt.Sprintf(" **%d/%d** |", r.Passed(), len(r.Results)))
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

func cell(c harness.CaseResult) string {
	if c.Status == "pass" {
		return "✅"
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
