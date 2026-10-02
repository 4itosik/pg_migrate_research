package pgschema

import (
	"fmt"
	"sort"

	"github.com/4itosik/pg_migrate_research/pgschema/subst"
)

// extensionObjects are the names a PostgreSQL extension provides.
type extensionObjects struct {
	funcs []string // functions and aggregates
	types []string
	rels  []string // tables and views
	ops   bool     // the extension has operators
}

// schemaRef is a schema that a name gets: its name as it goes into the tree
// and the text inserted before the name.
type schemaRef struct {
	name   string
	prefix string
}

// extensionUse maps the names of the objects of the active extensions to the
// schema of the extension.
type extensionUse struct {
	funcs, types, rels map[string]*schemaRef
}

func newExtensionUse() *extensionUse {
	return &extensionUse{funcs: map[string]*schemaRef{}, types: map[string]*schemaRef{}, rels: map[string]*schemaRef{}}
}

// targetRef is the target schema as a schemaRef (the placeholder in a
// template).
func (r *Rewriter) targetRef() *schemaRef { return &schemaRef{name: r.schema, prefix: r.prefix} }

// schemaRefOf is the schema "name" as a schemaRef; "" is the target schema.
func (r *Rewriter) schemaRefOf(name string) (*schemaRef, error) {
	if name == "" {
		return r.targetRef(), nil
	}
	if err := subst.ValidSchema(name); err != nil {
		return nil, err
	}
	return &schemaRef{name: name, prefix: subst.QuoteIdent(name) + "."}, nil
}

// activateExtension makes the uses of the objects of the extension get the
// schema ref: the contrib objects the library knows and the names the caller
// gave. A name that an active extension has taken stays with the first one.
func (r *Rewriter) activateExtension(ext string, ref *schemaRef) {
	if r.activeExt[ext] {
		return
	}
	r.activeExt[ext] = true
	objs := contribObjects[ext]
	extra := r.extraObjects[ext]
	put := func(m map[string]*schemaRef, names []string) {
		for _, n := range names {
			if _, taken := m[n]; !taken {
				m[n] = ref
			}
		}
	}
	put(r.ext.funcs, objs.funcs)
	put(r.ext.funcs, extra)
	put(r.ext.types, objs.types)
	put(r.ext.types, extra)
	put(r.ext.rels, objs.rels)
}

// KnownExtensions lists the extensions whose object names the library knows:
// the extensions of PostgreSQL's contrib, as the servers of PostgreSQL 12-16
// report them. Options.Extensions accepts any name; for an extension that is
// not on the list the names come from Options.ExtensionObjects.
func KnownExtensions() []string {
	names := make([]string, 0, len(contribObjects))
	for n := range contribObjects {
		names = append(names, n)
	}
	sort.Strings(names)
	return names
}

// knowsExtension reports whether the library has names for the extension.
func (r *Rewriter) knowsExtension(ext string) bool {
	_, contrib := contribObjects[ext]
	return contrib || len(r.extraObjects[ext]) > 0
}

// extensionNames returns the names of the extensions in the options, sorted,
// so that the names they provide are taken in a fixed order.
func extensionNames(m map[string]string) []string {
	names := make([]string, 0, len(m))
	for n := range m {
		names = append(names, n)
	}
	sort.Strings(names)
	return names
}

// initExtensions activates the extensions named in the options.
func (r *Rewriter) initExtensions(opts Options) error {
	for _, ext := range extensionNames(opts.Extensions) {
		ref, err := r.schemaRefOf(opts.Extensions[ext])
		if err != nil {
			return fmt.Errorf("schema of extension %s: %w", ext, err)
		}
		r.configuredExt[ext] = ref
	}
	for ext, names := range opts.ExtensionObjects {
		r.extraObjects[ext] = append([]string(nil), names...)
	}
	for _, ext := range extensionNames(opts.Extensions) {
		r.activateExtension(ext, r.configuredExt[ext])
	}
	return nil
}
