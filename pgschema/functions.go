package pgschema

import (
	"errors"
	"fmt"
	"strings"

	. "github.com/4itosik/pg_migrate_research/pgschema/internal/ast"
	"github.com/4itosik/pg_migrate_research/pgschema/internal/lex"
)

// createFunction qualifies the function name and rewrites a SQL or PL/pgSQL
// body given as a string. A SQL-standard body (BEGIN ATOMIC) is part of the
// main parse tree and is visited as a regular child.
func (w *walker) createFunction(n *CreateFunctionStmt) {
	w.defName(&n.Funcname, kindFunction)
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
	switch lang := language(n.Options, "sql"); lang {
	case "sql":
		newBody, err = w.sqlBody(str.Sval)
	case "plpgsql":
		newBody, err = w.plpgsqlBody(str.Sval)
	default:
		w.warn("function body in LANGUAGE %s is not rewritten: %s", lang, snippet(w.stmtText()))
		return
	}
	if err != nil {
		w.fail("function %s: %v", strings.Join(strs(n.Funcname), "."), err)
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
	newBody, err := w.plpgsqlBody(str.Sval)
	if err != nil {
		w.fail("DO block: %v", err)
		return
	}
	w.replaceBody(str.Loc, str, newBody)
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

// plpgsqlBody rewrites the SQL embedded in a PL/pgSQL body.
func (w *walker) plpgsqlBody(body string) (string, error) {
	if w.learnOnly {
		return body, nil
	}
	return "", errors.New(fmt.Sprint("PL/pgSQL bodies are not supported yet"))
}
