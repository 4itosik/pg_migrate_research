package pgschema

import "slices"

// registry remembers the objects the migrations create. Type and function
// names are qualified only when the migrations create them, so the registry
// is filled by Learn from all migrations before any of them is rewritten.
type registry struct {
	relations  map[string]bool // tables, views, sequences, indexes, composite types
	types      map[string]bool // enums, domains, composite and range types
	functions  map[string]bool // functions, procedures, aggregates
	temp       map[string]bool // temporary relations of the text being analyzed
	transition map[string]bool // trigger transition tables (REFERENCING ... AS name)

	// While a transaction is open every change of the state of a Rewriter (the
	// names put in the maps, the extensions it activates) is journaled with
	// the function that undoes it, so that a call of Learn or Rewrite that
	// fails, or a body that cannot be rewritten, leaves nothing behind.
	open int
	undo []func()
}

// put remembers name in set.
func (g *registry) put(set map[string]bool, name string) {
	if set[name] {
		return
	}
	set[name] = true
	g.journal(func() { delete(set, name) })
}

// journal records the function that undoes a change, if a transaction is
// open.
func (g *registry) journal(undo func()) {
	if g.open > 0 {
		g.undo = append(g.undo, undo)
	}
}

// begin opens a transaction; the result is the argument of end.
func (g *registry) begin() int {
	g.open++
	return len(g.undo)
}

// end closes the transaction opened at mark; without commit the changes made
// since then are undone, the last one first.
func (g *registry) end(mark int, commit bool) {
	if !commit {
		for i := len(g.undo) - 1; i >= mark; i-- {
			g.undo[i]()
		}
		g.undo = g.undo[:mark]
	}
	if g.open--; g.open == 0 {
		g.undo = g.undo[:0]
	}
}

func newRegistry() *registry {
	return &registry{
		relations:  map[string]bool{},
		types:      map[string]bool{},
		functions:  map[string]bool{},
		temp:       map[string]bool{},
		transition: map[string]bool{},
	}
}

// isType reports whether name is a user type; tables are types too (row types).
func (g *registry) isType(name string) bool {
	return g.types[name] || g.relations[name]
}

type objKind int

const (
	kindNone objKind = iota
	kindRelation
	kindType
	kindFunction
)

func (g *registry) add(k objKind, name string) {
	switch k {
	case kindRelation:
		g.put(g.relations, name)
	case kindType:
		g.put(g.types, name)
	case kindFunction:
		g.put(g.functions, name)
	}
}

func (g *registry) addTemp(name string)       { g.put(g.temp, name) }
func (g *registry) addTransition(name string) { g.put(g.transition, name) }

// isBuiltinType reports whether pg_catalog has a type of the name on some
// server of PostgreSQL 12-16, or the grammar maps a type keyword of the name
// to one (builtins_gen.go).
func isBuiltinType(name string) bool {
	_, ok := slices.BinarySearch(builtinTypes, name)
	return ok
}

// isBuiltinFunction reports whether pg_catalog has a function, an aggregate or
// a procedure of the name on some server of PostgreSQL 12-16.
func isBuiltinFunction(name string) bool {
	_, ok := slices.BinarySearch(builtinFunctions, name)
	return ok
}
