// This file is derived from PostgreSQL (src/pl/plpgsql/src/pl_gram.y).
//
// Portions Copyright (c) 1996-2024, PostgreSQL Global Development Group
// Portions Copyright (c) 1994, Regents of the University of California
//
// PostgreSQL License: see ../../LICENSE.PostgreSQL.

package plpgsql

import (
	"sort"

	"github.com/4itosik/pg_migrate_research/pgschema/internal/lex"
	"github.com/4itosik/pg_migrate_research/pgschema/internal/parse"
)

// until is a set of tokens that end an SQL fragment.
type until uint16

const (
	uSemi until = 1 << iota
	uComma
	uRParen
	uDotDot
	uThen
	uLoop
	uInto
	uUsing
	uWhen
	uBy
	uFrom
	uIn
)

// matchUntil returns the terminator t is, or zero.
func (p *parser) matchUntil(t *token) until {
	switch {
	case t.is(';'):
		return uSemi
	case t.is(','):
		return uComma
	case t.is(')'):
		return uRParen
	case t.Tok == lex.DOT_DOT:
		return uDotDot
	case t.res:
		switch t.text {
		case "then":
			return uThen
		case "loop":
			return uLoop
		case "into":
			return uInto
		case "using":
			return uUsing
		case "when":
			return uWhen
		case "by":
			return uBy
		case "from":
			return uFrom
		case "in":
			return uIn
		}
	}
	return 0
}

// readSQL is read_sql_construct: it reads tokens up to one of the
// terminators in set, outside parentheses and brackets, consumes the
// terminator and returns the range of the text before it, from the first
// token to the end of the last, and the terminator. A semicolon that is not a
// terminator and the end of input are errors. isExpr only picks the wording
// of the error.
func (p *parser) readSQL(set until, isExpr bool, expected string) (start, end int, found until) {
	start, end = -1, -1
	depth := 0
	for {
		t := p.next()
		if start < 0 {
			start = int(t.Start)
		}
		if u := p.matchUntil(t); u&set != 0 && depth == 0 {
			found = u
			break
		}
		if t.is('(') || t.is('[') {
			depth++
		} else if t.is(')') || t.is(']') {
			if depth--; depth < 0 {
				p.failAt(int(t.Start), "mismatched parentheses")
			}
		}
		if t.Tok == 0 || t.is(';') {
			if depth != 0 {
				p.failAt(int(t.Start), "mismatched parentheses")
			}
			what := "statement"
			if isExpr {
				what = "expression"
			}
			p.failAt(int(t.Start), "missing \""+expected+"\" at end of SQL "+what)
		}
		end = int(t.End)
	}
	if start >= end {
		if isExpr {
			p.failAt(start, "missing expression")
		}
		p.failAt(start, "missing SQL statement")
	}
	return start, end, found
}

// newFrag records a fragment.
func (p *parser) newFrag(kind FragKind, mode Mode, start, end, line int) *Fragment {
	f := &Fragment{Kind: kind, Mode: mode, Start: start, End: end, Line: line}
	p.body.Fragments = append(p.body.Fragments, f)
	return f
}

// expr reads an expression up to a terminator in set and records it. The
// statement s, if not nil, owns the fragment.
func (p *parser) expr(s *Stmt, set until, expected string, line int, kind FragKind) (*Fragment, until) {
	start, end, found := p.readSQL(set, true, expected)
	f := p.newFrag(kind, parse.ModePLpgSQLExpr, start, end, line)
	if s != nil {
		s.Frags = append(s.Frags, f)
	}
	return f, found
}

// readIntoTarget reads the target of INTO, which has just been read: [STRICT]
// name [, name ...]. The targets are names of variables, up to three dotted
// names each.
func (p *parser) readIntoTarget(strictOK bool) {
	if t := p.cur(); strictOK && t.res && t.text == "strict" {
		p.next()
	}
	for {
		if !p.cur().word {
			p.syntaxError()
		}
		_, end := p.compound(p.pos)
		p.pos = end
		if !p.cur().is(',') {
			return
		}
		p.next()
	}
}

// execSQLStmt is stmt_execsql and make_execsql_stmt: an SQL statement that
// ends at a semicolon outside parentheses and, in CREATE FUNCTION, outside
// BEGIN ... END. An INTO clause is cut out, except that of INSERT INTO, MERGE
// INTO and IMPORT FOREIGN SCHEMA ... INTO.
func (p *parser) execSQLStmt() *Stmt {
	first := p.next()
	s := p.newStmt(StmtExecSQL, first)
	var (
		prev           = first
		haveInto       bool
		intoStart      = -1
		intoEnd        = -1
		paren, begin   int
		inRoutine      bool
		tokens         [4]byte // records the first few tokens
		count          int
		semi           *token
		importFirstTok = first.kw("import")
	)
	if first.word && first.text == "create" {
		tokens[0] = 'c'
	}
	count++
	for {
		t := p.next()
		if haveInto && intoEnd < 0 {
			intoEnd = int(t.Start) // the token after the INTO part
		}
		// detect CREATE [OR REPLACE] {FUNCTION|PROCEDURE}
		if tokens[0] == 'c' && count < len(tokens) {
			switch {
			case t.res && t.text == "or":
				tokens[count] = 'o'
			case t.word && t.text == "replace":
				tokens[count] = 'r'
			case t.word && (t.text == "function" || t.text == "procedure"):
				tokens[count] = 'f'
			}
			if tokens[1] == 'f' || (tokens[1] == 'o' && tokens[2] == 'r' && tokens[3] == 'f') {
				inRoutine = true
			}
			count++
		}
		// track paren nesting (needed for CREATE RULE syntax)
		if t.is('(') {
			paren++
		} else if t.is(')') && paren > 0 {
			paren--
		}
		// BEGIN/END nesting matters only in a routine definition
		if inRoutine && paren == 0 {
			if t.res && (t.text == "begin" || t.text == "case") {
				begin++
			} else if t.res && t.text == "end" && begin > 0 {
				begin--
			}
		}
		if t.is(';') && paren == 0 && begin == 0 {
			semi = t
			break
		}
		if t.Tok == 0 {
			p.failAt(int(t.Start), "unexpected end of function definition")
		}
		if t.res && t.text == "into" {
			if prev.kw("insert") || prev.kw("merge") || importFirstTok {
				prev = t
				continue // not an INTO target
			}
			if haveInto {
				p.failAt(int(t.Start), "INTO specified more than once")
			}
			haveInto = true
			intoStart = int(t.Start)
			p.readIntoTarget(true)
			prev = t
			continue
		}
		prev = t
	}
	// the text ends at the semicolon; trailing white space and a blanked INTO
	// clause go from the end
	start, end := int(first.Start), int(semi.Start)
	f := p.newFrag(KindSQL, parse.ModeDefault, start, end, s.Line)
	if haveInto {
		if intoEnd < 0 {
			intoEnd = end
		}
		f.Into = Range{intoStart, intoEnd}
	}
	for f.End > f.Start && (isSpace(p.src[f.End-1]) || (f.Into.Start <= f.End-1 && f.End-1 < f.Into.End)) {
		f.End--
	}
	if f.Into.Start >= f.End {
		f.Into = Range{}
	} else if f.Into.End > f.End {
		f.Into.End = f.End
	}
	s.Frags = append(s.Frags, f)
	return p.finish(s)
}

// cursorArgs is read_cursor_args for a cursor whose declaration the parser
// does not look up: "( arg [, arg ...] )", or nothing, then the terminator
// until.
func (p *parser) cursorArgs(s *Stmt, until until, expected string) {
	t := p.next()
	if t.is('(') {
		for {
			name := ""
			if a := p.cur(); a.word && p.tok(p.pos+1).Tok == lex.COLON_EQUALS {
				name = a.text
				p.pos += 2
			}
			f, found := p.expr(s, uComma|uRParen, ", or )", s.Line, KindCursorArg)
			f.Name = name
			if found == uRParen {
				break
			}
		}
		t = p.next()
	}
	if p.matchUntil(t)&until == 0 {
		p.back(t)
		p.errorAtCurrent("syntax error, expected \"" + expected + "\"")
	}
}

// addDynamic records a statement that runs dynamic SQL: the command
// expression and the format(...) calls in it.
func (p *parser) addDynamic(kind DynamicKind, line int, cmd *Fragment) {
	d := &Dynamic{Kind: kind, Line: line, Command: cmd}
	i := sort.Search(len(p.toks), func(i int) bool { return int(p.toks[i].Start) >= cmd.Start })
	for ; i < len(p.toks) && int(p.toks[i].End) <= cmd.End; i++ {
		t := &p.toks[i]
		if !t.word || t.text != "format" || !p.tok(i+1).is('(') {
			continue
		}
		start := int(t.Start)
		if i > 0 && p.toks[i-1].is('.') {
			// only pg_catalog.format is the function of the same name
			if i < 2 || p.toks[i-2].text != "pg_catalog" || int(p.toks[i-2].Start) < cmd.Start {
				continue
			}
			start = int(p.toks[i-2].Start)
		}
		if end := p.skipGroup(i + 1); end > 0 {
			d.Format = append(d.Format, Range{start, int(p.toks[end-1].End)})
		}
	}
	p.body.Dynamic = append(p.body.Dynamic, d)
}
