// This file is derived from PostgreSQL (src/backend/parser/parser.c and scan.l).
//
// Portions Copyright (c) 1996-2024, PostgreSQL Global Development Group
// Portions Copyright (c) 1994, Regents of the University of California
//
// PostgreSQL License: see ../../LICENSE.PostgreSQL.

package parse

import (
	"strings"
	"unicode/utf8"

	"github.com/4itosik/pg_migrate_research/pgschema/internal/lex"
)

// udeescape is str_udeescape of parser.c: it decodes the escapes of a
// string of U&'...' or U&"..." (\XXXX, \+XXXXXX and the doubled escape
// character). position is the offset of the token; the errors point at the
// escape, counting the three characters of the U&" prefix.
func udeescape(str string, escape byte, position int32) (string, error) {
	var out strings.Builder
	out.Grow(len(str))
	var pairFirst uint32
	isHexAt := func(i int) bool { return i < len(str) && isHexDigit(str[i]) }
	for i := 0; i < len(str); {
		errPos := int(position) + i + 3
		if str[i] != escape {
			if pairFirst != 0 {
				return "", &lex.Error{Msg: "invalid Unicode surrogate pair", Loc: errPos}
			}
			out.WriteByte(str[i])
			i++
			continue
		}
		var unicode uint32
		var width int
		switch {
		case i+1 < len(str) && str[i+1] == escape:
			if pairFirst != 0 {
				return "", &lex.Error{Msg: "invalid Unicode surrogate pair", Loc: errPos}
			}
			out.WriteByte(escape)
			i += 2
			continue
		case isHexAt(i+1) && isHexAt(i+2) && isHexAt(i+3) && isHexAt(i+4):
			for _, c := range []byte(str[i+1 : i+5]) {
				unicode = unicode<<4 + hexDigit(c)
			}
			width = 5
		case i+1 < len(str) && str[i+1] == '+' && isHexAt(i+2) && isHexAt(i+3) && isHexAt(i+4) && isHexAt(i+5) && isHexAt(i+6) && isHexAt(i+7):
			for _, c := range []byte(str[i+2 : i+8]) {
				unicode = unicode<<4 + hexDigit(c)
			}
			width = 8
		default:
			return "", &lex.Error{Msg: "invalid Unicode escape", Loc: errPos}
		}
		if unicode == 0 || unicode > 0x10FFFF {
			return "", &lex.Error{Msg: "invalid Unicode escape value", Loc: errPos}
		}
		switch {
		case pairFirst != 0:
			if unicode&0xFC00 != 0xDC00 {
				return "", &lex.Error{Msg: "invalid Unicode surrogate pair", Loc: errPos}
			}
			unicode = 0x10000 + (pairFirst-0xD800)<<10 + (unicode - 0xDC00)
			pairFirst = 0
		case unicode&0xFC00 == 0xDC00:
			return "", &lex.Error{Msg: "invalid Unicode surrogate pair", Loc: errPos}
		}
		if unicode&0xFC00 == 0xD800 {
			pairFirst = unicode
		} else {
			var b [4]byte
			n := utf8.EncodeRune(b[:], rune(unicode))
			out.Write(b[:n])
		}
		i += width
	}
	if pairFirst != 0 {
		return "", &lex.Error{Msg: "invalid Unicode surrogate pair", Loc: int(position) + len(str) + 3}
	}
	return out.String(), nil
}

func isHexDigit(c byte) bool {
	return c >= '0' && c <= '9' || c >= 'a' && c <= 'f' || c >= 'A' && c <= 'F'
}

func hexDigit(c byte) uint32 {
	switch {
	case c >= '0' && c <= '9':
		return uint32(c - '0')
	case c >= 'a' && c <= 'f':
		return uint32(c-'a') + 10
	}
	return uint32(c-'A') + 10
}

// checkUescapechar is check_uescapechar: the escape character of UESCAPE
// must not be a hex digit, '+', a quote or white space.
func checkUescapechar(c byte) bool {
	switch {
	case isHexDigit(c), c == '+', c == '\'', c == '"':
		return false
	case c == ' ', c == '\t', c == '\n', c == '\r', c == '\f', c == '\v':
		return false
	}
	return true
}
