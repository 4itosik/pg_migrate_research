package oracle

import (
	"fmt"
	"math/rand"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/4itosik/pg_migrate_research/pgschema/internal/lex"
	"github.com/4itosik/pg_migrate_research/poc/harness"
)

// diffScan compares the tokens of the library lexer with the libpg_query
// scanner on src: token numbers, byte offsets and keyword categories. Both
// must fail or both succeed, and a failure must point at the same
// character. It returns "" when they agree.
func diffScan(src string) (diff string, tokens int, rejected, deviation bool) {
	diff = diffScanWith(src, &tokens, &rejected, lex.Scan)
	if diff != "" {
		// libpg_query does not continue strings across comments: not a
		// mismatch when the compatible lexer agrees with it
		var t2 int
		var r2 bool
		if diffScanWith(src, &t2, &r2, lex.ScanLibpgQuery) == "" {
			return "", tokens, rejected, true
		}
	}
	return
}

func diffScanWith(src string, tokens *int, rejected *bool, scan func(string, bool) ([]lex.Item, error)) string {
	want, werr := Scan(src)
	if werr != nil {
		*rejected = true
	} else {
		*tokens = len(want.Tokens)
	}
	got, gerr := scan(src, true)
	switch {
	case werr != nil && gerr != nil:
		wmsg, wpos := ErrorInfo(werr)
		ge := gerr.(*lex.Error)
		if gpos := ge.CursorPos(src); gpos != wpos {
			return fmt.Sprintf("error position: got %d, want %d (%v)", gpos, wpos, werr)
		}
		if ge.Msg != wmsg {
			return fmt.Sprintf("error message: got %q, want %q", ge.Msg, wmsg)
		}
		return ""
	case werr != nil:
		return fmt.Sprintf("libpg_query fails (%v), lexer returns %d tokens", werr, len(got))
	case gerr != nil:
		return fmt.Sprintf("lexer fails (%v), libpg_query returns %d tokens", gerr, len(want.Tokens))
	}
	for i := 0; i < len(want.Tokens) && i < len(got); i++ {
		w, g := want.Tokens[i], got[i]
		if int32(w.Token) != int32(g.Tok) || w.Start != g.Start || w.End != g.End || int32(w.KeywordKind) != int32(g.Kind) {
			return fmt.Sprintf("token %d: got %v %d..%d %v, want %v %d..%d %v", i,
				g.Tok, g.Start, g.End, g.Kind, w.Token, w.Start, w.End, w.KeywordKind)
		}
	}
	if len(want.Tokens) != len(got) {
		return fmt.Sprintf("got %d tokens, want %d", len(got), len(want.Tokens))
	}
	return ""
}

type lexStats struct {
	Inputs, Tokens, Mismatches, ErrorInputs int
	// Deviations are inputs on which the lexer agrees with the server and
	// not with libpg_query (strings continued across comments).
	Deviations int
	Samples    []string
}

func (st *lexStats) check(name, src string) {
	st.Inputs++
	d, tokens, rejected, deviation := diffScan(src)
	st.Tokens += tokens
	if rejected {
		st.ErrorInputs++
	}
	if deviation {
		st.Deviations++
	}
	if d != "" {
		st.Mismatches++
		if len(st.Samples) < 20 {
			st.Samples = append(st.Samples, fmt.Sprintf("%s: %s\n    %q", name, d, truncate(src, 160)))
		}
	}
}

func truncate(s string, n int) string {
	if len(s) > n {
		return s[:n] + "..."
	}
	return s
}

func TestLexCorpus(t *testing.T) {
	cases, err := harness.LoadCorpus(corpusDir())
	if err != nil {
		t.Fatal(err)
	}
	var st lexStats
	for _, c := range cases {
		for _, m := range c.Migrations {
			st.check(c.Name+"/"+m.UpFile, m.Up)
			st.check(c.Name+"/"+m.DownFile, m.Down)
		}
		st.check(c.Name+"/setup", c.Setup)
		st.check(c.Name+"/check", c.Check)
	}
	t.Logf("%d inputs, %d tokens, %d mismatches", st.Inputs, st.Tokens, st.Mismatches)
	for _, s := range st.Samples {
		t.Error(s)
	}
}

// TestLexRegress scans every statement of the regression tests of every
// PostgreSQL version, and every whole file with the lines the scanner
// rejects still in it, so that errors are compared too.
func TestLexRegress(t *testing.T) {
	root := os.Getenv("REGRESS_ROOT")
	if root == "" {
		skipUnlessCI(t, "REGRESS_ROOT is not set; run tools/get-data.sh and source tools/env.sh")
	}
	dirs, _ := filepath.Glob(filepath.Join(root, "REL_*_STABLE"))
	if len(dirs) == 0 {
		skipUnlessCI(t, "no regression tests in "+root)
	}
	report := map[string]any{}
	for _, dir := range dirs {
		branch := filepath.Base(dir)
		t.Run(branch, func(t *testing.T) {
			files, err := LoadRegress(dir)
			if err != nil {
				t.Fatal(err)
			}
			var stmts, whole lexStats
			for _, f := range files {
				raw, err := os.ReadFile(filepath.Join(dir, f.Name))
				if err != nil {
					t.Fatal(err)
				}
				whole.check(f.Name, StripPsql(string(raw)))
				for i, s := range f.Statements {
					stmts.check(fmt.Sprintf("%s#%d", f.Name, i), s)
				}
			}
			t.Logf("statements: %d inputs, %d tokens, %d mismatches, %d libpg_query deviations; whole files: %d inputs (%d rejected by the scanner), %d mismatches, %d deviations",
				stmts.Inputs, stmts.Tokens, stmts.Mismatches, stmts.Deviations, whole.Inputs, whole.ErrorInputs, whole.Mismatches, whole.Deviations)
			for _, s := range append(stmts.Samples, whole.Samples...) {
				t.Error(s)
			}
			report[branch] = map[string]any{
				"statements":                stmts.Inputs,
				"statement_tokens":          stmts.Tokens,
				"statement_mismatches":      stmts.Mismatches,
				"statement_deviations":      stmts.Deviations,
				"files":                     whole.Inputs,
				"files_rejected_by_scanner": whole.ErrorInputs,
				"file_mismatches":           whole.Mismatches,
				"file_deviations":           whole.Deviations,
			}
		})
	}
	if out := os.Getenv("METRICS_OUT"); out != "" && !t.Failed() {
		if err := UpdateMetrics(out, []string{"stage1", "lexer", "regress"}, report); err != nil {
			t.Fatal(err)
		}
	}
}

// fragments are the pieces of the random inputs: every lexical construct of
// scan.l, and the characters around which its rules change.
var fragments = []string{
	" ", " ", "\n", "\r\n", "\t", "\f",
	"a", "B", "x", "X", "n", "N", "e", "E", "u", "U", "U&", "_", "é", "é", "\xff",
	"select", "NOT", "nchar", "abort", "Abort", "insert", "uescape",
	"0", "1", "9", "00", "123", "0x", "0X1F", "0xg", "0o7", "0o8", "0b1", "0b2", "0b", "1_0", "1__0", "1_", "_1",
	".", "..", "...", "1.", "1.5", ".5", "1e5", "1e", "1e+", "1e-5", "1E+", "2147483647", "2147483648", "0xFFFFFFFF",
	"'", "''", "'a'", "E'", "E'\\n'", "E'\\", "\\", "\\u", "\\u0041", "\\ud83d", "\\ude00", "\\U0001F600", "\\x4", "\\x41", "\\101", "\\0", "\\'",
	"b'", "x'", "B'101'", "X'1F'", "U&'", "U&'d\\0061'", "u&\"", "u&",
	"\"", "\"\"", "\"a\"", "\"a\"\"b\"",
	"$", "$$", "$1", "$12", "$a$", "$a$x$a$", "$$x$$", "$a", "$1a", "$1$", "$ab$", "$b$",
	"--", "-- c\n", "/*", "*/", "/**/", "/*/", "/* /* */ */", "/*--*/",
	"+", "-", "*", "/", "%", "^", "<", ">", "=", "<=", ">=", "<>", "!=", "=>", "::", ":=", ":", ";", ",", "(", ")", "[", "]",
	"~", "!", "@", "#", "&", "|", "`", "?", "@>", "<@", "||", "->>", "=-", "+-", "*-", "?-", "--+", "/*+", "<=>", "+/*", "-/*",
	"{", "}",
}

// TestLexRandom compares the lexer with libpg_query on random
// concatenations of lexical fragments. The seed is fixed, so a failure is
// reproducible; LEX_RANDOM sets the number of inputs.
func TestLexRandom(t *testing.T) {
	n, seed := 20000, int64(1)
	if v := os.Getenv("LEX_RANDOM"); v != "" {
		fmt.Sscan(v, &n)
	}
	if v := os.Getenv("LEX_SEED"); v != "" {
		fmt.Sscan(v, &seed)
	}
	rng := rand.New(rand.NewSource(seed))
	var st lexStats
	start := time.Now()
	for i := 0; i < n; i++ {
		if i > 0 && i%50000 == 0 {
			t.Logf("%d inputs, %s", i, time.Since(start).Round(time.Millisecond))
		}
		var b strings.Builder
		for k := rng.Intn(10) + 1; k > 0; k-- {
			b.WriteString(fragments[rng.Intn(len(fragments))])
		}
		st.check(fmt.Sprintf("random#%d", i), b.String())
	}
	t.Logf("%d inputs, %d tokens, %d with scanner errors, %d mismatches, %d libpg_query deviations", st.Inputs, st.Tokens, st.ErrorInputs, st.Mismatches, st.Deviations)
	for _, s := range st.Samples {
		t.Error(s)
	}
}

// TestLexMutations damages real statements: it deletes, duplicates and
// inserts text at random places, which produces the inputs near the edges
// of the lexical rules that a grammar of fragments seldom reaches. The seed
// is fixed; LEX_MUTATIONS sets the number of inputs.
func TestLexMutations(t *testing.T) {
	root := os.Getenv("REGRESS_ROOT")
	if root == "" {
		skipUnlessCI(t, "REGRESS_ROOT is not set; run tools/get-data.sh and source tools/env.sh")
	}
	files, err := LoadRegress(filepath.Join(root, "REL_16_STABLE"))
	if err != nil {
		skipUnlessCI(t, err.Error())
	}
	var stmts []string
	for _, f := range files {
		for _, s := range f.Statements {
			if len(s) <= 600 {
				stmts = append(stmts, s)
			}
		}
	}
	n := 20000
	if v := os.Getenv("LEX_MUTATIONS"); v != "" {
		fmt.Sscan(v, &n)
	}
	rng := rand.New(rand.NewSource(7))
	var st lexStats
	for i := 0; i < n; i++ {
		s := stmts[rng.Intn(len(stmts))]
		for k := rng.Intn(3) + 1; k > 0 && len(s) > 2; k-- {
			a := rng.Intn(len(s))
			b := a + rng.Intn(min(8, len(s)-a)+1)
			switch rng.Intn(4) {
			case 0: // delete
				s = s[:a] + s[b:]
			case 1: // duplicate
				s = s[:b] + s[a:b] + s[b:]
			case 2: // insert a fragment
				s = s[:a] + fragments[rng.Intn(len(fragments))] + s[a:]
			default: // replace by a fragment
				s = s[:a] + fragments[rng.Intn(len(fragments))] + s[b:]
			}
		}
		st.check(fmt.Sprintf("mutation#%d", i), s)
	}
	t.Logf("%d inputs, %d tokens, %d with scanner errors, %d mismatches, %d libpg_query deviations", st.Inputs, st.Tokens, st.ErrorInputs, st.Mismatches, st.Deviations)
	for _, s := range st.Samples {
		t.Error(s)
	}
}

// TestLexSpeed times the lexer on the statements of the PostgreSQL 16
// regression tests and writes the figures to the metrics report.
func TestLexSpeed(t *testing.T) {
	root := os.Getenv("REGRESS_ROOT")
	if root == "" {
		skipUnlessCI(t, "REGRESS_ROOT is not set; run tools/get-data.sh and source tools/env.sh")
	}
	files, err := LoadRegress(filepath.Join(root, "REL_16_STABLE"))
	if err != nil {
		skipUnlessCI(t, err.Error())
	}
	var stmts []string
	size := 0
	for _, f := range files {
		for _, s := range f.Statements {
			stmts = append(stmts, s)
			size += len(s)
		}
	}
	best := time.Duration(1<<63 - 1)
	tokens := 0
	for run := 0; run < 5; run++ {
		tokens = 0
		start := time.Now()
		for _, s := range stmts {
			sc := lex.NewScanner(s)
			for {
				it, err := sc.Next()
				if err != nil || it.Tok == 0 {
					break
				}
				tokens++
			}
		}
		if d := time.Since(start); d < best {
			best = d
		}
	}
	perStmt := float64(best.Nanoseconds()) / float64(len(stmts)) / 1000
	mbps := float64(size) / best.Seconds() / (1 << 20)
	t.Logf("%d statements, %d tokens, %d bytes: %.2f us per statement, %.1f MB/s, %.0f ns per token",
		len(stmts), tokens, size, perStmt, mbps, float64(best.Nanoseconds())/float64(tokens))
	if out := os.Getenv("METRICS_OUT"); out != "" {
		err := UpdateMetrics(out, []string{"stage1", "lexer", "speed_pg16"}, map[string]any{
			"statements": len(stmts), "tokens": tokens, "bytes": size,
			"us_per_statement": perStmt, "mb_per_second": mbps,
		})
		if err != nil {
			t.Fatal(err)
		}
	}
}
