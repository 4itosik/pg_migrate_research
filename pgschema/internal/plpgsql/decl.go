// This file is derived from PostgreSQL (src/pl/plpgsql/src/pl_gram.y).
//
// Portions Copyright (c) 1996-2024, PostgreSQL Global Development Group
// Portions Copyright (c) 1994, Regents of the University of California
//
// PostgreSQL License: see ../../LICENSE.PostgreSQL.

package plpgsql

import (
	"github.com/4itosik/pg_migrate_research/pgschema/internal/lex"
	"github.com/4itosik/pg_migrate_research/pgschema/internal/parse"
)

// params records the parameters the caller passed as declarations.
func (p *parser) params(params []Param) {
	for _, pr := range params {
		d := &Decl{Kind: DeclParam, Name: pr.Name}
		if toks, err := scan(pr.Type); err == nil && len(toks) > 1 {
			d.Type = classify(toks[:len(toks)-1])
		}
		p.addDecl(d)
	}
}

// addDecl records a declaration and remembers the cursors.
func (p *parser) addDecl(d *Decl) {
	p.body.Decls = append(p.body.Decls, d)
	if d.Kind == DeclCursor || isCursorType(d.Type) {
		p.cursors[d.Name] = true
	}
}

// isCursorType reports whether the type is refcursor or cursor, which
// libpg_query treats as the type of cursor variables.
func isCursorType(t *TypeRef) bool {
	if t == nil || t.Kind != TypePlain || len(t.Names) == 0 {
		return false
	}
	last := t.Names[len(t.Names)-1]
	if last.End != t.End || (last.Text != "refcursor" && last.Text != "cursor") {
		return false
	}
	return len(t.Names) == 1 || (len(t.Names) == 2 && t.Names[0].Text == "pg_catalog")
}

// decls is decl_stmts: the declarations between DECLARE and BEGIN.
func (p *parser) decls(b *Block) {
	for {
		t := p.cur()
		switch {
		case t.res && t.text == "begin":
			return
		case t.Tok == 0:
			p.failAt(int(t.Start), "unexpected end of function definition")
		case t.res && t.text == "declare": // extra DECLAREs are allowed
			p.next()
		case t.op("<<"):
			p.errorAtCurrent("block label must be placed before DECLARE, not after")
		default:
			b.Decls = append(b.Decls, p.declStatement())
		}
	}
}

// declName is decl_varname: a word, an unreserved keyword included.
func (p *parser) declName(kind DeclKind) *Decl {
	t := p.cur()
	if !t.word {
		p.syntaxError()
	}
	p.next()
	return &Decl{Kind: kind, Name: t.text, NameStart: int(t.Start), NameEnd: int(t.End), Line: p.line(t.Start)}
}

// declStatement is decl_statement.
func (p *parser) declStatement() *Decl {
	d := p.declName(DeclVar)
	p.addDecl(d)
	switch t := p.cur(); {
	case t.kw("alias"):
		d.Kind = DeclAlias
		p.next()
		p.expectRes("for")
		a := p.cur()
		if !a.word {
			p.syntaxError()
		}
		_, end := p.compound(p.pos)
		p.pos = end
		d.Alias = p.src[a.Start:p.prevEnd()]
		p.expectPunct(';')
	case t.kw("no") || t.kw("scroll") || t.kw("cursor"):
		p.cursorDecl(d)
	default:
		p.varDecl(d)
	}
	return d
}

// varDecl is the first form of decl_statement: [CONSTANT] type [COLLATE c]
// [NOT NULL] [(:= | = | DEFAULT) expr] ;
func (p *parser) varDecl(d *Decl) {
	if p.cur().kw("constant") {
		d.Const = true
		p.next()
	}
	d.Type = p.dataType()
	if isCursorType(d.Type) {
		p.cursors[d.Name] = true
	}
	if p.cur().kw("collate") {
		p.next()
		if !p.cur().word {
			p.syntaxError()
		}
		_, end := p.compound(p.pos)
		p.pos = end
	}
	if t := p.cur(); t.res && t.text == "not" {
		p.next()
		p.expectRes("null")
		d.NotNull = true
	}
	switch t := p.cur(); {
	case t.is(';'):
		p.next()
	case t.is('=') || t.Tok == lex.COLON_EQUALS || t.kw("default"):
		p.next()
		d.Value, _ = p.expr(nil, uSemi, ";", d.Line, KindExpr)
	default:
		p.syntaxError()
	}
}

// cursorDecl is the third form: [[NO] SCROLL] CURSOR [(args)] (IS | FOR)
// query ;
func (p *parser) cursorDecl(d *Decl) {
	d.Kind = DeclCursor
	p.cursors[d.Name] = true
	if p.cur().kw("no") {
		p.next()
	}
	if p.cur().kw("scroll") {
		p.next()
	}
	p.expectKw("cursor")
	if p.cur().is('(') {
		p.next()
		for {
			a := p.declName(DeclCursorArg)
			a.Type = p.dataType()
			d.Args = append(d.Args, a)
			p.addDecl(a)
			if !p.cur().is(',') {
				break
			}
			p.next()
		}
		p.expectPunct(')')
	}
	if t := p.cur(); !t.kw("is") && !(t.res && t.text == "for") {
		p.syntaxError()
	}
	p.next()
	start, end, _ := p.readSQL(uSemi, false, ";")
	d.Value = p.newFrag(KindSQL, parse.ModeDefault, start, end, d.Line)
}

// dataType is read_datatype: it takes the tokens of a type up to the token
// that follows a declared type (a semicolon, COLLATE, NOT, the default, or,
// outside parentheses, a comma or a closing parenthesis).
func (p *parser) dataType() *TypeRef {
	first, depth := p.pos, 0
	if p.cur().word {
		// read_datatype takes a first word, an unreserved keyword like
		// COLLATE included, as part of the name before it looks for the end
		_, p.pos = p.compound(p.pos)
	}
	for {
		t := p.cur()
		if t.is(';') {
			break
		}
		if t.Tok == 0 {
			if depth != 0 {
				p.failAt(int(t.Start), "mismatched parentheses")
			}
			p.failAt(int(t.Start), "incomplete data type declaration")
		}
		if t.kw("collate") || (t.res && t.text == "not") || t.is('=') || t.Tok == lex.COLON_EQUALS || t.kw("default") {
			break
		}
		if (t.is(',') || t.is(')')) && depth == 0 {
			break
		}
		if t.is('(') {
			depth++
		} else if t.is(')') {
			depth--
		}
		p.next()
	}
	if p.pos == first {
		p.errorAtCurrent("missing data type declaration")
	}
	return classify(p.toks[first:p.pos])
}

// classify describes the type written in toks (not empty).
func classify(toks []token) *TypeRef {
	tr := &TypeRef{Start: int(toks[0].Start), End: int(toks[len(toks)-1].End)}
	// name%TYPE and name%ROWTYPE: read_datatype takes the words before the
	// percent sign, whatever they are for SQL (a table can be called position)
	if toks[0].word {
		names, i := qualifiedName(toks, func(t *token) bool { return t.word })
		if i+1 < len(toks) && toks[i].is('%') {
			switch {
			case toks[i+1].kw("type"):
				tr.Kind, tr.Names = TypeColumn, names
				return tr
			case toks[i+1].kw("rowtype"):
				tr.Kind, tr.Names = TypeRow, names
				return tr
			}
		}
	}
	if len(toks) == 1 && toks[0].word && !toks[0].quoted && toks[0].text == "record" {
		tr.Kind = TypeRecord
		return tr
	}
	// a type name that is not a keyword: name [. name ...]
	if t := &toks[0]; t.Tok == lex.IDENT || t.Kind == lex.UnreservedKeyword || t.Kind == lex.TypeFuncNameKeyword {
		tr.Names, _ = qualifiedName(toks, func(t *token) bool { return t.text != "" })
	}
	return tr
}

// qualifiedName reads name [. name ...] from the start of toks: the first
// token, then every token after a dot that is a name part (ok). It returns the
// parts and the index of the token after them.
func qualifiedName(toks []token, ok func(*token) bool) ([]Name, int) {
	names := []Name{{toks[0].text, int(toks[0].Start), int(toks[0].End)}}
	i := 1
	for ; i+1 < len(toks) && toks[i].is('.') && ok(&toks[i+1]); i += 2 {
		n := &toks[i+1]
		names = append(names, Name{n.text, int(n.Start), int(n.End)})
	}
	return names, i
}
