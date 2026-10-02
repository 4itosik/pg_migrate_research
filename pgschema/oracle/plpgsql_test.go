package oracle

import (
	"encoding/json"
	"fmt"
	"math/rand"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"testing"

	"github.com/4itosik/pg_migrate_research/pgschema/internal/lex"
	"github.com/4itosik/pg_migrate_research/pgschema/internal/plpgsql"
	"github.com/4itosik/pg_migrate_research/poc/harness"
	pg "github.com/pganalyze/pg_query_go/v6"
)

// This file checks internal/plpgsql against the PL/pgSQL compiler of
// libpg_query (the real pl_gram.y, run without a catalog). For every function
// or DO body of the corpus and of the regression tests that libpg_query
// compiles, the extractor must find the same embedded queries with the same
// parse modes and line numbers, the same statements with the same lines, the
// same declarations and the same dynamic SQL. Bodies that libpg_query
// rejects are listed with the reason; those it rejects for reasons that do
// not depend on the extractor (it compiles without a catalog) must still be
// extracted.

// ---- the bodies ------------------------------------------------------------

// plCase is a function or DO statement with the body the extractor gets.
type plCase struct {
	name     string
	sql      string
	body     string
	funcName string // libpg_query names the outermost block after the first part of the name
	params   []plpgsql.Param
}

// plCasesOf returns the PL/pgSQL bodies of the statement sql.
func plCasesOf(name, sql string) []plCase {
	tree, err := Parse(sql)
	if err != nil || len(tree.Stmts) != 1 {
		return nil
	}
	stmt := tree.Stmts[0].Stmt
	var opts []*pg.Node
	var params []plpgsql.Param
	funcName, isDo := "", false
	if fn := stmt.GetCreateFunctionStmt(); fn != nil {
		opts = fn.Options
		funcName = fn.Funcname[0].GetString_().Sval
		for _, p := range fn.Parameters {
			fp := p.GetFunctionParameter()
			var names []string
			for _, n := range fp.GetArgType().GetNames() {
				names = append(names, n.GetString_().Sval)
			}
			typ := strings.Join(names, ".")
			if fp.GetArgType().GetPctType() {
				typ += "%TYPE"
			}
			params = append(params, plpgsql.Param{Name: fp.Name, Type: typ})
		}
	} else if do := stmt.GetDoStmt(); do != nil {
		opts, isDo = do.Args, true
	} else {
		return nil
	}
	lang, body, bodies := "plpgsql", "", 0
	for _, o := range opts {
		d := o.GetDefElem()
		switch d.GetDefname() {
		case "language":
			lang = d.Arg.GetString_().Sval
		case "as":
			if isDo {
				body = d.Arg.GetString_().Sval
				bodies++
			} else if items := d.Arg.GetList().GetItems(); len(items) > 0 {
				body = items[len(items)-1].GetString_().Sval
				bodies += len(items)
			}
		}
	}
	if lang != "plpgsql" || bodies != 1 {
		return nil
	}
	return []plCase{{name: name, sql: sql, body: body, funcName: funcName, params: params}}
}

// plCandidate is a cheap test that keeps the statements that can be
// PL/pgSQL functions and DO blocks, so that not every statement of the
// regression tests has to be parsed twice.
var plCandidate = regexp.MustCompile(`(?i)\bplpgsql\b|\bdo\s+(\$|'|e'|language\b)`)

func plCasesOfStatements(file string, stmts []string) []plCase {
	var out []plCase
	for i, s := range stmts {
		if plCandidate.MatchString(s) {
			out = append(out, plCasesOf(fmt.Sprintf("%s#%d", file, i), s)...)
		}
	}
	return out
}

// ---- libpg_query's view ----------------------------------------------------

type plStmtRef struct {
	kind string
	line int
}

type plVarRef struct {
	name string
	line int
	typ  string // the text of the type; "" for a record
	rec  bool
}

type plRef struct {
	exprs []string // "line|mode|query"
	stmts []plStmtRef
	vars  []plVarRef
	dyn   []string
	// optional are the queries (of ours) that libpg_query may leave out: the
	// lone name of RETURN NEXT, which PL/pgSQL turns into a reference to a
	// variable without an expression when the name is a variable.
	optional []string
}

type jkv struct {
	k string
	v any
}

// jobj is a JSON object with its keys in document order.
type jobj []jkv

func (o jobj) get(k string) any {
	for _, e := range o {
		if e.k == k {
			return e.v
		}
	}
	return nil
}

func (o jobj) num(k string) int {
	f, _ := o.get(k).(float64)
	return int(f)
}

func decodeOrdered(dec *json.Decoder) (any, error) {
	tok, err := dec.Token()
	if err != nil {
		return nil, err
	}
	d, ok := tok.(json.Delim)
	if !ok {
		return tok, nil
	}
	switch d {
	case '{':
		var o jobj
		for dec.More() {
			kt, err := dec.Token()
			if err != nil {
				return nil, err
			}
			v, err := decodeOrdered(dec)
			if err != nil {
				return nil, err
			}
			o = append(o, jkv{kt.(string), v})
		}
		_, err := dec.Token()
		return o, err
	case '[':
		var a []any
		for dec.More() {
			v, err := decodeOrdered(dec)
			if err != nil {
				return nil, err
			}
			a = append(a, v)
		}
		_, err := dec.Token()
		return a, err
	}
	return nil, fmt.Errorf("unexpected delimiter %v", d)
}

// plReference compiles the statement with libpg_query and reads the result.
func plReference(sql string) (*plRef, error) {
	js, err := ParsePlPgSQL(sql)
	if err != nil {
		return nil, err
	}
	root, err := decodeOrdered(json.NewDecoder(strings.NewReader(js)))
	if err != nil {
		return nil, err
	}
	r := &plRef{}
	funcs, _ := root.([]any)
	if len(funcs) != 1 {
		return nil, fmt.Errorf("libpg_query returned %d functions", len(funcs))
	}
	fn, _ := funcs[0].(jobj)
	body, _ := fn.get("PLpgSQL_function").(jobj)
	for _, d := range body.get("datums").([]any) {
		r.datum(d)
	}
	r.walk(body.get("action"), 0)
	return r, nil
}

// datum reads an entry of the datums list: the variables with a line are
// those of the DECLARE sections, the loops and the exception blocks.
func (r *plRef) datum(v any) {
	o, _ := v.(jobj)
	for _, e := range o {
		inner, _ := e.v.(jobj)
		line := inner.num("lineno")
		name, _ := inner.get("refname").(string)
		switch e.k {
		case "PLpgSQL_var":
			if line > 0 {
				typ := ""
				if dt, ok := inner.get("datatype").(jobj); ok {
					if t, ok := dt.get("PLpgSQL_type").(jobj); ok {
						typ, _ = t.get("typname").(string)
					}
				}
				r.vars = append(r.vars, plVarRef{name: name, line: line, typ: strings.TrimRight(typ, " \t\r\n")})
			}
		case "PLpgSQL_rec":
			if line > 0 {
				r.vars = append(r.vars, plVarRef{name: name, line: line, rec: true})
			}
		}
		r.walk(e.v, line)
	}
}

// walk collects the expressions and the statements below v. line is the
// line of the innermost node that has one.
func (r *plRef) walk(v any, line int) {
	switch x := v.(type) {
	case []any:
		for _, e := range x {
			r.walk(e, line)
		}
	case jobj:
		for _, e := range x {
			inner, _ := e.v.(jobj)
			switch {
			case e.k == "PLpgSQL_expr":
				q, _ := inner.get("query").(string)
				r.exprs = append(r.exprs, fmt.Sprintf("%d|%d|%s", line, inner.num("parseMode"), q))
			case strings.HasPrefix(e.k, "PLpgSQL_stmt_"):
				kind := strings.TrimPrefix(e.k, "PLpgSQL_stmt_")
				ln := inner.num("lineno")
				if ln > 0 { // the compiler adds a RETURN and a block without a line
					r.stmts = append(r.stmts, plStmtRef{kind, ln})
				}
				switch kind {
				case "dynexecute":
					r.dyn = append(r.dyn, plpgsql.DynExecute.String())
				case "dynfors":
					r.dyn = append(r.dyn, plpgsql.DynForExecute.String())
				case "return_query":
					if inner.get("dynquery") != nil {
						r.dyn = append(r.dyn, plpgsql.DynReturnQuery.String())
					}
				case "open":
					if inner.get("dynquery") != nil {
						r.dyn = append(r.dyn, plpgsql.DynOpenExecute.String())
					}
				}
				r.walk(e.v, ln)
			case e.k == "PLpgSQL_if_elsif" || e.k == "PLpgSQL_case_when":
				r.walk(e.v, inner.num("lineno"))
			case strings.HasPrefix(e.k, "PLpgSQL_var") || e.k == "PLpgSQL_rec" || e.k == "PLpgSQL_row":
				// a variable inside a statement is also in the datums
			default:
				r.walk(e.v, line)
			}
		}
	}
}

// ---- the extractor's view --------------------------------------------------

var caseVarQuery = regexp.MustCompile(`(?s)^"__Case__Variable_\d+__" IN \((.*)\)$`)

// quoteIdent is quote_identifier for the names of cursor arguments.
func quoteIdent(name string) string {
	safe := regexp.MustCompile(`^[a-z_][a-z0-9_]*$`).MatchString(name)
	if items, err := lex.Scan(name, false); safe && err == nil && len(items) == 1 && items[0].Kind != lex.UnreservedKeyword && items[0].Kind != lex.NoKeyword {
		safe = false
	}
	if safe {
		return name
	}
	return `"` + strings.ReplaceAll(name, `"`, `""`) + `"`
}

// plOurs reads the result of the extractor in the form of plRef, with the
// transformations PL/pgSQL applies to the text of the queries undone on the
// other side or applied here.
func plOurs(b *plpgsql.Body) *plRef {
	r := &plRef{}
	argFrags := map[*plpgsql.Fragment]bool{}

	// statements
	var walk func(ss []*plpgsql.Stmt)
	var block func(blk *plpgsql.Block)
	block = func(blk *plpgsql.Block) {
		r.stmts = append(r.stmts, plStmtRef{"block", blk.Line})
		walk(blk.Stmts)
		for _, h := range blk.Handlers {
			walk(h.Stmts)
		}
	}
	walk = func(ss []*plpgsql.Stmt) {
		for _, s := range ss {
			if s.Kind == plpgsql.StmtBlock {
				block(s.Block)
				continue
			}
			r.stmts = append(r.stmts, plStmtRef{string(s.Kind), s.Line})
			// the arguments of a bound cursor are one query for PL/pgSQL
			var args []*plpgsql.Fragment
			for _, f := range s.Frags {
				if f.Kind == plpgsql.KindCursorArg {
					args = append(args, f)
					argFrags[f] = true
				}
			}
			if s.Kind != plpgsql.StmtOpen && s.Kind != plpgsql.StmtForCursor || len(args) == 0 {
				args = nil
			}
			if args != nil {
				r.exprs = append(r.exprs, fmt.Sprintf("%d|2|%s", s.Line, cursorArgsQuery(b, s, args)))
			}
			walk(s.Body)
			for _, br := range s.Branches {
				walk(br.Stmts)
			}
		}
	}
	block(b.Root)

	// fragments
	returnNext := map[*plpgsql.Fragment]bool{}
	var collect func(ss []*plpgsql.Stmt)
	collect = func(ss []*plpgsql.Stmt) {
		for _, s := range ss {
			if s.Kind == plpgsql.StmtReturnNext {
				for _, f := range s.Frags {
					returnNext[f] = true
				}
			}
			if s.Block != nil {
				collect(s.Block.Stmts)
				for _, h := range s.Block.Handlers {
					collect(h.Stmts)
				}
			}
			collect(s.Body)
			for _, br := range s.Branches {
				collect(br.Stmts)
			}
		}
	}
	collect(b.Root.Stmts)
	for _, h := range b.Root.Handlers {
		collect(h.Stmts)
	}
	// libpg_query's JSON has no default value for a record variable, and its
	// stub of the type parser makes a record of every prefix of "record"
	recDefault := map[*plpgsql.Fragment]bool{}
	for _, d := range b.Decls {
		if d.Kind != plpgsql.DeclVar || d.Value == nil {
			continue
		}
		typ := strings.ToLower(strings.TrimSpace(b.Text[d.Type.Start:d.Type.End]))
		if d.Type.Kind == plpgsql.TypeRecord || strings.HasPrefix("record", typ) {
			recDefault[d.Value] = true
		}
	}
	for _, f := range b.Fragments {
		if argFrags[f] {
			continue
		}
		q := f.SQL(b.Text)
		if f.Kind == plpgsql.KindPerform {
			q = "SELECT" + q[7:]
		}
		e := fmt.Sprintf("%d|%d|%s", f.Line, int(f.Mode), q)
		r.exprs = append(r.exprs, e)
		if (returnNext[f] && loneName(q)) || recDefault[f] {
			r.optional = append(r.optional, e)
		}
	}

	// declarations
	for _, d := range b.Decls {
		switch d.Kind {
		case plpgsql.DeclVar, plpgsql.DeclCursorArg:
			if d.Type.Kind == plpgsql.TypeRecord {
				r.vars = append(r.vars, plVarRef{name: d.Name, line: d.Line, rec: true})
			} else {
				r.vars = append(r.vars, plVarRef{name: d.Name, line: d.Line, typ: strings.TrimSpace(b.Text[d.Type.Start:d.Type.End])})
			}
		case plpgsql.DeclCursor:
			r.vars = append(r.vars, plVarRef{name: d.Name, line: d.Line, typ: "pg_catalog.refcursor"})
		}
	}

	for _, d := range b.Dynamic {
		r.dyn = append(r.dyn, d.Kind.String())
	}
	return r
}

// loneName reports whether the text is a name or a dotted name.
func loneName(text string) bool {
	items, err := lex.Scan(text, false)
	if err != nil || len(items) == 0 || len(items)%2 == 0 {
		return false
	}
	for i, it := range items {
		if i%2 == 0 && it.Tok != lex.IDENT && it.Kind == lex.NoKeyword || i%2 == 1 && it.Tok != lex.Token('.') {
			return false
		}
	}
	return true
}

// cursorArgsQuery is the query read_cursor_args builds from the arguments of
// a bound cursor: the arguments in the order of the parameters, each with its
// name when one of them was written in named notation.
func cursorArgsQuery(b *plpgsql.Body, s *plpgsql.Stmt, args []*plpgsql.Fragment) string {
	cursor := s.Cursor
	if i := strings.LastIndexByte(cursor, '.'); i >= 0 {
		cursor = cursor[i+1:]
	}
	var params []string
	for _, d := range b.Decls {
		if d.Kind == plpgsql.DeclCursor && d.Name == cursor {
			for _, a := range d.Args {
				params = append(params, a.Name)
			}
		}
	}
	argv := make([]string, max(len(params), len(args)))
	named := false
	for i, f := range args {
		pos := i
		if f.Name != "" {
			named = true
			for j, p := range params {
				if p == f.Name {
					pos = j
				}
			}
		}
		argv[pos] = b.Text[f.Start:f.End]
	}
	var parts []string
	for j, a := range argv {
		if named && j < len(params) {
			a += " AS " + quoteIdent(params[j])
		}
		parts = append(parts, a)
	}
	return strings.Join(parts, ", ")
}

// ---- comparison ------------------------------------------------------------

// multisetDiff returns the elements only in a and only in b.
func multisetDiff(a, b []string) (onlyA, onlyB []string) {
	a, b = append([]string(nil), a...), append([]string(nil), b...)
	sort.Strings(a)
	sort.Strings(b)
	i, j := 0, 0
	for i < len(a) || j < len(b) {
		switch {
		case j == len(b) || (i < len(a) && a[i] < b[j]):
			onlyA = append(onlyA, a[i])
			i++
		case i == len(a) || b[j] < a[i]:
			onlyB = append(onlyB, b[j])
			j++
		default:
			i++
			j++
		}
	}
	return
}

// plDiff compares the extractor's result with libpg_query's and returns the
// groups of differences: "" key for none.
func plDiff(b *plpgsql.Body, ref *plRef) map[string]string {
	ours := plOurs(b)
	out := map[string]string{}

	// queries: libpg_query rewrites the WHEN list of a CASE with a selector
	var theirs []string
	for _, e := range ref.exprs {
		parts := strings.SplitN(e, "|", 3)
		if m := caseVarQuery.FindStringSubmatch(parts[2]); m != nil {
			e = parts[0] + "|" + parts[1] + "|" + m[1]
		}
		theirs = append(theirs, e)
	}
	onlyT, onlyO := multisetDiff(theirs, ours.exprs)
	for _, opt := range ours.optional {
		for i, e := range onlyO {
			if e == opt {
				onlyO = append(onlyO[:i], onlyO[i+1:]...)
				break
			}
		}
	}
	if len(onlyT)+len(onlyO) > 0 {
		out["queries"] = fmt.Sprintf("only libpg_query: %q; only ours: %q", onlyT, onlyO)
	}

	// statements, in order
	ts, us := make([]string, len(ref.stmts)), make([]string, len(ours.stmts))
	for i, s := range ref.stmts {
		ts[i] = fmt.Sprintf("%s@%d", s.kind, s.line)
	}
	for i, s := range ours.stmts {
		us[i] = fmt.Sprintf("%s@%d", s.kind, s.line)
	}
	if strings.Join(ts, " ") != strings.Join(us, " ") {
		onlyT, onlyO := multisetDiff(ts, us)
		out["statements"] = fmt.Sprintf("libpg_query %d, ours %d; only libpg_query: %v; only ours: %v", len(ts), len(us), onlyT, onlyO)
	}

	// dynamic SQL
	if onlyT, onlyO := multisetDiff(ref.dyn, ours.dyn); len(onlyT)+len(onlyO) > 0 {
		out["dynamic"] = fmt.Sprintf("only libpg_query: %v; only ours: %v", onlyT, onlyO)
	}

	// declarations
	if d := declDiff(b, ref); d != "" {
		out["declarations"] = d
	}
	return out
}

// declDiff compares the declarations. libpg_query also lists the variables
// that statements declare (the loop variables of FOR, the variable of CASE,
// SQLSTATE and SQLERRM); they are matched by name against the statements.
func declDiff(b *plpgsql.Body, ref *plRef) string {
	ours := plOurs(b)
	implicit := map[string]int{} // names the statements declare
	var scan func(ss []*plpgsql.Stmt)
	var block func(blk *plpgsql.Block)
	block = func(blk *plpgsql.Block) {
		if len(blk.Handlers) > 0 {
			implicit["sqlstate"]++
			implicit["sqlerrm"]++
		}
		scan(blk.Stmts)
		for _, h := range blk.Handlers {
			scan(h.Stmts)
		}
	}
	scan = func(ss []*plpgsql.Stmt) {
		for _, s := range ss {
			if s.Kind == plpgsql.StmtBlock {
				block(s.Block)
				continue
			}
			switch s.Kind {
			case plpgsql.StmtForInt, plpgsql.StmtForCursor:
				implicit[s.Vars[0]]++
			case plpgsql.StmtCase:
				if len(s.Frags) > 0 {
					implicit["__Case__Variable_"]++
				}
			}
			scan(s.Body)
			for _, br := range s.Branches {
				scan(br.Stmts)
			}
		}
	}
	block(b.Root)

	used := make([]bool, len(ours.vars))
	var problems []string
nextTheirs:
	for _, tv := range ref.vars {
		for i, ov := range ours.vars {
			if used[i] || ov.name != tv.name || ov.line != tv.line {
				continue
			}
			// a comment after "record" makes libpg_query's stub see a scalar
			if ov.rec && !tv.rec && sameType(strings.ToLower(tv.typ), "record") {
				used[i] = true
				continue nextTheirs
			}
			// libpg_query's stub of the type parser makes a record of every type
			// text that is a prefix of "record" (the type "rec")
			if !ov.rec && tv.rec && ov.typ != "" && strings.HasPrefix("record", strings.ToLower(ov.typ)) {
				used[i] = true
				continue nextTheirs
			}
			if ov.rec != tv.rec {
				continue
			}
			if tv.rec || sameType(tv.typ, ov.typ) {
				used[i] = true
				continue nextTheirs
			}
		}
		key := tv.name
		if strings.HasPrefix(key, "__Case__Variable_") {
			key = "__Case__Variable_"
		}
		if implicit[key] > 0 {
			implicit[key]--
			continue
		}
		problems = append(problems, fmt.Sprintf("only libpg_query: %s line %d %q rec=%v", tv.name, tv.line, tv.typ, tv.rec))
	}
	for i, ov := range ours.vars {
		if !used[i] {
			problems = append(problems, fmt.Sprintf("only ours: %s line %d %q rec=%v", ov.name, ov.line, ov.typ, ov.rec))
		}
	}
	return strings.Join(problems, "; ")
}

// sameType compares the text of a type: libpg_query's text runs up to the
// next token and may carry comments after the type.
func sameType(theirs, ours string) bool {
	if theirs == ours {
		return true
	}
	if !strings.HasPrefix(theirs, ours) {
		return false
	}
	items, err := lex.Scan(theirs[len(ours):], false)
	return err == nil && len(items) == 0
}

// ---- the report ------------------------------------------------------------

// plExplained are the reasons libpg_query rejects a body that PostgreSQL
// accepts: it compiles without a catalog, and so the types of the variables
// are not known (every parameter has an unknown type, a variable of a
// composite type is a scalar to it, a refcursor parameter is not a cursor)
// and it has no function result type (RETURN NEXT needs a SETOF function and
// no OUT parameters).
var plExplained = []*regexp.Regexp{
	regexp.MustCompile(`is not a known variable$`),
	regexp.MustCompile(`is not a scalar variable$`),
	regexp.MustCompile(`^cursor variable must be a simple variable$`),
	regexp.MustCompile(`^variable ".*" must be of type cursor or refcursor$`),
	regexp.MustCompile(`^cursor FOR loop must use a bound cursor variable$`),
	regexp.MustCompile(`^variable ".*" does not exist$`),
	regexp.MustCompile(`^RETURN NEXT cannot have a parameter in function with OUT parameters$`),
	regexp.MustCompile(`^cannot use RETURN NEXT in a non-SETOF function$`),
	regexp.MustCompile(`^cannot use RETURN QUERY in a non-SETOF function$`),
	regexp.MustCompile(`^cursor ".*" has arguments$`),
	regexp.MustCompile(`^cursor ".*" has no arguments$`),
	regexp.MustCompile(`^FETCH statement cannot return multiple rows$`),
}

var quotedText = regexp.MustCompile(`"[^"]*"`)

// plSampleLen is how much of a body the log shows (PL_SAMPLE changes it).
var plSampleLen = func() int {
	n := 100
	if v := os.Getenv("PL_SAMPLE"); v != "" {
		fmt.Sscan(v, &n)
	}
	return n
}()

type plStats struct {
	bodies, compared, queries, stmts, decls, dynamic int
	rejected                                         int
	oursAcceptsRejected                              int
	mismatches                                       map[string]int
	kinds                                            map[string]int // statements and fragments compared, by kind
	samples                                          map[string][]string
	rejectedBy                                       map[string]*plRejected
	failures                                         []string
	compiled                                         []plCase // the cases libpg_query compiles
}

type plRejected struct {
	count, oursOK int
	explained     bool
	samples       []string
}

// plCompare runs the extractor and libpg_query on every case.
func plCompare(t *testing.T, cases []plCase) *plStats {
	st := &plStats{kinds: map[string]int{}, mismatches: map[string]int{}, samples: map[string][]string{}, rejectedBy: map[string]*plRejected{}}
	for _, c := range cases {
		st.bodies++
		got, perr := plpgsql.Parse(c.body, &plpgsql.Options{Name: c.funcName, Params: c.params})
		ref, rerr := plReference(c.sql)
		if rerr != nil {
			st.rejected++
			msg, _ := ErrorInfo(rerr)
			key := quotedText.ReplaceAllString(msg, `"X"`)
			g := st.rejectedBy[key]
			if g == nil {
				g = &plRejected{}
				for _, re := range plExplained {
					if re.MatchString(msg) {
						g.explained = true
					}
				}
				st.rejectedBy[key] = g
			}
			g.count++
			if perr == nil {
				g.oursOK++
				st.oursAcceptsRejected++
			}
			if len(g.samples) < 3 {
				res := "extractor accepts"
				if perr != nil {
					res = "extractor rejects: " + perr.Error()
				}
				g.samples = append(g.samples, fmt.Sprintf("%s [%s] (%s): %s", c.name, res, msg, truncate(strings.ReplaceAll(c.body, "\n", " "), plSampleLen)))
			}
			if g.explained && perr != nil {
				st.failures = append(st.failures, fmt.Sprintf("%s: libpg_query rejects (%s), the extractor must accept: %v", c.name, msg, perr))
			}
			continue
		}
		if perr != nil {
			st.mismatches["extractor fails"]++
			st.add("extractor fails", fmt.Sprintf("%s: %v\n    %s", c.name, perr, truncate(strings.ReplaceAll(c.body, "\n", " "), 200)))
			continue
		}
		st.compared++
		st.compiled = append(st.compiled, c)
		st.queries += len(ref.exprs)
		st.stmts += len(ref.stmts)
		st.decls += len(ref.vars)
		st.dynamic += len(ref.dyn)
		for _, s := range ref.stmts {
			st.kinds["stmt "+s.kind]++
		}
		for _, e := range ref.exprs {
			st.kinds[fmt.Sprintf("mode %s", strings.SplitN(e, "|", 3)[1])]++
		}
		for kind, detail := range plDiff(got, ref) {
			st.mismatches[kind]++
			st.add(kind, fmt.Sprintf("%s: %s\n    %s", c.name, detail, truncate(strings.ReplaceAll(c.body, "\n", " "), 200)))
		}
	}
	return st
}

func (st *plStats) add(group, sample string) {
	if len(st.samples[group]) < 5 {
		st.samples[group] = append(st.samples[group], sample)
	}
}

// report logs the numbers and the groups, and fails on a mismatch.
func (st *plStats) report(t *testing.T) {
	total := 0
	for _, n := range st.mismatches {
		total += n
	}
	t.Logf("%d bodies: libpg_query compiles %d (%d queries, %d statements, %d variables, %d dynamic SQL), %d mismatching bodies; libpg_query rejects %d, the extractor accepts %d of them",
		st.bodies, st.compared, st.queries, st.stmts, st.decls, st.dynamic, total, st.rejected, st.oursAcceptsRejected)
	var kinds []string
	for k, n := range st.kinds {
		kinds = append(kinds, fmt.Sprintf("%s %d", k, n))
	}
	sort.Strings(kinds)
	t.Logf("compared: %s", strings.Join(kinds, ", "))
	var keys []string
	for k := range st.rejectedBy {
		keys = append(keys, k)
	}
	sort.Slice(keys, func(i, j int) bool {
		if st.rejectedBy[keys[i]].count != st.rejectedBy[keys[j]].count {
			return st.rejectedBy[keys[i]].count > st.rejectedBy[keys[j]].count
		}
		return keys[i] < keys[j]
	})
	for _, k := range keys {
		g := st.rejectedBy[k]
		kind := "an error in the body"
		if g.explained {
			kind = "no catalog"
		}
		t.Logf("libpg_query rejects: %3d (%d accepted by the extractor), %s: %s", g.count, g.oursOK, kind, k)
		for _, s := range g.samples {
			t.Logf("        %s", s)
		}
	}
	var groups []string
	for k := range st.mismatches {
		groups = append(groups, k)
	}
	sort.Strings(groups)
	for _, k := range groups {
		t.Errorf("mismatch group %q: %d bodies", k, st.mismatches[k])
		for _, s := range st.samples[k] {
			t.Errorf("        %s", s)
		}
	}
	for i, f := range st.failures {
		if i == 20 {
			t.Errorf("... and %d more", len(st.failures)-i)
			break
		}
		t.Error(f)
	}
}

// ---- mutations -------------------------------------------------------------

// plGaps are the separators the mutations put between the tokens of a body.
// None of them can join two tokens: each has white space or a comment; the
// comments end where the line ends.
var plGaps = []string{
	" ", " ", " ", " ", " ", " ", " ", " ",
	"\n", "\n", "\n", "\n\t  ", "  ", "\t", "\r\n",
	" /* c; end; loop */ ", " /* a\nb */ ", "/**/", " /* /* nested */ */ ",
	" -- c; then\n", "\n-- x\n", " --\n",
}

// plMutate rewrites the white space and the comments of a body: every gap
// between two tokens (and before the first, after the last) becomes one of
// plGaps. The statement text is rebuilt around the new body. The mutation
// moves every line number and puts comments where statements and fragments
// end, which is what the extractor's ranges must tolerate.
func plMutate(c plCase, rnd *rand.Rand) (plCase, bool) {
	items, err := lex.Scan(c.body, false)
	if err != nil || len(items) == 0 {
		return c, false
	}
	var b strings.Builder
	// libpg_query's parser does not look past a comment for the second word of
	// WITH ORDINALITY, WITH TIME ZONE, NOT LIKE, NULLS FIRST, WITHOUT TIME ZONE
	// and FORMAT JSON: the gaps after these words are white space
	plain := []string{" ", "\n", "  ", "\t", "\r\n"}
	gap := func(prev lex.Token, strs bool) string {
		switch {
		case strs: // two strings in a row must not be one literal
			return " "
		case prev == lex.WITH || prev == lex.NOT || prev == lex.NULLS_P || prev == lex.WITHOUT || prev == lex.FORMAT:
			return plain[rnd.Intn(len(plain))]
		}
		return plGaps[rnd.Intn(len(plGaps))]
	}
	b.WriteString(gap(0, false))
	for i, it := range items {
		if i > 0 {
			prev := c.body[items[i-1].Start:items[i-1].End]
			next := c.body[it.Start:it.End]
			b.WriteString(gap(items[i-1].Tok, strings.HasSuffix(prev, "'") && strings.HasPrefix(next, "'")))
		}
		b.WriteString(c.body[it.Start:it.End])
	}
	b.WriteString(gap(0, false))
	body := b.String()
	if strings.Contains(body, "$pgs$") {
		return c, false
	}
	sqlItems, err := lex.Scan(c.sql, false)
	if err != nil {
		return c, false
	}
	for _, it := range sqlItems {
		if it.Tok == lex.SCONST && it.Str == c.body {
			out := c
			out.body = body
			out.sql = c.sql[:it.Start] + "$pgs$" + body + "$pgs$" + c.sql[it.End:]
			return out, true
		}
	}
	return c, false
}

// plMutations returns n mutations of every case.
func plMutations(cases []plCase, n int, seed int64) []plCase {
	rnd := rand.New(rand.NewSource(seed))
	var out []plCase
	for _, c := range cases {
		for i := 0; i < n; i++ {
			if m, ok := plMutate(c, rnd); ok {
				m.name = fmt.Sprintf("%s~%d", c.name, i)
				out = append(out, m)
			}
		}
	}
	return out
}

// plMutationRuns reads PL_MUTATIONS (the mutations per body, default 2) and
// PL_SEED.
func plMutationRuns() (n int, seed int64) {
	n, seed = 2, 1
	if v := os.Getenv("PL_MUTATIONS"); v != "" {
		fmt.Sscan(v, &n)
	}
	if v := os.Getenv("PL_SEED"); v != "" {
		fmt.Sscan(v, &seed)
	}
	return
}

// plCheckMutations compares the mutated bodies of the cases that libpg_query
// compiles. libpg_query must compile the mutations too: they only change
// white space and comments.
func plCheckMutations(t *testing.T, st *plStats) {
	n, seed := plMutationRuns()
	if n == 0 {
		return
	}
	m := plMutations(st.compiled, n, seed)
	mst := plCompare(t, m)
	t.Logf("mutations: %d bodies (%d per body, seed %d)", len(m), n, seed)
	for k, g := range mst.rejectedBy {
		// libpg_query's stub of the type parser compares the whole text of a
		// type with "record" and "text", comment after it included: a comment
		// after "record" makes a scalar variable of it, and a variable of type
		// text with a comment has no collation
		if g.explained || strings.HasPrefix(k, "collations are not supported by type") {
			t.Logf("libpg_query rejects a mutation (%d bodies, a comment after the type of a declaration): %s", g.count, k)
			continue
		}
		t.Errorf("libpg_query rejects a mutation (%d bodies): %s", g.count, k)
		for _, s := range g.samples {
			t.Errorf("        %s", s)
		}
	}
	mst.rejectedBy = nil
	mst.failures = nil
	mst.report(t)
}

// ---- the tests -------------------------------------------------------------

// TestPlpgsqlCorpus compares the extractor with libpg_query on every
// PL/pgSQL body of the migration corpus.
func TestPlpgsqlCorpus(t *testing.T) {
	cases, err := harness.LoadCorpus(corpusDir())
	if err != nil {
		t.Fatal(err)
	}
	var pl []plCase
	for _, c := range cases {
		var texts []string
		for _, m := range c.Migrations {
			texts = append(texts, m.Up, m.Down)
		}
		texts = append(texts, c.Setup, c.Check)
		for i, text := range texts {
			pl = append(pl, plCasesOfStatements(fmt.Sprintf("corpus/%s/%d", c.Name, i), SplitStatements(text))...)
		}
	}
	if len(pl) == 0 {
		t.Fatal("no PL/pgSQL bodies in the corpus")
	}
	st := plCompare(t, pl)
	st.report(t)
	plCheckMutations(t, st)
	plCheckBroken(t, st)
}

// TestPlpgsqlRegress compares the extractor with libpg_query on the
// PL/pgSQL functions and DO blocks of the regression tests (PL_VERSIONS
// limits the branches, e.g. "REL_16_STABLE").
func TestPlpgsqlRegress(t *testing.T) {
	root := os.Getenv("REGRESS_ROOT")
	if root == "" {
		skipUnlessCI(t, "REGRESS_ROOT is not set; run tools/get-data.sh and source tools/env.sh")
	}
	branches := []string{"REL_12_STABLE", "REL_13_STABLE", "REL_14_STABLE", "REL_15_STABLE", "REL_16_STABLE"}
	if v := os.Getenv("PL_VERSIONS"); v != "" {
		branches = strings.Fields(v)
	}
	report := map[string]any{}
	for _, branch := range branches {
		t.Run(branch, func(t *testing.T) {
			files, err := LoadRegress(filepath.Join(root, branch))
			if err != nil {
				skipUnlessCI(t, err.Error())
			}
			var pl []plCase
			for _, f := range files {
				pl = append(pl, plCasesOfStatements(f.Name, f.Statements)...)
			}
			st := plCompare(t, pl)
			st.report(t)
			plCheckMutations(t, st)
			plCheckBroken(t, st)
			mism := 0
			for _, n := range st.mismatches {
				mism += n
			}
			report[branch] = map[string]any{
				"bodies": st.bodies, "compiled_by_libpg_query": st.compared, "queries": st.queries,
				"statements": st.stmts, "variables": st.decls, "dynamic": st.dynamic,
				"mismatching_bodies": mism, "rejected_by_libpg_query": st.rejected,
				"rejected_but_extracted": st.oursAcceptsRejected,
			}
		})
	}
	if out := os.Getenv("METRICS_OUT"); out != "" && !t.Failed() && os.Getenv("PL_VERSIONS") == "" {
		if err := UpdateMetrics(out, []string{"stage3", "plpgsql", "regress"}, report); err != nil {
			t.Fatal(err)
		}
	}
}

// TestPlpgsqlSynthetic compares the extractor with libpg_query on the
// statements of plSynthetic. libpg_query must compile every one of them.
func TestPlpgsqlSynthetic(t *testing.T) {
	var pl []plCase
	for i, s := range plSynthetic {
		cs := plCasesOf(fmt.Sprintf("synthetic#%d", i), s)
		if len(cs) != 1 {
			t.Fatalf("synthetic#%d is not a PL/pgSQL function: %.60q", i, s)
		}
		pl = append(pl, cs...)
	}
	st := plCompare(t, pl)
	for k, g := range st.rejectedBy {
		t.Errorf("libpg_query rejects a synthetic body: %s", k)
		for _, s := range g.samples {
			t.Errorf("        %s", s)
		}
	}
	st.rejectedBy = nil
	st.report(t)
	plCheckMutations(t, st)
	plCheckBroken(t, st)
}

// ---- broken bodies ---------------------------------------------------------

// plBreak damages a body: one token is deleted, doubled or replaced by
// another token of the body. Most results are not valid PL/pgSQL; the ones
// libpg_query still compiles are valid inputs that must be extracted the same
// way. The decisions the grammar takes by the table of variables (assignment
// or SQL, cursor or query) come out differently from the structure often
// enough in these bodies to test the structural rules.
func plBreak(c plCase, rnd *rand.Rand) (plCase, bool) {
	items, err := lex.Scan(c.body, false)
	if err != nil || len(items) < 3 {
		return c, false
	}
	i := rnd.Intn(len(items))
	text := func(j int) string { return c.body[items[j].Start:items[j].End] }
	var repl string
	switch rnd.Intn(3) {
	case 0: // delete
		repl = " "
	case 1: // double
		repl = text(i) + " " + text(i)
	default: // replace by another token
		repl = " " + text(rnd.Intn(len(items))) + " "
	}
	body := c.body[:items[i].Start] + repl + c.body[items[i].End:]
	if strings.Contains(body, "$pgs$") {
		return c, false
	}
	sqlItems, err := lex.Scan(c.sql, false)
	if err != nil {
		return c, false
	}
	for _, it := range sqlItems {
		if it.Tok == lex.SCONST && it.Str == c.body {
			out := c
			out.body = body
			out.sql = c.sql[:it.Start] + "$pgs$" + body + "$pgs$" + c.sql[it.End:]
			return out, true
		}
	}
	return c, false
}

// plKeywordNames are names for variables that PL/pgSQL or SQL also uses as
// keywords. PL/pgSQL tells a variable from a keyword with the table of
// variables; the extractor must tell them by structure.
var plKeywordNames = []string{
	"perform", "call", "get", "exit", "continue", "return", "raise", "assert", "open", "fetch",
	"move", "close", "commit", "rollback", "insert", "import", "merge", "error", "log", "info",
	"notice", "warning", "debug", "type", "row_count", "next", "prior", "first", "last", "absolute",
	"relative", "forward", "backward", "scroll", "no", "alias", "constant", "cursor", "default",
	"collate", "current", "stacked", "slice", "reverse", "diagnostics", "elsif", "exception", "array",
	"and", "is", "table", "schema", "query", "message", "detail", "hint", "column", "constraint",
	"datatype", "option", "dump", "chain", "do", "select", "update", "delete", "values", "set", "reset",
	"show", "create", "drop", "alter", "truncate", "explain", "analyze", "vacuum", "lock", "grant",
	"listen", "notify", "comment", "copy", "prepare", "with", "returning", "end_", "sqlstate", "found",
}

// plRenameVars renames a variable of the DECLARE sections of a body to a
// keyword-like name, in every place the name stands as an identifier. The
// compiler of libpg_query has the new name in its table of variables.
func plRenameVars(c plCase, rnd *rand.Rand) (plCase, bool) {
	b, err := plpgsql.Parse(c.body, &plpgsql.Options{Name: c.funcName, Params: c.params})
	if err != nil {
		return c, false
	}
	var names []string
	for _, d := range b.Decls {
		if d.Kind == plpgsql.DeclVar || d.Kind == plpgsql.DeclCursor {
			names = append(names, d.Name)
		}
	}
	items, err := lex.Scan(c.body, false)
	if err != nil || len(names) == 0 {
		return c, false
	}
	old, repl := names[rnd.Intn(len(names))], plKeywordNames[rnd.Intn(len(plKeywordNames))]
	var sb strings.Builder
	last := 0
	for _, it := range items {
		if it.Tok == lex.IDENT && c.body[it.Start] != '"' && it.Str == old {
			sb.WriteString(c.body[last:it.Start])
			sb.WriteString(repl)
			last = int(it.End)
		}
	}
	sb.WriteString(c.body[last:])
	body := sb.String()
	sqlItems, err := lex.Scan(c.sql, false)
	if err != nil || body == c.body {
		return c, false
	}
	for _, it := range sqlItems {
		if it.Tok == lex.SCONST && it.Str == c.body {
			out := c
			out.body = body
			out.sql = c.sql[:it.Start] + "$pgs$" + body + "$pgs$" + c.sql[it.End:]
			return out, true
		}
	}
	return c, false
}

// plCheckBroken runs the extractor and libpg_query on damaged copies of the
// bodies libpg_query compiles (PL_BROKEN of them per body, default 4) and on
// copies with a variable renamed to a keyword. When libpg_query compiles a
// copy, the extractor must extract the same; when it rejects it, the
// extractor may do either, and the log tells how many it accepts.
func plCheckBroken(t *testing.T, st *plStats) {
	per := 4
	if v := os.Getenv("PL_BROKEN"); v != "" {
		fmt.Sscan(v, &per)
	}
	_, seed := plMutationRuns()
	plCheckDamaged(t, st, "damaged", per, rand.New(rand.NewSource(seed+1000)), plBreak)
	plCheckDamaged(t, st, "renamed", per, rand.New(rand.NewSource(seed+2000)), plRenameVars)
}

func plCheckDamaged(t *testing.T, st *plStats, label string, per int, rnd *rand.Rand, damage func(plCase, *rand.Rand) (plCase, bool)) {
	var compiled, bothRejected, lenient int
	mism := map[string]int{}
	samples := map[string][]string{}
	lenientBy := map[string]int{}
	for _, c := range st.compiled {
		for i := 0; i < per; i++ {
			m, ok := damage(c, rnd)
			if !ok {
				continue
			}
			ref, rerr := plReference(m.sql)
			got, perr := plpgsql.Parse(m.body, &plpgsql.Options{Name: m.funcName, Params: m.params})
			switch {
			case rerr != nil && perr != nil:
				bothRejected++
			case rerr != nil:
				lenient++
				msg, _ := ErrorInfo(rerr)
				lenientBy[quotedText.ReplaceAllString(msg, `"X"`)]++
			case perr != nil:
				mism["extractor fails"]++
				if len(samples["extractor fails"]) < 5 {
					samples["extractor fails"] = append(samples["extractor fails"], fmt.Sprintf("%s: %v\n    %s", m.name, perr, truncate(strings.ReplaceAll(m.body, "\n", " "), plSampleLen)))
				}
			default:
				compiled++
				for kind, detail := range plDiff(got, ref) {
					mism[kind]++
					if len(samples[kind]) < 5 {
						samples[kind] = append(samples[kind], fmt.Sprintf("%s: %s\n    %s", m.name, detail, truncate(strings.ReplaceAll(m.body, "\n", " "), plSampleLen)))
					}
				}
			}
		}
	}
	t.Logf("%s bodies: libpg_query compiles %d (extracted the same), rejects %d: the extractor rejects %d of those too and accepts %d", label, compiled, bothRejected+lenient, bothRejected, lenient)
	var keys []string
	for k := range lenientBy {
		keys = append(keys, k)
	}
	sort.Slice(keys, func(i, j int) bool { return lenientBy[keys[i]] > lenientBy[keys[j]] })
	for i, k := range keys {
		if i == 8 {
			break
		}
		t.Logf("  extractor accepts, libpg_query rejects: %4d  %s", lenientBy[k], k)
	}
	for k, c := range mism {
		t.Errorf("%s bodies, group %q: %d", label, k, c)
		for _, s := range samples[k] {
			t.Errorf("        %s", s)
		}
	}
}
