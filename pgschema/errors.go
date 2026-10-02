package pgschema

import (
	"errors"
	"fmt"
	"strings"
	"unicode/utf8"

	"github.com/4itosik/pg_migrate_research/pgschema/internal/parse"
)

// SyntaxError is the error for SQL that does not parse: the text of a
// migration, or a function body or DO block in it. Line and Column are
// 1-based and point into the text passed to Learn or Rewrite where PostgreSQL
// would put its error cursor (the column counts characters); both are 0 for
// an error without a position. Msg is the message, with the function or DO
// block for an error in a body.
type SyntaxError struct {
	Line, Column int
	Msg          string
}

func (e *SyntaxError) Error() string {
	if e.Line == 0 {
		return e.Msg
	}
	return fmt.Sprintf("line %d, column %d: %s", e.Line, e.Column, e.Msg)
}

// ErrNotVerified is wrapped by the errors of the verification: the rewritten
// SQL does not parse again, or its tree is not the tree of the input with the
// intended names qualified. Such an error is a defect of the library, not of
// the SQL.
var ErrNotVerified = errors.New("verification")

// posError is a syntax error while a text is analyzed: off is the byte offset
// in that text, -1 for none. A text inside another one (a function body, a
// fragment of PL/pgSQL) moves the offset into the enclosing text, so that the
// caller gets a SyntaxError for the text it passed.
type posError struct {
	off int
	msg string
}

func (e *posError) Error() string { return e.msg }

// syntaxError turns an error of the parser into a posError; other errors are
// returned as they are.
func syntaxError(err error) error {
	if pe, ok := err.(*parse.Error); ok {
		return &posError{off: pe.Loc, msg: pe.Msg}
	}
	return err
}

// shifted moves a posError by delta bytes and puts prefix in front of its
// message; other errors get the prefix only. An offset that falls before the
// start of the text (in a SELECT put in front of a fragment) is the start.
func shifted(err error, delta int, prefix string) error {
	if pe, ok := err.(*posError); ok {
		off := pe.off
		if off >= 0 {
			off = max(off+delta, 0)
		}
		return &posError{off: off, msg: prefix + pe.msg}
	}
	if prefix == "" {
		return err
	}
	return fmt.Errorf("%s%w", prefix, err)
}

// located turns a posError of the text src into a SyntaxError.
func located(src string, err error) error {
	pe, ok := err.(*posError)
	if !ok {
		return err
	}
	if pe.off < 0 {
		return &SyntaxError{Msg: pe.msg}
	}
	line, col := position(src, pe.off)
	return &SyntaxError{Line: line, Column: col, Msg: pe.msg}
}

// position returns the 1-based line and column (in characters) of byte offset
// off of src.
func position(src string, off int) (line, col int) {
	off = min(off, len(src))
	start := strings.LastIndexByte(src[:off], '\n') + 1
	return strings.Count(src[:start], "\n") + 1, utf8.RuneCountInString(src[start:off]) + 1
}
