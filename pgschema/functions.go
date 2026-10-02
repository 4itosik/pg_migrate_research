package pgschema

import (
	"errors"
	"fmt"
	"strings"

	. "github.com/4itosik/pg_migrate_research/pgschema/internal/ast"
	"github.com/4itosik/pg_migrate_research/pgschema/internal/lex"
	"github.com/4itosik/pg_migrate_research/pgschema/internal/parse"
	"github.com/4itosik/pg_migrate_research/pgschema/internal/plpgsql"
	"github.com/4itosik/pg_migrate_research/pgschema/subst"
)

// createFunction qualifies the function name and rewrites a SQL or PL/pgSQL
// body given as a string. A SQL-standard body (BEGIN ATOMIC) is part of the
// main parse tree and is visited as a regular child.
func (w *walker) createFunction(n *CreateFunctionStmt) {
	name := strings.Join(strs(n.Funcname), ".") // as written, before the schema goes in
	w.defName(&n.Funcname, kindFunction)
	w.singleColumnTable(n)
	as := defElem(n.Options, "as")
	if as == nil {
		return
	}
	list, ok := as.Arg.(*List)
	if !ok || len(list.Items) != 1 { // C function: AS 'obj_file', 'link_symbol'
		return
	}
	str, ok := list.Items[0].(*String)
	if !ok {
		return
	}
	var newBody string
	var err error
	w.triggerVars = triggerVars(n)
	switch lang := language(n.Options, "sql"); lang {
	case "sql":
		newBody, err = w.sqlBody(str.Sval)
	case "plpgsql":
		newBody, err = w.plpgsqlBody(plOptions(n), str.Sval)
	default:
		w.warn("function body in LANGUAGE %s is not rewritten: %s", lang, snippet(w.stmtText()))
		return
	}
	if err != nil {
		w.failErr(w.bodyError(err, str, "function "+name+": "))
		return
	}
	w.replaceBody(str.Loc, str, newBody)
}

func (w *walker) doStmt(n *DoStmt) {
	as := defElem(n.Args, "as")
	if as == nil {
		return
	}
	if lang := language(n.Args, "plpgsql"); lang != "plpgsql" {
		w.warn("DO block in LANGUAGE %s is not rewritten: %s", lang, snippet(w.stmtText()))
		return
	}
	str, ok := as.Arg.(*String)
	if !ok {
		return
	}
	w.triggerVars = nil
	newBody, err := w.plpgsqlBody(plOptions(nil), str.Sval)
	if err != nil {
		w.failErr(w.bodyError(err, str, "DO block: "))
		return
	}
	w.replaceBody(str.Loc, str, newBody)
}

// bodyError is the error of a body that cannot be rewritten, with prefix in
// front of the message. A syntax error in the body gets its position in the
// text of the statement: in the body as written when the literal holds the
// body as it is ($$...$$, '...' without escapes), otherwise at the literal.
func (w *walker) bodyError(err error, str *String, prefix string) error {
	pe, ok := err.(*posError)
	if !ok {
		return shifted(err, 0, prefix)
	}
	if it, terr := w.tokenAt(str.Loc); terr == nil && pe.off >= 0 {
		raw := w.src[str.Loc : int(str.Loc)+int(it.End)]
		if start, ok := literalContentStart(raw, str.Sval); ok {
			return shifted(err, int(str.Loc)+start, prefix)
		}
	}
	return &posError{off: int(str.Loc), msg: prefix + pe.msg}
}

// replaceBody replaces the body literal at offset loc. A dollar-quoted body
// keeps its tag; other literals are quoted again with dollar quotes.
func (w *walker) replaceBody(loc int32, str *String, newBody string) {
	if w.learnOnly || newBody == str.Sval {
		return
	}
	it, err := w.tokenAt(loc)
	if err != nil || it.Tok != lex.SCONST {
		w.fail("cannot locate the function body literal")
		return
	}
	start, end := int(loc), int(loc)+int(it.End)
	raw := w.src[start:end]
	if strings.HasPrefix(raw, "$") {
		n := strings.IndexByte(raw[1:], '$') + 2
		tag := raw[:n]
		if raw[n:len(raw)-n] == str.Sval && !strings.Contains(newBody, tag) {
			w.edits = append(w.edits, edit{start: start + n, end: end - n, text: newBody})
			str.Sval = newBody
			return
		}
	}
	w.edits = append(w.edits, edit{start: start, end: end, text: dollarQuote(newBody)})
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

// plOptions are the facts about a function that its body does not contain:
// the name, which is a label of the outermost block, the parameters and
// whether it is a trigger. n is nil for a DO block.
func plOptions(n *CreateFunctionStmt) plpgsql.Options {
	var o plpgsql.Options
	if n == nil {
		return o
	}
	if names := strs(n.Funcname); len(names) > 0 {
		o.Name = names[len(names)-1]
	}
	for _, p := range n.Parameters {
		fp, ok := p.(*FunctionParameter)
		if !ok {
			continue
		}
		o.Params = append(o.Params, plpgsql.Param{Name: fp.Name, Type: typeText(fp.ArgType)})
	}
	return o
}

// typeText writes a type name as the parameter list of CREATE FUNCTION had it,
// as far as the extractor needs it: the names, the array brackets, %TYPE.
func typeText(tn *TypeName) string {
	if tn == nil {
		return ""
	}
	var parts []string
	for _, s := range strs(tn.Names) {
		parts = append(parts, subst.QuoteIdent(s))
	}
	text := strings.Join(parts, ".")
	if tn.PctType {
		text += "%TYPE"
	}
	return text + strings.Repeat("[]", len(tn.ArrayBounds))
}

// triggerVars are the special variables PL/pgSQL declares for the body of a
// trigger function, from its return type.
func triggerVars(n *CreateFunctionStmt) []string {
	if n == nil || n.ReturnType == nil {
		return nil
	}
	names := strs(n.ReturnType.Names)
	if len(names) == 0 {
		return nil
	}
	switch names[len(names)-1] {
	case "trigger":
		return []string{"new", "old", "tg_name", "tg_when", "tg_level", "tg_op", "tg_relid", "tg_relname",
			"tg_table_name", "tg_table_schema", "tg_nargs", "tg_argv"}
	case "event_trigger":
		return []string{"tg_event", "tg_tag"}
	}
	return nil
}

// plpgsqlBody rewrites the SQL embedded in a PL/pgSQL body. The extractor
// finds the fragments of SQL (statements, expressions, assignments) and the
// declarations; each fragment is rewritten as a text of its own with the
// regular rules, and the types of the declarations are qualified.
func (w *walker) plpgsqlBody(opts plpgsql.Options, body string) (out string, err error) {
	pb, err := plpgsql.Parse(body, &opts)
	if err != nil {
		if pe, ok := err.(*plpgsql.Error); ok {
			return "", &posError{off: pe.Pos, msg: "PL/pgSQL: " + pe.Msg}
		}
		return "", fmt.Errorf("PL/pgSQL: %w", err)
	}
	// a body that cannot be rewritten leaves no objects in the registry,
	// as a function that the server would not create
	tx := w.r.reg.begin()
	defer func() { w.r.reg.end(tx, err == nil) }()
	if len(pb.Dynamic) > 0 {
		w.warn("dynamic SQL (EXECUTE) inside a function body or DO block is not rewritten: %s", snippet(w.stmtText()))
	}
	var edits []edit
	for _, f := range pb.Fragments {
		a, err := w.r.analyzeFragment(f, body, w.learnOnly)
		if err != nil {
			return "", shifted(err, f.Start, fmt.Sprintf("PL/pgSQL line %d %q: ", f.Line, snippet(f.SQL(body))))
		}
		w.warns = append(w.warns, a.warns...)
		edits = append(edits, shiftEdits(a.edits, f.Start)...)
	}
	if w.learnOnly {
		return body, nil
	}
	vars := plVars(pb, w.triggerVars)
	for _, d := range pb.Decls {
		if d.Type == nil || (d.Kind != plpgsql.DeclVar && d.Kind != plpgsql.DeclCursorArg) {
			continue
		}
		if e, ok, err := w.declEdit(body, d.Type, vars); err != nil {
			return "", err
		} else if ok {
			edits = append(edits, e)
		}
	}
	out, err = applyEdits(body, edits)
	if err != nil {
		return "", err
	}
	if out != body {
		if err := verifyBody(pb, out, opts); err != nil {
			return "", err
		}
	}
	return out, nil
}

// verifyBody checks that the rewritten body has the same structure as the
// original: the same fragments of the same kinds and modes, declarations and
// dynamic statements, in the same order.
func verifyBody(orig *plpgsql.Body, out string, opts plpgsql.Options) error {
	nb, err := plpgsql.Parse(out, &opts)
	if err != nil {
		return fmt.Errorf("%w: the rewritten PL/pgSQL body does not parse: %v", ErrNotVerified, err)
	}
	if len(nb.Fragments) != len(orig.Fragments) || len(nb.Decls) != len(orig.Decls) || len(nb.Dynamic) != len(orig.Dynamic) {
		return fmt.Errorf("%w: the rewritten PL/pgSQL body has a different structure", ErrNotVerified)
	}
	for i, f := range orig.Fragments {
		if g := nb.Fragments[i]; g.Kind != f.Kind || g.Mode != f.Mode {
			return fmt.Errorf("%w: fragment %d of the PL/pgSQL body changed its kind", ErrNotVerified, i+1)
		}
	}
	for i, d := range orig.Decls {
		if g := nb.Decls[i]; g.Kind != d.Kind || g.Name != d.Name {
			return fmt.Errorf("%w: declaration %d of the PL/pgSQL body changed", ErrNotVerified, i+1)
		}
	}
	return nil
}

// plVars are the names of the variables of a body, which shadow tables in
// table.column%TYPE: the declared ones, the loop variables, the special
// variables.
func plVars(pb *plpgsql.Body, special []string) map[string]bool {
	vars := map[string]bool{"found": true, "sqlstate": true, "sqlerrm": true}
	for _, n := range special {
		vars[n] = true
	}
	for _, d := range pb.Decls {
		vars[d.Name] = true
	}
	var walk func(stmts []*plpgsql.Stmt)
	var block func(b *plpgsql.Block)
	walk = func(stmts []*plpgsql.Stmt) {
		for _, s := range stmts {
			for _, v := range s.Vars {
				vars[v] = true
			}
			if s.Block != nil {
				block(s.Block)
			}
			walk(s.Body)
			for _, br := range s.Branches {
				walk(br.Stmts)
			}
		}
	}
	block = func(b *plpgsql.Block) {
		walk(b.Stmts)
		for _, h := range b.Handlers {
			walk(h.Stmts)
		}
	}
	if pb.Root != nil {
		block(pb.Root)
	}
	return vars
}

// declEdit qualifies the type of a declaration: table%ROWTYPE,
// table.column%TYPE (unless the first name is a variable) and a type or
// table created by the migrations.
func (w *walker) declEdit(body string, t *plpgsql.TypeRef, vars map[string]bool) (edit, bool, error) {
	var qualify bool
	ref := w.r.targetRef()
	switch t.Kind {
	case plpgsql.TypeRow:
		qualify = len(t.Names) == 1 && w.shouldQualifyRelation(t.Names[0].Text, false)
	case plpgsql.TypeColumn:
		qualify = len(t.Names) == 2 && !vars[t.Names[0].Text] && w.shouldQualifyRelation(t.Names[0].Text, false)
	case plpgsql.TypePlain:
		if len(t.Names) == 1 {
			if r := w.typeRef(t.Names[0].Text, false, -1); r != nil {
				ref, qualify = r, true
			}
		}
	}
	if !qualify {
		return edit{}, false, nil
	}
	n := t.Names[0]
	if !identAt(body, n.Start, n.Text) {
		return edit{}, false, fmt.Errorf("cannot locate the type %s in a declaration of the PL/pgSQL body", n.Text)
	}
	// the extractor reads the text of a type up to the end of the declaration
	// part, as PostgreSQL does, and PostgreSQL then parses it as a type name;
	// text that is not one is a function the server would not create
	if err := checkTypeText(body[t.Start:t.End], t); err != nil {
		return edit{}, false, fmt.Errorf("%s in a declaration of the PL/pgSQL body: %v", errInvalidType, err)
	}
	return edit{start: n.Start, end: n.Start, text: ref.prefix}, true, nil
}

// errInvalidType starts the error for a declaration with text that is not a
// type.
const errInvalidType = "invalid type"

// checkTypeText checks the text of a declared type: a type name for the plain
// kind, otherwise the form name[.name...]%TYPE or %ROWTYPE with nothing else.
func checkTypeText(text string, t *plpgsql.TypeRef) error {
	if t.Kind == plpgsql.TypePlain {
		_, err := parse.ParseMode(text, parse.ModeTypeName)
		return err
	}
	var toks []lex.Item
	sc := lex.NewScanner(text)
	for {
		it, err := sc.Next()
		if err != nil {
			return err
		}
		if it.Tok == 0 {
			break
		}
		toks = append(toks, it)
	}
	// names with dots, %, TYPE or ROWTYPE, then only array bounds
	i := 0
	for n := range t.Names {
		if n > 0 {
			if i >= len(toks) || toks[i].Tok != '.' {
				return fmt.Errorf("%q is not a name followed by %%TYPE or %%ROWTYPE", text)
			}
			i++
		}
		i++ // the name, which the extractor has found
	}
	if i+1 >= len(toks) || toks[i].Tok != '%' {
		return fmt.Errorf("%q is not a name followed by %%TYPE or %%ROWTYPE", text)
	}
	i += 2 // % and TYPE or ROWTYPE
	for ; i < len(toks); i++ {
		if tok := toks[i].Tok; tok != '[' && tok != ']' && tok != lex.ICONST && tok != lex.ARRAY {
			return fmt.Errorf("%q has text after %%TYPE or %%ROWTYPE that is not an array bound", text)
		}
	}
	return nil
}

// identAt reports whether an identifier with the value name starts at pos.
func identAt(src string, pos int, name string) bool {
	if pos < 0 || pos >= len(src) {
		return false
	}
	it, err := lex.NewScanner(src[pos:]).Next()
	return err == nil && it.Start == 0 && it.Str == name &&
		(it.Tok == lex.IDENT || (it.Kind != lex.NoKeyword && it.Kind != lex.ReservedKeyword))
}

// analyzeFragment rewrites a fragment of a PL/pgSQL body according to its
// parse mode and returns the edits relative to the start of the fragment.
func (r *Rewriter) analyzeFragment(f *plpgsql.Fragment, body string, learnOnly bool) (*analysis, error) {
	const prefix = "SELECT "
	q := f.SQL(body)
	// the fragment must parse in its own mode: the text below is analyzed with
	// a SELECT in front of it, which accepts things the mode does not
	// (RETURN INTO x would be SELECT INTO x, a statement that creates a table)
	if f.Mode != parse.ModeDefault {
		text, delta := q, 0
		if f.Kind == plpgsql.KindCaseWhen {
			text, delta = "x IN ("+q+")", -len("x IN (")
		}
		if _, err := parse.ParseMode(text, f.Mode); err != nil {
			return nil, shifted(syntaxError(err), delta, "")
		}
	}
	switch f.Mode {
	case parse.ModeDefault: // a whole SQL statement
		return r.analyze(q, true, learnOnly)
	case parse.ModePLpgSQLExpr:
		head := prefix
		if f.Kind == plpgsql.KindCaseWhen { // the list of WHEN is parsed as: var IN (list)
			head, q = prefix+"x IN (", q+")"
		}
		a, err := r.analyze(head+q, true, learnOnly)
		if err != nil {
			return nil, shifted(err, -len(head), "")
		}
		a.edits = shiftEdits(a.edits, -len(head))
		return a, nil
	case parse.ModePLpgSQLAssign1, parse.ModePLpgSQLAssign2, parse.ModePLpgSQLAssign3: // target := expr
		off, ok := assignmentEnd(q)
		if !ok {
			return nil, errors.New("assignment operator not found")
		}
		a, err := r.analyze(prefix+q[off:], true, learnOnly)
		if err != nil {
			return nil, shifted(err, off-len(prefix), "")
		}
		a.edits = shiftEdits(a.edits, off-len(prefix))
		return a, nil
	}
	return &analysis{}, nil
}

// assignmentEnd returns the offset after the := or = that ends the target of
// an assignment: the first one outside parentheses and brackets.
func assignmentEnd(q string) (int, bool) {
	sc := lex.NewScanner(q)
	depth := 0
	for {
		it, err := sc.Next()
		if err != nil || it.Tok == 0 {
			return 0, false
		}
		switch it.Tok {
		case '(', '[':
			depth++
		case ')', ']':
			depth--
		case lex.COLON_EQUALS, '=':
			if depth == 0 {
				return int(it.End), true
			}
		}
	}
}

// singleColumnTable handles RETURNS TABLE (c type) with one column. The
// grammar makes the return type a copy of the column type whose position is
// that of the TABLE keyword, so the name cannot be edited there: the column's
// own type is qualified and the copy follows.
func (w *walker) singleColumnTable(n *CreateFunctionStmt) {
	var column *FunctionParameter
	for _, p := range n.Parameters {
		if fp, ok := p.(*FunctionParameter); ok && fp.Mode == FUNC_PARAM_TABLE {
			if column != nil {
				return // several columns: the return type is record
			}
			column = fp
		}
	}
	if column == nil || column.ArgType == nil || n.ReturnType == nil || !n.ReturnType.Setof {
		return
	}
	w.typeName(column.ArgType, false)
	n.ReturnType.Names = append([]Node(nil), column.ArgType.Names...)
	w.done[n.ReturnType] = true
}
