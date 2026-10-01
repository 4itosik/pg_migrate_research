// Command crosscheck rewrites every statement of the PostgreSQL regression
// suite with the three PoC rewriters and compares the results with the
// go-pgquery rewriter, whose output is verified against the parse tree.
// ANTLR output must be byte-identical (both insert the same text at the same
// tokens); multigres output must parse into the same tree (it regenerates
// SQL).
package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"

	antlrrewrite "github.com/4itosik/pg_migrate_research/poc/antlr"
	mgrewrite "github.com/4itosik/pg_migrate_research/poc/multigres"
	pgqrewrite "github.com/4itosik/pg_migrate_research/poc/pgquery"
	mgparser "github.com/multigres/multigres/go/common/parser"
	pg "github.com/pganalyze/pg_query_go/v6"
	pgquery "github.com/wasilibs/go-pgquery"
	"google.golang.org/protobuf/proto"
	"google.golang.org/protobuf/reflect/protoreflect"
)

type rewriter interface {
	Learn(string) error
	Rewrite(string) (string, []string, error)
}

// result counts one candidate. DifferentKinds splits Different for multigres:
// "deparse" when its deparse of the original statement already changes the
// tree, "rewrite" otherwise (the rewriters qualified different names).
type result struct {
	Candidate      string         `json:"candidate"`
	Statements     int            `json:"statements"`
	Errors         int            `json:"errors"`
	Panics         int            `json:"panics"`
	Same           int            `json:"same_as_reference"`
	Different      int            `json:"different"`
	DifferentKinds map[string]int `json:"different_kinds,omitempty"`
	TimeMS         float64        `json:"time_ms"`
	ErrorKinds     map[string]int `json:"error_kinds"`
	Samples        []string       `json:"samples"`
}

func main() {
	dir := flag.String("regress", "", "directory with regression *.sql files")
	out := flag.String("out", "", "JSON report")
	only := flag.String("only", "", "candidate to run (default: all)")
	diffs := flag.String("diffs", "", "write every difference and error as JSON lines")
	flag.Parse()
	var diffLog *json.Encoder
	if *diffs != "" {
		f, err := os.Create(*diffs)
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
		defer f.Close()
		diffLog = json.NewEncoder(f)
	}
	files, _ := filepath.Glob(filepath.Join(*dir, "*.sql"))
	sort.Strings(files)

	type candidate struct {
		name    string
		mk      func() rewriter
		cmp     func(ref, got string) bool
		explain func(in string) string
	}
	cands := []candidate{
		{"multigres", func() rewriter { r, _ := mgrewrite.New(mgrewrite.Options{Schema: "auth"}); return r }, sameTree, mgExplain},
		{"bytebase-antlr", func() rewriter { r, _ := antlrrewrite.New(antlrrewrite.Options{Schema: "auth"}); return r }, func(a, b string) bool { return a == b }, nil},
	}
	if *only != "" {
		var sel []candidate
		for _, c := range cands {
			if c.name == *only {
				sel = append(sel, c)
			}
		}
		cands = sel
	}
	res := map[string]*result{}
	for _, c := range cands {
		res[c.name] = &result{Candidate: c.name, ErrorKinds: map[string]int{}, DifferentKinds: map[string]int{}}
	}
	var refErrors, total int
	for _, f := range files {
		b, _ := os.ReadFile(f)
		var stmts []string
		for _, s := range split(strip(string(b))) {
			if _, err := pgquery.Parse(s); err == nil {
				stmts = append(stmts, s)
			}
		}
		ref, _ := pgqrewrite.New(pgqrewrite.Options{Schema: "auth"})
		for _, s := range stmts {
			_ = ref.Learn(s)
		}
		refOut := make([]string, len(stmts))
		refOK := make([]bool, len(stmts))
		for i, s := range stmts {
			o, _, err := ref.Rewrite(s)
			refOut[i], refOK[i] = o, err == nil
			if err != nil {
				refErrors++
			}
		}
		for _, c := range cands {
			st := res[c.name]
			rw := c.mk()
			t0 := time.Now()
			for _, s := range stmts {
				_, _ = safe(func() (string, error) { return "", rw.Learn(s) })
			}
			for i, s := range stmts {
				if !refOK[i] {
					continue
				}
				st.Statements++
				o, err := safe(func() (string, error) { o, _, err := rw.Rewrite(s); return o, err })
				if err != nil {
					st.Errors++
					k := kind(err)
					if strings.HasPrefix(k, "panic") {
						st.Panics++
					}
					st.ErrorKinds[k]++
					if diffLog != nil {
						_ = diffLog.Encode(map[string]string{"candidate": c.name, "file": filepath.Base(f), "in": s, "error": err.Error()})
					}
					if len(st.Samples) < 40 {
						st.Samples = append(st.Samples, fmt.Sprintf("ERROR %s | %s | %s", filepath.Base(f), oneLine(s, 150), oneLine(err.Error(), 150)))
					}
					continue
				}
				if c.cmp(refOut[i], o) {
					st.Same++
				} else {
					st.Different++
					why := ""
					if c.explain != nil {
						why = c.explain(s)
						st.DifferentKinds[why]++
					}
					if diffLog != nil {
						_ = diffLog.Encode(map[string]string{"candidate": c.name, "file": filepath.Base(f), "in": s, "ref": refOut[i], "got": o, "kind": why})
					}
					if len(st.Samples) < 40 {
						st.Samples = append(st.Samples, fmt.Sprintf("DIFF %s | ref: %s | got: %s", filepath.Base(f), oneLine(refOut[i], 200), oneLine(o, 200)))
					}
				}
			}
			st.TimeMS += float64(time.Since(t0).Microseconds()) / 1000
		}
		total += len(stmts)
	}
	fmt.Fprintf(os.Stderr, "statements: %d, reference (go-pgquery) refused: %d\n", total, refErrors)
	var list []*result
	for _, c := range cands {
		st := res[c.name]
		list = append(list, st)
		fmt.Fprintf(os.Stderr, "%-15s compared %d: same %d (%.2f%%), different %d, errors %d (panics %d), %.0f s\n",
			st.Candidate, st.Statements, st.Same, 100*float64(st.Same)/float64(st.Statements), st.Different, st.Errors, st.Panics, st.TimeMS/1000)
		for k, n := range st.ErrorKinds {
			fmt.Fprintf(os.Stderr, "    %5d %s\n", n, k)
		}
		for k, n := range st.DifferentKinds {
			fmt.Fprintf(os.Stderr, "    %5d different: %s\n", n, k)
		}
	}
	if *out != "" {
		b, _ := json.MarshalIndent(map[string]any{"statements": total, "reference_refused": refErrors, "results": list}, "", "  ")
		_ = os.WriteFile(*out, append(b, '\n'), 0o644)
	}
}

func safe(f func() (string, error)) (out string, err error) {
	defer func() {
		if r := recover(); r != nil {
			err = fmt.Errorf("panic: %v", r)
		}
	}()
	return f()
}

func kind(err error) string {
	msg := err.Error()
	switch {
	case strings.HasPrefix(msg, "panic"):
		return "panic"
	case strings.Contains(msg, "PL/pgSQL parse error"), strings.Contains(msg, "function body"), strings.Contains(msg, "DO block"):
		return "function body"
	case strings.Contains(msg, "does not parse"):
		return "output does not parse"
	case strings.Contains(msg, "syntax error"):
		return "syntax error"
	}
	return "other"
}

func oneLine(s string, n int) string {
	s = strings.Join(strings.Fields(s), " ")
	if len(s) > n {
		s = s[:n-3] + "..."
	}
	return s
}

// mgExplain reports whether multigres deparse alone changes the tree of the
// original statement ("deparse") or the difference comes from rewriting.
func mgExplain(in string) string {
	out, err := safe(func() (string, error) {
		stmts, err := mgparser.ParseSQL(in)
		if err != nil {
			return "", err
		}
		parts := make([]string, len(stmts))
		for i, st := range stmts {
			parts[i] = st.SqlString()
		}
		return strings.Join(parts, ";\n"), nil
	})
	if err != nil || !sameTree(in, out) {
		return "deparse"
	}
	return "rewrite"
}

func sameTree(a, b string) bool {
	ta, err := pgquery.Parse(a)
	if err != nil {
		return false
	}
	tb, err := pgquery.Parse(b)
	if err != nil {
		return false
	}
	clear(ta.ProtoReflect())
	clear(tb.ProtoReflect())
	return proto.Equal(ta, tb)
}

func clear(m protoreflect.Message) {
	var fds []protoreflect.FieldDescriptor
	m.Range(func(fd protoreflect.FieldDescriptor, v protoreflect.Value) bool {
		switch {
		case fd.Name() == "location" || fd.Name() == "stmt_location" || fd.Name() == "stmt_len":
			fds = append(fds, fd)
		case fd.Kind() == protoreflect.MessageKind && fd.IsList():
			for i := 0; i < v.List().Len(); i++ {
				clear(v.List().Get(i).Message())
			}
		case fd.Kind() == protoreflect.MessageKind:
			clear(v.Message())
		}
		return true
	})
	for _, fd := range fds {
		m.Clear(fd)
	}
}

func strip(s string) string {
	lines := strings.Split(s, "\n")
	for i, l := range lines {
		if strings.HasPrefix(strings.TrimSpace(l), `\`) {
			lines[i] = ""
		}
	}
	return strings.Join(lines, "\n")
}

func split(s string) []string {
	res, err := pgquery.Scan(s)
	if err != nil {
		return nil
	}
	var out []string
	start, depth, atomic := 0, 0, 0
	for _, tok := range res.Tokens {
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
