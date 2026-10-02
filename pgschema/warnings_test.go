package pgschema

import (
	"strings"
	"testing"
)

// A warning has the line of the place it is about, or of its statement, in
// the text passed to Rewrite, also inside function bodies.
func TestWarningLines(t *testing.T) {
	sql := `CREATE TABLE text (a int);

SELECT
  current_schema();
CREATE FUNCTION f() RETURNS int LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE 'x';
  RETURN
    length('a'::text);
END $$;
CREATE FUNCTION g() RETURNS int LANGUAGE sql AS $$
SELECT length(
  'a'::text)
$$;
CREATE FUNCTION h() RETURNS int LANGUAGE sql AS 'SELECT length(
  ''a''::text)';
DO $$
DECLARE
  v int;
BEGIN
  v := 1 +
    length('a'::text);
END $$;
SELECT 'a'::text`
	_, warns, err := Rewrite(sql, Options{Schema: "auth"})
	if err != nil {
		t.Fatal(err)
	}
	want := []struct {
		line int
		text string
	}{
		{1, "text has the name of a built-in type"},
		{4, "current_schema()"},
		{5, "dynamic SQL"},
		{9, "text is also a built-in type"},
		{13, "text is also a built-in type"},
		{16, "text is also a built-in type"},
		{22, "text is also a built-in type"},
		{24, "text is also a built-in type"},
	}
	if len(warns) != len(want) {
		t.Fatalf("%d warnings, want %d:\n%s", len(warns), len(want), warningText(warns))
	}
	for i, w := range want {
		if warns[i].Line != w.line || !strings.HasPrefix(warns[i].Message, w.text) {
			t.Errorf("warning %d: %s, want line %d: %s...", i+1, warns[i], w.line, w.text)
		}
		if s := warns[i].String(); !strings.HasPrefix(s, "line ") || !strings.HasSuffix(s, warns[i].Message) {
			t.Errorf("String() = %q", s)
		}
	}
}
