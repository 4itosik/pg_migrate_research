// Package lex is the lexer of PostgreSQL: a port of src/backend/parser/scan.l
// (PostgreSQL 17) that reports tokens with byte offsets, the keyword
// categories of kwlist.h, and the decoded values the grammar needs.
//
// It follows the rules of scan.l, including the longest-match behaviour of
// flex: the rule that matches the most input wins, and for equal length the
// rule that comes first in scan.l. Tokens and offsets are checked against
// libpg_query on the regression tests of PostgreSQL 12-16 (see the oracle
// module).
//
// Portions Copyright (c) 1996-2024, PostgreSQL Global Development Group
// Portions Copyright (c) 1994, Regents of the University of California
//
// PostgreSQL License: see ../../LICENSE.PostgreSQL.
package lex

import "strconv"

// Token is a token number of PostgreSQL's grammar. Tokens below 256 are
// single characters and equal their byte; the rest are the constants in
// tokens_gen.go, numbered like libpg_query numbers them. Zero is the end of
// input.
type Token int32

// String returns the token name in the spelling of libpg_query: "IDENT",
// "SELECT", "ASCII_40" for a single character.
func (t Token) String() string {
	switch {
	case t == 0:
		return "NUL"
	case t < 256:
		return "ASCII_" + strconv.Itoa(int(t))
	case int(t) < len(tokenNames) && tokenNames[t] != "":
		return tokenNames[t]
	}
	return "Token(" + strconv.Itoa(int(t)) + ")"
}

// KeywordKind is the category of a keyword in kwlist.h. The values equal the
// KeywordKind enum of libpg_query.
type KeywordKind uint8

// Keyword categories.
const (
	NoKeyword KeywordKind = iota
	UnreservedKeyword
	ColNameKeyword
	TypeFuncNameKeyword
	ReservedKeyword
)

func (k KeywordKind) String() string {
	switch k {
	case NoKeyword:
		return "NO_KEYWORD"
	case UnreservedKeyword:
		return "UNRESERVED_KEYWORD"
	case ColNameKeyword:
		return "COL_NAME_KEYWORD"
	case TypeFuncNameKeyword:
		return "TYPE_FUNC_NAME_KEYWORD"
	case ReservedKeyword:
		return "RESERVED_KEYWORD"
	}
	return "KeywordKind(" + strconv.Itoa(int(k)) + ")"
}

type keyword struct {
	name string
	tok  Token
	kind KeywordKind
	bare bool
}

// Item is a token with its position and value.
type Item struct {
	Tok Token
	// Start and End are the byte offsets of the token: src[Start:End].
	Start, End int32
	// Kind is the keyword category for keyword tokens, NoKeyword otherwise.
	Kind KeywordKind
	// Str is the value the grammar receives:
	//   keywords                  the lower-case keyword
	//   IDENT                     the identifier, folded to lower case and
	//                             truncated unless it was quoted
	//   UIDENT, USCONST           the raw text; the escapes are not decoded
	//   SCONST                    the string with escapes and continuations
	//                             applied
	//   BCONST, XCONST            "b" or "x" followed by the digits
	//   FCONST                    the number as written
	//   Op                        the operator
	Str string
	// Int is the value of ICONST and the number of PARAM.
	Int int32
}

// BareLabel reports whether the keyword may be used as a column label
// without AS (the BARE_LABEL flag of kwlist.h).
func (it Item) BareLabel() bool {
	if it.Kind == NoKeyword {
		return false
	}
	k, ok := lookupKeyword(it.Str)
	return ok && k.bare
}

// Error is a scanner error. Loc is the byte offset the PostgreSQL error
// cursor points at, or -1 when the error has no position.
type Error struct {
	Msg string
	Loc int
}

func (e *Error) Error() string { return e.Msg }

// CursorPos returns the 1-based character position PostgreSQL reports for
// the error in src, or 0 when there is none.
func (e *Error) CursorPos(src string) int {
	if e.Loc < 0 || e.Loc > len(src) {
		return 0
	}
	n := 1
	for i := 0; i < e.Loc; i += mblen(src[i]) {
		n++
	}
	return n
}

// mblen is pg_utf_mblen: the length of a UTF-8 character from its first
// byte. It does not validate the continuation bytes, like PostgreSQL.
func mblen(b byte) int {
	switch {
	case b&0x80 == 0:
		return 1
	case b&0xe0 == 0xc0:
		return 2
	case b&0xf0 == 0xe0:
		return 3
	case b&0xf8 == 0xf0:
		return 4
	}
	return 1
}

var keywordIndex = func() map[string]uint16 {
	m := make(map[string]uint16, len(keywords))
	for i := range keywords {
		m[keywords[i].name] = uint16(i)
	}
	return m
}()

func lookupKeyword(name string) (*keyword, bool) {
	i, ok := keywordIndex[name]
	if !ok {
		return nil, false
	}
	return &keywords[i], true
}
