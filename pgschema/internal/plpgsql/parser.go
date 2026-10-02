// This file is derived from PostgreSQL (src/pl/plpgsql/src/pl_gram.y and pl_scanner.c).
//
// Portions Copyright (c) 1996-2024, PostgreSQL Global Development Group
// Portions Copyright (c) 1994, Regents of the University of California
//
// PostgreSQL License: see ../../LICENSE.PostgreSQL.

package plpgsql

import (
	"strings"

	"github.com/4itosik/pg_migrate_research/pgschema/internal/lex"
	"github.com/4itosik/pg_migrate_research/pgschema/internal/parse"
)

// Parse extracts the embedded SQL from the body of a PL/pgSQL function,
// procedure or DO block: the decoded text of the $$...$$ literal. opts may be
// nil.
func Parse(body string, opts *Options) (b *Body, err error) {
	toks, err := scan(body)
	if err != nil {
		e := &Error{Msg: err.Error()}
		if le, ok := err.(*lex.Error); ok && le.Loc >= 0 {
			e.Pos = le.Loc
		}
		e.Line = newLineIndex(body).line(e.Pos)
		return nil, e
	}
	p := &parser{src: body, toks: toks, lines: newLineIndex(body), body: &Body{Text: body}, cursors: map[string]bool{}}
	if opts != nil && opts.Name != "" {
		p.labels = []string{opts.Name}
	}
	defer func() {
		if r := recover(); r != nil {
			a, ok := r.(abort)
			if !ok {
				panic(r)
			}
			b, err = nil, a.err
		}
	}()
	if opts != nil {
		p.params(opts.Params)
	}
	p.compOptions()
	p.body.Root = p.block()
	if p.cur().is(';') {
		p.next()
	}
	if p.cur().Tok != 0 {
		p.syntaxError()
	}
	return p.body, nil
}

// abort is the panic that ends a parse at the first error.
type abort struct{ err *Error }

type parser struct {
	src   string
	toks  []token
	pos   int
	lines lineIndex
	body  *Body
	// cursors are the names of the variables declared as cursors or
	// refcursors so far.
	cursors map[string]bool
	// labels are the labels in scope: the name of the function and the labels
	// of the enclosing blocks and loops.
	labels []string
}

// ---- token access ----------------------------------------------------------

func (p *parser) tok(i int) *token {
	if i >= len(p.toks) {
		i = len(p.toks) - 1
	}
	return &p.toks[i]
}

func (p *parser) cur() *token { return p.tok(p.pos) }

// next returns the current token and moves past it; at the end of input it
// stays on the end token.
func (p *parser) next() *token {
	t := p.cur()
	if t.Tok != 0 {
		p.pos++
	}
	return t
}

// back gives the token t, just returned by next, back to the input.
func (p *parser) back(t *token) {
	if t.Tok != 0 {
		p.pos--
	}
}

// prevEnd is the end of the last token consumed.
func (p *parser) prevEnd() int { return int(p.toks[p.pos-1].End) }

func (p *parser) line(off int32) int { return p.lines.line(int(off)) }

// ---- errors ----------------------------------------------------------------

func (p *parser) failAt(pos int, msg string) {
	panic(abort{&Error{Msg: msg, Pos: pos, Line: p.lines.line(pos)}})
}

// syntaxError reports a syntax error at the current token.
func (p *parser) syntaxError() { p.errorAtCurrent("syntax error") }

func (p *parser) errorAtCurrent(msg string) {
	t := p.cur()
	if t.Tok == 0 {
		p.failAt(int(t.Start), msg+" at end of input")
	}
	p.failAt(int(t.Start), msg+` at or near "`+p.src[t.Start:t.End]+`"`)
}

func (p *parser) expectPunct(c byte) {
	if !p.cur().is(c) {
		p.errorAtCurrent("syntax error, expected \"" + string(c) + "\"")
	}
	p.next()
}

// expectRes consumes the reserved keyword s.
func (p *parser) expectRes(s string) *token {
	if t := p.cur(); !t.res || t.text != s {
		p.errorAtCurrent("syntax error, expected \"" + strings.ToUpper(s) + "\"")
	}
	return p.next()
}

// expectKw consumes the word or reserved keyword s.
func (p *parser) expectKw(s string) *token {
	if !p.cur().kw(s) {
		p.errorAtCurrent("syntax error, expected \"" + strings.ToUpper(s) + "\"")
	}
	return p.next()
}

// ---- names -----------------------------------------------------------------

// compound is what plpgsql_yylex does with a word: it joins up to three
// dotted words into one token. It returns the number of names and the index
// of the token after them.
func (p *parser) compound(i int) (n, end int) {
	n, end = 1, i+1
	for n < 3 && p.tok(end).is('.') && p.tok(end+1).word {
		n++
		end += 2
	}
	return n, end
}

// dotted returns the dotted name made of the words of the compound
// identifier in tokens [i, end), as folded by the scanner.
func (p *parser) dotted(i, end int) string {
	if end == i+1 {
		return p.toks[i].text
	}
	var parts []string
	for ; i < end; i += 2 {
		parts = append(parts, p.toks[i].text)
	}
	return strings.Join(parts, ".")
}

// skipGroup returns the index after the bracket that closes the one at i,
// counting ( and [ like read_sql_construct, or -1 when a semicolon or the end
// of input comes first.
func (p *parser) skipGroup(i int) int {
	depth := 0
	for ; ; i++ {
		t := p.tok(i)
		switch {
		case t.is('(') || t.is('['):
			depth++
		case t.is(')') || t.is(']'):
			depth--
			if depth == 0 {
				return i + 1
			}
		case t.Tok == 0 || t.is(';'):
			return -1
		}
	}
}

// assignTarget decides by structure whether the statement at token i is an
// assignment, where the grammar asks the table of variable names: a name,
// up to two more dotted names, subscripts and field selections, then := or
// =. It returns the number of leading dotted names (at most three), which
// selects the parse mode.
func (p *parser) assignTarget(i int) (n int, ok bool) {
	if !p.tok(i).word {
		return 0, false
	}
	n, j := p.compound(i)
	for {
		t := p.tok(j)
		switch {
		case t.is('['):
			if j = p.skipGroup(j); j < 0 {
				return 0, false
			}
		case t.is('.') && (p.tok(j+1).text != "" || p.tok(j+1).is('*')): // field, or .* as in new.* := rec
			j += 2
		default:
			return n, t.Tok == lex.COLON_EQUALS || t.is('=')
		}
	}
}

func (p *parser) isLabel(name string) bool {
	for _, l := range p.labels {
		if l == name {
			return true
		}
	}
	return false
}

// label reads <<name>> and returns the name.
func (p *parser) label() string {
	if !p.cur().op("<<") {
		p.syntaxError()
	}
	p.next()
	t := p.cur()
	if !t.word {
		p.syntaxError()
	}
	p.next()
	if !p.cur().op(">>") {
		p.syntaxError()
	}
	p.next()
	return t.text
}

// ---- header ----------------------------------------------------------------

// compOptions skips the compile options: "#option dump",
// "#print_strict_params on", "#variable_conflict use_column".
func (p *parser) compOptions() {
	for p.cur().op("#") {
		p.next()
		p.next()
		if p.cur().Tok == 0 {
			p.syntaxError()
		}
		p.next()
	}
}

// ---- blocks ----------------------------------------------------------------

// block is pl_block: [<<label>>] [DECLARE ...] BEGIN ... [EXCEPTION ...] END
// [label]. The semicolon after it belongs to the caller.
func (p *parser) block() *Block {
	b := &Block{Start: int(p.cur().Start)}
	defer func(n int) { p.labels = p.labels[:n] }(len(p.labels))
	if p.cur().op("<<") {
		b.Label = p.label()
		p.labels = append(p.labels, b.Label)
	}
	if t := p.cur(); t.res && t.text == "declare" {
		p.next()
		p.decls(b)
	}
	begin := p.expectRes("begin")
	b.Line = p.line(begin.Start)
	b.Stmts = p.procSect()
	if p.cur().kw("exception") {
		p.handlers(b)
	}
	p.expectRes("end")
	if p.cur().word { // opt_label
		p.next()
	}
	b.End = p.prevEnd()
	return b
}

func (p *parser) blockStmt() *Stmt {
	start := int(p.cur().Start)
	b := p.block()
	s := &Stmt{Kind: StmtBlock, Line: b.Line, Start: start, Label: b.Label, Block: b}
	p.expectPunct(';')
	s.End = p.prevEnd()
	return s
}

// handlers is exception_sect: EXCEPTION WHEN cond [OR cond ...] THEN stmts ...
func (p *parser) handlers(b *Block) {
	p.next() // EXCEPTION
	for t := p.cur(); t.res && t.text == "when"; t = p.cur() {
		p.next()
		h := &Handler{Line: p.line(t.Start)}
		for {
			c := p.cur()
			if !c.word {
				p.syntaxError()
			}
			p.next()
			if c.text == "sqlstate" {
				s := p.cur()
				if s.Tok != lex.SCONST {
					p.syntaxError()
				}
				p.next()
				h.Conditions = append(h.Conditions, s.Str)
			} else {
				h.Conditions = append(h.Conditions, c.text)
			}
			if o := p.cur(); o.res && o.text == "or" {
				p.next()
				continue
			}
			break
		}
		p.expectRes("then")
		h.Stmts = p.procSect()
		b.Handlers = append(b.Handlers, h)
	}
	if len(b.Handlers) == 0 {
		p.syntaxError()
	}
}

// procSect is proc_sect: statements up to the keyword that ends the section.
func (p *parser) procSect() []*Stmt {
	var out []*Stmt
	for !p.sectionEnd() {
		if s := p.stmt(); s != nil {
			out = append(out, s)
		}
	}
	return out
}

// sectionEnd reports whether the current token ends a statement list: END,
// ELSE, WHEN, ELSIF, EXCEPTION, or the end of input (the caller then reports
// the missing END).
func (p *parser) sectionEnd() bool {
	t := p.cur()
	switch {
	case t.Tok == 0:
		return true
	case t.res:
		return t.text == "end" || t.text == "else" || t.text == "when"
	case t.word && !t.quoted && (t.text == "elsif" || t.text == "elseif" || t.text == "exception"):
		// a variable of that name starts an assignment
		if n, _ := p.compound(p.pos); n > 1 {
			return false
		}
		_, assign := p.assignTarget(p.pos)
		return !assign
	}
	return false
}

// ---- statements ------------------------------------------------------------

func isLoopKeyword(s string) bool {
	return s == "loop" || s == "while" || s == "for" || s == "foreach"
}

// stmt is proc_stmt. It returns nil for NULL.
func (p *parser) stmt() *Stmt {
	t := p.cur()
	start := int(t.Start)
	label := ""
	if t.op("<<") {
		if k := p.tok(p.pos + 3); !k.res || !isLoopKeyword(k.text) {
			return p.blockStmt()
		}
		label = p.label()
		t = p.cur()
	}
	switch {
	case t.res:
		switch t.text {
		case "begin", "declare":
			return p.blockStmt()
		case "if":
			return p.ifStmt()
		case "case":
			return p.caseStmt()
		case "loop", "while", "for", "foreach":
			return p.loopStmt(start, label)
		case "execute":
			return p.executeStmt()
		case "null":
			p.next()
			p.expectPunct(';')
			return nil
		}
	case t.word:
		if n, ok := p.assignTarget(p.pos); ok {
			return p.assignStmt(n)
		}
		if n, _ := p.compound(p.pos); n == 1 && !t.quoted {
			switch t.text {
			case "perform":
				return p.sqlStmt(StmtPerform, KindPerform)
			case "call", "do":
				return p.sqlStmt(StmtCall, KindSQL)
			case "get":
				return p.getDiagStmt()
			case "exit", "continue":
				return p.exitStmt()
			case "return":
				return p.returnStmt()
			case "raise":
				return p.raiseStmt()
			case "assert":
				return p.assertStmt()
			case "open":
				return p.openStmt()
			case "fetch", "move":
				return p.fetchStmt()
			case "close":
				return p.closeStmt()
			case "commit", "rollback":
				return p.transactionStmt()
			}
		}
		return p.execSQLStmt()
	}
	p.syntaxError()
	return nil
}

func (p *parser) newStmt(kind StmtKind, t *token) *Stmt {
	return &Stmt{Kind: kind, Line: p.line(t.Start), Start: int(t.Start)}
}

func (p *parser) finish(s *Stmt) *Stmt {
	s.End = p.prevEnd()
	return s
}

// assignStmt is stmt_assign. n is the number of names the scanner joined.
// plpgsql_parse_tripword takes three names as a label, a record variable and
// a field, only when the first is a label (or the name of the function);
// otherwise the third name is a field of a field, and the target has two
// names.
func (p *parser) assignStmt(n int) *Stmt {
	s := p.newStmt(StmtAssign, p.cur())
	if n == 3 && !p.isLabel(p.cur().text) {
		n = 2
	}
	start, end, _ := p.readSQL(uSemi, false, ";")
	f := p.newFrag(KindAssign, parse.ModePLpgSQLAssign1+parse.Mode(n-1), start, end, s.Line)
	s.Frags = append(s.Frags, f)
	return p.finish(s)
}

// sqlStmt is PERFORM, CALL and DO: the statement is the SQL text, keyword
// included.
func (p *parser) sqlStmt(kind StmtKind, fk FragKind) *Stmt {
	s := p.newStmt(kind, p.cur())
	start, end, _ := p.readSQL(uSemi, false, ";")
	s.Frags = append(s.Frags, p.newFrag(fk, parse.ModeDefault, start, end, s.Line))
	return p.finish(s)
}

func (p *parser) ifStmt() *Stmt {
	t := p.next()
	s := p.newStmt(StmtIf, t)
	for {
		cond, _ := p.expr(nil, uThen, "THEN", p.line(t.Start), KindExpr)
		br := &Branch{Line: p.line(t.Start), Cond: cond}
		br.Stmts = p.procSect()
		s.Branches = append(s.Branches, br)
		if t = p.cur(); t.kw("elsif") || t.kw("elseif") {
			p.next()
			continue
		}
		break
	}
	if t = p.cur(); t.res && t.text == "else" {
		p.next()
		s.Branches = append(s.Branches, &Branch{Line: p.line(t.Start), Stmts: p.procSect()})
	}
	p.expectRes("end")
	p.expectRes("if")
	p.expectPunct(';')
	return p.finish(s)
}

func (p *parser) caseStmt() *Stmt {
	s := p.newStmt(StmtCase, p.next())
	selector := false
	if t := p.cur(); !t.res || t.text != "when" {
		p.expr(s, uWhen, "WHEN", s.Line, KindExpr)
		p.pos-- // push WHEN back
		selector = true
	}
	for t := p.cur(); t.res && t.text == "when"; t = p.cur() {
		p.next()
		kind := KindExpr
		if selector {
			kind = KindCaseWhen
		}
		line := p.line(t.Start)
		cond, _ := p.expr(nil, uThen, "THEN", line, kind)
		s.Branches = append(s.Branches, &Branch{Line: line, Cond: cond, Stmts: p.procSect()})
	}
	if len(s.Branches) == 0 {
		p.syntaxError()
	}
	if t := p.cur(); t.res && t.text == "else" {
		p.next()
		s.Branches = append(s.Branches, &Branch{Line: p.line(t.Start), Stmts: p.procSect()})
	}
	p.expectRes("end")
	p.expectRes("case")
	p.expectPunct(';')
	return p.finish(s)
}

// loopStmt is LOOP, WHILE, FOR and FOREACH, with the label that was read.
func (p *parser) loopStmt(start int, label string) *Stmt {
	t := p.next()
	s := &Stmt{Line: p.line(t.Start), Start: start, Label: label}
	if label != "" {
		defer func(n int) { p.labels = p.labels[:n] }(len(p.labels))
		p.labels = append(p.labels, label)
	}
	switch t.text {
	case "loop":
		s.Kind = StmtLoop
	case "while":
		s.Kind = StmtWhile
		p.expr(s, uLoop, "LOOP", s.Line, KindExpr)
	case "for":
		p.forControl(s)
	case "foreach":
		p.foreachControl(s)
	}
	// loop_body
	s.Body = p.procSect()
	p.expectRes("end")
	p.expectRes("loop")
	if p.cur().word { // opt_label
		p.next()
	}
	p.expectPunct(';')
	return p.finish(s)
}

// forVars reads the loop variables: name [, name ...].
func (p *parser) forVars(s *Stmt) {
	for {
		t := p.cur()
		if !t.word {
			p.syntaxError()
		}
		_, end := p.compound(p.pos)
		s.Vars = append(s.Vars, p.dotted(p.pos, end))
		p.pos = end
		if !p.cur().is(',') {
			return
		}
		p.next()
	}
}

// forControl is for_control: what follows FOR up to and including LOOP.
func (p *parser) forControl(s *Stmt) {
	p.forVars(s)
	p.expectRes("in")
	t := p.cur()
	switch {
	case t.res && t.text == "execute":
		p.next()
		s.Kind = StmtForExecute
		cmd, found := p.expr(s, uLoop|uUsing, "LOOP or USING", s.Line, KindCommand)
		p.addDynamic(DynForExecute, s.Line, cmd)
		if found == uUsing {
			for found = uComma; found == uComma; {
				_, found = p.expr(s, uComma|uLoop, ", or LOOP", s.Line, KindExpr)
			}
		}
	case p.isCursorLoop():
		s.Kind = StmtForCursor
		_, end := p.compound(p.pos)
		s.Cursor = p.dotted(p.pos, end)
		p.pos = end
		p.cursorArgs(s, uLoop, "LOOP")
	default:
		// FOR var IN a .. b and FOR var IN query: the first tokens decide, up
		// to ".." or LOOP
		if t.kw("reverse") {
			p.next()
		}
		start, end, found := p.readSQL(uDotDot|uLoop, true, "LOOP")
		if found == uDotDot {
			s.Kind = StmtForInt
			s.Frags = append(s.Frags, p.newFrag(KindExpr, parse.ModePLpgSQLExpr, start, end, s.Line))
			if _, found = p.expr(s, uLoop|uBy, "LOOP", s.Line, KindExpr); found == uBy {
				p.expr(s, uLoop, "LOOP", s.Line, KindExpr)
			}
		} else {
			s.Kind = StmtForQuery
			s.Frags = append(s.Frags, p.newFrag(KindSQL, parse.ModeDefault, start, end, s.Line))
		}
	}
}

// isCursorLoop decides FOR var IN cursor [(args)] LOOP by structure. A bare
// name, possibly with an argument list, in front of LOOP cannot be a query. A
// SQL keyword in front of it may start one (VALUES (1)), so then the name
// must be a declared cursor.
func (p *parser) isCursorLoop() bool {
	t := p.cur()
	if !t.word {
		return false
	}
	_, j := p.compound(p.pos)
	last := p.tok(j - 1)
	if p.tok(j).is('(') {
		if j = p.skipGroup(j); j < 0 {
			return false
		}
	}
	if k := p.tok(j); !k.res || k.text != "loop" {
		return false
	}
	return p.cursors[last.text] || (t.Tok == lex.IDENT || t.Tok == lex.PARAM)
}

// foreachControl is what follows FOREACH up to and including LOOP.
func (p *parser) foreachControl(s *Stmt) {
	s.Kind = StmtForeach
	p.forVars(s)
	if p.cur().kw("slice") {
		p.next()
		if p.cur().Tok != lex.ICONST {
			p.syntaxError()
		}
		p.next()
	}
	p.expectRes("in")
	p.expectKw("array")
	p.expr(s, uLoop, "LOOP", s.Line, KindExpr)
}

// exitStmt is EXIT and CONTINUE.
func (p *parser) exitStmt() *Stmt {
	s := p.newStmt(StmtExit, p.next())
	if t := p.cur(); t.word {
		s.Label = t.text
		p.next()
	}
	if t := p.cur(); t.is(';') {
		p.next()
	} else if t.res && t.text == "when" {
		p.next()
		p.expr(s, uSemi, ";", s.Line, KindExpr)
	} else {
		p.syntaxError()
	}
	return p.finish(s)
}

func (p *parser) returnStmt() *Stmt {
	s := p.newStmt(StmtReturn, p.next())
	t := p.cur()
	switch {
	case t.Tok == 0:
		p.failAt(int(t.Start), "unexpected end of function definition")
	case t.is(';'):
	case t.kw("next") && !p.tok(p.pos+1).is('.'): // next.x is a name, not RETURN NEXT
		p.next()
		s.Kind = StmtReturnNext
		if !p.cur().is(';') {
			p.expr(s, uSemi, ";", s.Line, KindExpr)
			return p.finish(s)
		}
	case t.kw("query") && !p.tok(p.pos+1).is('.'): // query.x is a name
		p.next()
		s.Kind = StmtReturnQuery
		if e := p.cur(); e.res && e.text == "execute" {
			p.next()
			cmd, found := p.expr(s, uSemi|uUsing, "; or USING", s.Line, KindCommand)
			p.addDynamic(DynReturnQuery, s.Line, cmd)
			if found == uUsing {
				for found = uComma; found == uComma; {
					_, found = p.expr(s, uComma|uSemi, ", or ;", s.Line, KindExpr)
				}
			}
			return p.finish(s)
		}
		start, end, _ := p.readSQL(uSemi, false, ";")
		s.Frags = append(s.Frags, p.newFrag(KindSQL, parse.ModeDefault, start, end, s.Line))
		return p.finish(s)
	default:
		p.expr(s, uSemi, ";", s.Line, KindExpr)
		return p.finish(s)
	}
	p.expectPunct(';')
	return p.finish(s)
}

// raiseStmt is stmt_raise.
func (p *parser) raiseStmt() *Stmt {
	s := p.newStmt(StmtRaise, p.next())
	t := p.next()
	if t.Tok == 0 {
		p.failAt(int(t.Start), "unexpected end of function definition")
	}
	if t.is(';') {
		return p.finish(s)
	}
	for _, level := range []string{"exception", "warning", "notice", "info", "log", "debug"} {
		if t.kw(level) {
			t = p.next()
			break
		}
	}
	switch {
	case t.Tok == lex.SCONST:
		// old style message and parameters
		t = p.next()
		found := p.matchUntil(t)
		if found&(uComma|uSemi|uUsing) == 0 {
			p.back(t)
			p.syntaxError()
		}
		for found == uComma {
			_, found = p.expr(s, uComma|uSemi|uUsing, ", or ; or USING", s.Line, KindExpr)
		}
		if found == uUsing {
			p.raiseOptions(s)
		}
	case t.res && t.text == "using":
		p.raiseOptions(s)
	default:
		// condition name or SQLSTATE 'xxxxx'
		switch {
		case t.kw("sqlstate"):
			if p.cur().Tok != lex.SCONST {
				p.syntaxError()
			}
			p.next()
		case t.word:
		default:
			p.back(t)
			p.syntaxError()
		}
		t = p.next()
		switch {
		case t.is(';'):
		case t.res && t.text == "using":
			p.raiseOptions(s)
		default:
			p.back(t)
			p.syntaxError()
		}
	}
	return p.finish(s)
}

// raiseOptions is read_raise_options: USING has been read.
func (p *parser) raiseOptions(s *Stmt) {
	for {
		t := p.next()
		if t.Tok == 0 {
			p.failAt(int(t.Start), "unexpected end of function definition")
		}
		if !t.word {
			p.back(t)
			p.errorAtCurrent("unrecognized RAISE statement option")
		}
		if op := p.cur(); !op.is('=') && op.Tok != lex.COLON_EQUALS {
			p.errorAtCurrent("syntax error, expected \"=\"")
		}
		p.next()
		if _, found := p.expr(s, uComma|uSemi, ", or ;", s.Line, KindExpr); found == uSemi {
			return
		}
	}
}

func (p *parser) assertStmt() *Stmt {
	s := p.newStmt(StmtAssert, p.next())
	if _, found := p.expr(s, uComma|uSemi, ", or ;", s.Line, KindExpr); found == uComma {
		p.expr(s, uSemi, ";", s.Line, KindExpr)
	}
	return p.finish(s)
}

// getDiagStmt is stmt_getdiag: GET [CURRENT|STACKED] DIAGNOSTICS target =
// item [, ...]. It embeds no SQL.
func (p *parser) getDiagStmt() *Stmt {
	s := p.newStmt(StmtGetDiag, p.next())
	if t := p.cur(); t.kw("current") || t.kw("stacked") {
		p.next()
	}
	p.expectKw("diagnostics")
	for {
		if !p.cur().word {
			p.syntaxError()
		}
		_, end := p.compound(p.pos)
		p.pos = end
		if p.cur().is('[') { // not supported by PostgreSQL, but a target
			if end = p.skipGroup(p.pos); end < 0 {
				p.syntaxError()
			}
			p.pos = end
		}
		if t := p.cur(); !t.is('=') && t.Tok != lex.COLON_EQUALS {
			p.syntaxError()
		}
		p.next()
		if p.cur().Tok == 0 { // the item
			p.syntaxError()
		}
		p.next()
		if !p.cur().is(',') {
			break
		}
		p.next()
	}
	p.expectPunct(';')
	return p.finish(s)
}

// openStmt is stmt_open.
func (p *parser) openStmt() *Stmt {
	s := p.newStmt(StmtOpen, p.next())
	if !p.cur().word {
		p.syntaxError()
	}
	_, end := p.compound(p.pos)
	s.Cursor = p.dotted(p.pos, end)
	p.pos = end
	if t := p.cur(); t.is(';') || t.is('(') {
		// a bound cursor
		p.cursorArgs(s, uSemi, ";")
		return p.finish(s)
	}
	// an unbound one: [[NO] SCROLL] FOR query
	if p.cur().kw("no") {
		p.next()
	}
	if p.cur().kw("scroll") {
		p.next()
	}
	p.expectRes("for")
	if t := p.cur(); t.res && t.text == "execute" {
		p.next()
		cmd, found := p.expr(s, uUsing|uSemi, "USING or ;", s.Line, KindCommand)
		p.addDynamic(DynOpenExecute, s.Line, cmd)
		if found == uUsing {
			for found = uComma; found == uComma; {
				_, found = p.expr(s, uComma|uSemi, ", or ;", s.Line, KindExpr)
			}
		}
		return p.finish(s)
	}
	start, end, _ := p.readSQL(uSemi, false, ";")
	s.Frags = append(s.Frags, p.newFrag(KindSQL, parse.ModeDefault, start, end, s.Line))
	return p.finish(s)
}

// fetchStmt is FETCH and MOVE.
func (p *parser) fetchStmt() *Stmt {
	t := p.next()
	s := p.newStmt(StmtFetch, t)
	s.Move = t.text == "move"
	p.fetchDirection(s)
	if !p.cur().word {
		p.syntaxError()
	}
	_, end := p.compound(p.pos)
	s.Cursor = p.dotted(p.pos, end)
	p.pos = end
	if !s.Move {
		p.expectRes("into")
		p.readIntoTarget(false)
	}
	p.expectPunct(';')
	return p.finish(s)
}

// fetchDirection is read_fetch_direction: everything through FROM or IN.
func (p *parser) fetchDirection(s *Stmt) {
	t := p.cur()
	if t.Tok == 0 {
		p.failAt(int(t.Start), "unexpected end of function definition")
	}
	checkFrom := true
	switch {
	case t.kw("next") || t.kw("prior") || t.kw("first") || t.kw("last") || (t.res && t.text == "all"):
		p.next()
	case t.kw("absolute") || t.kw("relative"):
		p.next()
		p.expr(s, uFrom|uIn, "FROM or IN", s.Line, KindExpr)
		checkFrom = false
	case t.kw("forward") || t.kw("backward"):
		p.next()
		switch t2 := p.cur(); {
		case t2.res && (t2.text == "from" || t2.text == "in"):
			p.next()
			checkFrom = false
		case t2.res && t2.text == "all":
			p.next()
		default:
			p.expr(s, uFrom|uIn, "FROM or IN", s.Line, KindExpr)
			checkFrom = false
		}
	case t.res && (t.text == "from" || t.text == "in"):
		p.next()
		checkFrom = false
	case t.word && p.cursorNameFollows():
		// no direction: the word is the cursor
		checkFrom = false
	default:
		// a count expression with no keyword in front of it
		p.expr(s, uFrom|uIn, "FROM or IN", s.Line, KindExpr)
		checkFrom = false
	}
	if checkFrom {
		if t = p.cur(); !t.res || (t.text != "from" && t.text != "in") {
			p.errorAtCurrent("expected FROM or IN")
		}
		p.next()
	}
}

// cursorNameFollows reports whether the name at the current token is followed
// by INTO or a semicolon: the end of FETCH and MOVE.
func (p *parser) cursorNameFollows() bool {
	_, j := p.compound(p.pos)
	t := p.tok(j)
	return t.is(';') || (t.res && t.text == "into")
}

func (p *parser) closeStmt() *Stmt {
	s := p.newStmt(StmtClose, p.next())
	if !p.cur().word {
		p.syntaxError()
	}
	_, end := p.compound(p.pos)
	s.Cursor = p.dotted(p.pos, end)
	p.pos = end
	p.expectPunct(';')
	return p.finish(s)
}

// transactionStmt is COMMIT and ROLLBACK [AND [NO] CHAIN].
func (p *parser) transactionStmt() *Stmt {
	t := p.next()
	s := p.newStmt(StmtCommit, t)
	if t.text == "rollback" {
		s.Kind = StmtRollback
	}
	for !p.cur().is(';') {
		if p.next().Tok == 0 {
			p.syntaxError()
		}
	}
	p.next()
	return p.finish(s)
}

// executeStmt is stmt_dynexecute: EXECUTE command [INTO [STRICT] target]
// [USING expr, ...], the clauses in any order.
func (p *parser) executeStmt() *Stmt {
	s := p.newStmt(StmtDynExecute, p.next())
	cmd, found := p.expr(s, uInto|uUsing|uSemi, "INTO or USING or ;", s.Line, KindCommand)
	p.addDynamic(DynExecute, s.Line, cmd)
	for found != uSemi {
		switch found {
		case uInto:
			p.readIntoTarget(true)
			t := p.next()
			if found = p.matchUntil(t); found&(uInto|uUsing|uSemi) == 0 {
				p.back(t)
				p.syntaxError()
			}
		case uUsing:
			for found = uComma; found == uComma; {
				_, found = p.expr(s, uComma|uSemi|uInto, ", or ; or INTO", s.Line, KindExpr)
			}
		}
	}
	return p.finish(s)
}
