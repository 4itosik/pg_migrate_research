%{
// Code derived from PostgreSQL's src/backend/parser/gram.y (REL_17_STABLE).
//
// Portions Copyright (c) 1996-2024, PostgreSQL Global Development Group
// Portions Copyright (c) 1994, Regents of the University of California
//
// PostgreSQL License: see ../../LICENSE.PostgreSQL.

package parse

import (
	"fmt"
	"strings"

	. "github.com/4itosik/pg_migrate_research/pgschema/internal/ast"
)

// fmt and strings are for the actions
var (
	_ = fmt.Sprintf
	_ = strings.EqualFold
)
%}

// The semantic value. node holds every node pointer of gram.y's %union
// whatever its type; use as[*T]($N) where the C code reads a field of $N.
// loc is the start of the symbol, what bison calls @N.
%union {
	loc     int32
	ival    int32
	boolean bool
	str     string
	node    Node
	list    []Node
}

%start parse_toplevel
