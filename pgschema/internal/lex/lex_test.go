package lex

import (
	"fmt"
	"strings"
	"testing"
)

// dump renders items as "TOKEN start..end", with the value in brackets for
// tokens that have one.
func dump(items []Item) string {
	var b strings.Builder
	for i, it := range items {
		if i > 0 {
			b.WriteString("; ")
		}
		fmt.Fprintf(&b, "%s %d..%d", it.Tok, it.Start, it.End)
		switch it.Tok {
		case ICONST, PARAM:
			fmt.Fprintf(&b, " [%d]", it.Int)
		case IDENT, UIDENT, SCONST, USCONST, BCONST, XCONST, FCONST, Op:
			fmt.Fprintf(&b, " [%s]", it.Str)
		}
	}
	return b.String()
}

// bs is a backslash: inputs with unicode escapes are built with it, so that
// no backslash-u sequence appears in this file's source.
const bs = "\\"

func TestScanTokens(t *testing.T) {
	tests := []struct {
		name, src, want string
	}{
		{"keywords and comments", "SELECT /* a /* n */ b */ 1 -- x",
			"SELECT 0..6; C_COMMENT 7..24; ICONST 25..26 [1]; SQL_COMMENT 27..31"},
		{"identifier folding", `FooBar "FooBar" "a""b" x$y é`,
			`IDENT 0..6 [foobar]; IDENT 7..15 [FooBar]; IDENT 16..22 [a"b]; IDENT 23..26 [x$y]; IDENT 27..29 [é]`},
		{"national string", "N'abc'", "NCHAR 0..1; SCONST 1..6 [abc]"},
		{"string continuation needs a newline", "'a'\n'b' 'c'", "SCONST 0..7 [ab]; SCONST 8..11 [c]"},
		{"string continuation across a comment", "'a' -- c\n'b'", "SCONST 0..12 [ab]"},
		{"doubled quote", "'it''s'", "SCONST 0..7 [it's]"},
		{"bit and hex strings", "B'101' X'1F' b'' 'x'", "BCONST 0..6 [b101]; XCONST 7..12 [x1F]; BCONST 13..16 [b]; SCONST 17..20 [x]"},
		{"unicode strings stay raw", `U&'d\0061t' U&"d\0061t" u&`,
			`USCONST 0..11 [d\0061t]; UIDENT 12..23 [d\0061t]; IDENT 24..25 [u]; Op 25..26 [&]`},
		{"escape strings", "E'a" + bs + "nb" + bs + "x41" + bs + "101" + bs + "u00e9" + bs + bs + bs + "''", "SCONST 0..25 [a\nbAAé\\']"},
		{"surrogate pair", "E'" + bs + "ud83d" + bs + "ude00'", "SCONST 0..15 [😀]"},
		{"dollar quotes", "$$x$$ $a$ $b$ $a$ $a$$a$", "SCONST 0..5 [x]; SCONST 6..17 [ $b$ ]; SCONST 18..24 []"},
		{"parameters and lone dollar", "$1 $12 $ $a", "PARAM 0..2 [1]; PARAM 3..6 [12]; ASCII_36 7..8; ASCII_36 9..10; IDENT 10..11 [a]"},
		{"numbers", "1..10 0x1F 1_000 1e5 .5 1.e+3 2147483647 2147483648 0b101 0o17",
			"ICONST 0..1 [1]; DOT_DOT 1..3; ICONST 3..5 [10]; ICONST 6..10 [31]; ICONST 11..16 [1000]; " +
				"FCONST 17..20 [1e5]; FCONST 21..23 [.5]; FCONST 24..29 [1.e+3]; ICONST 30..40 [2147483647]; " +
				"FCONST 41..51 [2147483648]; ICONST 52..57 [5]; ICONST 58..62 [15]"},
		{"operators", "a<=>b <= =- +-* /*c*/ ::= != <> =>",
			"IDENT 0..1 [a]; Op 1..4 [<=>]; IDENT 4..5 [b]; LESS_EQUALS 6..8; ASCII_61 9..10; ASCII_45 10..11; " +
				"Op 12..15 [+-*]; C_COMMENT 16..21; TYPECAST 22..24; ASCII_61 24..25; NOT_EQUALS 26..28; NOT_EQUALS 29..31; EQUALS_GREATER 32..34"},
		{"operator ends at a comment", "+--x\n*/*y*/", "ASCII_43 0..1; SQL_COMMENT 1..4; ASCII_42 5..6; C_COMMENT 6..11"},
		{"trailing plus and minus", "a =- b @- c", "IDENT 0..1 [a]; ASCII_61 2..3; ASCII_45 3..4; IDENT 5..6 [b]; Op 7..9 [@-]; IDENT 10..11 [c]"},
		{"single characters", "a.b(c)[d],e;f:g", "IDENT 0..1 [a]; ASCII_46 1..2; IDENT 2..3 [b]; ASCII_40 3..4; IDENT 4..5 [c]; ASCII_41 5..6; " +
			"ASCII_91 6..7; IDENT 7..8 [d]; ASCII_93 8..9; ASCII_44 9..10; IDENT 10..11 [e]; ASCII_59 11..12; IDENT 12..13 [f]; ASCII_58 13..14; IDENT 14..15 [g]"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			items, err := Scan(tt.src, true)
			if err != nil {
				t.Fatalf("Scan(%q): %v", tt.src, err)
			}
			if got := dump(items); got != tt.want {
				t.Errorf("Scan(%q)\n got %s\nwant %s", tt.src, got, tt.want)
			}
		})
	}
}

// TestLibpgQueryCompat is the behaviour the oracle compares against: no
// continuation of a string across a comment.
func TestLibpgQueryCompat(t *testing.T) {
	items, err := ScanLibpgQuery("'a' -- c\n'b'", true)
	if err != nil {
		t.Fatal(err)
	}
	want := "SCONST 0..3 [a]; SQL_COMMENT 4..8; SCONST 9..12 [b]"
	if got := dump(items); got != want {
		t.Errorf("got %s\nwant %s", got, want)
	}
}

func TestKeywords(t *testing.T) {
	tests := []struct {
		word string
		tok  Token
		kind KeywordKind
		bare bool
	}{
		{"select", SELECT, ReservedKeyword, true},
		{"SELECT", SELECT, ReservedKeyword, true},
		{"as", AS, ReservedKeyword, false},
		{"abort", ABORT_P, UnreservedKeyword, true},
		{"between", BETWEEN, ColNameKeyword, true},
		{"inner", INNER_P, TypeFuncNameKeyword, true},
		{"nchar", NCHAR, ColNameKeyword, true},
	}
	for _, tt := range tests {
		items, err := Scan(tt.word, false)
		if err != nil || len(items) != 1 {
			t.Fatalf("Scan(%q) = %v, %v", tt.word, items, err)
		}
		it := items[0]
		if it.Tok != tt.tok || it.Kind != tt.kind || it.BareLabel() != tt.bare || it.Str != strings.ToLower(tt.word) {
			t.Errorf("%q: got %v %v bare=%v %q, want %v %v bare=%v", tt.word, it.Tok, it.Kind, it.BareLabel(), it.Str, tt.tok, tt.kind, tt.bare)
		}
	}
	if len(keywords) != 491 {
		t.Errorf("%d keywords, want 491 (PostgreSQL 17)", len(keywords))
	}
}

func TestIdentifierTruncation(t *testing.T) {
	long := strings.Repeat("a", 70)
	items, err := Scan(strings.ToUpper(long), false)
	if err != nil {
		t.Fatal(err)
	}
	if got := items[0].Str; got != long[:63] {
		t.Errorf("ASCII: got %d bytes, want 63", len(got))
	}
	// 40 two-byte characters are 80 bytes: the cut falls on a boundary
	items, err = Scan(strings.Repeat("é", 40), false)
	if err != nil {
		t.Fatal(err)
	}
	if got := items[0].Str; got != strings.Repeat("é", 31) {
		t.Errorf("UTF-8: got %d bytes, want 62", len(got))
	}
	// a quoted identifier is truncated but not folded
	items, err = Scan(`"`+strings.ToUpper(long)+`"`, false)
	if err != nil {
		t.Fatal(err)
	}
	if got := items[0].Str; got != strings.ToUpper(long)[:63] {
		t.Errorf("quoted: got %q", got)
	}
}

func TestScanErrors(t *testing.T) {
	tests := []struct {
		src     string
		msg     string
		cursor  int // 1-based character position, 0 for none
		partial int // tokens returned before the error
	}{
		{"select 'abc", `unterminated quoted string at or near "'abc"`, 8, 1},
		{"select /* a", `unterminated /* comment at or near "/* a"`, 8, 1},
		{`select "abc`, `unterminated quoted identifier at or near ""abc"`, 8, 1},
		{"select $a$ x", `unterminated dollar-quoted string at or near "$a$ x"`, 8, 1},
		{"select B'1", `unterminated bit string literal at or near "B'1"`, 8, 1},
		{"select X'1", `unterminated hexadecimal string literal at or near "X'1"`, 8, 1},
		{"select 0x", `invalid hexadecimal integer at or near "0x"`, 8, 1},
		{"select 0o", `invalid octal integer at or near "0o"`, 8, 1},
		{"select 0b", `invalid binary integer at or near "0b"`, 8, 1},
		{"select 1a", `trailing junk after numeric literal at or near "1a"`, 8, 1},
		{"select 1e+", `trailing junk after numeric literal at or near "1e+"`, 8, 1},
		{"select 1_0$", `trailing junk after numeric literal at or near "1_0$"`, 8, 1},
		{`select ""`, `zero-length delimited identifier at or near """"`, 8, 1},
		{"select E'" + bs + "u12'", "invalid Unicode escape", 10, 1},
		{"select E'" + bs + "ud800'", `invalid Unicode surrogate pair at or near "'"`, 16, 1},
		{"select E'" + bs + "ud800x'", `invalid Unicode surrogate pair at or near "x"`, 16, 1},
		{"select E'" + bs + "udc00'", `invalid Unicode surrogate pair at or near "` + bs + `udc00"`, 10, 1},
		{"select E'" + bs + "u0000'", `invalid Unicode escape value at or near "` + bs + `u0000"`, 10, 1},
		{"select E'\\xff'", `invalid byte sequence for encoding "UTF8": 0xff`, 0, 1},
		{"select E'\\0'", `invalid byte sequence for encoding "UTF8": 0x00`, 0, 1},
		{"é 'x", `unterminated quoted string at or near "'x"`, 3, 1},
		{"select " + strings.Repeat("+*", 40), "", 8, 1},
	}
	for _, tt := range tests {
		items, err := Scan(tt.src, false)
		if err == nil {
			t.Errorf("Scan(%q): no error", tt.src)
			continue
		}
		e := err.(*Error)
		if tt.msg != "" && e.Msg != tt.msg {
			t.Errorf("Scan(%q): message %q, want %q", tt.src, e.Msg, tt.msg)
		}
		if tt.msg == "" && !strings.HasPrefix(e.Msg, "operator too long") {
			t.Errorf("Scan(%q): message %q, want operator too long", tt.src, e.Msg)
		}
		if got := e.CursorPos(tt.src); got != tt.cursor {
			t.Errorf("Scan(%q): cursor %d, want %d", tt.src, got, tt.cursor)
		}
		if len(items) != tt.partial {
			t.Errorf("Scan(%q): %d tokens before the error, want %d", tt.src, len(items), tt.partial)
		}
	}
}

func TestErrorAtEndOfInput(t *testing.T) {
	// a token that starts at the end of the input cannot happen; the helper
	// still words it like PostgreSQL
	s := NewScanner("abc")
	if e := s.errorAt("x", 3, 3); e.Msg != "x at end of input" {
		t.Errorf("got %q", e.Msg)
	}
}

func BenchmarkScan(b *testing.B) {
	const sql = `CREATE TABLE users (
	id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
	name text NOT NULL DEFAULT 'anonymous', -- display name
	created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX users_name_idx ON users (lower(name)) WHERE created_at > '2020-01-01';`
	b.SetBytes(int64(len(sql)))
	b.ReportAllocs()
	for i := 0; i < b.N; i++ {
		s := NewScanner(sql)
		for {
			it, err := s.Next()
			if err != nil || it.Tok == 0 {
				break
			}
		}
	}
}
