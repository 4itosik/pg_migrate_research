package plpgsql

import (
	"fmt"
	"strings"
	"testing"

	"github.com/4itosik/pg_migrate_research/pgschema/internal/lex"
	"github.com/4itosik/pg_migrate_research/pgschema/internal/parse"
)

var modeNames = map[Mode]string{
	parse.ModeDefault:        "stmt",
	parse.ModePLpgSQLExpr:    "expr",
	parse.ModePLpgSQLAssign1: "assign1",
	parse.ModePLpgSQLAssign2: "assign2",
	parse.ModePLpgSQLAssign3: "assign3",
}

// dumpFragments describes the fragments one per line: line, mode, kind and
// the text as handed to the SQL parser.
func dumpFragments(b *Body) []string {
	var out []string
	for _, f := range b.Fragments {
		out = append(out, fmt.Sprintf("%d %s %s %q", f.Line, modeNames[f.Mode], f.Kind, f.SQL(b.Text)))
	}
	return out
}

func mustParse(t *testing.T, body string, opts *Options) *Body {
	t.Helper()
	b, err := Parse(body, opts)
	if err != nil {
		t.Fatalf("Parse: %v\n%s", err, body)
	}
	return b
}

func checkLines(t *testing.T, got, want []string) {
	t.Helper()
	if strings.Join(got, "\n") != strings.Join(want, "\n") {
		t.Errorf("got:\n  %s\nwant:\n  %s", strings.Join(got, "\n  "), strings.Join(want, "\n  "))
	}
}

func TestFragments(t *testing.T) {
	tests := []struct {
		name string
		body string
		opts *Options
		want []string
	}{
		{"assignments", `
<<blk>>
DECLARE
  v int;
  r record;
BEGIN
  v := 1;
  v = 2;
  r.f := 3;
  r.f.g := 4;
  v[1] := 5;
  r.f[1].g := 6;
  blk.v := 7;
  blk.r.f := 8;
  blk.r.f = 9;
  fn.p := 10;
  fn.p.f := 11;
END`, &Options{Name: "fn"}, []string{
			`7 assign1 assign "v := 1"`,
			`8 assign1 assign "v = 2"`,
			`9 assign2 assign "r.f := 3"`,
			`10 assign2 assign "r.f.g := 4"`,
			`11 assign1 assign "v[1] := 5"`,
			`12 assign2 assign "r.f[1].g := 6"`,
			`13 assign2 assign "blk.v := 7"`,
			`14 assign3 assign "blk.r.f := 8"`,
			`15 assign3 assign "blk.r.f = 9"`,
			`16 assign2 assign "fn.p := 10"`,
			`17 assign3 assign "fn.p.f := 11"`,
		}},
		{"sql and into", `
DECLARE x int; y text; r record;
BEGIN
  SELECT 1;
  SELECT a INTO x FROM t WHERE b = 1;
  SELECT a, b INTO STRICT x, y FROM t;
  SELECT 1 INTO x;
  SELECT 2 INTO x  /* c */ ;
  INSERT INTO t VALUES (1) RETURNING a INTO x;
  INSERT INTO t VALUES (1);
  MERGE INTO t USING s ON t.a = s.a WHEN MATCHED THEN DELETE;
  WITH q AS (SELECT 1) SELECT * INTO r FROM q;
  IMPORT FOREIGN SCHEMA s FROM SERVER v INTO l;
  EXPLAIN SELECT 1;
  UPDATE t SET a = 1, b = 2;
  SET x.y = 'z';
END`, nil, []string{
			`4 stmt sql "SELECT 1"`,
			`5 stmt sql "SELECT a        FROM t WHERE b = 1"`,
			`6 stmt sql "SELECT a, b                  FROM t"`,
			`7 stmt sql "SELECT 1"`,
			`8 stmt sql "SELECT 2"`,
			`9 stmt sql "INSERT INTO t VALUES (1) RETURNING a"`,
			`10 stmt sql "INSERT INTO t VALUES (1)"`,
			`11 stmt sql "MERGE INTO t USING s ON t.a = s.a WHEN MATCHED THEN DELETE"`,
			`12 stmt sql "WITH q AS (SELECT 1) SELECT *        FROM q"`,
			`13 stmt sql "IMPORT FOREIGN SCHEMA s FROM SERVER v INTO l"`,
			`14 stmt sql "EXPLAIN SELECT 1"`,
			`15 stmt sql "UPDATE t SET a = 1, b = 2"`,
			`16 stmt sql "SET x.y = 'z'"`,
		}},
		{"perform call do", `
BEGIN
  PERFORM 1;
  perform(f(2));
  PERFORM a FROM t;
  CALL p(1, 2);
  DO $$ BEGIN NULL; END $$;
END`, nil, []string{
			`3 stmt perform "SELECT  1"`,
			`4 stmt perform "SELECT (f(2))"`,
			`5 stmt perform "SELECT  a FROM t"`,
			`6 stmt sql "CALL p(1, 2)"`,
			`7 stmt sql "DO $$ BEGIN NULL; END $$"`,
		}},
		{"if case while", `
BEGIN
  IF a > 1 THEN NULL;
  ELSIF b THEN NULL;
  ELSE NULL;
  END IF;
  CASE x WHEN 1, 2 THEN NULL; WHEN 3 THEN NULL; ELSE NULL; END CASE;
  CASE WHEN a THEN NULL; WHEN b THEN NULL; END CASE;
  WHILE n < 3 LOOP n := n + 1; END LOOP;
END`, nil, []string{
			`3 expr expr "a > 1"`,
			`4 expr expr "b"`,
			`7 expr expr "x"`,
			`7 expr case-when "1, 2"`,
			`7 expr case-when "3"`,
			`8 expr expr "a"`,
			`8 expr expr "b"`,
			`9 expr expr "n < 3"`,
			`9 assign1 assign "n := n + 1"`,
		}},
		{"elseif", `
BEGIN
  IF a THEN NULL;
  ELSEIF b THEN NULL;
  ELSIF c THEN NULL;
  END IF;
END`, nil, []string{
			`3 expr expr "a"`,
			`4 expr expr "b"`,
			`5 expr expr "c"`,
		}},
		{"for loops", `
DECLARE
  c1 CURSOR FOR SELECT 1;
  c2 CURSOR (p int, q int) FOR SELECT p, q;
BEGIN
  FOR i IN 1..10 LOOP NULL; END LOOP;
  FOR i IN REVERSE a..b BY 2 LOOP NULL; END LOOP;
  FOR r IN SELECT * FROM t WHERE a > 1 LOOP NULL; END LOOP;
  FOR r IN VALUES (1) LOOP NULL; END LOOP;
  FOR a, b IN SELECT 1, 2 LOOP NULL; END LOOP;
  FOR r IN EXECUTE 'select 1' USING x, y LOOP NULL; END LOOP;
  FOR r IN c1 LOOP NULL; END LOOP;
  FOR r IN c2(1, q := 2) LOOP NULL; END LOOP;
  FOREACH x SLICE 1 IN ARRAY arr LOOP NULL; END LOOP;
END`, nil, []string{
			`3 stmt sql "SELECT 1"`,
			`4 stmt sql "SELECT p, q"`,
			`6 expr expr "1"`,
			`6 expr expr "10"`,
			`7 expr expr "a"`,
			`7 expr expr "b"`,
			`7 expr expr "2"`,
			`8 stmt sql "SELECT * FROM t WHERE a > 1"`,
			`9 stmt sql "VALUES (1)"`,
			`10 stmt sql "SELECT 1, 2"`,
			`11 expr command "'select 1'"`,
			`11 expr expr "x"`,
			`11 expr expr "y"`,
			`13 expr cursor-arg "1"`,
			`13 expr cursor-arg "2"`,
			`14 expr expr "arr"`,
		}},
		{"cursors", `
DECLARE
  c1 CURSOR FOR SELECT 1;
  c2 CURSOR (p int, q int) FOR SELECT p, q;
  rc refcursor;
BEGIN
  OPEN c1;
  OPEN c2(1, q := x + 1);
  OPEN rc FOR SELECT * FROM t;
  OPEN rc NO SCROLL FOR EXECUTE 'select ' || a USING b;
  FETCH c1 INTO r;
  FETCH ABSOLUTE n + 1 FROM c1 INTO r;
  FETCH FORWARD 2 FROM c1 INTO r;
  MOVE n FROM c1;
  MOVE c1;
  CLOSE c1;
END`, nil, []string{
			`3 stmt sql "SELECT 1"`,
			`4 stmt sql "SELECT p, q"`,
			`8 expr cursor-arg "1"`,
			`8 expr cursor-arg "x + 1"`,
			`9 stmt sql "SELECT * FROM t"`,
			`10 expr command "'select ' || a"`,
			`10 expr expr "b"`,
			`12 expr expr "n + 1"`,
			`13 expr expr "2"`,
			`14 expr expr "n"`,
		}},
		{"raise assert diagnostics return", `
BEGIN
  RAISE NOTICE 'a % %', x, y + 1;
  RAISE EXCEPTION 'e' USING ERRCODE = 'P0001', DETAIL = d;
  RAISE division_by_zero;
  RAISE SQLSTATE '22012' USING MESSAGE = m;
  RAISE;
  ASSERT a > 0, 'msg' || b;
  GET DIAGNOSTICS n = ROW_COUNT, c = PG_CONTEXT;
  RETURN NEXT a;
  RETURN QUERY SELECT 1;
  RETURN QUERY EXECUTE 'select 1' USING a;
  EXIT WHEN a > 1;
  CONTINUE l WHEN b;
  RETURN a + 1;
END`, nil, []string{
			`3 expr expr "x"`,
			`3 expr expr "y + 1"`,
			`4 expr expr "'P0001'"`,
			`4 expr expr "d"`,
			`6 expr expr "m"`,
			`8 expr expr "a > 0"`,
			`8 expr expr "'msg' || b"`,
			`10 expr expr "a"`,
			`11 stmt sql "SELECT 1"`,
			`12 expr command "'select 1'"`,
			`12 expr expr "a"`,
			`13 expr expr "a > 1"`,
			`14 expr expr "b"`,
			`15 expr expr "a + 1"`,
		}},
		{"execute", `
BEGIN
  EXECUTE 'select 1';
  EXECUTE format('select %I', t) INTO x USING a, b;
  EXECUTE 'select $1' USING a INTO STRICT y;
END`, nil, []string{
			`3 expr command "'select 1'"`,
			`4 expr command "format('select %I', t)"`,
			`4 expr expr "a"`,
			`4 expr expr "b"`,
			`5 expr command "'select $1'"`,
			`5 expr expr "a"`,
		}},
		{"declarations", `
DECLARE
  a int := 1;
  b CONSTANT text NOT NULL DEFAULT 'x';
  c numeric(10, 2) = 5;
  h CURSOR (p int, q s.mytype) FOR SELECT p;
BEGIN
  NULL;
END`, nil, []string{
			`3 expr expr "1"`,
			`4 expr expr "'x'"`,
			`5 expr expr "5"`,
			`6 stmt sql "SELECT p"`,
		}},
		{"names that are keywords", `
DECLARE
  log int; error text; type int; "end" int;
BEGIN
  log := 1;
  error = 'e';
  type := 3;
  "end" := 4;
  select 1 into type;
END`, nil, []string{
			`5 assign1 assign "log := 1"`,
			`6 assign1 assign "error = 'e'"`,
			`7 assign1 assign "type := 3"`,
			`8 assign1 assign "\"end\" := 4"`,
			`9 stmt sql "select 1"`,
		}},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			checkLines(t, dumpFragments(mustParse(t, tt.body, tt.opts)), tt.want)
		})
	}
}

// shape renders statements with their nesting: kind@line, the label, the
// loop variables and the cursor, then the children.
func shape(ss []*Stmt) string {
	var out []string
	for _, s := range ss {
		o := fmt.Sprintf("%s@%d", s.Kind, s.Line)
		if s.Label != "" {
			o += ":" + s.Label
		}
		if len(s.Vars) > 0 {
			o += "(" + strings.Join(s.Vars, ",") + ")"
		}
		if s.Cursor != "" {
			o += "<" + s.Cursor + ">"
		}
		switch {
		case s.Block != nil:
			o += shapeBlock(s.Block)
		case len(s.Body) > 0:
			o += "{" + shape(s.Body) + "}"
		case len(s.Branches) > 0:
			var br []string
			for _, b := range s.Branches {
				c := "else"
				if b.Cond != nil {
					c = "cond"
				}
				br = append(br, fmt.Sprintf("%s@%d{%s}", c, b.Line, shape(b.Stmts)))
			}
			o += "[" + strings.Join(br, " ") + "]"
		}
		out = append(out, o)
	}
	return strings.Join(out, " ")
}

func shapeBlock(b *Block) string {
	o := "{" + shape(b.Stmts)
	for _, h := range b.Handlers {
		o += fmt.Sprintf(" when@%d%v{%s}", h.Line, h.Conditions, shape(h.Stmts))
	}
	return o + "}"
}

func TestStatements(t *testing.T) {
	body := `
<<outer>>
DECLARE
  x int;
BEGIN
  x := 1;
  IF x > 1 THEN
    x := 2;
  ELSIF x < 0 THEN
    NULL;
  ELSE
    RETURN;
  END IF;
  CASE x WHEN 1 THEN x := 1; ELSE x := 2; END CASE;
  <<l1>>
  LOOP
    EXIT l1 WHEN x > 3;
    FOR i IN 1..3 LOOP CONTINUE; END LOOP;
  END LOOP l1;
  BEGIN
    NULL;
    PERFORM 1;
  EXCEPTION
    WHEN division_by_zero OR SQLSTATE '23505' THEN
      RAISE NOTICE 'x';
    WHEN OTHERS THEN
      NULL;
  END;
  <<b2>>
  DECLARE y int;
  BEGIN
    y := 1;
  END b2;
  OPEN c;
  FETCH c INTO x;
  MOVE c;
  CLOSE c;
  FOREACH x IN ARRAY a LOOP NULL; END LOOP;
  WHILE x < 3 LOOP x := x + 1; END LOOP;
  FOR r IN c2(1) LOOP NULL; END LOOP;
  COMMIT;
  ROLLBACK AND CHAIN;
EXCEPTION
  WHEN OTHERS THEN RETURN;
END outer`
	b := mustParse(t, body, nil)
	want := "{assign@6 if@7[cond@7{assign@8} cond@9{} else@11{return@12}] case@14[cond@14{assign@14} else@14{assign@14}] " +
		"loop@16:l1{exit@17:l1 fori@18(i){exit@18}} block@20{perform@22 when@24[division_by_zero 23505]{raise@25} when@26[others]{}} " +
		"block@31:b2{assign@32} open@34<c> fetch@35<c> fetch@36<c> close@37<c> foreach_a@38(x) while@39{assign@39} " +
		"forc@40(r)<c2> commit@41 rollback@42 when@44[others]{return@44}}"
	if got := shapeBlock(b.Root); got != want {
		t.Errorf("got:\n  %s\nwant:\n  %s", got, want)
	}
	r := b.Root
	if r.Label != "outer" || r.Line != 5 || r.Start != 1 || r.End != len(body) {
		t.Errorf("root: label %q line %d range %d..%d of %d", r.Label, r.Line, r.Start, r.End, len(body))
	}
	if len(r.Decls) != 1 || r.Decls[0].Name != "x" {
		t.Errorf("root declarations: %+v", r.Decls)
	}
	if m := r.Stmts[len(r.Stmts)-7]; !m.Move || m.Kind != StmtFetch {
		t.Errorf("MOVE: %+v", m)
	}
	// the range of a statement runs from its first token to its semicolon
	for _, s := range r.Stmts[:3] {
		if got := body[s.Start:s.End]; !strings.HasSuffix(got, ";") {
			t.Errorf("%s: %q", s.Kind, got)
		}
	}
	if got := body[r.Stmts[3].Start:r.Stmts[3].End]; !strings.HasPrefix(got, "<<l1>>") || !strings.HasSuffix(got, "END LOOP l1;") {
		t.Errorf("labelled loop: %q", got)
	}
}

// typeDesc describes a type: its kind, its text and the parts of its name.
// text is the text the offsets of the type refer to.
func typeDesc(text string, d *Decl) string {
	if d.Type == nil {
		return "-"
	}
	var names []string
	for _, n := range d.Type.Names {
		if got := text[n.Start:n.End]; got != n.Text && got != `"`+n.Text+`"` {
			names = append(names, "?"+got)
		}
		names = append(names, n.Text)
	}
	return fmt.Sprintf("%s %q %v", d.Type.Kind, text[d.Type.Start:d.Type.End], names)
}

func TestDeclarations(t *testing.T) {
	body := `
DECLARE
  a int := 1;
  b CONSTANT text NOT NULL DEFAULT 'x';
  c numeric(10, 2) = 5;
  d t.col%TYPE;
  e s.t%ROWTYPE;
  f record;
  g ALIAS FOR $1;
  h CURSOR (p int, q s.mytype) FOR SELECT p;
  i text COLLATE "C";
  j timestamp with time zone;
  k mytype[];
  l "My Type";
  m db.s.t%TYPE[];
  n NO SCROLL CURSOR FOR SELECT 1;
  o SCROLL CURSOR (z int) IS SELECT z;
  q refcursor;
  r pg_catalog.refcursor;
  type int;
  pos position.col%TYPE;
  vv values%ROWTYPE;
BEGIN
  NULL;
END`
	params := []Param{
		{Name: "pa", Type: "int"},
		{Name: "pb", Type: "public.t1"},
		{Name: "", Type: "tbl.col%TYPE"},
		{Name: "pc", Type: "refcursor"},
	}
	b := mustParse(t, body, &Options{Params: params})
	var got []string
	for i, d := range b.Decls {
		text := b.Text
		if d.Kind == DeclParam {
			text = params[i].Type
		}
		flags := ""
		if d.Const {
			flags += " const"
		}
		if d.NotNull {
			flags += " notnull"
		}
		if d.Value != nil {
			flags += fmt.Sprintf(" value=%q", b.Text[d.Value.Start:d.Value.End])
		}
		if d.Alias != "" {
			flags += " alias=" + d.Alias
		}
		got = append(got, fmt.Sprintf("%s %s@%d %s%s", d.Kind, d.Name, d.Line, typeDesc(text, d), flags))
	}
	want := []string{
		`param pa@0 plain "int" []`,
		`param pb@0 plain "public.t1" [public t1]`,
		`param @0 %type "tbl.col%TYPE" [tbl col]`,
		`param pc@0 plain "refcursor" [refcursor]`,
		`var a@3 plain "int" [] value="1"`,
		`var b@4 plain "text" [text] const notnull value="'x'"`,
		`var c@5 plain "numeric(10, 2)" [] value="5"`,
		`var d@6 %type "t.col%TYPE" [t col]`,
		`var e@7 %rowtype "s.t%ROWTYPE" [s t]`,
		`var f@8 record "record" []`,
		`alias g@9 - alias=$1`,
		`cursor h@10 - value="SELECT p"`,
		`cursor-arg p@10 plain "int" []`,
		`cursor-arg q@10 plain "s.mytype" [s mytype]`,
		`var i@11 plain "text" [text]`,
		`var j@12 plain "timestamp with time zone" []`,
		`var k@13 plain "mytype[]" [mytype]`,
		`var l@14 plain "\"My Type\"" [My Type]`,
		`var m@15 %type "db.s.t%TYPE[]" [db s t]`,
		`cursor n@16 - value="SELECT 1"`,
		`cursor o@17 - value="SELECT z"`,
		`cursor-arg z@17 plain "int" []`,
		`var q@18 plain "refcursor" [refcursor]`,
		`var r@19 plain "pg_catalog.refcursor" [pg_catalog refcursor]`,
		`var type@20 plain "int" []`,
		`var pos@21 %type "position.col%TYPE" [position col]`,
		`var vv@22 %rowtype "values%ROWTYPE" [values]`,
	}
	// the cursor arguments follow their cursor
	checkLines(t, got, want)

	// the name positions
	for _, d := range b.Decls {
		if d.Kind == DeclParam {
			continue
		}
		if b.Text[d.NameStart:d.NameEnd] != d.Name {
			t.Errorf("%s: name at %d..%d is %q", d.Name, d.NameStart, d.NameEnd, b.Text[d.NameStart:d.NameEnd])
		}
	}
}

func TestDynamic(t *testing.T) {
	body := `
DECLARE rc refcursor;
BEGIN
  EXECUTE 'select 1';
  EXECUTE format('a %s', format('b')) || pg_catalog.format('c') || public.format('d') || x.format(1) || "format"(2);
  FOR r IN EXECUTE format('select %s', 1) USING a LOOP NULL; END LOOP;
  RETURN QUERY EXECUTE 'select ' || a;
  OPEN rc FOR EXECUTE 'select 1' USING a;
  OPEN rc FOR SELECT 1;
  RETURN QUERY SELECT 1;
  FOR r IN SELECT format('x') LOOP NULL; END LOOP;
END`
	b := mustParse(t, body, nil)
	var got []string
	for _, d := range b.Dynamic {
		var fm []string
		for _, r := range d.Format {
			fm = append(fm, body[r.Start:r.End])
		}
		got = append(got, fmt.Sprintf("%s@%d %q %q", d.Kind, d.Line, body[d.Command.Start:d.Command.End], fm))
	}
	want := []string{
		`execute@4 "'select 1'" []`,
		`execute@5 "format('a %s', format('b')) || pg_catalog.format('c') || public.format('d') || x.format(1) || \"format\"(2)" ["format('a %s', format('b'))" "format('b')" "pg_catalog.format('c')" "\"format\"(2)"]`,
		`for-execute@6 "format('select %s', 1)" ["format('select %s', 1)"]`,
		`return-query-execute@7 "'select ' || a" []`,
		`open-execute@8 "'select 1'" []`,
	}
	checkLines(t, got, want)
	for _, d := range b.Dynamic {
		if d.Command.Kind != KindCommand {
			t.Errorf("%s: the command is %s", d.Kind, d.Command.Kind)
		}
	}
}

// TestNoCatalog is the bodies libpg_query rejects because it compiles
// without a catalog: parameters of the type refcursor, $0 in polymorphic
// functions, an array element as the target of GET DIAGNOSTICS, assignments
// to fields of composite variables and parameters, RETURN NEXT in a function
// with OUT parameters. The extractor does not look at types.
func TestNoCatalog(t *testing.T) {
	tests := []struct {
		name  string
		body  string
		opts  *Options
		want  []string
		shape string
	}{
		{"refcursor parameter", `
BEGIN
  OPEN rc FOR SELECT a FROM t;
  FETCH rc INTO x;
  FETCH NEXT FROM rc INTO x;
  MOVE rc;
  FOR r IN rc LOOP NULL; END LOOP;
  CLOSE rc;
END`, &Options{Params: []Param{{"rc", "refcursor"}}}, []string{
			`3 stmt sql "SELECT a FROM t"`,
		}, "{open@3<rc> fetch@4<rc> fetch@5<rc> fetch@6<rc> forc@7(r)<rc> close@8<rc>}"},
		{"polymorphic alias", `
DECLARE r ALIAS FOR $0;
BEGIN
  r := 1;
  RETURN r;
END`, nil, []string{
			`4 assign1 assign "r := 1"`,
			`5 expr expr "r"`,
		}, "{assign@4 return@5}"},
		{"diagnostics into an array element", `
DECLARE arr int[]; rca int[];
BEGIN
  GET DIAGNOSTICS arr[1] = ROW_COUNT;
  GET DIAGNOSTICS rca[1] = ROW_COUNT, rca[2] = ROW_COUNT;
END`, nil, nil, "{getdiag@4 getdiag@5}"},
		{"field of a composite variable", `
DECLARE w wallets%ROWTYPE;
BEGIN
  w.balance := w.balance + 1;
  SELECT * INTO w FROM wallets;
  SELECT 1 INTO w.balance;
  UPDATE wallets SET balance = w.balance WHERE id = w.id;
END`, nil, []string{
			`4 assign2 assign "w.balance := w.balance + 1"`,
			`5 stmt sql "SELECT *        FROM wallets"`,
			`6 stmt sql "SELECT 1"`,
			`7 stmt sql "UPDATE wallets SET balance = w.balance WHERE id = w.id"`,
		}, "{assign@4 execsql@5 execsql@6 execsql@7}"},
		{"field of a composite parameter", `
BEGIN
  p.id := 1;
  p.name = 'x';
  SELECT 1 INTO p.id;
END`, &Options{Params: []Param{{"p", "t1"}}}, []string{
			`3 assign2 assign "p.id := 1"`,
			`4 assign2 assign "p.name = 'x'"`,
			`5 stmt sql "SELECT 1"`,
		}, "{assign@3 assign@4 execsql@5}"},
		{"return next with out parameters", `
BEGIN
  a := 1;
  RETURN NEXT;
  RETURN NEXT a;
  RETURN QUERY SELECT 1;
END`, &Options{Params: []Param{{"a", "int"}}}, []string{
			`3 assign1 assign "a := 1"`,
			`5 expr expr "a"`,
			`6 stmt sql "SELECT 1"`,
		}, "{assign@3 return_next@4 return_next@5 return_query@6}"},
		{"bound cursor loop through a block label", `
DECLARE c CURSOR (a int) FOR SELECT a;
BEGIN
  FOR r IN c(1) LOOP NULL; END LOOP;
  FOR r IN values (1) LOOP NULL; END LOOP;
  FOR r IN values (1), (2) LOOP NULL; END LOOP;
END`, nil, []string{
			`2 stmt sql "SELECT a"`,
			`4 expr cursor-arg "1"`,
			`5 stmt sql "values (1)"`,
			`6 stmt sql "values (1), (2)"`,
		}, "{forc@4(r)<c> fors@5(r) fors@6(r)}"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			b := mustParse(t, tt.body, tt.opts)
			checkLines(t, dumpFragments(b), tt.want)
			if got := shapeBlock(b.Root); got != tt.shape {
				t.Errorf("shape: got %s, want %s", got, tt.shape)
			}
		})
	}
}

// TestRanges checks the byte offsets: the text of a fragment is the text in
// the body, and the INTO clause is the range that is blanked.
func TestRanges(t *testing.T) {
	body := "BEGIN\n  SELECT a INTO STRICT x /* c */ FROM t -- end\n ;\n  x := 1 + /* in */ 2 ; y = 3;\n  PERFORM  f( 1 )\n  ;\nEND"
	b := mustParse(t, body, nil)
	var got []string
	for _, f := range b.Fragments {
		s := fmt.Sprintf("%q", body[f.Start:f.End])
		if f.Into != (Range{}) {
			s += fmt.Sprintf(" into=%q", body[f.Into.Start:f.Into.End])
		}
		got = append(got, s)
	}
	checkLines(t, got, []string{
		`"SELECT a INTO STRICT x /* c */ FROM t -- end" into="INTO STRICT x /* c */ "`,
		`"x := 1 + /* in */ 2"`,
		`"y = 3"`,
		`"PERFORM  f( 1 )"`,
	})
}

// TestLines: lines count the newlines before the offset; a carriage return
// alone does not end a line.
func TestLines(t *testing.T) {
	body := "BEGIN\r\n  x := 1;\r\n  y := 'a\nb';\r  z := 3;\n\n  w := 4;\nEND"
	b := mustParse(t, body, nil)
	var lines []int
	for _, f := range b.Fragments {
		lines = append(lines, f.Line)
	}
	if fmt.Sprint(lines) != "[2 3 4 6]" {
		t.Errorf("lines %v", lines)
	}
	if b.Root.Line != 1 {
		t.Errorf("BEGIN on line %d", b.Root.Line)
	}
}

func TestErrors(t *testing.T) {
	tests := []struct {
		body string
		want string
		line int
	}{
		{"BEGIN x := 1", `missing ";" at end of SQL statement`, 1},
		{"BEGIN IF a THEN NULL;", `syntax error, expected "END" at end of input`, 1},
		{"BEGIN\n IF a THEN NULL; END;", `syntax error, expected "IF"`, 2},
		{"BEGIN SELECT 'a; END", `unterminated quoted string`, 1},
		{"BEGIN\n IF (a; THEN NULL; END IF; END", `mismatched parentheses`, 2},
		{"BEGIN IF a) THEN NULL; END IF; END", `mismatched parentheses`, 1},
		{"BEGIN\n SELECT (1;\n END", `unexpected end of function definition`, 3},
		{"DECLARE x BEGIN END", `incomplete data type declaration`, 1},
		{"DECLARE x ; BEGIN END", `missing data type declaration`, 1},
		{"BEGIN END END", `syntax error at or near "END"`, 1},
		{"BEGIN FOR i IN 1..3 END LOOP; END", `syntax error at or near ";"`, 1},
		{"BEGIN FOR i IN 1..3; END", `missing "LOOP" at end of SQL expression`, 1},
		{"BEGIN IF THEN NULL; END IF; END", `missing expression`, 1},
		{"BEGIN EXIT 1; END", `syntax error`, 1},
		{"BEGIN RAISE NOTICE; END", `syntax error`, 1},
		{"", `expected "BEGIN" at end of input`, 1},
		{"BEGIN CASE END CASE; END", `missing "WHEN" at end of SQL expression`, 1},
		{"DECLARE <<l>> BEGIN END", `block label must be placed before DECLARE, not after`, 1},
		{"BEGIN FETCH c; END", `syntax error`, 1},
		{"BEGIN WHEN x THEN NULL; END", `syntax error`, 1},
		{"BEGIN EXCEPTION END", `syntax error`, 1},
		{"BEGIN COMMIT", `syntax error at end of input`, 1},
	}
	for _, tt := range tests {
		_, err := Parse(tt.body, nil)
		e, ok := err.(*Error)
		if !ok || !strings.Contains(e.Msg, tt.want) || e.Line != tt.line {
			t.Errorf("%q: got %v, want %q at line %d", tt.body, err, tt.want, tt.line)
		}
	}
}

// TestRobust: no input makes the parser panic or run away. Every truncation
// and every deletion of a token of some bodies is parsed; whatever the
// result, the ranges it gives are inside the body.
func TestRobust(t *testing.T) {
	bodies := []string{
		`<<o>> DECLARE a int := 1; c CURSOR (p int) FOR SELECT p; r record; BEGIN
  a := 1; r.f := 2; SELECT 1 INTO a; PERFORM f(a); OPEN c(1); FETCH c INTO r; CLOSE c;
  IF a > 1 THEN NULL; ELSIF a THEN NULL; ELSE RETURN; END IF;
  CASE a WHEN 1, 2 THEN NULL; ELSE NULL; END CASE;
  FOR i IN 1..3 LOOP EXIT WHEN i > 2; END LOOP;
  FOR r IN SELECT 1 LOOP NULL; END LOOP;
  FOR r IN EXECUTE format('x') USING a LOOP NULL; END LOOP;
  FOREACH a SLICE 1 IN ARRAY b LOOP NULL; END LOOP;
  RAISE NOTICE 'a %', a USING ERRCODE = 'P0001';
  GET DIAGNOSTICS a = ROW_COUNT;
  EXECUTE 'x' INTO a USING b;
  RETURN QUERY EXECUTE 'x';
  BEGIN NULL; EXCEPTION WHEN OTHERS THEN NULL; END;
  COMMIT; CALL p(); DO $$ x $$;
END o`,
		`DECLARE a int; BEGIN a := ARRAY[1, 2][1]; SELECT (1 INTO a; END`,
	}
	for _, body := range bodies {
		check := func(src string) {
			defer func() {
				if r := recover(); r != nil {
					t.Fatalf("panic %v on %q", r, src)
				}
			}()
			b, err := Parse(src, nil)
			if err != nil {
				return
			}
			for _, f := range b.Fragments {
				if f.Start < 0 || f.End > len(src) || f.Start >= f.End {
					t.Fatalf("fragment %d..%d in %q", f.Start, f.End, src)
				}
				_ = f.SQL(src)
			}
		}
		for i := 0; i <= len(body); i++ {
			check(body[:i])
		}
		items, _ := lex.Scan(body, false)
		for _, it := range items {
			check(body[:it.Start] + " " + body[it.End:])
			check(body[:it.End] + " " + body[it.Start:it.End] + " " + body[it.End:])
		}
	}
}

func TestMode(t *testing.T) {
	// the modes are those of parse, which are those of RawParseMode
	if parse.ModeDefault != 0 || parse.ModePLpgSQLExpr != 2 || parse.ModePLpgSQLAssign1 != 3 || parse.ModePLpgSQLAssign3 != 5 {
		t.Fatal("parse modes changed")
	}
}
