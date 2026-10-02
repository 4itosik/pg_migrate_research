package parse

import . "github.com/4itosik/pg_migrate_research/pgschema/internal/ast"

// The private structs of gram.y for the results of some productions. They
// are stored in the Node field of a semantic value, so they are Nodes that
// have no children.

// privTarget is PrivTarget, the result of privilege_target.
type privTarget struct {
	targtype GrantTargetType
	objtype  ObjectType
	objs     []Node
}

// importQual is ImportQual, the result of import_qualification.
type importQual struct {
	typ        ImportForeignSchemaType
	tableNames []Node
}

// selectLimit is SelectLimit, the result of opt_select_limit.
type selectLimit struct {
	limitOffset Node
	limitCount  Node
	limitOption LimitOption
}

// groupClause is GroupClause, the result of group_clause.
type groupClause struct {
	distinct bool
	list     []Node
}

// keyAction is KeyAction, the result of key_action.
type keyAction struct {
	action string // one character
	cols   []Node
}

// keyActions is KeyActions, the result of key_actions.
type keyActions struct {
	updateAction *keyAction
	deleteAction *keyAction
}

func (*privTarget) Children(func(Node))  {}
func (*importQual) Children(func(Node))  {}
func (*selectLimit) Children(func(Node)) {}
func (*groupClause) Children(func(Node)) {}
func (*keyAction) Children(func(Node))   {}
func (*keyActions) Children(func(Node))  {}

// The bits of the result of ConstraintAttributeSpec.
const (
	casNotDeferrable      = 0x01
	casDeferrable         = 0x02
	casInitiallyImmediate = 0x04
	casInitiallyDeferred  = 0x08
	casNotValid           = 0x10
	casNoInherit          = 0x20
)

// Constants of utils/datetime.h and utils/timestamp.h that the grammar uses
// for the fields and the ranges of INTERVAL.
const (
	dtMonth  = 1
	dtYear   = 2
	dtDay    = 3
	dtHour   = 10
	dtMinute = 11
	dtSecond = 12

	intervalFullRange     = 0x7FFF
	intervalFullPrecision = 0xFFFF
)

// intervalMask is INTERVAL_MASK.
func intervalMask(b int32) int32 { return 1 << b }

// The FRAMEOPTION_* bits of nodes/parsenodes.h, the frame options of a window
// definition.
const (
	frameoptionNondefault              = 0x00001
	frameoptionRange                   = 0x00002
	frameoptionRows                    = 0x00004
	frameoptionGroups                  = 0x00008
	frameoptionBetween                 = 0x00010
	frameoptionStartUnboundedPreceding = 0x00020
	frameoptionEndUnboundedPreceding   = 0x00040
	frameoptionStartUnboundedFollowing = 0x00080
	frameoptionEndUnboundedFollowing   = 0x00100
	frameoptionStartCurrentRow         = 0x00200
	frameoptionEndCurrentRow           = 0x00400
	frameoptionStartOffsetPreceding    = 0x00800
	frameoptionEndOffsetPreceding      = 0x01000
	frameoptionStartOffsetFollowing    = 0x02000
	frameoptionEndOffsetFollowing      = 0x04000
	frameoptionExcludeCurrentRow       = 0x08000
	frameoptionExcludeGroup            = 0x10000
	frameoptionExcludeTies             = 0x20000

	frameoptionDefaults = frameoptionRange | frameoptionStartUnboundedPreceding | frameoptionEndCurrentRow
)

// XmlStandaloneType of utils/xml.h.
const (
	xmlStandaloneYes = iota
	xmlStandaloneNo
	xmlStandaloneNoValue
	xmlStandaloneOmitted
)
