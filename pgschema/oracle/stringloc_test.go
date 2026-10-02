package oracle

import (
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"testing"

	"github.com/4itosik/pg_migrate_research/pgschema/internal/ast"
	"github.com/4itosik/pg_migrate_research/pgschema/internal/lex"
	"github.com/4itosik/pg_migrate_research/pgschema/internal/parse"
)

// TestStringLocations checks the extension of the tree the rewriter relies
// on: the Loc of a String node is the byte offset of the name it holds. For
// every String of every statement that has a Loc, the token at that offset
// must be the name; the Strings without a Loc are counted by the node they
// hang from, so that rules that forget the position show up.
//
// Strings that are values of constants (A_Const) never have a position.
func TestStringLocations(t *testing.T) {
	root := os.Getenv("REGRESS_ROOT")
	if root == "" {
		skipUnlessCI(t, "REGRESS_ROOT is not set; run tools/get-data.sh and source tools/env.sh")
	}
	files, err := LoadRegress(filepath.Join(root, "REL_16_STABLE"))
	if err != nil {
		skipUnlessCI(t, err.Error())
	}
	type counts struct{ total, known, wrong int }
	byParent := map[string]*counts{}
	var wrong []string
	total := 0
	for _, f := range files {
		for _, s := range f.Statements {
			stmts, err := parse.Parse(s)
			if err != nil {
				continue
			}
			total++
			for _, st := range stmts {
				var walk func(n ast.Node, parent string)
				walk = func(n ast.Node, parent string) {
					if n == nil {
						return
					}
					name := fmt.Sprintf("%T", n)
					name = name[strings.LastIndex(name, ".")+1:]
					if str, ok := n.(*ast.String); ok && parent != "A_Const" {
						c := byParent[parent]
						if c == nil {
							c = &counts{}
							byParent[parent] = c
						}
						c.total++
						if str.Loc >= 0 {
							c.known++
							if !tokenIs(s, int(str.Loc), str.Sval) {
								c.wrong++
								if len(wrong) < 20 {
									wrong = append(wrong, fmt.Sprintf("%s: %s String %q at %d: %q", f.Name, parent, str.Sval, str.Loc, truncate(strings.ReplaceAll(s, "\n", " "), 100)))
								}
							}
						}
					}
					n.Children(func(c ast.Node) { walk(c, name) })
				}
				walk(st, "")
			}
		}
	}
	var names []string
	var sumTotal, sumKnown, sumWrong int
	for p, c := range byParent {
		names = append(names, p)
		sumTotal += c.total
		sumKnown += c.known
		sumWrong += c.wrong
	}
	sort.Slice(names, func(i, j int) bool {
		return byParent[names[i]].total-byParent[names[i]].known > byParent[names[j]].total-byParent[names[j]].known
	})
	t.Logf("%d statements; %d Strings, %d with a position, %d with a wrong one", total, sumTotal, sumKnown, sumWrong)
	for i, p := range names {
		c := byParent[p]
		if i < 40 && c.total != c.known {
			t.Logf("  %-28s %6d Strings, %6d without a position, %d wrong", p, c.total, c.total-c.known, c.wrong)
		}
	}
	for _, w := range wrong {
		t.Error("wrong position: " + w)
	}
}

// tokenIs reports whether the token at offset loc of src has the value name.
func tokenIs(src string, loc int, name string) bool {
	if loc < 0 || loc >= len(src) {
		return false
	}
	it, err := lex.NewScanner(src[loc:]).Next()
	if err != nil {
		return false
	}
	switch {
	case it.Tok == lex.UIDENT:
		return true // the escapes are decoded by the parser, not compared here
	case it.Tok == lex.NOT_EQUALS:
		return name == "<>" // != is stored as <>
	case it.Str == "" && it.Tok != lex.SCONST:
		// operators of one or two characters carry no value: compare the text
		return src[loc+int(it.Start):loc+int(it.End)] == name
	}
	return it.Str == name
}
