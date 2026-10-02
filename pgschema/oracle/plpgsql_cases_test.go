package oracle

// plSynthetic are function and DO statements written to cover the PL/pgSQL
// grammar where the regression tests are thin: every statement, every form of
// DECLARE, the forms of FETCH, OPEN, RAISE and FOR, INTO in the different
// statements, assignments to subscripts and fields, labels, comments in the
// places where a statement ends, and names that are keywords. libpg_query
// compiles all of them without a catalog.
var plSynthetic = []string{
	// declarations
	`CREATE FUNCTION s_decl(a int, b text) RETURNS int LANGUAGE plpgsql AS $pgs$
<<outer>>
DECLARE
  x int := 1;
  y CONSTANT text NOT NULL DEFAULT 'abc';
  z numeric(10, 2) = 5;
  r record;
  w t1.col%TYPE;
  v public.t1%ROWTYPE;
  v2 t1%ROWTYPE;
  arr int[] := ARRAY[1, 2, 3];
  arr2 t1.col%TYPE[];
  al ALIAS FOR $1;
  c1 CURSOR FOR SELECT * FROM t1;
  c2 CURSOR (p1 int, p2 text) IS SELECT * FROM t2 WHERE a = p1 AND b = p2;
  c3 NO SCROLL CURSOR (q "My Type", s varchar(10)) FOR SELECT q, s;
  c4 SCROLL CURSOR FOR VALUES (1), (2);
  rc refcursor;
  ts timestamp with time zone DEFAULT now();
  dp double precision;
  txt text COLLATE "C" := 'x';
  u myschema.mytype;
  q1 "Quoted Name" int;
BEGIN
  RETURN x;
END
$pgs$`,
	// declarations with a comment and a newline in odd places, and names that
	// are keywords of PL/pgSQL
	`CREATE FUNCTION s_kw() RETURNS void LANGUAGE plpgsql AS $pgs$
DECLARE
  log int := 1;
  error text;
  info int;
  first int;
  query text := 'q';
  type int;
  schema int;
  row_count int;
  "end" int;
  perform int;
BEGIN
  log := 2;
  error = 'e';
  info := log + 1;
  first := 1;
  query := query || 'x';
  type := 3;
  schema := 4;
  row_count := 5;
  "end" := 6;
  perform := 7;
END
$pgs$`,
	// assignments
	`CREATE FUNCTION s_assign(a int) RETURNS void LANGUAGE plpgsql AS $pgs$
DECLARE
  x int;
  arr int[];
  r record;
  r2 record;
BEGIN
  x := 1;
  x = 2;
  x := (SELECT max(id) FROM t1);
  x := a + (SELECT count(*) FROM t2 WHERE t2.id = a);
  arr[1] := 5;
  arr[x][2] := 6;
  arr[x + 1] = 7;
  r := ROW(1, 2);
  r.f1 := 3;
  r.f1 = 4;
  r.f1.f2 := 5;
  r.arr[2] := 4;
  r.f1[1].f2 := 5;
  <<lbl>>
  DECLARE
    x int;
    arr int[];
    rr record;
  BEGIN
    lbl.x := 1;
    lbl.arr[1] := 2;
    lbl.rr.f := 3;
    lbl.rr.f = 4;
    rr.f.g := 5;
  END;
  r.f1 :=
     -- a comment
     7 /* x */;
  r2.a := x /* trailing */ ;
  x := a
  ;
END
$pgs$`,
	// SQL statements and INTO
	`CREATE FUNCTION s_sql(a int) RETURNS void LANGUAGE plpgsql AS $pgs$
DECLARE
  x int;
  y text;
  r record;
BEGIN
  SELECT 1;
  SELECT id INTO x FROM t1 WHERE id = a;
  SELECT id, name INTO x, y FROM t1;
  SELECT id, name INTO STRICT x, y FROM t1 /* c */ ;
  SELECT * INTO r FROM t1 LIMIT 1;
  SELECT 1 INTO x;
  SELECT 1 INTO x  /* c1 */ -- c2
  ;
  INSERT INTO t1 (id) VALUES (1);
  INSERT INTO t1 (id) VALUES (2) RETURNING id INTO x;
  INSERT INTO t1 (id) SELECT id FROM t2 RETURNING id, name INTO STRICT x, y;
  UPDATE t1 SET name = 'a' WHERE id = 1 RETURNING name INTO y;
  DELETE FROM t1 WHERE id = 3 RETURNING id INTO x;
  WITH q AS (SELECT 1 AS n) SELECT n INTO x FROM q;
  WITH ins AS (INSERT INTO t1 VALUES (5) RETURNING id) SELECT id INTO x FROM ins;
  CREATE TABLE tmp1 AS SELECT 1 AS a;
  CREATE TEMP TABLE tmp2 (a int);
  DROP TABLE tmp1, tmp2;
  ALTER TABLE t1 ADD COLUMN c int;
  TRUNCATE t1;
  VALUES (1), (2);
  SET search_path = public;
  SET LOCAL x.y = 'z';
  COMMENT ON TABLE t1 IS 'a; b';
  CREATE INDEX ON t1 (id);
  GRANT SELECT ON t1 TO PUBLIC;
  LOCK TABLE t1 IN SHARE MODE;
  EXPLAIN SELECT 1;
  SELECT 'a;b', "x;y", $$c;d$$, E'e\';f' FROM t1;
  SELECT (SELECT 1) INTO x;
  SELECT (array[1,2])[1] INTO x;
  SELECT CASE WHEN a > 1 THEN 1 ELSE 2 END INTO x;
  INSERT INTO t1 SELECT * FROM t2 WHERE id IN (SELECT id FROM t3);
END
$pgs$`,
	// MERGE, IMPORT, CREATE FUNCTION and CREATE RULE inside the body
	`CREATE FUNCTION s_sql2() RETURNS void LANGUAGE plpgsql AS $pgs$
DECLARE x int;
BEGIN
  MERGE INTO t1 USING t2 ON t1.id = t2.id WHEN MATCHED THEN UPDATE SET name = t2.name WHEN NOT MATCHED THEN INSERT VALUES (t2.id, t2.name);
  CREATE RULE r1 AS ON INSERT TO t1 DO ALSO (INSERT INTO t2 VALUES (NEW.id); INSERT INTO t3 VALUES (NEW.id););
  CREATE FUNCTION inner_f() RETURNS int LANGUAGE sql BEGIN ATOMIC SELECT 1; SELECT 2; END;
  CREATE OR REPLACE FUNCTION inner_g(a int) RETURNS int LANGUAGE sql
    BEGIN ATOMIC SELECT CASE WHEN a > 0 THEN 1 ELSE 2 END; END;
  CREATE PROCEDURE inner_p() LANGUAGE sql BEGIN ATOMIC INSERT INTO t1 VALUES (1); END;
  IMPORT FOREIGN SCHEMA remote LIMIT TO (a) FROM SERVER srv INTO local_schema;
  CALL p1(1, 2);
  CALL p2();
  DO $$ BEGIN PERFORM 1; END $$;
  DO LANGUAGE plpgsql $$ BEGIN NULL; END $$;
END
$pgs$`,
	// PERFORM
	`CREATE FUNCTION s_perform() RETURNS void LANGUAGE plpgsql AS $pgs$
BEGIN
  PERFORM 1;
  PERFORM(1);
  PERFORM f(1), g(2) FROM t1 WHERE id = 1;
  perform /* c */ 2;
  PERFORM
     3
     ;
  PERFORM * FROM t1;
  PERFORM id FROM t1 WHERE EXISTS (SELECT 1);
END
$pgs$`,
	// IF, CASE, loops, labels
	`CREATE FUNCTION s_flow(a int) RETURNS int LANGUAGE plpgsql AS $pgs$
DECLARE
  x int := 0;
BEGIN
  IF a > 1 THEN
    x := 1;
  ELSIF a < 0 THEN
    x := 2;
  ELSIF a = 0
  THEN
    x := 3;
  ELSEIF a = 99 THEN
    x := 5;
  ELSE
    x := 4;
  END IF;
  IF (SELECT count(*) FROM t1 WHERE id = a) > 0 THEN NULL; END IF;
  CASE a WHEN 1 THEN x := 1; WHEN 2, 3 THEN x := 2; WHEN (SELECT 4), 5 THEN NULL; ELSE x := 3; END CASE;
  CASE WHEN a = 1 THEN x := 1; WHEN a IN (SELECT id FROM t1) THEN x := 2; END CASE;
  CASE a + 1 WHEN 1 THEN NULL; END CASE;
  CASE
    WHEN a = 1 THEN NULL;
    ELSE NULL;
  END CASE;
  <<l1>>
  LOOP
    x := x + 1;
    EXIT l1 WHEN x > 10;
    CONTINUE l1 WHEN x = 3;
    EXIT WHEN x > 5;
    CONTINUE WHEN x = 1;
    EXIT;
    CONTINUE;
    EXIT l1;
  END LOOP l1;
  WHILE x < 20 LOOP
    x := x + 1;
  END LOOP;
  <<w1>> WHILE x < (SELECT 30) LOOP x := x + 1; EXIT w1; END LOOP w1;
  FOR i IN 1..10 LOOP x := x + i; END LOOP;
  FOR i IN REVERSE 10..1 LOOP x := x + i; END LOOP;
  FOR i IN 1..10 BY 2 LOOP x := x + i; END LOOP;
  FOR i IN REVERSE 10..1 BY a LOOP x := x + i; END LOOP;
  <<f1>> FOR i IN a..(SELECT 10) LOOP NULL; END LOOP f1;
  FOR i IN
    1
    ..
    3
  LOOP NULL; END LOOP;
  RETURN x;
END
$pgs$`,
	// FOR over queries, EXECUTE, cursors; FOREACH
	`CREATE FUNCTION s_for(a int) RETURNS int LANGUAGE plpgsql AS $pgs$
DECLARE
  r record;
  x int;
  y text;
  c1 CURSOR FOR SELECT 1;
  c2 CURSOR (p1 int, p2 int) FOR SELECT p1, p2;
  arr int[];
  tsl text[];
BEGIN
  FOR r IN SELECT * FROM t1 LOOP NULL; END LOOP;
  FOR r IN SELECT * FROM t1 WHERE id IN (SELECT id FROM t2) ORDER BY 1 LOOP NULL; END LOOP;
  FOR r IN WITH q AS (SELECT 1 AS n) SELECT n FROM q LOOP NULL; END LOOP;
  FOR r IN VALUES (1), (2) LOOP NULL; END LOOP;
  FOR r IN VALUES (1) LOOP NULL; END LOOP;
  FOR r IN TABLE t1 LOOP NULL; END LOOP;
  FOR r IN INSERT INTO t1 VALUES (1) RETURNING * LOOP NULL; END LOOP;
  FOR r IN (SELECT 1) LOOP NULL; END LOOP;
  FOR x, y IN SELECT 1, 'a' LOOP NULL; END LOOP;
  FOR r IN EXECUTE 'select 1' LOOP NULL; END LOOP;
  FOR r IN EXECUTE format('select %s', a) USING a, 2 LOOP NULL; END LOOP;
  FOR x, y IN EXECUTE 'select 1, 2' USING a LOOP NULL; END LOOP;
  FOR r IN c1 LOOP NULL; END LOOP;
  FOR r IN c2(1, 2) LOOP NULL; END LOOP;
  FOR r IN c2(p2 := 1, p1 := 2) LOOP NULL; END LOOP;
  FOR r IN c2(a, (SELECT 5)) LOOP NULL; END LOOP;
  <<fl>> FOR r IN c2(a, a + 1) LOOP EXIT fl; END LOOP fl;
  FOREACH x IN ARRAY arr LOOP NULL; END LOOP;
  FOREACH x IN ARRAY ARRAY[1, 2, 3] LOOP NULL; END LOOP;
  FOREACH arr SLICE 1 IN ARRAY (SELECT array[array[1]]) LOOP NULL; END LOOP;
  <<fe>> FOREACH x IN ARRAY arr LOOP CONTINUE fe; END LOOP fe;
  RETURN 1;
END
$pgs$`,
	// OPEN, FETCH, MOVE, CLOSE
	`CREATE FUNCTION s_cursor(a int) RETURNS int LANGUAGE plpgsql AS $pgs$
DECLARE
  c1 CURSOR FOR SELECT 1;
  c2 CURSOR (p1 int, p2 int) FOR SELECT p1, p2;
  rc refcursor;
  rc2 refcursor := 'portal';
  r record;
  x int;
  y int;
BEGIN
  OPEN c1;
  OPEN c2(1, 2);
  OPEN c2(p2 := 1, p1 := 2);
  OPEN c2(a, a + 1);
  OPEN c2 ( (SELECT 1), 2 );
  OPEN rc FOR SELECT * FROM t1;
  OPEN rc SCROLL FOR SELECT * FROM t1 WHERE id = a;
  OPEN rc NO SCROLL FOR SELECT 1;
  OPEN rc FOR WITH q AS (SELECT 1) SELECT * FROM q;
  OPEN rc FOR VALUES (1);
  OPEN rc FOR EXECUTE 'select 1';
  OPEN rc FOR EXECUTE format('select %s', a) USING a, 2;
  OPEN rc SCROLL FOR EXECUTE 'select $1' USING a;
  FETCH c1 INTO r;
  FETCH NEXT FROM c1 INTO r;
  FETCH PRIOR FROM c1 INTO r;
  FETCH FIRST FROM c1 INTO r;
  FETCH LAST FROM c1 INTO r;
  FETCH ABSOLUTE 3 FROM c1 INTO r;
  FETCH ABSOLUTE a + 1 FROM c1 INTO r;
  FETCH RELATIVE -1 IN c1 INTO r;
  FETCH FORWARD FROM c1 INTO r;
  FETCH BACKWARD IN c1 INTO r;
  FETCH FROM c1 INTO x;
  FETCH IN c1 INTO x, y;
  FETCH c1 INTO x, y;
  FETCH c1
    INTO r;
  MOVE c1;
  MOVE NEXT FROM c1;
  MOVE PRIOR IN c1;
  MOVE FIRST FROM c1;
  MOVE LAST FROM c1;
  MOVE ABSOLUTE 3 FROM c1;
  MOVE RELATIVE a FROM c1;
  MOVE FORWARD 2 FROM c1;
  MOVE FORWARD ALL FROM c1;
  MOVE BACKWARD ALL IN c1;
  MOVE BACKWARD a + 1 FROM c1;
  MOVE ALL FROM c1;
  MOVE 3 FROM c1;
  MOVE FROM c1;
  CLOSE c1;
  CLOSE rc;
  RETURN 1;
END
$pgs$`,
	// RAISE, ASSERT, GET DIAGNOSTICS
	`CREATE FUNCTION s_raise(a int) RETURNS void LANGUAGE plpgsql AS $pgs$
DECLARE
  x int;
  y text;
  st text;
  arr int[];
BEGIN
  RAISE;
  RAISE NOTICE 'hello';
  RAISE NOTICE 'a %, b %', a, (SELECT 1);
  RAISE WARNING 'w %', a + 1;
  RAISE INFO 'i';
  RAISE LOG 'l';
  RAISE DEBUG 'd %', 'x';
  RAISE EXCEPTION 'e %', 'x' USING ERRCODE = 'P0001', DETAIL = 'det' || y, HINT := 'h';
  RAISE 'plain %', a;
  RAISE EXCEPTION USING MESSAGE = 'm', ERRCODE = '22012';
  RAISE division_by_zero;
  RAISE EXCEPTION division_by_zero USING MESSAGE = 'm';
  RAISE SQLSTATE '22012';
  RAISE EXCEPTION SQLSTATE '22012' USING DETAIL = 'x', COLUMN = 'c', CONSTRAINT = 'k', DATATYPE = 't', TABLE = 'tb', SCHEMA = 's';
  RAISE NOTICE 'x' USING MESSAGE = 'y';
  RAISE NOTICE '% %', a, a USING HINT = 'h';
  ASSERT a > 0;
  ASSERT a > 0, 'a must be positive';
  ASSERT (SELECT count(*) FROM t1) > 0, format('bad %s', a);
  GET DIAGNOSTICS x = ROW_COUNT;
  GET CURRENT DIAGNOSTICS x = ROW_COUNT, y = PG_CONTEXT;
  GET DIAGNOSTICS x = PG_ROUTINE_OID;
END
$pgs$`,
	// exceptions
	`CREATE FUNCTION s_exc(a int) RETURNS void LANGUAGE plpgsql AS $pgs$
DECLARE
  x int;
  y text;
  m text;
BEGIN
  x := 1;
EXCEPTION
  WHEN division_by_zero THEN
    x := 2;
  WHEN unique_violation OR foreign_key_violation THEN
    RAISE NOTICE 'u %', SQLERRM;
  WHEN SQLSTATE '22012' OR SQLSTATE '23505' THEN
    NULL;
  WHEN others THEN
    GET STACKED DIAGNOSTICS m = MESSAGE_TEXT, y = PG_EXCEPTION_DETAIL;
    RAISE EXCEPTION 'e: %', SQLSTATE;
END
$pgs$`,
	`CREATE FUNCTION s_nested(a int) RETURNS int LANGUAGE plpgsql AS $pgs$
DECLARE
  x int := 0;
BEGIN
  <<b1>>
  DECLARE
    y int := x + 1;
  BEGIN
    x := y;
    BEGIN
      x := x + 1;
    EXCEPTION WHEN OTHERS THEN
      x := 0;
    END;
    <<b2>>
    DECLARE q int;
    BEGIN
      b2.q := 1;
    END b2;
  EXCEPTION
    WHEN OTHERS THEN x := -1;
  END b1;
  DECLARE
    z int;
  BEGIN
    z := 1;
  END;
  BEGIN
    NULL;
  END;
  RETURN x;
EXCEPTION
  WHEN OTHERS THEN
    RETURN -1;
END
$pgs$`,
	// RETURN forms
	`CREATE FUNCTION s_ret(a int) RETURNS SETOF int LANGUAGE plpgsql AS $pgs$
DECLARE
  x int;
  r record;
BEGIN
  RETURN NEXT 1;
  RETURN NEXT a;
  RETURN NEXT a + 1;
  RETURN NEXT (SELECT 1);
  RETURN NEXT x;
  RETURN QUERY SELECT 1;
  RETURN QUERY SELECT id FROM t1 WHERE id = a;
  RETURN QUERY WITH q AS (SELECT 1) SELECT * FROM q;
  RETURN QUERY VALUES (1), (2);
  RETURN QUERY EXECUTE 'select 1';
  RETURN QUERY EXECUTE format('select %s', a) USING a, 2;
  RETURN QUERY EXECUTE 'select $1' USING a;
  RETURN;
END
$pgs$`,
	`CREATE FUNCTION s_ret2(a int) RETURNS int LANGUAGE plpgsql AS $pgs$
BEGIN
  IF a > 1 THEN RETURN 1; END IF;
  IF a > 2 THEN RETURN (SELECT 1); END IF;
  RETURN a + 1
  ;
END
$pgs$`,
	// dynamic SQL
	`CREATE FUNCTION s_dyn(a int, tbl text) RETURNS void LANGUAGE plpgsql AS $pgs$
DECLARE
  x int;
  y text;
  r record;
BEGIN
  EXECUTE 'select 1';
  EXECUTE 'select ' || a;
  EXECUTE 'select 1' INTO x;
  EXECUTE 'select 1' INTO STRICT x;
  EXECUTE 'select 1, 2' INTO x, y;
  EXECUTE 'select $1' INTO x USING a;
  EXECUTE 'select $1' USING a INTO x;
  EXECUTE 'select $1, $2' USING a, tbl;
  EXECUTE format('select count(*) from %I where id = %L', tbl, a) INTO x;
  EXECUTE format('select count(*) from %I', tbl) INTO x USING a;
  EXECUTE pg_catalog.format('select %s', a);
  EXECUTE 'a' || format('b %s', a) || format('c');
  EXECUTE (SELECT 'select 1');
  EXECUTE 'select 1' INTO r;
  EXECUTE 'insert into ' || quote_ident(tbl) || ' values ($1)' USING a;
END
$pgs$`,
	// transaction control, CALL, DO
	`CREATE PROCEDURE s_proc(a int) LANGUAGE plpgsql AS $pgs$
BEGIN
  COMMIT;
  ROLLBACK;
  COMMIT AND CHAIN;
  ROLLBACK AND NO CHAIN;
  COMMIT AND NO CHAIN;
  ROLLBACK AND CHAIN;
  CALL p1(1, 2);
  CALL p2();
  CALL p3(a + 1, (SELECT 1));
  DO $$ BEGIN PERFORM 1; END $$;
END
$pgs$`,
	// the compile options
	`CREATE FUNCTION s_opt(a int) RETURNS int LANGUAGE plpgsql AS $pgs$
#variable_conflict use_column
#print_strict_params on
#option dump
DECLARE x int;
BEGIN
  x := a;
  RETURN x;
END;
$pgs$`,
	// DO blocks
	`DO $pgs$
DECLARE
  x int := 1;
BEGIN
  x := x + 1;
  INSERT INTO t1 VALUES (x);
  RAISE NOTICE '%', x;
END
$pgs$`,
	`DO LANGUAGE plpgsql $pgs$ BEGIN PERFORM 1; END $pgs$`,
	`DO $pgs$ BEGIN
  FOR i IN 1..3 LOOP EXECUTE format('select %s', i); END LOOP;
END $pgs$`,
	// a string literal body with quotes doubled: the decoded text is what counts
	`CREATE FUNCTION s_quoted(a int) RETURNS int LANGUAGE plpgsql AS 'DECLARE x int := 1; BEGIN x := a + 1; RAISE NOTICE ''x = %'', x; RETURN x; END'`,
	`CREATE FUNCTION s_estring(a int) RETURNS int LANGUAGE plpgsql AS E'DECLARE\n x int := 1;\nBEGIN\n  x := a + 1;\n  PERFORM \'a\';\n  RETURN x;\nEND'`,
	// comments and strings with ; and keywords
	`CREATE FUNCTION s_comments(a int) RETURNS int LANGUAGE plpgsql AS $pgs$
-- leading comment; with a semicolon
/* block comment /* nested; */ still */
DECLARE
  x int; -- trailing; comment
BEGIN
  -- comment before
  x := 1; /* after */ x := 2; -- end
  SELECT 'it''s; a string' /* c; */ INTO x;
  x := length($q$a;b$q$);
  RAISE NOTICE 'end; loop; then;';
  IF x > 1 /* then */ THEN -- then
    NULL;
  END /* c */ IF /* d */ ;
  RETURN x;
END -- done
$pgs$`,
	// quoted identifiers and mixed case
	`CREATE FUNCTION s_case(a int) RETURNS int LANGUAGE plpgsql AS $pgs$
DECLARE
  "X" int := 1;
  Y int;
  "select" int;
BEGIN
  "X" := a;
  y := "X";
  "select" := 1;
  <<"Lbl">>
  DECLARE "Y2" int;
  BEGIN
    "Lbl"."Y2" := 2;
  END "Lbl";
  SeLeCt 1 InTo y;
  iF y > 1 ThEn NULL; eNd If;
  RETURN "X";
END
$pgs$`,
	// Windows line ends and tabs
	"CREATE FUNCTION s_crlf(a int) RETURNS int LANGUAGE plpgsql AS $pgs$\r\nDECLARE\r\n\tx int;\r\nBEGIN\r\n\tx := a;\r\n\tSELECT 1 INTO x;\r\n\tRETURN x;\r\nEND\r\n$pgs$",
	// trigger function
	`CREATE FUNCTION s_trg() RETURNS trigger LANGUAGE plpgsql AS $pgs$
BEGIN
  NEW.a := 1;
  NEW.b = TG_OP;
  NEW.c.d := 1;
  OLD.x := 1;
  IF TG_OP = 'INSERT' THEN RETURN NEW; END IF;
  INSERT INTO log SELECT NEW.*;
  RETURN OLD;
END
$pgs$`,
	// functions with OUT parameters and composite parameters
	`CREATE FUNCTION s_out(IN a int, OUT b int, OUT c text) LANGUAGE plpgsql AS $pgs$
BEGIN
  b := a;
  c := 'x';
  RETURN;
END
$pgs$`,
	`CREATE FUNCTION s_comp(p public.t1, q int[]) RETURNS int LANGUAGE plpgsql AS $pgs$
BEGIN
  p.id := 1;
  p.name = 'x';
  q[1] := 2;
  RETURN p.id;
END
$pgs$`,
	// statements that start like an assignment or a keyword but are not
	`CREATE FUNCTION s_tricky(a int) RETURNS void LANGUAGE plpgsql AS $pgs$
DECLARE
  x int;
  r record;
BEGIN
  UPDATE t1 SET a = 1, b = 2 WHERE c = 3;
  UPDATE t1 SET arr[1] = 5, r.f = 3;
  UPDATE t1 SET (a, b) = (1, 2);
  SET x.y = 1;
  SET LOCAL search_path = a, b;
  INSERT INTO t1 (a) VALUES (a = 1);
  INSERT INTO t1 VALUES (1) ON CONFLICT (id) DO UPDATE SET a = excluded.a;
  VALUES (a = 1);
  SELECT a = 1 INTO x;
  SELECT a[1] FROM (SELECT ARRAY[1,2] AS a) s;
  WITH x AS (SELECT 1) SELECT * FROM x;
  x := x = 1;
  x := (x = 1)::int;
  x := CASE WHEN x = 1 THEN 1 ELSE 2 END;
  x := (ARRAY[1,2])[x];
  x := a::int;
  r := (SELECT t1 FROM t1 LIMIT 1);
  x := (r).id;
END
$pgs$`,
	// statements whose first word is not a keyword the grammar knows
	`CREATE FUNCTION s_first() RETURNS void LANGUAGE plpgsql AS $pgs$
BEGIN
  COMMENT ON TABLE t1 IS 'x';
  REFRESH MATERIALIZED VIEW mv;
  ANALYZE t1;
  VACUUM t1;
  NOTIFY ch, 'p';
  LISTEN ch;
  SECURITY LABEL ON TABLE t1 IS 'x';
  CLUSTER t1;
  REINDEX TABLE t1;
  PREPARE p1 AS SELECT 1;
END
$pgs$`,
	// labels and the name of the function qualify variables
	`CREATE FUNCTION s_lab(a int, p public.t1) RETURNS void LANGUAGE plpgsql AS $pgs$
<<blk>>
DECLARE
  r record;
  v int;
BEGIN
  blk.v := 1;
  blk.r.f := 2;
  blk.r.f1 = 3;
  r.f.g := 4;
  s_lab.a := 5;
  s_lab.p.id := 6;
  s_lab.p.id = 7;
  <<lp>>
  FOR i IN 1..2 LOOP
    lp.i := 3;
  END LOOP;
  p.id := 8;
  p.id.x := 9;
END
$pgs$`,
}
