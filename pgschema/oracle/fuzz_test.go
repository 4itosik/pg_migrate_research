package oracle

import (
	"errors"
	"fmt"
	"math/rand"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
	"time"
	"unicode/utf8"

	"github.com/4itosik/pg_migrate_research/pgschema"
	"github.com/4itosik/pg_migrate_research/pgschema/internal/ast"
	"github.com/4itosik/pg_migrate_research/pgschema/internal/lex"
	"github.com/4itosik/pg_migrate_research/pgschema/internal/parse"
	"github.com/4itosik/pg_migrate_research/poc/harness"
)

// compareParse parses sql with the library and with libpg_query and returns
// a description of the first difference, or "": acceptance, the error message
// and its cursor, the trees with the positions.
//
// Three differences from libpg_query are deliberate and not reported, see
// docs/differences.md:
//
//   - a string continued across a comment: the server and the library
//     continue it, libpg_query does not;
//   - the library checks the encoding of the whole text first (invalid UTF-8,
//     a NUL), as PostgreSQL does before it parses; libpg_query does not, and
//     its C string ends at a NUL;
//   - the library does not accept the parameter markers ($1) that libpg_query's
//     own patches allow in the places of string constants (PASSWORD $1,
//     SET search_path = $1, type $1), where PostgreSQL itself gives a syntax
//     error.
func compareParse(sql string) string {
	theirs, werr := Parse(sql)
	ours, gerr := parse.Parse(sql)
	var ie *parse.InternalError
	if errors.As(gerr, &ie) {
		return fmt.Sprintf("the library panics: %v\n%s", ie.Value, ie.Stack)
	}
	if !utf8.ValidString(sql) || strings.IndexByte(sql, 0) >= 0 {
		if ge, ok := gerr.(*parse.Error); !ok || !strings.HasPrefix(ge.Msg, "invalid byte sequence for encoding") {
			return fmt.Sprintf("invalid UTF-8 or a NUL is not rejected as PostgreSQL does: %v", gerr)
		}
		return ""
	}
	switch {
	case werr != nil && gerr == nil && lexDeviates(sql):
		// a string continued across a comment: the server and the library
		// continue it, libpg_query does not (docs/differences.md)
		return ""
	case gerr != nil && paramMarkerError.MatchString(gerr.Error()):
		// libpg_query takes the marker as a constant and goes on, whether it
		// accepts the statement in the end or fails further on
		return ""
	case werr != nil && gerr != nil:
		wmsg, wpos := ErrorInfo(werr)
		ge, ok := gerr.(*parse.Error)
		if !ok {
			return fmt.Sprintf("the library fails with %q, libpg_query with %q", gerr, wmsg)
		}
		if ge.Msg != wmsg || ge.CursorPos(sql) != wpos {
			return fmt.Sprintf("the error differs: library %q at %d, libpg_query %q at %d", ge.Msg, ge.CursorPos(sql), wmsg, wpos)
		}
		return ""
	case werr != nil:
		return fmt.Sprintf("the library accepts what libpg_query rejects (%v)", werr)
	case gerr != nil:
		return fmt.Sprintf("the library rejects what libpg_query accepts (%v)", gerr)
	}
	if d := safeDiff(ours, theirs); d != nil {
		return "the trees differ: " + d.String()
	}
	return ""
}

// lexDeviates reports whether the text is scanned differently in the way
// libpg_query scans it (lex.Scanner.LibpgQueryCompat) and in the way the
// server does.
func lexDeviates(sql string) bool {
	scan := func(compat bool) (toks [][3]int, err error) {
		sc := lex.NewScanner(sql)
		sc.LibpgQueryCompat = compat
		for {
			it, err := sc.Next()
			if err != nil {
				return toks, err
			}
			if it.Tok == 0 {
				return toks, nil
			}
			toks = append(toks, [3]int{int(it.Tok), int(it.Start), int(it.End)})
		}
	}
	a, aerr := scan(false)
	b, berr := scan(true)
	if (aerr == nil) != (berr == nil) || len(a) != len(b) {
		return true
	}
	for i := range a {
		if a[i] != b[i] {
			return true
		}
	}
	return false
}

// paramMarkerInError matches a syntax error at a parameter marker anywhere in
// the text of an error.
var paramMarkerInError = regexp.MustCompile(`syntax error at or near "\$\d+`)

// paramMarkerError matches the syntax error at a parameter marker.
var paramMarkerError = regexp.MustCompile(`^syntax error at or near "\$\d+"`)

// tokenPieces cuts sql into alternating gaps and tokens with the lexer of the
// library. ok is false when the text does not lex.
func tokenPieces(sql string) (gaps, toks []string, ok bool) {
	sc := lex.NewScanner(sql)
	pos := 0
	for {
		it, err := sc.Next()
		if err != nil {
			return nil, nil, false
		}
		if it.Tok == 0 {
			gaps = append(gaps, sql[pos:])
			return gaps, toks, true
		}
		gaps = append(gaps, sql[pos:it.Start])
		toks = append(toks, sql[it.Start:it.End])
		pos = int(it.End)
	}
}

// mutate changes a statement at the level of tokens, which reaches the
// grammar's edges (a missing, doubled, swapped or foreign token) far more
// often than changes of bytes. Statements that do not lex are changed at the
// level of bytes.
func mutate(rng *rand.Rand, sql string, pool []string) string {
	gaps, toks, ok := tokenPieces(sql)
	if !ok || len(toks) == 0 {
		if sql == "" {
			return pool[rng.Intn(len(pool))]
		}
		a := rng.Intn(len(sql))
		return sql[:a] + sql[a+1:]
	}
	for k := rng.Intn(3) + 1; k > 0; k-- {
		i := rng.Intn(len(toks))
		switch rng.Intn(5) {
		case 0: // delete
			toks[i] = ""
		case 1: // duplicate
			toks[i] += " " + toks[i]
		case 2: // swap with a neighbour
			j := min(i+1+rng.Intn(2), len(toks)-1)
			toks[i], toks[j] = toks[j], toks[i]
		case 3: // replace by a token from another statement
			toks[i] = pool[rng.Intn(len(pool))]
		default: // insert a token from another statement
			toks[i] = pool[rng.Intn(len(pool))] + " " + toks[i]
		}
	}
	var b strings.Builder
	for i, t := range toks {
		b.WriteString(gaps[i])
		b.WriteString(t)
	}
	b.WriteString(gaps[len(toks)])
	return b.String()
}

// mutateBody damages the dollar-quoted body of a statement at the level of
// tokens, so that the SQL and PL/pgSQL inside it get the mutations.
func mutateBody(rng *rand.Rand, sql string, pool []string) string {
	a := strings.Index(sql, "$$") + 2
	b := strings.LastIndex(sql, "$$")
	if a > b {
		return sql
	}
	body := mutate(rng, sql[a:b], pool)
	if strings.Contains(body, "$$") {
		return sql
	}
	return sql[:a] + body + sql[b:]
}

// regressStatements returns the statements of the PostgreSQL 16 regression
// tests and of the corpus that are not longer than limit bytes.
func regressStatements(t testing.TB, limit int) []string {
	var out []string
	if root := os.Getenv("REGRESS_ROOT"); root != "" {
		files, err := LoadRegress(filepath.Join(root, "REL_16_STABLE"))
		if err == nil {
			for _, f := range files {
				for _, s := range f.Statements {
					if len(s) <= limit {
						out = append(out, s)
					}
				}
			}
		}
	}
	if cases, err := harness.LoadCorpus(corpusDir()); err == nil {
		for _, c := range cases {
			for _, m := range c.Migrations {
				for _, s := range SplitStatements(m.Up) {
					if len(s) <= limit {
						out = append(out, s)
					}
				}
			}
		}
	}
	if len(out) == 0 {
		skipUnlessCI(t, "no statements: set REGRESS_ROOT and CORPUS_DIR (tools/env.sh)")
	}
	return out
}

func tokenPool(stmts []string, rng *rand.Rand) []string {
	var pool []string
	for _, s := range stmts {
		if _, toks, ok := tokenPieces(s); ok && len(toks) > 0 && rng.Intn(8) == 0 {
			pool = append(pool, toks[rng.Intn(len(toks))])
		}
	}
	return append(pool, "(", ")", ",", ";", "$1", "'x'", "1", "*", ".", "NOT", "NULL", "DEFAULT", "ON", "AS", "SELECT", "a", `"A"`)
}

// TestParseMutations compares the parser with libpg_query on statements
// damaged at the level of tokens: acceptance, error message and cursor,
// trees. The seed is fixed; PARSE_MUTATIONS sets the number of inputs
// (default 20000; go-pgquery slows down over long series, so keep it below
// 60000 per process), PARSE_SEED the seed.
func TestParseMutations(t *testing.T) {
	n, seed := 20000, int64(11)
	if v := os.Getenv("PARSE_MUTATIONS"); v != "" {
		fmt.Sscan(v, &n)
	}
	if v := os.Getenv("PARSE_SEED"); v != "" {
		fmt.Sscan(v, &seed)
	}
	stmts := regressStatements(t, 800)
	rng := rand.New(rand.NewSource(seed))
	pool := tokenPool(stmts, rng)
	var bad []string
	accepted := 0
	start := time.Now()
	for i := 0; i < n; i++ {
		s := mutate(rng, stmts[rng.Intn(len(stmts))], pool)
		if _, err := safeParse(s); err == nil {
			accepted++
		}
		if d := compareParse(s); d != "" {
			bad = append(bad, fmt.Sprintf("%s\n    %q", d, truncate(s, 1500)))
		}
	}
	t.Logf("%d inputs in %s, %d accepted by the library, %d differences", n, time.Since(start).Round(time.Second), accepted, len(bad))
	for i, b := range bad {
		if i == 20 {
			t.Logf("... and %d more", len(bad)-i)
			break
		}
		t.Error(b)
	}
}

// FuzzParse is the same comparison under the native Go fuzzer:
//
//	go test -run '^$' -fuzz FuzzParse -fuzztime 10m .
func FuzzParse(f *testing.F) {
	for _, s := range []string{
		"SELECT 1", "CREATE TABLE t (id int PRIMARY KEY, n text DEFAULT 'x')",
		"CREATE FUNCTION f() RETURNS int LANGUAGE sql AS $$ SELECT 1 $$",
		"WITH a AS (SELECT 1) SELECT * FROM a JOIN b USING (id) WHERE x IN (1, 2) ORDER BY 1",
		"ALTER TABLE t ADD COLUMN c int, DROP COLUMN d", "SELECT U&'d\\0061t\\+000061' UESCAPE '\\'",
		"INSERT INTO t VALUES (1) ON CONFLICT (id) DO UPDATE SET n = excluded.n RETURNING *",
	} {
		f.Add(s)
	}
	f.Fuzz(func(t *testing.T, sql string) {
		if len(sql) > 4000 {
			t.Skip()
		}
		if d := compareParse(sql); d != "" {
			t.Errorf("%s\n%q", d, sql)
		}
	})
}

// rewriteIssues checks one input against the guarantees of the rewriter and
// returns a description of the first violation, or "".
//
//   - no panic;
//   - an output parses with libpg_query, and the statements are of the same
//     types in the same order as the input's;
//   - the output equals the input with text inserted: removing the inserted
//     schema qualifiers gives the input back, and
//   - when the prototype also rewrites the input, both outputs are equal.
func rewriteIssues(p pair, sql string) (issue string) {
	defer func() {
		if r := recover(); r != nil {
			issue = fmt.Sprintf("panic: %v", r)
		}
	}()
	out, _, err := p.our.Rewrite(sql)
	if !utf8.ValidString(sql) || strings.IndexByte(sql, 0) >= 0 {
		// as the server, the library rejects such a text before parsing
		if err == nil || !strings.Contains(err.Error(), "invalid byte sequence") {
			return fmt.Sprintf("invalid UTF-8 or a NUL is not refused: %v", err)
		}
		return ""
	}
	if err != nil {
		if strings.Contains(err.Error(), "internal error") {
			return "internal error: " + err.Error()
		}
		// a refusal where the prototype rewrites is a loss; a parameter
		// marker that libpg_query accepts and PostgreSQL does not is the
		// documented exception
		if paramMarkerInError.MatchString(err.Error()) {
			return ""
		}
		if !bodiesComplete(sql) {
			return ""
		}
		// a declaration whose type is not a type name: the server does not
		// create the function, libpg_query compiles it without a catalog
		if strings.Contains(err.Error(), "invalid type in a declaration") {
			return ""
		}
		if want, perr := safeProto(p.proto, sql); perr == nil && want != sql {
			return fmt.Sprintf("the library refuses (%v), the prototype rewrites to %q", err, truncate(want, 200))
		}
		return ""
	}
	if _, perr := Parse(out); perr != nil {
		return fmt.Sprintf("libpg_query does not parse the output: %v\n    output: %q", perr, truncate(out, 200))
	}
	if !bodiesComplete(sql) {
		return "" // the compiler and the prototype of libpg_query trap on it
	}
	// a body that libpg_query compiles must compile after the rewriting; the
	// output for a body it does not compile is not compared with the
	// prototype's, because the library reads such a body more leniently
	cerr := safeCompile(sql)
	if cerr == nil {
		if cerr := safeCompile(out); cerr != nil {
			return fmt.Sprintf("libpg_query compiles the input body but not the output: %v\n    output: %q", cerr, truncate(out, 200))
		}
	}
	if !isInsertionOnly(sql, out, "auth.") && !requotedBody(sql, out) {
		return fmt.Sprintf("the output is not the input with insertions of %q\n    output: %q", "auth.", truncate(out, 200))
	}
	if want, perr := safeProto(p.proto, sql); perr == nil && want != out && cerr == nil && !junkAfterType(sql) && trimQuoted(unqualifyKeywordTypes(want)) != trimQuoted(out) {
		return fmt.Sprintf("the output differs from the prototype's:\n%s", firstDiff(want, out))
	}
	return ""
}

var keywordTypeQualified = regexp.MustCompile(`(?i)\bauth\.(varchar|char|character|int|integer|bigint|smallint|numeric|decimal|dec|real|float|double|timestamp|time|interval|boolean|bit)\b`)

// unqualifyKeywordTypes takes the schema off the type keywords (varchar, int,
// ...) that the prototype puts it on when a migration creates a type of that
// name: in a PL/pgSQL declaration the keyword is the type of pg_catalog and
// the schema changes the type (docs/differences.md, "Ошибки прототипа").
func unqualifyKeywordTypes(s string) string {
	return keywordTypeQualified.ReplaceAllString(s, "$1")
}

var quotedLiteral = regexp.MustCompile(`[eE]?'([^']*)'|\$\$([^$]*)\$\$`)

// trimQuoted writes every simple string literal as '...' with the white space
// at its edges stripped: the prototype writes the literal of a relation name
// again in that form and trims the name in nextval(' s '), the library keeps
// the literal as written (docs/differences.md).
func trimQuoted(s string) string {
	return quotedLiteral.ReplaceAllStringFunc(s, func(m string) string {
		sub := quotedLiteral.FindStringSubmatch(m)
		return "'" + strings.TrimSpace(sub[1]+sub[2]) + "'"
	})
}

var typeJunk = regexp.MustCompile(`(?i)%(?:row)?type\s+(\w+)`)

// junkAfterType reports whether a %TYPE or %ROWTYPE declaration is followed by
// something that is not part of a declaration. libpg_query accepts such text
// as part of the type name, PostgreSQL gives a syntax error, and the library
// and the prototype edit the declaration differently; the function does not
// exist either way.
func junkAfterType(sql string) bool {
	for _, m := range typeJunk.FindAllStringSubmatch(sql, -1) {
		switch strings.ToLower(m[1]) {
		case "collate", "not", "default", "language", "as", "returns", "strict", "stable", "immutable", "volatile",
			"security", "cost", "rows", "parallel", "called", "leakproof", "window", "set", "support", "transform":
		default:
			return true
		}
	}
	return false
}

// bodiesComplete reports whether every function and DO block of sql has a body
// (an AS clause). The PL/pgSQL compiler of libpg_query traps on a function
// without one ("Assertion failed: proc_source != NULL", a WebAssembly trap),
// and in one fuzzing run the calls after a trap failed with "out of bounds
// memory access" in the same process, so such inputs are kept away from it.
func bodiesComplete(sql string) bool {
	stmts, err := parse.Parse(sql)
	if err != nil {
		return false
	}
	has := func(opts []ast.Node) bool {
		for _, o := range opts {
			if d, ok := o.(*ast.DefElem); ok && d.Defname == "as" {
				return true
			}
		}
		return false
	}
	for _, raw := range stmts {
		switch n := raw.Stmt.(type) {
		case *ast.CreateFunctionStmt:
			if !has(n.Options) && n.SqlBody == nil {
				return false
			}
		case *ast.DoStmt:
			if !has(n.Args) {
				return false
			}
		}
	}
	return true
}

// safeCompile compiles the PL/pgSQL of sql with libpg_query. The compiler
// of libpg_query can crash (a WebAssembly trap) on a function without a body;
// that is its failure, reported as an error.
func safeCompile(sql string) (err error) {
	defer func() {
		if r := recover(); r != nil {
			err = fmt.Errorf("libpg_query crashes: %v", r)
		}
	}()
	_, err = ParsePlPgSQL(sql)
	return err
}

// safeProto rewrites sql with the prototype, which relies on libpg_query and
// fails with it.
func safeProto(p *Prototype, sql string) (out string, err error) {
	defer func() {
		if r := recover(); r != nil {
			err = fmt.Errorf("the prototype crashes: %v", r)
		}
	}()
	out, _, err = p.Rewrite(sql)
	return out, err
}

// requotedBody reports whether the statement is a function or a DO block whose
// body the rewriter writes with dollar quotes: the output is then not the
// input with insertions, which is as documented (the body is edited decoded).
func requotedBody(in, out string) bool {
	return len(dollarQuotes.FindAllString(out, -1)) > len(dollarQuotes.FindAllString(in, -1)) && strings.Contains(in, "'")
}

// dollarQuotes matches the delimiters of dollar-quoted strings.
var dollarQuotes = regexp.MustCompile(`\$[A-Za-z_][A-Za-z_0-9]*\$|\$\$`)

// isInsertionOnly reports whether out is in with some occurrences of ins
// added. Where a character can be matched or taken as the start of an
// insertion, both are tried.
func isInsertionOnly(in, out, ins string) bool {
	memo := map[[2]int]bool{}
	var f func(i, o int) bool
	f = func(i, o int) bool {
		for {
			if i == len(in) {
				rest := out[o:]
				return strings.Repeat(ins, strings.Count(rest, ins)) == rest
			}
			if o >= len(out) {
				return false
			}
			lit, add := in[i] == out[o], strings.HasPrefix(out[o:], ins)
			switch {
			case lit && add:
				key := [2]int{i, o}
				if r, ok := memo[key]; ok {
					return r
				}
				r := f(i+1, o+1) || f(i, o+len(ins))
				memo[key] = r
				return r
			case lit:
				i, o = i+1, o+1
			case add:
				o += len(ins)
			default:
				return false
			}
		}
	}
	return f(0, 0)
}

// TestRewriteMutations rewrites damaged statements that both parsers accept:
// the library must not panic, must give SQL that libpg_query parses and that
// is the input with insertions, and must agree with the prototype wherever
// both rewrite. REWRITE_MUTATIONS sets the number of inputs, REWRITE_SEED the seed.
func TestRewriteMutations(t *testing.T) {
	n := 20000
	if v := os.Getenv("REWRITE_MUTATIONS"); v != "" {
		fmt.Sscan(v, &n)
	}
	seed := int64(5)
	if v := os.Getenv("REWRITE_SEED"); v != "" {
		fmt.Sscan(v, &seed)
	}
	stmts := regressStatements(t, 800)
	rng := rand.New(rand.NewSource(seed))
	pool := tokenPool(stmts, rng)
	pr := newPair(t)
	for _, s := range stmts[:min(len(stmts), 4000)] {
		_ = pr.proto.Learn(s)
		_ = pr.our.Learn(s)
	}
	var bodies []string // statements with a dollar-quoted body
	for _, s := range stmts {
		if strings.Count(s, "$$") == 2 {
			bodies = append(bodies, s)
		}
	}
	var bad []string
	rewritten, refused := 0, 0
	for i := 0; i < n; i++ {
		var s string
		if i%2 == 1 && len(bodies) > 0 {
			s = mutateBody(rng, bodies[rng.Intn(len(bodies))], pool)
		} else {
			s = mutate(rng, stmts[rng.Intn(len(stmts))], pool)
		}
		if _, err := Parse(s); err != nil {
			continue
		}
		// both learn every statement, whether or not it can be rewritten; the
		// prototype is kept away from functions without a body, which trap
		// libpg_query's PL/pgSQL compiler
		if bodiesComplete(s) {
			_ = pr.proto.Learn(s)
		}
		_ = pr.our.Learn(s)
		if _, _, err := pr.our.Rewrite(s); err != nil {
			refused++
		} else {
			rewritten++
		}
		if d := rewriteIssues(pr, s); d != "" {
			bad = append(bad, fmt.Sprintf("%s\n    input: %q", d, truncate(s, 200)))
		}
	}
	t.Logf("%d accepted inputs rewritten, %d refused, %d violations", rewritten, refused, len(bad))
	for i, b := range bad {
		if i == 20 {
			t.Logf("... and %d more", len(bad)-i)
			break
		}
		t.Error(b)
	}
	_ = pgschema.Options{}
}

// FuzzRewrite checks the guarantees of the rewriter under the native fuzzer.
func FuzzRewrite(f *testing.F) {
	for _, s := range []string{
		"CREATE TABLE t (id serial PRIMARY KEY); CREATE INDEX ON t (id)",
		"CREATE TYPE mood AS ENUM ('a'); CREATE TABLE u (m mood DEFAULT 'a')",
		"WITH c AS (SELECT 1) SELECT * FROM c, t",
		"CREATE FUNCTION f() RETURNS int LANGUAGE sql AS $$ SELECT * FROM t $$",
		"SELECT nextval('t_id_seq'), 't'::regclass", "DROP TABLE IF EXISTS a, b CASCADE",
	} {
		f.Add(s)
	}
	pr := newPair(f)
	f.Fuzz(func(t *testing.T, sql string) {
		if len(sql) > 4000 {
			t.Skip()
		}
		if _, err := Parse(sql); err != nil {
			t.Skip()
		}
		if d := rewriteIssues(pr, sql); d != "" {
			t.Errorf("%s\ninput: %q", d, sql)
		}
	})
}

// FuzzLex compares the lexer with libpg_query's Scan under the native fuzzer:
// tokens, offsets, keyword categories, errors and their cursor.
//
//	go test -run '^$' -fuzz FuzzLex -fuzztime 5m .
func FuzzLex(f *testing.F) {
	for _, s := range fragments {
		f.Add(s)
	}
	for _, s := range []string{
		"SELECT 'a' 'b', E'\\x41\\u00e9', U&'d\\0061t' UESCAPE '!', $tag$ x $tag$, 1_000, 0x1F, .5e-3, a.b, \"q\"\"q\" /* c /* n */ */ -- e\n",
		"SELECT $1, $a, x::int, a<>b, a!=b, a<=b, ~~* '%', :=, =>, ..",
	} {
		f.Add(s)
	}
	f.Fuzz(func(t *testing.T, sql string) {
		// the parser entry points reject a NUL and invalid UTF-8 first, as the
		// server does; libpg_query's C string ends at a NUL
		if len(sql) > 4000 || !utf8.ValidString(sql) || strings.IndexByte(sql, 0) >= 0 {
			t.Skip()
		}
		if d, _, _, _ := diffScan(sql); d != "" {
			t.Errorf("%s\n%q", d, sql)
		}
	})
}

// TestParseErrorCases compares the errors on inputs found by fuzzing and by
// hand: the text "at or near", which runs to the end of what the scanner has
// read, and the cursor.
func TestParseErrorCases(t *testing.T) {
	for _, sql := range []string{
		"U&''UESCAPE'X'",  // the UESCAPE clause is part of the text
		"U&'a' UESCAPE",   // no escape string
		"U&'a' UESCAPE 1", // not a string
		"U&'a' UESCAPE 'ab'",
		"SELECT U&'d\\0061' UESCAPE '\\' x y",
		"SELECT U&\"d\\0061\" UESCAPE '!' FROM",
		"SELECT 1 WITH x", // WITH looks ahead, the text is WITH
		"SELECT NOT",
		"SELECT a NOT x",
		"SELECT * FROM t WITH ORDINALITY x",
		"SELECT x NULLS y",
		"SELECT 1 FORMAT JSON x",
		"CREATE TABLE t (a int) WITH OIDS",
		"SELECT",
		"SELECT 1 +",
		"SELECT ,",
	} {
		if d := compareParse(sql); d != "" {
			t.Errorf("%s\n    %q", d, sql)
		}
	}
}
