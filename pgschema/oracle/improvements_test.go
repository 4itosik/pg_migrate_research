package oracle

import (
	"regexp"
	"slices"
	"sort"
	"strings"
	"sync"
	"testing"

	"go/ast"
	"go/parser"
	"go/token"

	pgast "github.com/4itosik/pg_migrate_research/pgschema/internal/ast"
	"github.com/4itosik/pg_migrate_research/pgschema/internal/parse"
)

// The improvements of the library over the prototype that change the output
// (docs/differences.md, "Ошибки прототипа"): wherever the outputs of the two
// differ, the difference must be one of these, every other one is an error.
const (
	// a type or a function created by a migration with the name of a
	// built-in of pg_catalog: the prototype qualifies every use of the name,
	// the library leaves the uses to the built-in
	improvementBuiltin = "built-in name"
	// a string constant under nested casts to regclass
	// (nextval(('s'::text)::regclass)): the prototype leaves it unqualified
	improvementNestedCast = "nested cast"
	// a temporary relation hides a relation of the same name only in the text
	// that creates it: the prototype keeps its name for good
	improvementTempScope = "temp scope"
)

const schemaPrefix = "auth."

// insertion is a schema inserted into an output: at the offset in the output
// with the inserted prefixes removed, before the name.
type insertion struct {
	at   int
	name string
	pos  int // the offset in the output itself
}

// insertions removes every "auth." from out and returns the rest and the
// places where they stood.
func insertions(out string) (string, []insertion) {
	var b strings.Builder
	var ins []insertion
	for i := 0; i < len(out); {
		if strings.HasPrefix(out[i:], schemaPrefix) {
			ins = append(ins, insertion{at: b.Len(), name: nameAt(out[i+len(schemaPrefix):]), pos: i})
			i += len(schemaPrefix)
			continue
		}
		b.WriteByte(out[i])
		i++
	}
	return b.String(), ins
}

// nameAt reads the identifier at the start of s as PostgreSQL does: a quoted
// one exactly, an unquoted one folded to lower case.
func nameAt(s string) string {
	if strings.HasPrefix(s, `"`) {
		var b strings.Builder
		for i := 1; i < len(s); i++ {
			if s[i] == '"' {
				if i+1 < len(s) && s[i+1] == '"' {
					b.WriteByte('"')
					i++
					continue
				}
				break
			}
			b.WriteByte(s[i])
		}
		return b.String()
	}
	end := 0
	for end < len(s) {
		c := s[end]
		if c == '_' || c == '$' || c >= '0' && c <= '9' || c >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z' || c >= 0x80 {
			end++
			continue
		}
		break
	}
	return strings.ToLower(s[:end])
}

// nestedRegclassCast matches what follows the name of a string constant
// under nested casts to regclass: the closing quote and at least two casts,
// one of them to text or varchar, the last to regclass.
var nestedRegclassCast = regexp.MustCompile(`(?is)^[^']*'((?:[\s)]*::\s*(?:pg_catalog\.)?(?:text|varchar|character\s+varying|regclass)\b)+)`)

func underNestedCast(after string) bool {
	m := nestedRegclassCast.FindStringSubmatch(after)
	if m == nil {
		return false
	}
	casts := strings.ToLower(m[1])
	return strings.Count(casts, "::") >= 2 && strings.HasSuffix(strings.TrimSpace(casts), "regclass") &&
		(strings.Contains(casts, "text") || strings.Contains(casts, "varchar") || strings.Contains(casts, "varying"))
}

// knownImprovement explains a difference between the prototype's output want
// and the library's output got for the same input with the improvements
// above, or returns "" when it cannot: the outputs must be the same text with
// "auth." inserted in different places, and each such place must be one of
// them. temp are the names of the temporary relations the prototype has
// learned. The result lists the improvements found.
func knownImprovement(want, got string, temp map[string]bool) string {
	ws, wi := insertions(want)
	gs, gi := insertions(got)
	if ws != gs {
		// the library writes a body in quotes that it changes again in dollar
		// quotes, the prototype leaves a body it does not change as it was
		want, got = singleQuoted(want), singleQuoted(got)
		ws, wi = insertions(want)
		gs, gi = insertions(got)
		if ws != gs {
			return ""
		}
	}
	kinds := map[string]bool{}
	// the places only one side has
	only := func(a, b []insertion) []insertion {
		var out []insertion
		for _, x := range a {
			if !slices.ContainsFunc(b, func(y insertion) bool { return y.at == x.at }) {
				out = append(out, x)
			}
		}
		return out
	}
	for _, x := range only(wi, gi) { // the prototype qualifies, the library does not
		if !isBuiltinType(x.name) && !isBuiltinFunction(x.name) {
			return ""
		}
		kinds[improvementBuiltin] = true
	}
	for _, x := range only(gi, wi) { // the library qualifies, the prototype does not
		switch {
		case temp[x.name]:
			kinds[improvementTempScope] = true
		case x.pos > 0 && underNestedCast(got[x.pos:]) && strings.TrimRight(got[:x.pos], " \t\n") != "" &&
			strings.HasSuffix(strings.TrimRight(got[:x.pos], " \t\n"), "'"):
			kinds[improvementNestedCast] = true
		default:
			return ""
		}
	}
	if len(kinds) == 0 {
		return ""
	}
	var out []string
	for k := range kinds {
		out = append(out, k)
	}
	sort.Strings(out)
	return strings.Join(out, ", ")
}

// singleQuoted writes every dollar-quoted literal of s in single quotes.
func singleQuoted(s string) string {
	var b strings.Builder
	for i := 0; i < len(s); {
		if s[i] == '$' && (i == 0 || !isIdentChar(s[i-1])) {
			if tag, ok := dollarTag(s[i:]); ok {
				if end := strings.Index(s[i+len(tag):], tag); end >= 0 {
					body := s[i+len(tag) : i+len(tag)+end]
					b.WriteString("'" + strings.ReplaceAll(body, "'", "''") + "'")
					i += 2*len(tag) + end
					continue
				}
			}
		}
		b.WriteByte(s[i])
		i++
	}
	return b.String()
}

// dollarTag returns the $tag$ at the start of s.
func dollarTag(s string) (string, bool) {
	for i := 1; i < len(s); i++ {
		switch {
		case s[i] == '$':
			return s[:i+1], true
		case !isIdentChar(s[i]) || i == 1 && s[i] >= '0' && s[i] <= '9':
			return "", false
		}
	}
	return "", false
}

func isIdentChar(c byte) bool {
	return c == '_' || c >= '0' && c <= '9' || c >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z' || c >= 0x80
}

// tempInText finds CREATE TEMP ... and SELECT ... INTO TEMP in text, also in
// function bodies, which the parse tree has as strings.
var tempInText = regexp.MustCompile(`(?is)\b(?:create\s+(?:(?:global|local)\s+)?temp(?:orary)?\s+(?:recursive\s+)?(?:table|view|sequence)|into\s+temp(?:orary)?(?:\s+table)?)\s+(?:if\s+not\s+exists\s+)?("(?:[^"]|"")+"|[a-z_\x80-\xff][\w$\x80-\xff]*)`)

// tempNames adds the names of the temporary relations the statements create,
// as the prototype learns them: in the statements and in their bodies.
func tempNames(into map[string]bool, sqls ...string) {
	for _, sql := range sqls {
		for _, m := range tempInText.FindAllStringSubmatch(sql, -1) {
			into[nameAt(m[1])] = true
		}
		stmts, err := parse.Parse(sql)
		if err != nil {
			continue
		}
		var visit func(n pgast.Node)
		visit = func(n pgast.Node) {
			if rv, ok := n.(*pgast.RangeVar); ok && rv != nil && rv.Relpersistence == "t" {
				into[rv.Relname] = true
			}
			n.Children(func(c pgast.Node) {
				if c != nil {
					visit(c)
				}
			})
		}
		for _, s := range stmts {
			visit(s)
		}
	}
}

// The names of pg_catalog come from the library's generated file, read as Go
// source: the lists are unexported, and they were read from live servers.
var (
	builtinsOnce              sync.Once
	builtinTypes, builtinFunc map[string]bool
)

func loadBuiltins() {
	builtinsOnce.Do(func() {
		builtinTypes, builtinFunc = map[string]bool{}, map[string]bool{}
		f, err := parser.ParseFile(token.NewFileSet(), "../builtins_gen.go", nil, 0)
		if err != nil {
			panic(err)
		}
		for _, d := range f.Decls {
			g, ok := d.(*ast.GenDecl)
			if !ok {
				continue
			}
			for _, s := range g.Specs {
				v, ok := s.(*ast.ValueSpec)
				if !ok || len(v.Values) != 1 {
					continue
				}
				into := map[string]map[string]bool{"builtinTypes": builtinTypes, "builtinFunctions": builtinFunc}[v.Names[0].Name]
				lit, ok := v.Values[0].(*ast.CompositeLit)
				if into == nil || !ok {
					continue
				}
				for _, e := range lit.Elts {
					if b, ok := e.(*ast.BasicLit); ok {
						into[strings.Trim(b.Value, `"`)] = true
					}
				}
			}
		}
		if len(builtinTypes) < 100 || len(builtinFunc) < 1000 {
			panic("builtins_gen.go: the lists are not where they were")
		}
	})
}

func isBuiltinType(name string) bool     { loadBuiltins(); return builtinTypes[name] }
func isBuiltinFunction(name string) bool { loadBuiltins(); return builtinFunc[name] }

func TestKnownImprovement(t *testing.T) {
	temp := map[string]bool{"tmp": true}
	tests := []struct{ want, got, kind string }{
		{"SELECT auth.round(price, 2) FROM auth.items", "SELECT round(price, 2) FROM auth.items", improvementBuiltin},
		{"CREATE TABLE auth.p (name auth.text)", "CREATE TABLE auth.p (name text)", improvementBuiltin},
		{"SELECT 'auth.text'::regtype", "SELECT 'text'::regtype", improvementBuiltin},
		{"SELECT nextval(('s'::text)::regclass)", "SELECT nextval(('auth.s'::text)::regclass)", improvementNestedCast},
		{"SELECT 's'::text::regclass", "SELECT 'auth.s'::text::regclass", improvementNestedCast},
		{"INSERT INTO tmp VALUES (1)", "INSERT INTO auth.tmp VALUES (1)", improvementTempScope},
		{"SELECT auth.f(1) FROM tmp", "SELECT f(1) FROM tmp", ""},                 // not a built-in
		{"SELECT * FROM t", "SELECT * FROM auth.t", ""},                           // not temporary
		{"SELECT 's'::regclass", "SELECT 'auth.s'::regclass", ""},                 // one cast: both qualify it
		{"SELECT ('s'::name)::regclass", "SELECT ('auth.s'::name)::regclass", ""}, // not a cast to text
		{"SELECT auth.round(1)", "SELECT round(2)", ""},
		{"CREATE FUNCTION auth.f() RETURNS int AS 'SELECT 1 FROM tmp WHERE a = ''x''' LANGUAGE sql",
			"CREATE FUNCTION auth.f() RETURNS int AS $$SELECT 1 FROM auth.tmp WHERE a = 'x'$$ LANGUAGE sql", improvementTempScope},
		{"CREATE FUNCTION auth.f() RETURNS int AS 'SELECT 1 FROM t' LANGUAGE sql",
			"CREATE FUNCTION auth.f() RETURNS int AS $$SELECT 1 FROM auth.t$$ LANGUAGE sql", ""}, // another text
	}
	for _, tc := range tests {
		if got := knownImprovement(tc.want, tc.got, temp); got != tc.kind {
			t.Errorf("%q / %q: %q, want %q", tc.want, tc.got, got, tc.kind)
		}
	}
	names := map[string]bool{}
	tempNames(names, "CREATE TEMP TABLE a (id int); CREATE TABLE b (id int); SELECT 1 INTO TEMP c; CREATE TEMPORARY VIEW d AS SELECT 1; DO $$ BEGIN CREATE TEMP TABLE e (id int); END $$")
	if len(names) != 4 || !names["a"] || !names["c"] || !names["d"] || !names["e"] {
		t.Errorf("temp names %v", names)
	}
}
