package lex

import (
	"fmt"
	"strings"
	"unicode/utf8"
)

// nameDataLen is NAMEDATALEN: identifiers are truncated to nameDataLen-1
// bytes and operators of that length are errors.
const nameDataLen = 64

// Scanner splits SQL text into tokens the way core_yylex does. Whitespace
// and comments are skipped unless Comments is set.
type Scanner struct {
	// Comments makes Next return comments as SQL_COMMENT and C_COMMENT
	// items, as libpg_query's Scan does. The grammar never sees them.
	Comments bool
	// LibpgQueryCompat reproduces a deviation of libpg_query, which the
	// oracle tests need to explain mismatches: libpg_query turns comments
	// into tokens and, as a side effect, does not continue a string literal
	// across a comment ('a' -- c NEWLINE 'b'), which the server does.
	LibpgQueryCompat bool

	src string
	pos int
	buf []byte // literal buffer, reused between tokens
	err error
}

// NewScanner returns a scanner for src.
func NewScanner(src string) *Scanner { return &Scanner{src: src} }

// Scan returns all tokens of src, comments included when comments is set.
// On error it returns the tokens before the error and the error.
func Scan(src string, comments bool) ([]Item, error) {
	return (&Scanner{Comments: comments}).scanAll(src)
}

// ScanLibpgQuery is Scan with LibpgQueryCompat set.
func ScanLibpgQuery(src string, comments bool) ([]Item, error) {
	return (&Scanner{Comments: comments, LibpgQueryCompat: true}).scanAll(src)
}

func (s *Scanner) scanAll(src string) ([]Item, error) {
	s.src = src
	var items []Item
	for {
		it, err := s.Next()
		if err != nil {
			return items, err
		}
		if it.Tok == 0 {
			return items, nil
		}
		items = append(items, it)
	}
}

// Next returns the next token. At the end of input it returns an item with
// Tok 0. After an error it keeps returning the same error.
func (s *Scanner) Next() (Item, error) {
	if s.err != nil {
		return Item{}, s.err
	}
	it, err := s.next()
	if err != nil {
		s.err = err
	}
	return it, err
}

func (s *Scanner) next() (Item, error) {
	src := s.src
	for {
		p := s.pos
		if p >= len(src) {
			return Item{Start: int32(p), End: int32(p)}, nil
		}
		switch c := src[p]; {
		case isSpace(c):
			s.pos++
			continue
		case c == '-' && p+1 < len(src) && src[p+1] == '-':
			// {comment}: up to, not including, the newline
			e := p + 2
			for e < len(src) && src[e] != '\n' && src[e] != '\r' {
				e++
			}
			s.pos = e
			if s.Comments {
				return Item{Tok: SQL_COMMENT, Start: int32(p), End: int32(e)}, nil
			}
			continue
		case c == '/' && p+1 < len(src) && src[p+1] == '*':
			e, err := s.skipBlockComment(p)
			if err != nil {
				return Item{}, err
			}
			s.pos = e
			if s.Comments {
				return Item{Tok: C_COMMENT, Start: int32(p), End: int32(e)}, nil
			}
			continue
		default:
			return s.token(p)
		}
	}
}

// skipBlockComment returns the end of the possibly nested comment that
// starts at p.
func (s *Scanner) skipBlockComment(p int) (int, error) {
	src := s.src
	depth := 0
	i := p + 2
	for i < len(src) {
		switch {
		case src[i] == '/' && i+1 < len(src) && src[i+1] == '*':
			depth++
			i += 2
		case src[i] == '*' && i+1 < len(src) && src[i+1] == '/':
			if depth == 0 {
				return i + 2, nil
			}
			depth--
			i += 2
		default:
			i++
		}
	}
	return 0, s.errorAt("unterminated /* comment", p, len(src))
}

func isSpace(c byte) bool {
	return c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '\f' || c == '\v'
}

func isDigit(c byte) bool { return c >= '0' && c <= '9' }

func isHex(c byte) bool {
	return isDigit(c) || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F')
}

// identStart is [A-Za-z\200-\377_].
func identStart(c byte) bool {
	return c >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z' || c == '_' || c >= 0x80
}

// identCont is [A-Za-z\200-\377_0-9\$].
func identCont(c byte) bool { return identStart(c) || isDigit(c) || c == '$' }

// dolqCont is [A-Za-z\200-\377_0-9], the tag of a dollar quote.
func dolqCont(c byte) bool { return identStart(c) || isDigit(c) }

func isOpChar(c byte) bool {
	switch c {
	case '~', '!', '@', '#', '^', '&', '|', '`', '?', '+', '-', '*', '/', '%', '<', '>', '=':
		return true
	}
	return false
}

func (s *Scanner) item(tok Token, start, end int) Item {
	s.pos = end
	return Item{Tok: tok, Start: int32(start), End: int32(end)}
}

// errorAt builds scanner_yyerror's error. The cursor is loc. The message
// quotes src[loc:end], where end is the end of the text flex matched when
// the error was raised: flex puts a NUL after the current match, and
// PostgreSQL prints the string from loc up to it. An error at the end of
// the input says so instead.
func (s *Scanner) errorAt(msg string, loc, end int) *Error {
	if loc >= len(s.src) {
		return &Error{Msg: msg + " at end of input", Loc: loc}
	}
	return &Error{Msg: msg + " at or near \"" + s.src[loc:end] + "\"", Loc: loc}
}

func (s *Scanner) token(p int) (Item, error) {
	src := s.src
	c := src[p]
	var next byte
	if p+1 < len(src) {
		next = src[p+1]
	}
	switch {
	case c == '\'':
		return s.quoted(p, p+1, strKind{})
	case c == '"':
		return s.delimIdent(p, p+1, false)
	case c == '$':
		return s.dollar(p)
	case isDigit(c) || (c == '.' && isDigit(next)):
		return s.number(p)
	case identStart(c):
		return s.identOrPrefixed(p)
	}
	// operators and single-character tokens
	switch c {
	case ':':
		switch next {
		case ':':
			return s.item(TYPECAST, p, p+2), nil
		case '=':
			return s.item(COLON_EQUALS, p, p+2), nil
		}
		return s.item(Token(c), p, p+1), nil
	case '.':
		if next == '.' {
			return s.item(DOT_DOT, p, p+2), nil
		}
		return s.item(Token(c), p, p+1), nil
	case ',', '(', ')', '[', ']', ';':
		return s.item(Token(c), p, p+1), nil
	}
	if isOpChar(c) {
		return s.operator(p)
	}
	// {other}
	return s.item(Token(c), p, p+1), nil
}

// operator implements the {operator} rule together with the rules that tie
// with it ({self}, <=, >=, =>, <>, !=).
func (s *Scanner) operator(p int) (Item, error) {
	src := s.src
	e := p
	for e < len(src) && isOpChar(src[e]) {
		e++
	}
	text := src[p:e]
	n := len(text)
	// slash-star and dash-dash inside an operator start a comment
	if i := strings.Index(text, "/*"); i >= 0 && i < n {
		n = i
	}
	if i := strings.Index(text, "--"); i >= 0 && i < n {
		n = i
	}
	// '+' and '-' cannot end a multi-character operator unless it has
	// characters that are not in SQL operators
	if n > 1 && (text[n-1] == '+' || text[n-1] == '-') {
		ic := n - 2
		for ; ic >= 0; ic-- {
			if strings.IndexByte("~!@#^&|`?%", text[ic]) >= 0 {
				break
			}
		}
		if ic < 0 {
			for {
				n--
				if !(n > 1 && (text[n-1] == '+' || text[n-1] == '-')) {
					break
				}
			}
		}
	}
	end := p + n
	if n == 1 && strings.IndexByte("+-*/%^<>=", text[0]) >= 0 {
		return s.item(Token(text[0]), p, end), nil
	}
	if n == 2 {
		switch text[:2] {
		case "=>":
			return s.item(EQUALS_GREATER, p, end), nil
		case ">=":
			return s.item(GREATER_EQUALS, p, end), nil
		case "<=":
			return s.item(LESS_EQUALS, p, end), nil
		case "<>", "!=":
			return s.item(NOT_EQUALS, p, end), nil
		}
	}
	if n >= nameDataLen {
		return Item{}, s.errorAt("operator too long", p, p+n)
	}
	it := s.item(Op, p, end)
	it.Str = text[:n]
	return it, nil
}

// identOrPrefixed scans an identifier or keyword, or one of the literals
// that start with a letter: b'..', x'..', n'..', e'..', u&'..', u&"..".
func (s *Scanner) identOrPrefixed(p int) (Item, error) {
	src := s.src
	if p+1 < len(src) {
		c, n := src[p], src[p+1]
		switch {
		case n == '\'':
			switch c {
			case 'b', 'B':
				return s.quoted(p, p+2, strKind{bit: 'b'})
			case 'x', 'X':
				return s.quoted(p, p+2, strKind{bit: 'x'})
			case 'e', 'E':
				return s.quoted(p, p+2, strKind{esc: true})
			case 'n', 'N':
				// National character: only the n is the token, it is the
				// keyword NCHAR; the string follows as its own token.
				it := s.item(NCHAR, p, p+1)
				it.Kind, it.Str = ColNameKeyword, "nchar"
				if k, ok := lookupKeyword("nchar"); ok {
					it.Tok, it.Kind = k.tok, k.kind
				}
				return it, nil
			}
		case n == '&' && (c == 'u' || c == 'U') && p+2 < len(src):
			switch src[p+2] {
			case '\'':
				return s.quoted(p, p+3, strKind{uni: true})
			case '"':
				return s.delimIdent(p, p+3, true)
			}
		}
	}
	e := p + 1
	for e < len(src) && identCont(src[e]) {
		e++
	}
	text := src[p:e]
	if len(text) <= maxKeywordLen {
		var lower [maxKeywordLen]byte
		for i := 0; i < len(text); i++ {
			ch := text[i]
			if ch >= 'A' && ch <= 'Z' {
				ch += 'a' - 'A'
			}
			lower[i] = ch
		}
		if k, ok := lookupKeyword(string(lower[:len(text)])); ok {
			it := s.item(k.tok, p, e)
			it.Kind, it.Str = k.kind, k.name
			return it, nil
		}
	}
	it := s.item(IDENT, p, e)
	it.Str = downcaseTruncate(text)
	return it, nil
}

// downcaseTruncate is downcase_truncate_identifier for a UTF-8 database:
// ASCII letters are folded, other bytes are kept, and the result is cut to
// NAMEDATALEN-1 bytes at a character boundary.
func downcaseTruncate(id string) string {
	i := 0
	for ; i < len(id); i++ {
		if c := id[i]; c >= 'A' && c <= 'Z' {
			break
		}
	}
	if i == len(id) {
		return truncateIdent(id)
	}
	b := []byte(id)
	for ; i < len(b); i++ {
		if c := b[i]; c >= 'A' && c <= 'Z' {
			b[i] = c + 'a' - 'A'
		}
	}
	return truncateIdent(string(b))
}

// TruncateIdent cuts an identifier to NAMEDATALEN-1 bytes at a character
// boundary.
func TruncateIdent(id string) string {
	return truncateIdent(id)
}

func truncateIdent(id string) string {
	if len(id) < nameDataLen {
		return id
	}
	return id[:mbcliplen(id, nameDataLen-1)]
}

// mbcliplen is pg_mbcliplen for UTF-8: the longest prefix of at most limit
// bytes that does not cut a character.
func mbcliplen(s string, limit int) int {
	clen := 0
	for clen < len(s) {
		l := mblen(s[clen])
		if clen+l > limit {
			break
		}
		clen += l
		if clen == limit {
			break
		}
	}
	return clen
}

// delimIdent scans a "quoted identifier"; p is the token start and i the
// first byte after the opening quote. With uni it is U&"...", which is
// returned as UIDENT with the raw text.
func (s *Scanner) delimIdent(p, i int, uni bool) (Item, error) {
	src := s.src
	buf := s.buf[:0]
	simple := true
	start := i
	for {
		j := strings.IndexByte(src[i:], '"')
		if j < 0 {
			return Item{}, s.errorAt("unterminated quoted identifier", p, len(src))
		}
		j += i
		if j+1 < len(src) && src[j+1] == '"' {
			if simple {
				buf = append(buf, src[start:j]...)
				simple = false
			} else {
				buf = append(buf, src[i:j]...)
			}
			buf = append(buf, '"')
			i = j + 2
			continue
		}
		var val string
		if simple {
			val = src[start:j]
		} else {
			buf = append(buf, src[i:j]...)
			val = string(buf)
		}
		s.buf = buf
		if len(val) == 0 {
			return Item{}, s.errorAt("zero-length delimited identifier", p, j+1)
		}
		if uni {
			it := s.item(UIDENT, p, j+1)
			it.Str = val
			return it, nil
		}
		it := s.item(IDENT, p, j+1)
		it.Str = truncateIdent(val)
		return it, nil
	}
}

// dollar scans $$...$$ strings, $tag$...$tag$ strings and $n parameters.
func (s *Scanner) dollar(p int) (Item, error) {
	src := s.src
	if p+1 < len(src) {
		if isDigit(src[p+1]) {
			e := p + 1
			for e < len(src) && isDigit(src[e]) {
				e++
			}
			it := s.item(PARAM, p, e)
			it.Int = atol32(src[p+1 : e])
			return it, nil
		}
		// dolqdelim: $ tag? $
		e := p + 1
		if identStart(src[e]) {
			for e < len(src) && dolqCont(src[e]) {
				e++
			}
		}
		if e < len(src) && src[e] == '$' {
			delim := src[p : e+1]
			body := e + 1
			j := strings.Index(src[body:], delim)
			if j < 0 {
				return Item{}, s.errorAt("unterminated dollar-quoted string", p, len(src))
			}
			it := s.item(SCONST, p, body+j+len(delim))
			it.Str = src[body : body+j]
			return it, nil
		}
	}
	// {dolqfailed} and {other}: a lone $
	return s.item(Token('$'), p, p+1), nil
}

// atol32 is atol assigned to an int: saturating at LONG_MAX, then
// truncated to 32 bits.
func atol32(digits string) int32 {
	var v int64
	for i := 0; i < len(digits); i++ {
		d := int64(digits[i] - '0')
		if v > (1<<63-1-d)/10 {
			v = 1<<63 - 1
			break
		}
		v = v*10 + d
	}
	return int32(v)
}

// strKind tells the string scanner which literal it is in.
type strKind struct {
	bit byte // 'b' or 'x' for B'..' and X'..'
	esc bool // E'..'
	uni bool // U&'..'
}

// quoted scans a quoted literal. p is the token start, i the first byte
// after the opening quote. Adjacent literals separated by whitespace with a
// newline are one token (the xqs state of scan.l).
//
// The value is the source text between the quotes when nothing in it needs
// translating; otherwise it is built in s.buf from the segments of source
// text between the translated parts.
func (s *Scanner) quoted(p, i int, k strKind) (Item, error) {
	src := s.src
	buf := s.buf[:0]
	useBuf := false
	seg := i // start of the source text not yet in buf
	sawNonASCII := false
	if k.bit != 0 {
		buf = append(buf, k.bit)
		useBuf = true
	}
	flush := func(upto int) {
		useBuf = true
		buf = append(buf, src[seg:upto]...)
	}
	for {
		if !k.esc {
			// the next quote ends the text; nothing else is special
			j := strings.IndexByte(src[i:], '\'')
			if j < 0 {
				return Item{}, s.errorAt(unterminatedMsg(k), p, len(src))
			}
			i += j
		} else {
			for i < len(src) && src[i] != '\'' && src[i] != '\\' {
				i++
			}
			if i >= len(src) {
				return Item{}, s.errorAt(unterminatedMsg(k), p, len(src))
			}
		}
		if src[i] == '\\' {
			flush(i)
			n, err := s.escape(i, &buf, &sawNonASCII)
			if err != nil {
				return Item{}, err
			}
			i, seg = n, n
			continue
		}
		// a quote
		if k.bit == 0 && i+1 < len(src) && src[i+1] == '\'' {
			// '' stands for one quote
			flush(i)
			buf = append(buf, '\'')
			i += 2
			seg = i
			continue
		}
		if n, ok := s.continuation(i + 1); ok {
			flush(i)
			i, seg = n, n
			continue
		}
		var val string
		if useBuf {
			buf = append(buf, src[seg:i]...)
			val = string(buf)
		} else {
			val = src[seg:i]
		}
		s.buf = buf
		if sawNonASCII && !validMB(val) {
			return Item{}, &Error{Msg: invalidEncoding(val), Loc: -1}
		}
		tok := SCONST
		switch {
		case k.bit == 'b':
			tok = BCONST
		case k.bit == 'x':
			tok = XCONST
		case k.uni:
			tok = USCONST
		}
		it := s.item(tok, p, i+1)
		it.Str = val
		return it, nil
	}
}

func unterminatedMsg(k strKind) string {
	switch k.bit {
	case 'b':
		return "unterminated bit string literal"
	case 'x':
		return "unterminated hexadecimal string literal"
	}
	return "unterminated quoted string"
}

// continuation reports whether the closing quote that ended at i is
// followed by whitespace with a newline and another quote, and returns the
// offset after that quote. This is {quotecontinue}:
//
//	{non_newline_space | comment}* {newline} {space+ | comment newline}* '
func (s *Scanner) continuation(i int) (int, bool) {
	src := s.src
	// whitespace without newline, comments
	for i < len(src) {
		c := src[i]
		switch {
		case c == ' ' || c == '\t' || c == '\f' || c == '\v':
			i++
			continue
		case c == '-' && i+1 < len(src) && src[i+1] == '-' && !s.LibpgQueryCompat:
			for i < len(src) && src[i] != '\n' && src[i] != '\r' {
				i++
			}
			continue
		}
		break
	}
	if i >= len(src) || (src[i] != '\n' && src[i] != '\r') {
		return 0, false
	}
	i++
	for i < len(src) {
		c := src[i]
		switch {
		case isSpace(c):
			i++
			continue
		case c == '-' && i+1 < len(src) && src[i+1] == '-' && !s.LibpgQueryCompat:
			j := i
			for j < len(src) && src[j] != '\n' && src[j] != '\r' {
				j++
			}
			if j >= len(src) {
				return 0, false // {comment}{newline} needs the newline
			}
			i = j + 1
			continue
		}
		break
	}
	if i < len(src) && src[i] == '\'' {
		return i + 1, true
	}
	return 0, false
}

func hexVal(c byte) uint32 {
	switch {
	case c >= '0' && c <= '9':
		return uint32(c - '0')
	case c >= 'a' && c <= 'f':
		return uint32(c-'a') + 10
	}
	return uint32(c-'A') + 10
}

func hexRun(src string, i, max int) int {
	n := 0
	for n < max && i+n < len(src) && isHex(src[i+n]) {
		n++
	}
	return n
}

// escape handles the backslash sequence at i inside E'..' and returns the
// offset after it.
func (s *Scanner) escape(i int, buf *[]byte, sawNonASCII *bool) (int, error) {
	src := s.src
	if i+1 >= len(src) {
		// a backslash just before the end of input
		*buf = append(*buf, '\\')
		return i + 1, nil
	}
	c := src[i+1]
	switch {
	case c == 'u' || c == 'U':
		want := 4
		if c == 'U' {
			want = 8
		}
		if hexRun(src, i+2, want) < want {
			return 0, &Error{Msg: "invalid Unicode escape", Loc: i}
		}
		var cp uint32
		for _, h := range []byte(src[i+2 : i+2+want]) {
			cp = cp<<4 | hexVal(h)
		}
		n := i + 2 + want
		switch {
		case isUTF16SurrogateFirst(cp):
			// a second \u escape must follow at once
			if n+1 < len(src) && src[n] == '\\' && (src[n+1] == 'u' || src[n+1] == 'U') {
				w2 := 4
				if src[n+1] == 'U' {
					w2 = 8
				}
				if hexRun(src, n+2, w2) < w2 {
					return 0, &Error{Msg: "invalid Unicode escape", Loc: n}
				}
				var cp2 uint32
				for _, h := range []byte(src[n+2 : n+2+w2]) {
					cp2 = cp2<<4 | hexVal(h)
				}
				if !isUTF16SurrogateSecond(cp2) {
					return 0, s.errorAt("invalid Unicode surrogate pair", n, n+2+w2)
				}
				cp = 0x10000 + (cp-0xD800)<<10 + (cp2 - 0xDC00)
				*buf = utf8.AppendRune(*buf, rune(cp))
				return n + 2 + w2, nil
			}
			// the rule that fails is "." and matches one byte
			return 0, s.errorAt("invalid Unicode surrogate pair", n, min(n+1, len(src)))
		case isUTF16SurrogateSecond(cp):
			return 0, s.errorAt("invalid Unicode surrogate pair", i, n)
		case cp == 0 || cp > 0x10FFFF:
			return 0, s.errorAt("invalid Unicode escape value", i, n)
		}
		*buf = utf8.AppendRune(*buf, rune(cp))
		return n, nil
	case c >= '0' && c <= '7':
		v, j := 0, i+1
		for k := 0; k < 3 && j < len(src) && src[j] >= '0' && src[j] <= '7'; k++ {
			v = v*8 + int(src[j]-'0')
			j++
		}
		b := byte(v)
		*buf = append(*buf, b)
		if b == 0 || b >= 0x80 {
			*sawNonASCII = true
		}
		return j, nil
	case c == 'x' && hexRun(src, i+2, 1) == 1:
		n := hexRun(src, i+2, 2)
		var b byte
		for _, h := range []byte(src[i+2 : i+2+n]) {
			b = b<<4 | byte(hexVal(h))
		}
		*buf = append(*buf, b)
		if b == 0 || b >= 0x80 {
			*sawNonASCII = true
		}
		return i + 2 + n, nil
	}
	// xeescape: backslash and one byte
	switch c {
	case 'b':
		*buf = append(*buf, '\b')
	case 'f':
		*buf = append(*buf, '\f')
	case 'n':
		*buf = append(*buf, '\n')
	case 'r':
		*buf = append(*buf, '\r')
	case 't':
		*buf = append(*buf, '\t')
	case 'v':
		*buf = append(*buf, '\v')
	default:
		if c == 0 || c >= 0x80 {
			*sawNonASCII = true
		}
		*buf = append(*buf, c)
	}
	return i + 2, nil
}

func isUTF16SurrogateFirst(c uint32) bool  { return c&0xFC00 == 0xD800 }
func isUTF16SurrogateSecond(c uint32) bool { return c&0xFC00 == 0xDC00 }

// validMB is pg_verifymbstr for UTF-8: valid UTF-8 without a NUL.
func validMB(s string) bool {
	return utf8.ValidString(s) && strings.IndexByte(s, 0) < 0
}

// invalidEncoding words the error of report_invalid_encoding for the first
// invalid character of s.
func invalidEncoding(s string) string {
	for i := 0; i < len(s); {
		if s[i] == 0 {
			return `invalid byte sequence for encoding "UTF8": 0x00`
		}
		r, n := utf8.DecodeRuneInString(s[i:])
		if r == utf8.RuneError && n <= 1 {
			l := mblen(s[i])
			if l > len(s)-i {
				l = len(s) - i
			}
			var hex []string
			for _, b := range []byte(s[i : i+l]) {
				hex = append(hex, fmt.Sprintf("0x%02x", b))
			}
			return `invalid byte sequence for encoding "UTF8": ` + strings.Join(hex, " ")
		}
		i += n
	}
	return `invalid byte sequence for encoding "UTF8"`
}
