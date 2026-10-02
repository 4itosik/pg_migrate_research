package parse

import . "github.com/4itosik/pg_migrate_research/pgschema/internal/ast"

// TEXTOID is the OID of the type text (pg_type.dat); MERGE_ACTION() returns it.
const TEXTOID uint32 = 25

// nodeAt is list_nth for the lists the grammar builds as pairs, such as the
// result of json_behavior_clause_opt: the item i, nil when the list has no such
// item.
func nodeAt(l []Node, i int) Node {
	if i < len(l) {
		return l[i]
	}
	return nil
}
