// This file is derived from PostgreSQL (src/backend/parser/parser.c and gram.y).
//
// Portions Copyright (c) 1996-2024, PostgreSQL Global Development Group
// Portions Copyright (c) 1994, Regents of the University of California
//
// PostgreSQL License: see ../../LICENSE.PostgreSQL.

package parse

import (
	"fmt"
	"runtime/debug"
	"sync"

	"github.com/4itosik/pg_migrate_research/pgschema/internal/ast"
	"github.com/4itosik/pg_migrate_research/pgschema/internal/lex"
)

// Error is a scan or parse error. Loc is the byte offset the PostgreSQL
// error cursor points at, -1 when there is none.
type Error = lex.Error

// Mode selects what the parser accepts, like RawParseMode of PostgreSQL.
type Mode int

// The parse modes.
const (
	ModeDefault        Mode = iota // a script of statements
	ModeTypeName                   // a type name
	ModePLpgSQLExpr                // a PL/pgSQL expression
	ModePLpgSQLAssign1             // PL/pgSQL assignment, "var := expr"
	ModePLpgSQLAssign2             // PL/pgSQL assignment, "var[...] := expr"
	ModePLpgSQLAssign3             // PL/pgSQL assignment, "a.b.c := expr"
)

// Parse parses a script and returns its statements.
func Parse(src string) ([]*ast.RawStmt, error) {
	nodes, err := ParseMode(src, ModeDefault)
	if err != nil {
		return nil, err
	}
	stmts := make([]*ast.RawStmt, len(nodes))
	for i, n := range nodes {
		stmts[i] = n.(*ast.RawStmt)
	}
	return stmts, nil
}

// ParseMode is raw_parser: it parses src in the given mode. The result is
// the list of RawStmt of the script, or, in the other modes, the one node
// the grammar produces (a TypeName, an expression, an assignment).
func ParseMode(src string, mode Mode) (result []ast.Node, err error) {
	if err := lex.CheckEncoding(src); err != nil {
		return nil, err
	}
	p := &parser{src: src, sc: lex.NewScanner(src), mode: mode}
	defer func() {
		if r := recover(); r != nil {
			if a, ok := r.(parseAbort); ok {
				result, err = nil, a.err
				return
			}
			// a defect of the parser must not take down the caller: the
			// rewriter turns it into a refusal
			result, err = nil, &InternalError{Value: r, Stack: debug.Stack()}
		}
	}()
	initTokens()
	yyParse(p)
	return p.result, nil
}

// InternalError is returned when the parser itself fails, which is a defect
// of the library and not a mistake in the SQL. Value is what panicked.
type InternalError struct {
	Value any
	Stack []byte
}

func (e *InternalError) Error() string {
	return fmt.Sprintf("internal error of the SQL parser: %v", e.Value)
}

// parseAbort is the panic that ends a parse at the first error.
type parseAbort struct{ err *Error }

// parser is the state of one parse. It is the lexer of the generated parser
// and the receiver of the grammar actions.
type parser struct {
	src  string
	sc   *lex.Scanner
	mode Mode

	modeTokenSent bool
	la            lex.Item // lookahead token of base_yylex
	haveLA        bool

	// the last token handed to the parser, for syntax errors
	lastStart, lastEnd int32

	result []ast.Node
}

// fail ends the parse with an error that has no "at or near" text. loc is the
// byte offset of the error cursor, -1 for none.
func (p *parser) fail(loc int32, msg string) {
	panic(parseAbort{&Error{Msg: msg, Loc: int(loc)}})
}

// yyerror is parser_yyerror: an error at the last token read, worded like a
// syntax error ("msg at or near ...").
func (p *parser) yyerror(msg string) {
	panic(parseAbort{p.syntaxError(msg)})
}

func (p *parser) syntaxError(msg string) *Error {
	loc := int(p.lastStart)
	if loc >= len(p.src) {
		return &Error{Msg: msg + " at end of input", Loc: loc}
	}
	return &Error{Msg: msg + " at or near \"" + p.src[p.lastStart:p.lastEnd] + "\"", Loc: loc}
}

// Error is called by the generated parser on a syntax error.
func (p *parser) Error(msg string) { p.yyerror(msg) }

// tokMap translates the token numbers of package lex to those of the
// generated parser. Characters below 256 are their own code.
var (
	tokMap  []int32
	tokOnce sync.Once
)

func initTokens() {
	tokOnce.Do(func() {
		tokMap = make([]int32, 1024)
		// yyToknames lists "$end", "error", "$unk" and then the tokens in the
		// order of their numbers, which start at yyPrivate+2 = 57346
		for i := 3; i < len(yyToknames); i++ {
			if t, ok := lex.TokenByName(yyToknames[i]); ok && int(t) < len(tokMap) {
				tokMap[t] = int32(yyPrivate + i - 1)
			}
		}
	})
}

// Lex is base_yylex: the scanner plus the one-token lookahead that turns
// NOT, NULLS, WITH, WITHOUT and FORMAT into their _LA variants, and the
// decoding of Unicode escapes.
func (p *parser) Lex(lval *yySymType) int {
	*lval = yySymType{}
	if p.mode != ModeDefault && !p.modeTokenSent {
		p.modeTokenSent = true
		p.lastStart, p.lastEnd = 0, 0
		var t lex.Token
		switch p.mode {
		case ModeTypeName:
			t = lex.MODE_TYPE_NAME
		case ModePLpgSQLExpr:
			t = lex.MODE_PLPGSQL_EXPR
		case ModePLpgSQLAssign1:
			t = lex.MODE_PLPGSQL_ASSIGN1
		case ModePLpgSQLAssign2:
			t = lex.MODE_PLPGSQL_ASSIGN2
		case ModePLpgSQLAssign3:
			t = lex.MODE_PLPGSQL_ASSIGN3
		}
		return int(tokMap[t])
	}
	it, err := p.token()
	if err != nil {
		panic(parseAbort{err.(*Error)})
	}
	p.lastStart, p.lastEnd = it.Start, it.End
	lval.loc = it.Start
	switch it.Tok {
	case 0:
		return 0
	case lex.ICONST, lex.PARAM:
		lval.ival = it.Int
	default:
		lval.str = it.Str
	}
	if it.Tok < 256 {
		return int(it.Tok)
	}
	return int(tokMap[it.Tok])
}

// token returns the next token of base_yylex.
func (p *parser) token() (lex.Item, error) {
	var it lex.Item
	if p.haveLA {
		it, p.haveLA = p.la, false
	} else {
		var err error
		if it, err = p.sc.Next(); err != nil {
			return it, err
		}
	}
	switch it.Tok {
	case lex.FORMAT, lex.NOT, lex.NULLS_P, lex.WITH, lex.WITHOUT, lex.UIDENT, lex.USCONST:
	default:
		return it, nil
	}
	next, err := p.sc.Next()
	if err != nil {
		return it, err
	}
	p.la, p.haveLA = next, true
	switch it.Tok {
	case lex.FORMAT:
		if next.Tok == lex.JSON {
			it.Tok = lex.FORMAT_LA
		}
	case lex.NOT:
		switch next.Tok {
		case lex.BETWEEN, lex.IN_P, lex.LIKE, lex.ILIKE, lex.SIMILAR:
			it.Tok = lex.NOT_LA
		}
	case lex.NULLS_P:
		switch next.Tok {
		case lex.FIRST_P, lex.LAST_P:
			it.Tok = lex.NULLS_LA
		}
	case lex.WITH:
		switch next.Tok {
		case lex.TIME, lex.ORDINALITY:
			it.Tok = lex.WITH_LA
		}
	case lex.WITHOUT:
		if next.Tok == lex.TIME {
			it.Tok = lex.WITHOUT_LA
		}
	case lex.UIDENT, lex.USCONST:
		escape := byte('\\')
		if next.Tok == lex.UESCAPE {
			// the third token must be the escape character as a string
			esc, err := p.sc.Next()
			if err != nil {
				return it, err
			}
			p.lastStart, p.lastEnd = esc.Start, esc.End
			if esc.Tok != lex.SCONST {
				return it, p.syntaxError("UESCAPE must be followed by a simple string literal")
			}
			if len(esc.Str) != 1 || !checkUescapechar(esc.Str[0]) {
				return it, p.syntaxError("invalid Unicode escape character")
			}
			escape = esc.Str[0]
			p.haveLA = false
		}
		str, err := udeescape(it.Str, escape, it.Start)
		if err != nil {
			return it, err
		}
		it.Str = str
		if it.Tok == lex.UIDENT {
			it.Str = lex.TruncateIdent(it.Str)
			it.Tok = lex.IDENT
		} else {
			it.Tok = lex.SCONST
		}
	}
	return it, nil
}
