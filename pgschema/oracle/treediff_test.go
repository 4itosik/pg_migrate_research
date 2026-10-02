package oracle

import (
	"testing"

	"github.com/4itosik/pg_migrate_research/pgschema/internal/ast"
)

// the tree of SELECT a FROM t, built by hand
func selectAFromT(location int32) []*ast.RawStmt {
	return []*ast.RawStmt{{
		Stmt: &ast.SelectStmt{
			TargetList: []ast.Node{&ast.ResTarget{
				Val:      &ast.ColumnRef{Fields: []ast.Node{&ast.String{Sval: "a", Loc: 7}}, Location: location},
				Location: 7,
			}},
			FromClause:  []ast.Node{&ast.RangeVar{Relname: "t", Inh: true, Relpersistence: "p", Location: 14}},
			LimitOption: ast.LIMIT_OPTION_DEFAULT,
			Op:          ast.SETOP_NONE,
		},
		StmtLen: 0,
	}}
}

func TestDiffStatements(t *testing.T) {
	want, err := Parse("SELECT a FROM t")
	if err != nil {
		t.Fatal(err)
	}
	if d := DiffStatements(selectAFromT(7), want); d != nil {
		t.Fatalf("equal trees differ: %v", d)
	}
	d := DiffStatements(selectAFromT(8), want)
	if d == nil {
		t.Fatal("a wrong location was not found")
	}
	t.Log(d)
	if d.Ours != "8" || d.Theirs != "7" || d.PathNodes() != "SelectStmt/ResTarget/ColumnRef" {
		t.Errorf("unexpected difference: %v (%s)", d, d.PathNodes())
	}
}
