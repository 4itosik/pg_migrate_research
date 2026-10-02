package subst

import (
	"os/exec"
	"strings"
	"testing"
)

func TestQuoteIdent(t *testing.T) {
	tests := map[string]string{
		"auth":          "auth",
		"_x1":           "_x1",
		"Auth":          `"Auth"`,
		"my schema":     `"my schema"`,
		"user":          `"user"`, // reserved
		"select":        `"select"`,
		"authorization": `"authorization"`, // type_func_name
		"between":       `"between"`,       // col_name
		"abort":         "abort",           // unreserved: bare, like quote_identifier
		"data":          "data",
		"1abc":          `"1abc"`,
		"a$b":           `"a$b"`,
		`a"b`:           `"a""b"`,
		"é":             `"é"`,
	}
	for in, want := range tests {
		if got := QuoteIdent(in); got != want {
			t.Errorf("QuoteIdent(%q) = %s, want %s", in, got, want)
		}
	}
}

func TestApply(t *testing.T) {
	tmpl := "CREATE TABLE pgschema_placeholder.t (id int DEFAULT nextval('pgschema_placeholder.s'));\n" +
		"-- pgschema_placeholder\nSELECT $$pgschema_placeholder.x$$"
	got, err := Apply(tmpl, "my schema")
	if err != nil {
		t.Fatal(err)
	}
	want := `CREATE TABLE "my schema".t (id int DEFAULT nextval('"my schema".s'));` + "\n" +
		`-- "my schema"` + "\nSELECT $$\"my schema\".x$$"
	if got != want {
		t.Errorf("got\n%s\nwant\n%s", got, want)
	}
	if out, err := Apply("SELECT 1", "auth"); err != nil || out != "SELECT 1" {
		t.Errorf("no placeholder: %q, %v", out, err)
	}
}

func TestApplyRejects(t *testing.T) {
	for _, bad := range []string{"", "a'b", "a$b", `a\b`, "a\nb", "a\x00b", string(make([]byte, 64)), "a\xffb",
		"pg_temp", "pg_x", "information_schema", " auth", "auth ", "a/*b", "a*/b", "a--b"} {
		if _, err := Apply("pgschema_placeholder.t", bad); err == nil {
			t.Errorf("Apply accepted the schema %q", bad)
		}
	}
	// near misses are names like any other
	for _, good := range []string{"PG_x", "pg", "pgx", "information_schema2", "a b", "a-b", "a/b", "a*b"} {
		if _, err := Apply("pgschema_placeholder.t", good); err != nil {
			t.Errorf("Apply rejected the schema %q: %v", good, err)
		}
	}
	// quotes in the name are fine: they are doubled
	if got, err := Apply("pgschema_placeholder.t", `a"b`); err != nil || got != `"a""b".t` {
		t.Errorf("got %q, %v", got, err)
	}
}

// TestNoParser: services import this package for the substitution, and the
// parser must not come with it.
func TestNoParser(t *testing.T) {
	out, err := exec.Command("go", "list", "-deps", ".").Output()
	if err != nil {
		t.Fatal(err)
	}
	for _, pkg := range strings.Fields(string(out)) {
		if strings.Contains(pkg, "pgschema") && pkg != "github.com/4itosik/pg_migrate_research/pgschema/subst" {
			t.Errorf("subst depends on %s", pkg)
		}
	}
}
