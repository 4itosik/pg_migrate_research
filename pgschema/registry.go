package pgschema

// registry remembers the objects the migrations create. Type and function
// names are qualified only when the migrations create them, so the registry
// is filled by Learn from all migrations before any of them is rewritten.
type registry struct {
	relations  map[string]bool // tables, views, sequences, indexes, composite types
	types      map[string]bool // enums, domains, composite and range types
	functions  map[string]bool // functions, procedures, aggregates
	temp       map[string]bool // temporary relations
	transition map[string]bool // trigger transition tables (REFERENCING ... AS name)
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
		g.relations[name] = true
	case kindType:
		g.types[name] = true
	case kindFunction:
		g.functions[name] = true
	}
}
