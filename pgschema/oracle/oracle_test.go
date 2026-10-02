package oracle

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/4itosik/pg_migrate_research/poc/harness"
)

func corpusDir() string {
	if d := os.Getenv("CORPUS_DIR"); d != "" {
		return d
	}
	return filepath.Join("..", "..", "poc", "corpus")
}

func TestLibpgQuery(t *testing.T) {
	tree, err := Parse("CREATE TABLE users (id int)")
	if err != nil {
		t.Fatal(err)
	}
	if len(tree.Stmts) != 1 {
		t.Fatalf("got %d statements", len(tree.Stmts))
	}
	res, err := Scan("SELECT 1 -- c")
	if err != nil {
		t.Fatal(err)
	}
	if len(res.Tokens) != 3 { // SELECT, ICONST, SQL_COMMENT
		t.Fatalf("got %d tokens: %v", len(res.Tokens), res.Tokens)
	}
}

func TestCountNodes(t *testing.T) {
	tree, err := Parse("SELECT a FROM t")
	if err != nil {
		t.Fatal(err)
	}
	// RawStmt, SelectStmt, ResTarget, ColumnRef, String, RangeVar
	if n := CountNodes(tree); n != 6 {
		t.Fatalf("got %d nodes, want 6", n)
	}
}

func TestPrototype(t *testing.T) {
	p, err := NewPrototype(PrototypeOptions{Schema: "auth"})
	if err != nil {
		t.Fatal(err)
	}
	out, _, err := p.Rewrite("CREATE TABLE users (id int) -- keep")
	if err != nil {
		t.Fatal(err)
	}
	if want := "CREATE TABLE auth.users (id int) -- keep"; out != want {
		t.Fatalf("got %q, want %q", out, want)
	}
}

func TestCorpus(t *testing.T) {
	cases, err := harness.LoadCorpus(corpusDir())
	if err != nil {
		t.Fatal(err)
	}
	if len(cases) != 23 {
		t.Fatalf("got %d corpus cases, want 23", len(cases))
	}
	var up int
	for _, c := range cases {
		for _, m := range c.Migrations {
			if m.Up != "" {
				up++
			}
			if _, err := Parse(m.Up); err != nil {
				t.Errorf("%s/%s: libpg_query rejects the corpus file: %v", c.Name, m.UpFile, err)
			}
			if _, err := Parse(m.Down); err != nil {
				t.Errorf("%s/%s: libpg_query rejects the corpus file: %v", c.Name, m.DownFile, err)
			}
		}
	}
	if up != 27 {
		t.Errorf("got %d up files, want 27", up)
	}
}

// TestRegressDataset checks that the splitter reproduces the statement
// counts of the research (DATASET.md, section 2).
func TestRegressDataset(t *testing.T) {
	root := os.Getenv("REGRESS_ROOT")
	if root == "" {
		t.Skip("REGRESS_ROOT is not set; run tools/get-data.sh and source tools/env.sh")
	}
	want := map[string][2]int{ // files, statements accepted by libpg_query
		"REL_12_STABLE": {189, 32024},
		"REL_13_STABLE": {197, 34733},
		"REL_14_STABLE": {206, 37777},
		"REL_15_STABLE": {217, 41116},
		"REL_16_STABLE": {220, 42798},
	}
	for branch, w := range want {
		t.Run(branch, func(t *testing.T) {
			files, err := LoadRegress(filepath.Join(root, branch))
			if err != nil {
				t.Skip(err)
			}
			got := [2]int{len(files), len(Accepted(files))}
			if got != w {
				t.Errorf("files, accepted statements = %v, want %v", got, w)
			}
		})
	}
}
