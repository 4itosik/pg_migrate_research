package pgschema

import (
	"slices"
	"testing"

	"github.com/4itosik/pg_migrate_research/pgschema/internal/ast"
	"github.com/4itosik/pg_migrate_research/pgschema/internal/parse"
)

// The generated lists are sorted (they are searched) and hold what the rules
// rely on: the type keywords that the grammar maps to pg_catalog, the array
// types, the functions, aggregates and procedures.
func TestBuiltinNames(t *testing.T) {
	if !slices.IsSorted(builtinTypes) || !slices.IsSorted(builtinFunctions) {
		t.Fatal("the lists are not sorted")
	}
	for _, kw := range []string{"int", "integer", "smallint", "bigint", "real", "float", "decimal", "dec", "numeric",
		"boolean", "bit", "character", "char", "varchar", "nchar", "timestamp", "time", "interval", "json"} {
		if !isBuiltinType(kw) {
			t.Errorf("type keyword %s is missing", kw)
		}
		// the grammar gives the keyword the schema pg_catalog
		stmts, err := parse.Parse("CREATE TABLE t (c " + kw + ")")
		if err != nil {
			t.Fatal(err)
		}
		col := stmts[0].Stmt.(*ast.CreateStmt).TableElts[0].(*ast.ColumnDef)
		if names := strs(col.TypeName.Names); len(names) != 2 || names[0] != "pg_catalog" {
			t.Errorf("%s: %v", kw, names)
		}
	}
	for _, n := range []string{"text", "money", "_int4", "record", "trigger", "jsonb", "int4multirange"} {
		if !isBuiltinType(n) {
			t.Errorf("type %s is missing", n)
		}
	}
	for _, n := range []string{"round", "lower", "count", "string_agg", "gen_random_uuid", "now"} {
		if !isBuiltinFunction(n) {
			t.Errorf("function %s is missing", n)
		}
	}
	for _, n := range []string{"mood", "users", "digest"} {
		if isBuiltinType(n) || isBuiltinFunction(n) {
			t.Errorf("%s is not a built-in", n)
		}
	}
}
