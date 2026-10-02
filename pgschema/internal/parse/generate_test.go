package parse

import (
	"bytes"
	"go/ast"
	"go/format"
	goparser "go/parser"
	"go/token"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// TestGrammarGenerated checks that gram_gen.go is what the goyacc of this
// module makes of gram/*.y, and that the grammar has no conflicts (ADR 0001).
// It runs the generator, which takes a few seconds.
func TestGrammarGenerated(t *testing.T) {
	if testing.Short() {
		t.Skip("runs goyacc")
	}
	tmp := t.TempDir()
	parts, err := filepath.Glob("gram/*.y")
	if err != nil || len(parts) == 0 {
		t.Fatalf("no grammar files: %v", err)
	}
	var gram bytes.Buffer
	for _, p := range parts { // the order of the names is the order of the file
		b, err := os.ReadFile(p)
		if err != nil {
			t.Fatal(err)
		}
		gram.Write(b)
	}
	if err := os.WriteFile(filepath.Join(tmp, "gram.y"), gram.Bytes(), 0o644); err != nil {
		t.Fatal(err)
	}
	// the generator runs in the directory of the files, as gengram.sh does: the
	// names in its output (//line directives) are relative
	goyacc := filepath.Join(tmp, "goyacc")
	if msg, err := exec.Command("go", "build", "-o", goyacc, "../tools/goyacc").CombinedOutput(); err != nil {
		t.Fatalf("building goyacc: %v\n%s", err, msg)
	}
	cmd := exec.Command(goyacc, "-o", "gram_gen.go", "-v", "", "-recv", "p *parser", "gram.y")
	cmd.Dir = tmp
	msg, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("goyacc: %v\n%s", err, msg)
	}
	if strings.Contains(string(msg), "conflict") {
		t.Errorf("the grammar has conflicts:\n%s", msg)
	}
	generated, err := os.ReadFile(filepath.Join(tmp, "gram_gen.go"))
	if err != nil {
		t.Fatal(err)
	}
	if generated, err = format.Source(generated); err != nil {
		t.Fatal(err)
	}
	committed, err := os.ReadFile("gram_gen.go")
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(generated, committed) {
		t.Error("gram_gen.go is not what goyacc makes of gram/*.y: run go generate ./internal/parse")
	}
}

// maxFuncLines is the ceiling on the length of a function (ADR 0004): the
// Go compiler needs memory in proportion to the size of one function, and a
// parser that keeps its actions in separate small functions stays cheap to
// compile.
const maxFuncLines = 200

// TestFunctionSize checks that no function of the parser, generated or
// written by hand, is longer than maxFuncLines.
func TestFunctionSize(t *testing.T) {
	files, _ := filepath.Glob("*.go")
	lexFiles, _ := filepath.Glob("../lex/*.go")
	longest, where := 0, ""
	fset := token.NewFileSet()
	for _, name := range append(files, lexFiles...) {
		if strings.HasSuffix(name, "_test.go") {
			continue
		}
		f, err := goparser.ParseFile(fset, name, nil, 0)
		if err != nil {
			t.Fatal(err)
		}
		for _, d := range f.Decls {
			fn, ok := d.(*ast.FuncDecl)
			if !ok || fn.Body == nil {
				continue
			}
			// PositionFor with adjusted=false: the //line directives of the
			// generated file must not distort the count
			n := fset.PositionFor(fn.End(), false).Line - fset.PositionFor(fn.Pos(), false).Line + 1
			if n > longest {
				longest, where = n, name+": "+fn.Name.Name
			}
			if n > maxFuncLines {
				t.Errorf("%s: %s has %d lines, the ceiling is %d", name, fn.Name.Name, n, maxFuncLines)
			}
		}
	}
	t.Logf("the longest function is %s with %d lines", where, longest)
}
