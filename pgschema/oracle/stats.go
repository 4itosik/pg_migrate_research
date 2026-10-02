package oracle

import (
	pg "github.com/pganalyze/pg_query_go/v6"
	"google.golang.org/protobuf/reflect/protoreflect"
)

// CountNodes returns the number of parse tree nodes in tree, RawStmt
// included: every message below the result except the Node wrappers.
func CountNodes(tree *pg.ParseResult) int {
	n := 0
	for _, s := range tree.Stmts {
		n += countNodes(s.ProtoReflect())
	}
	return n
}

func countNodes(m protoreflect.Message) int {
	n := 0
	if m.Descriptor().FullName() != "pg_query.Node" {
		n = 1
	}
	m.Range(func(fd protoreflect.FieldDescriptor, v protoreflect.Value) bool {
		switch {
		case fd.IsList() && fd.Message() != nil:
			l := v.List()
			for i := 0; i < l.Len(); i++ {
				n += countNodes(l.Get(i).Message())
			}
		case fd.Message() != nil && !fd.IsMap():
			n += countNodes(v.Message())
		}
		return true
	})
	return n
}
