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
	"github.com/4itosik/pg_migrate_research/pgschema/internal/lex"
	"github.com/4itosik/pg_migrate_research/pgschema/internal/parse"
	"github.com/4itosik/pg_migrate_research/poc/harness"
)

// compareParse parses sql with the library and with libpg_query and returns
// a description of the first difference, or "": acceptance, the error message
// and its cursor, the trees with the positions.
//
// Two differences from libpg_query are deliberate and not reported, see
// docs/differences.md: the library checks the encoding of the whole text first,
// as PostgreSQL does before it parses (libpg_query does not), and it does not
// accept the parameter markers ($1) that libpg_query's own patches allow in
// the places of string constants (PASSWORD $1, SET search_path = $1,
// type $1), where PostgreSQL itself gives a syntax error.
func compareParse(sql string) string {
	theirs, werr := Parse(sql)
	ours, gerr := parse.Parse(sql)
	var ie *parse.InternalError
	if errors.As(gerr, &ie) {
		return fmt.Sprintf("the library panics: %v\n%s", ie.Value, ie.Stack)
	}
	if !utf8.ValidString(sql) {
		if ge, ok := gerr.(*parse.Error); !ok || !strings.HasPrefix(ge.Msg, "invalid byte sequence for encoding") {
			return fmt.Sprintf("invalid UTF-8 is not rejected as PostgreSQL does: %v", gerr)
		}
		return ""
	}
	switch {
	case werr == nil && gerr != nil && paramMarkerError.MatchString(gerr.Error()):
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
			bad = append(bad, fmt.Sprintf("%s\n    %q", d, truncate(s, 200)))
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
		if want, _, perr := p.proto.Rewrite(sql); perr == nil && want != sql {
			return fmt.Sprintf("the library refuses (%v), the prototype rewrites to %q", err, truncate(want, 200))
		}
		return ""
	}
	if _, perr := Parse(out); perr != nil {
		return fmt.Sprintf("libpg_query does not parse the output: %v\n    output: %q", perr, truncate(out, 200))
	}
	// a body that libpg_query compiles must compile after the rewriting; the
	// output for a body it does not compile is not compared with the
	// prototype's, because the library reads such a body more leniently
	_, cerr := ParsePlPgSQL(sql)
	if cerr == nil {
		if _, cerr := ParsePlPgSQL(out); cerr != nil {
			return fmt.Sprintf("libpg_query compiles the input body but not the output: %v\n    output: %q", cerr, truncate(out, 200))
		}
	}
	if !isInsertionOnly(sql, out, "auth.") && !requotedBody(sql, out) {
		return fmt.Sprintf("the output is not the input with insertions of %q\n    output: %q", "auth.", truncate(out, 200))
	}
	if want, _, perr := p.proto.Rewrite(sql); perr == nil && want != out && cerr == nil && !junkAfterType(sql) {
		return fmt.Sprintf("the output differs from the prototype's:\n%s", firstDiff(want, out))
	}
	return ""
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
		case "collate", "not", "default":
		default:
			return true
		}
	}
	return false
}

// requotedBody reports whether the statement is a function or a DO block whose
// body the rewriter writes with dollar quotes: the output is then not the
// input with insertions, which is as documented (the body is edited decoded).
func requotedBody(in, out string) bool {
	return !strings.Contains(in, "$") && strings.Contains(out, "$") && strings.Contains(strings.ToLower(in), "'")
}

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
// both rewrite. REWRITE_MUTATIONS sets the number of inputs.
func TestRewriteMutations(t *testing.T) {
	n := 20000
	if v := os.Getenv("REWRITE_MUTATIONS"); v != "" {
		fmt.Sscan(v, &n)
	}
	stmts := regressStatements(t, 800)
	rng := rand.New(rand.NewSource(5))
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
		// both learn every statement, whether or not it can be rewritten
		_ = pr.proto.Learn(s)
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
