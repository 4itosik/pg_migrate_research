package pgqrewrite

import (
	"fmt"
	"os"
	"path/filepath"
	"reflect"
	"regexp"
	"sort"
	"strings"
	"testing"
	"time"

	pgquery "github.com/4itosik/pg_migrate_research/poc/pgquery/internal/pgparse"
	pg "github.com/pganalyze/pg_query_go/v6"
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
	var samples, skipped []string
	start := time.Now()
	for _, f := range files {
		b, err := os.ReadFile(f)
		if err != nil {
			t.Fatal(err)
		}
		stmts := splitStatements(stripPsql(string(b)))
		if stmts == nil && strings.TrimSpace(string(b)) != "" {
			skipped = append(skipped, filepath.Base(f))
		}
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
	if len(skipped) > 0 {
		t.Logf("files skipped, scanner error: %s", strings.Join(skipped, " "))
	}
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

// stripPsql blanks psql meta-commands and the inline data of COPY ... FROM
// stdin: neither is SQL, and the data can break the scanner.
func stripPsql(s string) string {
	lines := strings.Split(s, "\n")
	inCopy := false
	for i, l := range lines {
		t := strings.TrimSpace(l)
		switch {
		case inCopy: // inline data of COPY ... FROM stdin, up to \.
			inCopy = t != `\.`
			lines[i] = ""
		case strings.HasPrefix(t, `\`): // psql meta-command
			lines[i] = ""
		case copyFromStdin.MatchString(t):
			inCopy = true
		}
	}
	return strings.Join(lines, "\n")
}

var copyFromStdin = regexp.MustCompile(`(?i)\bfrom\s+stdin\b[^;]*;\s*$`)

// splitStatements splits a script on top-level semicolons using the
// PostgreSQL scanner, so semicolons in strings, comments and dollar quotes
// are ignored. BEGIN ATOMIC ... END bodies are kept together.
func splitStatements(s string) []string {
	s, res, err := scanScript(s)
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

// scanScript scans a whole script. The regression tests contain tokens the
// scanner rejects on purpose ("123abc", bad Unicode escapes); the line with
// such a token is blanked and the scan is repeated, so only that statement
// is lost.
func scanScript(s string) (string, *pg.ScanResult, error) {
	var err error
	for try := 0; try < 100; try++ {
		var res *pg.ScanResult
		if res, err = pgquery.Scan(s); err == nil {
			return s, res, nil
		}
		v := reflect.ValueOf(err)
		if v.Kind() != reflect.Pointer || v.Elem().Kind() != reflect.Struct {
			break
		}
		f := v.Elem().FieldByName("Cursorpos")
		if !f.IsValid() || f.Int() <= 0 {
			break
		}
		// Cursorpos counts characters from 1.
		pos, n := len(s), int(f.Int())-1
		for i := range s {
			if n == 0 {
				pos = i
				break
			}
			n--
		}
		start := strings.LastIndexByte(s[:pos], '\n') + 1
		end := strings.IndexByte(s[pos:], '\n')
		if end < 0 {
			end = len(s)
		} else {
			end += pos
		}
		if start == end {
			break
		}
		s = s[:start] + s[end:]
	}
	return s, nil, err
}
