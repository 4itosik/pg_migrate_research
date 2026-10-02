// This file is derived from PostgreSQL (the function quote_identifier of src/backend/utils/adt/ruleutils.c).
//
// Portions Copyright (c) 1996-2024, PostgreSQL Global Development Group
// Portions Copyright (c) 1994, Regents of the University of California
//
// PostgreSQL License: see ../LICENSE.PostgreSQL.

// Package subst puts the name of a schema into migrations that were rewritten
// with a placeholder instead of the schema.
//
// A migration rewritten with the placeholder ("pgschema -placeholder") is a
// template: the placeholder stands wherever the rewriter would put the
// schema, inside string literals and function bodies as well. A service
// replaces the placeholder when it reads the migration, with no parser:
//
//	sql, err := subst.Apply(tmpl, "auth")
//
// The result is exactly what rewriting with the schema itself would give.
//
// The package uses only the standard library.
package subst

import (
	"errors"
	"fmt"
	"strings"
	"unicode"
	"unicode/utf8"
)

// Placeholder is the schema name the rewriter writes in a template. Do not
// use it as a name of your own: every occurrence is replaced.
const Placeholder = "pgschema_placeholder"

// maxIdentLen is NAMEDATALEN-1: PostgreSQL cuts longer identifiers.
const maxIdentLen = 63

// Apply replaces the placeholder in tmpl with the schema name, quoted as an
// identifier when it needs quotes (upper case, a space, a keyword that is not
// unreserved). It returns an error for a schema name that ValidSchema
// rejects.
func Apply(tmpl, schema string) (string, error) {
	if err := ValidSchema(schema); err != nil {
		return "", err
	}
	if !strings.Contains(tmpl, Placeholder) {
		return tmpl, nil
	}
	return strings.ReplaceAll(tmpl, Placeholder, QuoteIdent(schema)), nil
}

// ValidSchema checks that a schema name can be substituted. It rejects a name
// that cannot be put into text safely: empty, longer than 63 bytes, not valid
// UTF-8, with a quote ('), a dollar sign ($), a backslash or a control
// character, with white space at either end, or with /*, */ or --. The
// placeholder stands inside string literals, dollar-quoted bodies and
// comments too, where such text would change the meaning of the SQL. It also
// rejects the names that cannot be the schema of a service: those starting
// with pg_, which PostgreSQL reserves for system schemas (CREATE SCHEMA
// rejects them), and information_schema.
func ValidSchema(schema string) error {
	first, _ := utf8.DecodeRuneInString(schema)
	last, _ := utf8.DecodeLastRuneInString(schema)
	switch {
	case schema == "":
		return errors.New("subst: empty schema name")
	case len(schema) > maxIdentLen:
		return fmt.Errorf("subst: schema name %q is longer than %d bytes", schema, maxIdentLen)
	case !utf8.ValidString(schema):
		return fmt.Errorf("subst: schema name %q is not valid UTF-8", schema)
	case strings.HasPrefix(schema, "pg_"):
		return fmt.Errorf("subst: schema name %q starts with pg_, which PostgreSQL reserves for system schemas", schema)
	case schema == "information_schema":
		return errors.New("subst: information_schema is a system schema")
	case unicode.IsSpace(first) || unicode.IsSpace(last):
		return fmt.Errorf("subst: schema name %q starts or ends with white space", schema)
	case strings.Contains(schema, "/*") || strings.Contains(schema, "*/") || strings.Contains(schema, "--"):
		return fmt.Errorf("subst: schema name %q contains a comment delimiter (/*, */ or --)", schema)
	}
	for i := 0; i < len(schema); i++ {
		if c := schema[i]; c == '\'' || c == '$' || c == '\\' || c < 0x20 || c == 0x7f {
			return fmt.Errorf("subst: schema name %q has a character that is not allowed: %q", schema, c)
		}
	}
	return nil
}

// QuoteIdent quotes an identifier the way PostgreSQL's quote_identifier does:
// it stays bare when it is made of lower-case letters, digits and underscores,
// does not start with a digit and is not a keyword other than an unreserved
// one; otherwise it is put in double quotes, with embedded quotes doubled.
func QuoteIdent(name string) string {
	safe := name != "" && (name[0] >= 'a' && name[0] <= 'z' || name[0] == '_')
	for i := 1; safe && i < len(name); i++ {
		c := name[i]
		safe = c >= 'a' && c <= 'z' || c >= '0' && c <= '9' || c == '_'
	}
	if safe && !quotedKeywords[name] {
		return name
	}
	return `"` + strings.ReplaceAll(name, `"`, `""`) + `"`
}
