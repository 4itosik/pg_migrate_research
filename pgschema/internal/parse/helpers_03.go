package parse

// Helpers of the actions of gram/10_rules_03.y: the C macros and enum values
// of parsenodes.h and pg_attribute.h that the actions use, and the test for
// a null file name of COPY.

import (
	"strings"

	. "github.com/4itosik/pg_migrate_research/pgschema/internal/ast"
)

// The bits of TableLikeClause.options, CREATE_TABLE_LIKE_*. The constants of
// package ast with these names are the ordinals of the enum (0, 1, 2, ...),
// not the bit values, so the grammar does not use them.
const (
	createTableLikeComments    = 1 << 0
	createTableLikeCompression = 1 << 1
	createTableLikeConstraints = 1 << 2
	createTableLikeDefaults    = 1 << 3
	createTableLikeGenerated   = 1 << 4
	createTableLikeIdentity    = 1 << 5
	createTableLikeIndexes     = 1 << 6
	createTableLikeStatistics  = 1 << 7
	createTableLikeStorage     = 1 << 8
	createTableLikeAll         = 1<<31 - 1 // PG_INT32_MAX
)

// ATTRIBUTE_IDENTITY_*, the values of generated_when. They are characters,
// and stay so in a semantic value of type ival (int32): the grammar converts
// them to a one-character string with string(rune(v)) where a node field has
// the C type char.
const (
	ATTRIBUTE_IDENTITY_ALWAYS     = 'a'
	ATTRIBUTE_IDENTITY_BY_DEFAULT = 'd'
)

// FKCONSTR_MATCH_*, the values of key_match: characters in an ival, like
// ATTRIBUTE_IDENTITY_*.
const (
	FKCONSTR_MATCH_FULL    = 'f'
	FKCONSTR_MATCH_PARTIAL = 'p'
	FKCONSTR_MATCH_SIMPLE  = 's'
)

// FKCONSTR_ACTION_*, the values of KeyAction.action: a character, which is
// a one-character string in the fields of the ast.
const (
	FKCONSTR_ACTION_NOACTION   = "a"
	FKCONSTR_ACTION_RESTRICT   = "r"
	FKCONSTR_ACTION_CASCADE    = "c"
	FKCONSTR_ACTION_SETNULL    = "n"
	FKCONSTR_ACTION_SETDEFAULT = "d"
)

// copyFileNameIsNull is "filename == NULL" for the result of copy_file_name,
// the file name of COPY: NULL means STDIN or STDOUT. A null char pointer is
// the empty string in a semantic value, so it is not told from an empty
// string constant by the value alone; loc is the position of the
// copy_file_name symbol, where the text starts with the keyword for NULL and
// with a quote for a string.
func (p *parser) copyFileNameIsNull(filename string, loc int32) bool {
	if filename != "" {
		return false
	}
	if loc < 0 || int(loc) >= len(p.src) {
		return true
	}
	rest := p.src[loc:]
	return len(rest) >= 3 && strings.EqualFold(rest[:3], "std")
}

// setRelpersistence is "r->relpersistence = c" for the RangeVar r of a
// qualified_name; c is the character that OptTemp and OptNoLog return in an
// ival. It does nothing for a nil r.
func setRelpersistence(r *RangeVar, c int32) {
	if r != nil {
		r.Relpersistence = string(rune(c))
	}
}
