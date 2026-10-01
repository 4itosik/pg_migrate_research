package pgqrewrite

import (
	"encoding/json"
	"errors"
	"fmt"
	"strings"

	pg "github.com/pganalyze/pg_query_go/v6"
	pgquery "github.com/wasilibs/go-pgquery"
)

// createFunction qualifies the function name and rewrites a SQL or PL/pgSQL
// body given as a string. A SQL-standard body (BEGIN ATOMIC) is part of the
// main parse tree and is visited as a regular child.
func (w *walker) createFunction(n *pg.CreateFunctionStmt) {
	anchor := pg.Token_FUNCTION
	if n.IsProcedure {
		anchor = pg.Token_PROCEDURE
	}
	w.defName(&n.Funcname, kindFunction, anchor)
	as := defElem(n.Options, "as")
	if as == nil {
		return
	}
	items := as.GetArg().GetList().GetItems()
	if len(items) != 1 { // C function: AS 'obj_file', 'link_symbol'
		return
	}
	str := items[0].GetString_()
	var newBody string
	var err error
	switch lang := language(n.Options, "sql"); lang {
	case "sql":
		newBody, err = w.sqlBody(str.Sval)
	case "plpgsql":
		newBody, err = w.plpgsqlBody(w.stmtText(), str.Sval)
	default:
		w.warn("function body in LANGUAGE %s is not rewritten: %s", lang, snippet(w.stmtText()))
		return
	}
	if err != nil {
		w.fail("function %s: %v", strings.Join(strs(n.Funcname), "."), err)
		return
	}
	w.replaceBody(w.toks.findToken(w.toks.firstFrom(int(as.Location)), w.tokEnd, pg.Token_SCONST), str, newBody)
}

func (w *walker) doStmt(n *pg.DoStmt) {
	as := defElem(n.Args, "as")
	if as == nil {
		return
	}
	if lang := language(n.Args, "plpgsql"); lang != "plpgsql" {
		w.warn("DO block in LANGUAGE %s is not rewritten: %s", lang, snippet(w.stmtText()))
		return
	}
	str := as.GetArg().GetString_()
	i := w.toks.at(int(as.Location))
	if i < 0 {
		w.fail("cannot locate DO block body")
		return
	}
	newBody, err := w.plpgsqlBody(doWrapper+w.toks.text(i), str.Sval)
	if err != nil {
		w.fail("DO block: %v", err)
		return
	}
	w.replaceBody(i, str, newBody)
}

// replaceBody replaces the body literal at token i. A dollar-quoted body keeps
// its tag; other literals are re-quoted with dollar quotes.
func (w *walker) replaceBody(i int, str *pg.String, newBody string) {
	if w.learnOnly || newBody == str.Sval {
		return
	}
	if i < 0 || !w.toks.is(i, pg.Token_SCONST) {
		w.fail("cannot locate function body literal")
		return
	}
	tok := w.toks.list[i]
	raw := w.src[tok.Start:tok.End]
	if strings.HasPrefix(raw, "$") {
		n := strings.IndexByte(raw[1:], '$') + 2
		tag := raw[:n]
		if raw[n:len(raw)-n] == str.Sval && !strings.Contains(newBody, tag) {
			w.edits = append(w.edits, edit{start: int(tok.Start) + n, end: int(tok.End) - n, text: newBody})
			str.Sval = newBody
			return
		}
	}
	w.edits = append(w.edits, edit{start: int(tok.Start), end: int(tok.End), text: dollarQuote(newBody)})
	str.Sval = newBody
}

// sqlBody rewrites the body of a LANGUAGE sql function.
func (w *walker) sqlBody(body string) (string, error) {
	a, err := w.r.analyze(body, true, w.learnOnly)
	if err != nil {
		return "", err
	}
	w.warns = append(w.warns, a.warns...)
	return applyEdits(body, a.edits)
}

// plpgsqlBody rewrites the SQL embedded in a PL/pgSQL body.
//
// libpg_query compiles the function like PostgreSQL does and reports every
// embedded SQL statement or expression (PLpgSQL_expr.query) together with the
// line of the PL/pgSQL statement. The query text is a copy of the source with
// INTO clauses blanked out (and PERFORM turned into SELECT), so it is located
// in the body by matching the text, then rewritten with the regular SQL rules.
// Variable declarations (%TYPE, %ROWTYPE, user types) are located by line.
func (w *walker) plpgsqlBody(stmt, body string) (string, error) {
	js, err := pgquery.ParsePlPgSqlToJSON(stmt)
	if err != nil {
		return "", fmt.Errorf("PL/pgSQL parse error: %w", err)
	}
	var root any
	dec := json.NewDecoder(strings.NewReader(js))
	c := &plCollector{vars: map[string]bool{}}
	if root, err = decodeOrdered(dec); err != nil {
		return "", err
	}
	c.walk(root, "", 0)
	if c.dynamic {
		w.warn("dynamic SQL (EXECUTE) inside a function body or DO block is not rewritten: %s", snippet(w.stmtText()))
	}

	var edits []edit
	cursor := 0
	for _, e := range c.exprs {
		a, err := w.r.analyzeExpr(e.query, e.mode, w.learnOnly)
		if err != nil {
			return "", fmt.Errorf("PL/pgSQL line %d %q: %w", e.lineno, snippet(e.query), err)
		}
		w.warns = append(w.warns, a.warns...)
		if len(a.edits) == 0 {
			continue
		}
		p := locateExpr(body, e, cursor)
		if p < 0 {
			p = locateExpr(body, e, 0)
		}
		if p < 0 {
			return "", fmt.Errorf("cannot locate PL/pgSQL expression %q in the body", snippet(e.query))
		}
		cursor = p + len(e.query)
		base := p
		if e.perform { // "PERFORM x" is stored as "SELECT x", one byte shorter
			base++
		}
		edits = append(edits, shiftEdits(a.edits, base)...)
	}
	if !w.learnOnly && len(c.decls) > 0 {
		declEdits, err := w.declEdits(body, c)
		if err != nil {
			return "", err
		}
		edits = append(edits, declEdits...)
	}
	if w.learnOnly {
		return body, nil
	}
	return applyEdits(body, edits)
}

// analyzeExpr rewrites the query of a PLpgSQL_expr according to its parse mode
// and returns edits relative to the query text.
func (r *Rewriter) analyzeExpr(q string, mode int, learnOnly bool) (*analysis, error) {
	const prefix = "SELECT "
	switch mode {
	case 0: // RAW_PARSE_DEFAULT: a whole SQL statement
		return r.analyze(q, true, learnOnly)
	case 2: // RAW_PARSE_PLPGSQL_EXPR
		a, err := r.analyze(prefix+q, true, learnOnly)
		if err != nil {
			return nil, err
		}
		a.edits = shiftEdits(a.edits, -len(prefix))
		return a, nil
	case 3, 4, 5: // RAW_PARSE_PLPGSQL_ASSIGNn: target := expr
		toks, err := scanTokens(q)
		if err != nil {
			return nil, err
		}
		i := toks.findToken(0, toks.len(), pg.Token_COLON_EQUALS, pg.Token_ASCII_61)
		if i < 0 {
			return nil, errors.New("assignment operator not found")
		}
		off := int(toks.list[i].End)
		a, err := r.analyze(prefix+q[off:], true, learnOnly)
		if err != nil {
			return nil, err
		}
		a.edits = shiftEdits(a.edits, off-len(prefix))
		return a, nil
	}
	return &analysis{}, nil
}

// locateExpr finds the query of e in body starting at from. Blanks in the
// query match any character (INTO clauses are blanked out by PL/pgSQL).
func locateExpr(body string, e plExpr, from int) int {
	q := e.query
	if e.perform {
		if !strings.HasPrefix(q, "SELECT") {
			return -1
		}
		for p := from; p+7 <= len(body); p++ {
			if strings.EqualFold(body[p:p+7], "perform") && matchBlank(body, p+7, q[6:]) {
				return p
			}
		}
		return -1
	}
	for p := from; p+len(q) <= len(body); p++ {
		if body[p] == q[0] && matchBlank(body, p, q) {
			return p
		}
	}
	return -1
}

func matchBlank(body string, p int, q string) bool {
	if p+len(q) > len(body) {
		return false
	}
	for i := 0; i < len(q); i++ {
		if q[i] != body[p+i] && q[i] != ' ' {
			return false
		}
	}
	return true
}

// declEdits qualifies types of variable declarations: table%ROWTYPE,
// table.column%TYPE and user types.
func (w *walker) declEdits(body string, c *plCollector) ([]edit, error) {
	toks, err := scanTokens(body)
	if err != nil {
		return nil, err
	}
	lines := lineStarts(body)
	var edits []edit
	for _, d := range c.decls {
		parts := w.declTypeToQualify(d.typname, c.vars)
		if parts == nil || d.lineno < 1 || d.lineno > len(lines) {
			continue
		}
		lineEnd := len(body)
		if d.lineno < len(lines) {
			lineEnd = lines[d.lineno]
		}
		i := toks.firstFrom(lines[d.lineno-1])
		end := toks.firstFrom(lineEnd)
		for ; i < end; i++ {
			if id, ok := toks.ident(i); ok && id == d.refname {
				break
			}
		}
		j := toks.findName(parts, i+1, toks.len())
		if i >= end || j < 0 {
			return nil, fmt.Errorf("cannot locate declaration of %s %s", d.refname, d.typname)
		}
		pos := int(toks.list[j].Start)
		edits = append(edits, edit{start: pos, end: pos, text: w.r.prefix})
	}
	return edits, nil
}

// declTypeToQualify returns the name parts of a declared type that must be
// qualified (the schema goes before the first part), or nil.
func (w *walker) declTypeToQualify(typname string, vars map[string]bool) []string {
	t := strings.TrimSpace(typname)
	upper := strings.ToUpper(t)
	switch {
	case strings.HasSuffix(upper, "%ROWTYPE"):
		parts, ok := splitQualifiedName(t[:len(t)-len("%ROWTYPE")])
		if ok && len(parts) == 1 && w.shouldQualifyRelation(parts[0], false) {
			return parts
		}
	case strings.HasSuffix(upper, "%TYPE"):
		parts, ok := splitQualifiedName(t[:len(t)-len("%TYPE")])
		if ok && len(parts) == 2 && !vars[parts[0]] && w.shouldQualifyRelation(parts[0], false) {
			return parts
		}
	default:
		if i := strings.IndexAny(t, "[("); i >= 0 {
			t = t[:i]
		}
		parts, ok := splitQualifiedName(t)
		if ok && len(parts) == 1 && w.r.reg.isType(parts[0]) {
			return parts
		}
	}
	return nil
}

// ---- PL/pgSQL parse tree ---------------------------------------------------

type plExpr struct {
	query   string
	mode    int
	perform bool
	lineno  int
}

type plDecl struct {
	refname string
	typname string
	lineno  int
}

type plCollector struct {
	exprs   []plExpr
	decls   []plDecl
	vars    map[string]bool
	dynamic bool
}

type kv struct {
	k string
	v any
}

// obj is a JSON object with its keys in document order.
type obj []kv

func (o obj) get(k string) any {
	for _, e := range o {
		if e.k == k {
			return e.v
		}
	}
	return nil
}

func (c *plCollector) walk(v any, stmt string, lineno int) {
	switch x := v.(type) {
	case []any:
		for _, e := range x {
			c.walk(e, stmt, lineno)
		}
	case obj:
		for _, e := range x {
			inner, _ := e.v.(obj)
			switch {
			case e.k == "PLpgSQL_expr":
				q, _ := inner.get("query").(string)
				mode, _ := inner.get("parseMode").(float64)
				c.exprs = append(c.exprs, plExpr{query: q, mode: int(mode), perform: stmt == "PLpgSQL_stmt_perform", lineno: lineno})
			case strings.HasPrefix(e.k, "PLpgSQL_stmt_"):
				ln := lineno
				if l, ok := inner.get("lineno").(float64); ok {
					ln = int(l)
				}
				switch e.k {
				case "PLpgSQL_stmt_dynexecute", "PLpgSQL_stmt_dynfors":
					c.dynamic = true
				case "PLpgSQL_stmt_return_query", "PLpgSQL_stmt_open":
					if inner.get("dynquery") != nil {
						c.dynamic = true
					}
				}
				c.walk(e.v, e.k, ln)
			case e.k == "PLpgSQL_var" || e.k == "PLpgSQL_rec" || e.k == "PLpgSQL_row":
				ref, _ := inner.get("refname").(string)
				c.vars[strings.ToLower(ref)] = true
				ln, _ := inner.get("lineno").(float64)
				if dt, ok := inner.get("datatype").(obj); ok && ln > 0 {
					if t, ok := dt.get("PLpgSQL_type").(obj); ok {
						name, _ := t.get("typname").(string)
						c.decls = append(c.decls, plDecl{refname: strings.ToLower(ref), typname: name, lineno: int(ln)})
					}
				}
				c.walk(e.v, "", int(ln))
			default:
				c.walk(e.v, stmt, lineno)
			}
		}
	}
}

// decodeOrdered decodes JSON keeping the order of object keys.
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
		var o obj
		for dec.More() {
			kt, err := dec.Token()
			if err != nil {
				return nil, err
			}
			v, err := decodeOrdered(dec)
			if err != nil {
				return nil, err
			}
			o = append(o, kv{kt.(string), v})
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
