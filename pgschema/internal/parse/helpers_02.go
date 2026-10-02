// This file is derived from PostgreSQL (src/backend/parser/gram.y).
//
// Portions Copyright (c) 1996-2024, PostgreSQL Global Development Group
// Portions Copyright (c) 1994, Regents of the University of California
//
// PostgreSQL License: see ../../LICENSE.PostgreSQL.

package parse

// Helpers of the actions of gram/10_rules_02.y (ALTER TABLE, ALTER TYPE).

import (
	. "github.com/4itosik/pg_migrate_research/pgschema/internal/ast"
)

// defGetInt32 extracts an int32 value from a DefElem, as defGetInt32 of
// src/backend/commands/define.c does. The errors carry no position, as in C.
func (p *parser) defGetInt32(def *DefElem) int32 {
	if def.Arg == nil {
		p.fail(-1, def.Defname+" requires an integer value")
	}
	i, ok := def.Arg.(*Integer)
	if !ok {
		p.fail(-1, def.Defname+" requires an integer value")
	}
	return i.Ival
}
