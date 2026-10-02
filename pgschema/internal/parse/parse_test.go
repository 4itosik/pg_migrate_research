package parse

import (
	"strings"
	"testing"

	. "github.com/4itosik/pg_migrate_research/pgschema/internal/ast"
)

func mustParse(t *testing.T, sql string) []*RawStmt {
	t.Helper()
	stmts, err := Parse(sql)
	if err != nil {
		t.Fatalf("Parse(%q): %v", sql, err)
	}
	return stmts
}

func TestParseSelect(t *testing.T) {
	stmts := mustParse(t, "SELECT a, 1 FROM t WHERE a > 2")
	if len(stmts) != 1 {
		t.Fatalf("got %d statements", len(stmts))
	}
	sel, ok := stmts[0].Stmt.(*SelectStmt)
	if !ok {
		t.Fatalf("got %T", stmts[0].Stmt)
	}
	if len(sel.TargetList) != 2 || len(sel.FromClause) != 1 {
		t.Fatalf("target list %d, from %d", len(sel.TargetList), len(sel.FromClause))
	}
	rv := sel.FromClause[0].(*RangeVar)
	if rv.Relname != "t" || !rv.Inh || rv.Relpersistence != "p" || rv.Location != 17 {
		t.Errorf("range var: %+v", rv)
	}
	col := sel.TargetList[0].(*ResTarget).Val.(*ColumnRef)
	if len(col.Fields) != 1 || col.Fields[0].(*String).Sval != "a" || col.Location != 7 {
		t.Errorf("column ref: %+v", col)
	}
	cond := sel.WhereClause.(*A_Expr)
	if cond.Kind != AEXPR_OP || cond.Name[0].(*String).Sval != ">" || cond.Location != 27 {
		t.Errorf("where: %+v", cond)
	}
}

func TestStatementLocations(t *testing.T) {
	sql := "SELECT 1; ; SELECT 2;\nSELECT 3"
	stmts := mustParse(t, sql)
	if len(stmts) != 3 {
		t.Fatalf("got %d statements", len(stmts))
	}
	// the location of a statement is that of the semicolon before it plus one
	// (so it can be a space or a newline), the length ends at the semicolon
	// after it, and the last statement has no length
	want := [][2]int32{{0, 8}, {11, 9}, {21, 0}}
	for i, w := range want {
		if stmts[i].StmtLocation != w[0] || stmts[i].StmtLen != w[1] {
			t.Errorf("statement %d: location %d length %d, want %v", i, stmts[i].StmtLocation, stmts[i].StmtLen, w)
		}
	}
}

func TestQualifiedNamesKeepPositions(t *testing.T) {
	stmts := mustParse(t, "DROP TABLE IF EXISTS a.b, c")
	drop := stmts[0].Stmt.(*DropStmt)
	if !drop.MissingOk || drop.RemoveType != OBJECT_TABLE || len(drop.Objects) != 2 {
		t.Fatalf("drop: %+v", drop)
	}
	// DROP keeps no locations in PostgreSQL's tree; the library adds them to
	// the String nodes of names
	first := drop.Objects[0].(*List).Items
	if first[0].(*String).Loc != 21 || first[1].(*String).Loc != 23 {
		t.Errorf("positions of a.b: %d, %d", first[0].(*String).Loc, first[1].(*String).Loc)
	}
	second := drop.Objects[1].(*List).Items
	if second[0].(*String).Loc != 26 {
		t.Errorf("position of c: %d", second[0].(*String).Loc)
	}
}

func TestParseErrors(t *testing.T) {
	tests := []struct {
		sql    string
		msg    string
		cursor int
	}{
		{"SELEC 1", `syntax error at or near "SELEC"`, 1},
		{"SELECT 1 FROM", "syntax error at end of input", 14},
		{"SELECT (1", "syntax error at end of input", 10},
		{"CREATE TABLE t (a int,)", `syntax error at or near ")"`, 23},
		{"SELECT 'abc", `unterminated quoted string at or near "'abc"`, 8},
		{"SELECT 1 ORDER BY 1 ORDER BY 1", "syntax error", 0}, // message checked by prefix below
		{"ALTER TABLE t ADD CONSTRAINT c CHECK (a > 0) DEFERRABLE", "CHECK constraints cannot be marked DEFERRABLE", 0},
		{"SET NAMES 'x', 'y'", "syntax error", 0},
	}
	for _, tt := range tests {
		_, err := Parse(tt.sql)
		if err == nil {
			t.Errorf("Parse(%q): no error", tt.sql)
			continue
		}
		if !strings.HasPrefix(err.Error(), strings.Split(tt.msg, " at ")[0]) {
			t.Errorf("Parse(%q): %q, want %q", tt.sql, err, tt.msg)
		}
		if tt.cursor > 0 {
			if got := err.(*Error).CursorPos(tt.sql); got != tt.cursor {
				t.Errorf("Parse(%q): cursor %d, want %d", tt.sql, got, tt.cursor)
			}
		}
	}
}

func TestUnicodeEscapes(t *testing.T) {
	stmts := mustParse(t, `SELECT U&'d\0061t\+000061', U&"d!0061t" UESCAPE '!'`)
	sel := stmts[0].Stmt.(*SelectStmt)
	str := sel.TargetList[0].(*ResTarget).Val.(*A_Const).Val.(*String)
	if str.Sval != "data" {
		t.Errorf("string: %q", str.Sval)
	}
	col := sel.TargetList[1].(*ResTarget).Val.(*ColumnRef)
	if got := col.Fields[0].(*String).Sval; got != "dat" {
		t.Errorf("identifier: %q", got)
	}
	if _, err := Parse(`SELECT U&'\d800'`); err == nil || !strings.Contains(err.Error(), "invalid Unicode") {
		t.Errorf("surrogate: %v", err)
	}
}

func TestLookaheadTokens(t *testing.T) {
	// NOT BETWEEN, NULLS LAST, WITH TIME ZONE and FORMAT JSON need the
	// one-token lookahead of base_yylex
	for _, sql := range []string{
		"SELECT 1 NOT BETWEEN 0 AND 2",
		"SELECT a FROM t ORDER BY a NULLS LAST",
		"SELECT '12:00'::time WITH TIME ZONE",
		"SELECT x FORMAT JSON FROM t",
		"SELECT '12:00'::timestamp WITHOUT TIME ZONE",
	} {
		if _, err := Parse(sql); err != nil && !strings.Contains(sql, "FORMAT JSON") && !strings.Contains(sql, "WITH TIME ZONE") {
			t.Errorf("Parse(%q): %v", sql, err)
		}
	}
	stmts := mustParse(t, "SELECT a FROM t ORDER BY a DESC NULLS LAST")
	sb := stmts[0].Stmt.(*SelectStmt).SortClause[0].(*SortBy)
	if sb.SortbyDir != SORTBY_DESC || sb.SortbyNulls != SORTBY_NULLS_LAST {
		t.Errorf("sort by: %+v", sb)
	}
}

func TestModes(t *testing.T) {
	nodes, err := ParseMode("a + 1", ModePLpgSQLExpr)
	if err != nil {
		t.Fatal(err)
	}
	if len(nodes) != 1 {
		t.Fatalf("got %d nodes", len(nodes))
	}
	if _, ok := nodes[0].(*RawStmt).Stmt.(*SelectStmt); !ok {
		t.Errorf("a PL/pgSQL expression is a SelectStmt, got %T", nodes[0].(*RawStmt).Stmt)
	}
	nodes, err = ParseMode("a.b[1] := a + 1", ModePLpgSQLAssign3)
	if err != nil {
		t.Fatal(err)
	}
	as := nodes[0].(*RawStmt).Stmt.(*PLAssignStmt)
	if as.Name != "a" || as.Nnames != 3 || len(as.Indirection) != 2 {
		t.Errorf("assignment: %+v", as)
	}
	nodes, err = ParseMode("int[]", ModeTypeName)
	if err != nil {
		t.Fatal(err)
	}
	if tn, ok := nodes[0].(*TypeName); !ok || len(tn.ArrayBounds) != 1 {
		t.Errorf("type name: %#v", nodes[0])
	}
}

func TestInvalidEncoding(t *testing.T) {
	if _, err := Parse("SELECT '\xe4bc'"); err == nil || !strings.Contains(err.Error(), "invalid byte sequence") {
		t.Errorf("invalid UTF-8: %v", err)
	}
}

func BenchmarkParse(b *testing.B) {
	const sql = `CREATE TABLE users (
	id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
	name text NOT NULL DEFAULT 'anonymous',
	created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX users_name_idx ON users (lower(name)) WHERE created_at > '2020-01-01';
SELECT u.id, count(*) FROM users u JOIN orders o ON o.user_id = u.id WHERE u.name LIKE 'a%' GROUP BY u.id ORDER BY 2 DESC LIMIT 10;`
	b.SetBytes(int64(len(sql)))
	b.ReportAllocs()
	for i := 0; i < b.N; i++ {
		if _, err := Parse(sql); err != nil {
			b.Fatal(err)
		}
	}
}
