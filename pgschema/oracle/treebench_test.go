package oracle

import (
	"testing"
	"unsafe"

	pg "github.com/pganalyze/pg_query_go/v6"
)

// The benchmarks behind ADR 0002: what it costs to build a tree node in the
// protobuf types of pg_query_go and in plain structs of the shape the
// library uses. A ColumnRef "t.c" is three nodes: ColumnRef and two Strings.
//
//	go test -run XXX -bench TreeNodes -benchtime 2s .

type node interface{ node() }

type ownString struct {
	Sval string
	Loc  int32
}

type ownColumnRef struct {
	Fields   []node
	Location int32
}

func (*ownString) node()    {}
func (*ownColumnRef) node() {}

var (
	sinkProto *pg.Node
	sinkOwn   node
)

func BenchmarkTreeNodesProtobuf(b *testing.B) {
	b.ReportAllocs()
	for i := 0; i < b.N; i++ {
		sinkProto = &pg.Node{Node: &pg.Node_ColumnRef{ColumnRef: &pg.ColumnRef{
			Fields: []*pg.Node{
				{Node: &pg.Node_String_{String_: &pg.String{Sval: "t"}}},
				{Node: &pg.Node_String_{String_: &pg.String{Sval: "c"}}},
			},
			Location: 7,
		}}}
	}
}

func BenchmarkTreeNodesOwn(b *testing.B) {
	b.ReportAllocs()
	for i := 0; i < b.N; i++ {
		sinkOwn = &ownColumnRef{Fields: []node{&ownString{Sval: "t"}, &ownString{Sval: "c"}}, Location: 7}
	}
}

func TestTreeNodeSizes(t *testing.T) {
	t.Logf("protobuf: Node=%d ColumnRef=%d String=%d RangeVar=%d bytes; own: ColumnRef=%d String=%d bytes",
		unsafe.Sizeof(pg.Node{}), unsafe.Sizeof(pg.ColumnRef{}), unsafe.Sizeof(pg.String{}), unsafe.Sizeof(pg.RangeVar{}),
		unsafe.Sizeof(ownColumnRef{}), unsafe.Sizeof(ownString{}))
}
