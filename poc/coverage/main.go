// Command coverage compares PostgreSQL parsers for Go on the same statements:
// how many statements each parser accepts, how faithful its deparser is and
// how fast it is. The reference is libpg_query (the parser of PostgreSQL
// itself, via go-pgquery): only statements it accepts are counted, and a
// deparsed statement is correct when libpg_query parses it into the same tree.
//
//	go run . -regress /path/to/postgres/src/test/regress/sql -corpus ../corpus
package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"reflect"
	"sort"
	"strings"
	"time"

	"github.com/antlr4-go/antlr/v4"
	bbpg "github.com/bytebase/parser/postgresql"
	crdb "github.com/cockroachdb/cockroachdb-parser/pkg/sql/parser"
	"github.com/cockroachdb/cockroachdb-parser/pkg/sql/sem/tree"
	mgparser "github.com/multigres/multigres/go/common/parser"
	pg "github.com/pganalyze/pg_query_go/v6"
	pgplex "github.com/pgplex/pgparser/parser"
	pgquery "github.com/wasilibs/go-pgquery"
	"google.golang.org/protobuf/proto"
	"google.golang.org/protobuf/reflect/protoreflect"
)

type candidate struct {
	name    string
	parse   func(sql string) error
	deparse func(sql string) (string, error)
}

type stats struct {
	Candidate     string   `json:"candidate"`
	Statements    int      `json:"statements"`
	Parsed        int      `json:"parsed"`
	Panics        int      `json:"panics"`
	Deparsed      int      `json:"deparsed,omitempty"`
	DeparseSame   int      `json:"deparse_same,omitempty"`
	FirstCallMS   float64  `json:"first_call_ms"`
	TotalMS       float64  `json:"total_ms"`
	PerStmtUS     float64  `json:"per_statement_us"`
	ParseFailures []string `json:"parse_failures,omitempty"`
	DeparseDiffs  []string `json:"deparse_diffs,omitempty"`
}

type report struct {
	Source     string  `json:"source"`
	Statements int     `json:"statements"`
	Results    []stats `json:"results"`
}

func main() {
	regress := flag.String("regress", "", "directory with PostgreSQL regression *.sql files")
	corpus := flag.String("corpus", "", "corpus directory with case subdirectories")
	only := flag.String("only", "", "comma-separated candidate names")
	out := flag.String("out", "", "write JSON report to this file")
	diffs := flag.String("diffs", "", "write every deparse mismatch as JSON lines to this file")
	flag.Parse()
	if *diffs != "" {
		f, err := os.Create(*diffs)
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
		defer f.Close()
		dumpDiffs = json.NewEncoder(f)
	}

	var stmts []string
	var source string
	switch {
	case *regress != "":
		source = "PostgreSQL regression suite"
		files, _ := filepath.Glob(filepath.Join(*regress, "*.sql"))
		sort.Strings(files)
		for _, f := range files {
			b, _ := os.ReadFile(f)
			stmts = append(stmts, splitStatements(stripPsql(string(b)))...)
		}
	case *corpus != "":
		source = "PoC corpus"
		files, _ := filepath.Glob(filepath.Join(*corpus, "*", "*.sql"))
		sort.Strings(files)
		for _, f := range files {
			b, _ := os.ReadFile(f)
			stmts = append(stmts, splitStatements(string(b))...)
		}
	default:
		flag.Usage()
		os.Exit(2)
	}
	// Keep what PostgreSQL itself accepts.
	var ref []string
	for _, s := range stmts {
		if _, err := pgquery.Parse(s); err == nil {
			ref = append(ref, s)
		}
	}
	rep := report{Source: source, Statements: len(ref)}
	for _, c := range candidates() {
		if *only != "" && !strings.Contains(","+*only+",", ","+c.name+",") {
			continue
		}
		st := run(c, ref)
		rep.Results = append(rep.Results, st)
		fmt.Fprintf(os.Stderr, "%-22s parsed %6d/%d (%.2f%%) panics %d  deparse same %d/%d  first %.0f ms  %.0f µs/stmt\n",
			st.Candidate, st.Parsed, st.Statements, pct(st.Parsed, st.Statements), st.Panics, st.DeparseSame, st.Deparsed, st.FirstCallMS, st.PerStmtUS)
	}
	if *out != "" {
		b, _ := json.MarshalIndent(rep, "", "  ")
		_ = os.WriteFile(*out, append(b, '\n'), 0o644)
	}
}

// dumpDiffs receives every deparse mismatch when -diffs is set.
var dumpDiffs *json.Encoder

func pct(a, b int) float64 {
	if b == 0 {
		return 0
	}
	return 100 * float64(a) / float64(b)
}

func run(c candidate, stmts []string) stats {
	st := stats{Candidate: c.name, Statements: len(stmts)}
	start := time.Now()
	for i, s := range stmts {
		t0 := time.Now()
		err, panicked := safe(func() error { return c.parse(s) })
		if i == 0 {
			st.FirstCallMS = float64(time.Since(t0).Microseconds()) / 1000
		}
		if panicked {
			st.Panics++
		}
		if err != nil {
			if len(st.ParseFailures) < 25 {
				st.ParseFailures = append(st.ParseFailures, snippet(s)+"  ->  "+snippet(err.Error()))
			}
			continue
		}
		st.Parsed++
	}
	elapsed := time.Since(start)
	st.TotalMS = float64(elapsed.Microseconds()) / 1000
	st.PerStmtUS = float64(elapsed.Microseconds()) / float64(len(stmts))
	if c.deparse == nil {
		return st
	}
	for _, s := range stmts {
		var out string
		err, _ := safe(func() error {
			var err error
			out, err = c.deparse(s)
			return err
		})
		if err != nil {
			continue
		}
		st.Deparsed++
		if same(s, out) {
			st.DeparseSame++
			continue
		}
		if len(st.DeparseDiffs) < 25 {
			st.DeparseDiffs = append(st.DeparseDiffs, snippet(s)+"  ->  "+snippet(out))
		}
		if dumpDiffs != nil {
			_ = dumpDiffs.Encode(map[string]string{"candidate": c.name, "in": s, "out": out})
		}
	}
	return st
}

func safe(f func() error) (err error, panicked bool) {
	defer func() {
		if r := recover(); r != nil {
			err, panicked = fmt.Errorf("panic: %v", r), true
		}
	}()
	return f(), false
}

// same reports whether libpg_query parses both texts into the same tree.
func same(a, b string) bool {
	ta, err := pgquery.Parse(a)
	if err != nil {
		return false
	}
	tb, err := pgquery.Parse(b)
	if err != nil {
		return false
	}
	clearLocations(ta.ProtoReflect())
	clearLocations(tb.ProtoReflect())
	return proto.Equal(ta, tb)
}

func clearLocations(m protoreflect.Message) {
	var clear []protoreflect.FieldDescriptor
	m.Range(func(fd protoreflect.FieldDescriptor, v protoreflect.Value) bool {
		switch {
		case fd.Name() == "location" || fd.Name() == "stmt_location" || fd.Name() == "stmt_len":
			clear = append(clear, fd)
		case fd.Kind() == protoreflect.MessageKind && fd.IsList():
			l := v.List()
			for i := 0; i < l.Len(); i++ {
				clearLocations(l.Get(i).Message())
			}
		case fd.Kind() == protoreflect.MessageKind:
			clearLocations(v.Message())
		}
		return true
	})
	for _, fd := range clear {
		m.Clear(fd)
	}
}

func candidates() []candidate {
	return []candidate{
		{
			name:  "go-pgquery",
			parse: func(s string) error { _, err := pgquery.Parse(s); return err },
			deparse: func(s string) (string, error) {
				t, err := pgquery.Parse(s)
				if err != nil {
					return "", err
				}
				return pgquery.Deparse(t)
			},
		},
		{
			name:  "multigres",
			parse: func(s string) error { _, err := mgparser.ParseSQL(s); return err },
			deparse: func(s string) (string, error) {
				stmts, err := mgparser.ParseSQL(s)
				if err != nil {
					return "", err
				}
				parts := make([]string, len(stmts))
				for i, st := range stmts {
					parts[i] = st.SqlString()
				}
				return strings.Join(parts, ";\n"), nil
			},
		},
		{
			name:  "pgplex/pgparser",
			parse: func(s string) error { _, err := pgplex.Parse(s); return err },
		},
		{
			name:  "cockroachdb-parser",
			parse: func(s string) error { _, err := crdb.Parse(s); return err },
			deparse: func(s string) (string, error) {
				stmts, err := crdb.Parse(s)
				if err != nil {
					return "", err
				}
				parts := make([]string, len(stmts))
				for i, st := range stmts {
					parts[i] = tree.AsStringWithFlags(st.AST, tree.FmtParsable)
				}
				return strings.Join(parts, ";\n"), nil
			},
		},
		{
			name:  "bytebase ANTLR",
			parse: antlrParse,
		},
	}
}

type errListener struct {
	*antlr.DefaultErrorListener
	err error
}

func (l *errListener) SyntaxError(_ antlr.Recognizer, _ any, line, column int, msg string, _ antlr.RecognitionException) {
	if l.err == nil {
		l.err = fmt.Errorf("line %d:%d %s", line, column, msg)
	}
}

func antlrParse(s string) error {
	l := &errListener{DefaultErrorListener: antlr.NewDefaultErrorListener()}
	lexer := bbpg.NewPostgreSQLLexer(antlr.NewInputStream(s))
	lexer.RemoveErrorListeners()
	lexer.AddErrorListener(l)
	p := bbpg.NewPostgreSQLParser(antlr.NewCommonTokenStream(lexer, antlr.TokenDefaultChannel))
	p.RemoveErrorListeners()
	p.AddErrorListener(l)
	p.Root()
	if l.err != nil {
		return l.err
	}
	// Function bodies are parsed by nested parsers; their errors are kept in
	// an unexported field of the outer parser.
	if n := reflect.ValueOf(p).Elem().FieldByName("PostgreSQLParserBase").FieldByName("parseErrors").Len(); n > 0 {
		return fmt.Errorf("%d syntax errors in function bodies", n)
	}
	return nil
}

func snippet(s string) string {
	s = strings.Join(strings.Fields(s), " ")
	if len(s) > 160 {
		s = s[:157] + "..."
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

// splitStatements splits a script on top-level semicolons with the
// PostgreSQL scanner; BEGIN ATOMIC ... END bodies stay together.
func splitStatements(s string) []string {
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
