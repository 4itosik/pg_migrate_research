package pgschema

import "slices"

// registry remembers the objects the migrations create. Type and function
// names are qualified only when the migrations create them, so the registry
// is filled by Learn from all migrations before any of them is rewritten.
type registry struct {
	relations  map[string]bool // tables, views, sequences, indexes, composite types
	types      map[string]bool // enums, domains, composite and range types
	functions  map[string]bool // functions, procedures, aggregates
	temp       map[string]bool // temporary relations
	transition map[string]bool // trigger transition tables (REFERENCING ... AS name)

	// While a transaction is open the names put in the maps are journaled, so
	// that a body that cannot be rewritten leaves nothing behind.
	open    int
	journal []journalEntry
}

type journalEntry struct {
	set  map[string]bool
	name string
}

// put remembers name in set.
func (g *registry) put(set map[string]bool, name string) {
	if set[name] {
		return
	}
	set[name] = true
	if g.open > 0 {
		g.journal = append(g.journal, journalEntry{set, name})
	}
}

// begin opens a transaction; the result is the argument of end.
func (g *registry) begin() int {
	g.open++
	return len(g.journal)
}

// end closes the transaction opened at mark; without commit the names put
// since then are forgotten.
func (g *registry) end(mark int, commit bool) {
	if !commit {
		for _, e := range g.journal[mark:] {
			delete(e.set, e.name)
		}
		g.journal = g.journal[:mark]
	}
	if g.open--; g.open == 0 {
		g.journal = g.journal[:0]
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
