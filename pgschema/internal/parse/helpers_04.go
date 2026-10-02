// This file is derived from PostgreSQL (src/backend/parser/gram.y).
//
// Portions Copyright (c) 1996-2024, PostgreSQL Global Development Group
// Portions Copyright (c) 1994, Regents of the University of California
//
// PostgreSQL License: see ../../LICENSE.PostgreSQL.

package parse

// Constants of PostgreSQL headers used by the actions of gram/10_rules_04.y
// (triggers, access methods, operator classes). Names follow the C macros.
// The char constants are one-character strings, as the char fields of ast.

// Bits of pg_trigger.tgtype (catalog/pg_trigger.h), as TriggerEvents and
// TriggerActionTime build them.
const (
	triggerTypeRow      = 1 << 0
	triggerTypeBefore   = 1 << 1
	triggerTypeInsert   = 1 << 2
	triggerTypeDelete   = 1 << 3
	triggerTypeUpdate   = 1 << 4
	triggerTypeTruncate = 1 << 5
	triggerTypeInstead  = 1 << 6
	triggerTypeAfter    = 0
)

// Values of pg_trigger.tgenabled (commands/trigger.h).
const (
	triggerFiresOnOrigin  = "O"
	triggerFiresAlways    = "A"
	triggerFiresOnReplica = "R"
	triggerDisabled       = "D"
)

// Values of pg_am.amtype (catalog/pg_am.h).
const (
	amtypeIndex = "i"
	amtypeTable = "t"
)

// Values of CreateOpClassItem.itemtype (nodes/parsenodes.h).
const (
	opclassItemOperator    = 1
	opclassItemFunction    = 2
	opclassItemStoragetype = 3
)
