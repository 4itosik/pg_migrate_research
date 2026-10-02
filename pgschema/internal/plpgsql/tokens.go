// This file is derived from PostgreSQL (src/pl/plpgsql/src/pl_scanner.c and pl_reserved_kwlist.h).
//
// Portions Copyright (c) 1996-2024, PostgreSQL Global Development Group
// Portions Copyright (c) 1994, Regents of the University of California
//
// PostgreSQL License: see ../../LICENSE.PostgreSQL.

package plpgsql

import (
	"sort"

	"github.com/4itosik/pg_migrate_research/pgschema/internal/lex"
)

// reserved are the keywords PL/pgSQL reserves (pl_reserved_kwlist.h). They
// are passed to the core scanner in place of the SQL keywords, so every other
// word, SQL keywords included, is an identifier to PL/pgSQL; its unreserved
// keywords (pl_unreserved_kwlist.h) are recognised by the grammar by name.
var reserved = map[string]bool{
	"all": true, "begin": true, "by": true, "case": true, "declare": true,
	"else": true, "end": true, "execute": true, "for": true, "foreach": true,
	"from": true, "if": true, "in": true, "into": true, "loop": true,
	"not": true, "null": true, "or": true, "strict": true, "then": true,
	"to": true, "using": true, "when": true, "while": true,
}

// token is a lexer item as the PL/pgSQL scanner sees it.
type token struct {
	lex.Item
	// text is the folded text of a word or of a reserved keyword, "" for
	// other tokens.
	text string
	// word is an IDENT of the PL/pgSQL scanner: an identifier, a quoted
	// identifier, a $n parameter, or a keyword PL/pgSQL does not reserve.
	word   bool
	quoted bool
	// res is a keyword reserved by PL/pgSQL.
	res bool
	// dotted is a word followed by . and another word: plpgsql_yylex joins
	// such words into one compound identifier before it looks for the
	// unreserved keywords, so next.x or alias.t is a name, never the keyword.
	dotted bool
}

func (t *token) is(c byte) bool { return t.Tok == lex.Token(c) }

// kw reports whether t is the unquoted word or reserved keyword s: what
// tok_is_keyword and the unreserved keyword lookup recognise.
func (t *token) kw(s string) bool { return (t.word || t.res) && !t.quoted && !t.dotted && t.text == s }

func (t *token) op(s string) bool { return t.Tok == lex.Op && t.Str == s }

// makeToken classifies a lexer item of src.
func makeToken(src string, it lex.Item) token {
	t := token{Item: it}
	switch {
	case it.Tok == lex.IDENT:
		t.text = it.Str
		t.quoted = src[it.Start] == '"'
	case it.Tok == lex.PARAM:
		t.text = src[it.Start:it.End]
		t.word = true
		return t
	case it.Kind != lex.NoKeyword:
		t.text = it.Str
		if it.Tok == lex.NCHAR && it.End-it.Start == 1 {
			// n'...': PL/pgSQL has no keyword NCHAR, so the scanner returns
			// the identifier n and then the string
			t.text = "n"
		}
	default:
		return t
	}
	if !t.quoted && reserved[t.text] {
		t.res = true
	} else {
		t.word = true
	}
	return t
}

func isSpace(c byte) bool {
	return c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '\f' || c == '\v'
}

// lineIndex finds the line of an offset.
type lineIndex []int // offsets of the newlines

func newLineIndex(src string) lineIndex {
	var nl lineIndex
	for i := 0; i < len(src); i++ {
		if src[i] == '\n' {
			nl = append(nl, i)
		}
	}
	return nl
}

// line is plpgsql_location_to_lineno: one plus the newlines before off.
func (nl lineIndex) line(off int) int { return 1 + sort.SearchInts(nl, off) }

// scan splits src into tokens and appends the end-of-input token.
func scan(src string) ([]token, error) {
	items, err := lex.Scan(src, false)
	if err != nil {
		return nil, err
	}
	toks := make([]token, 0, len(items)+1)
	for _, it := range items {
		toks = append(toks, makeToken(src, it))
	}
	n := int32(len(src))
	toks = append(toks, token{Item: lex.Item{Start: n, End: n}})
	for i := 0; i+2 < len(toks); i++ {
		toks[i].dotted = toks[i].word && toks[i+1].is('.') && toks[i+2].word
	}
	return toks, nil
}
