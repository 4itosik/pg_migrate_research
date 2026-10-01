package pgqrewrite

import (
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"testing"
	"time"

	pg "github.com/pganalyze/pg_query_go/v6"
	pgquery "github.com/wasilibs/go-pgquery"
)

// TestRegress rewrites every statement of the PostgreSQL regression suite
// (REGRESS_DIR with *.sql files) and counts failures. A failure is either a
// statement the rewriter refuses (it never returns unverified output) or a
// verification mismatch. psql meta-commands are dropped; statements that do
// not parse are skipped.
//
//	REGRESS_DIR=/path/to/src/test/regress/sql go test -run TestRegress -v
func TestRegress(t *testing.T) {
	dir := os.Getenv("REGRESS_DIR")
	if dir == "" {
		t.Skip("REGRESS_DIR is not set")
	}
	files, _ := filepath.Glob(filepath.Join(dir, "*.sql"))
	sort.Strings(files)
	var total, parsed, changed, failed int
	byKind := map[string]int{}
	var samples []string
	start := time.Now()
	for _, f := range files {
		b, err := os.ReadFile(f)
		if err != nil {
			t.Fatal(err)
		}
		stmts := splitStatements(stripPsql(string(b)))
		r, _ := New(Options{Schema: "auth"})
		var ok []string
		for _, s := range stmts {
			total++
			if _, err := pgquery.Parse(s); err != nil {
				continue
			}
			parsed++
			ok = append(ok, s)
			_ = r.Learn(s)
		}
		for _, s := range ok {
			out, _, err := r.Rewrite(s)
			if err != nil {
				failed++
				kind := errKind(err)
				byKind[kind]++
				if len(samples) < 60 {
					samples = append(samples, fmt.Sprintf("%s [%s] %s\n      %v", filepath.Base(f), kind, snippet(s), firstLine(err.Error())))
				}
				continue
			}
			if out != s {
				changed++
			}
		}
	}
	elapsed := time.Since(start)
	t.Logf("files=%d statements=%d parsed=%d rewritten=%d changed=%d failed=%d (%.3f%%) time=%s (%.2f ms/statement)",
		len(files), total, parsed, parsed-failed, changed, failed, 100*float64(failed)/float64(parsed), elapsed.Round(time.Millisecond),
		float64(elapsed.Microseconds())/1000/float64(parsed))
	kinds := make([]string, 0, len(byKind))
	for k := range byKind {
		kinds = append(kinds, k)
	}
	sort.Slice(kinds, func(i, j int) bool { return byKind[kinds[i]] > byKind[kinds[j]] })
	for _, k := range kinds {
		t.Logf("  %5d %s", byKind[k], k)
	}
	for _, s := range samples {
		t.Log(s)
	}
}

func errKind(err error) string {
	msg := err.Error()
	for _, k := range []string{"verification", "cannot locate", "PL/pgSQL parse error", "token at offset", "keyword", "conflicting edits", "does not parse", "ON not found"} {
		if strings.Contains(msg, k) {
			return k
		}
	}
	return "other"
}

func firstLine(s string) string {
	if i := strings.IndexByte(s, '\n'); i >= 0 {
		return s[:i]
	}
	return s
}

func stripPsql(s string) string {
	lines := strings.Split(s, "\n")
	for i, l := range lines {
		if strings.HasPrefix(strings.TrimSpace(l), `\`) {
			lines[i] = ""
		}
	}
	return strings.Join(lines, "\n")
}

// splitStatements splits a script on top-level semicolons using the
// PostgreSQL scanner, so semicolons in strings, comments and dollar quotes
// are ignored. BEGIN ATOMIC ... END bodies are kept together.
func splitStatements(s string) []string {
	res, err := pgquery.Scan(s)
	if err != nil {
		return nil
	}
	var out []string
	start, depth, atomic := 0, 0, 0
	toks := res.Tokens
	for _, tok := range toks {
		switch tok.Token {
		case pg.Token_ASCII_40:
			depth++
		case pg.Token_ASCII_41:
			depth--
		case pg.Token_ATOMIC:
			atomic++
		case pg.Token_CASE:
			if atomic > 0 {
				atomic++
			}
		case pg.Token_END_P:
			if atomic > 0 {
				atomic--
			}
		case pg.Token_ASCII_59:
			if depth == 0 && atomic == 0 {
				if stmt := strings.TrimSpace(s[start:tok.End]); stmt != ";" {
					out = append(out, stmt)
				}
				start = int(tok.End)
			}
		}
	}
	if rest := strings.TrimSpace(s[start:]); rest != "" {
		out = append(out, rest)
	}
	return out
}
