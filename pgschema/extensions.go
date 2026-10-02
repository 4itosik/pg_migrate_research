package pgschema

import (
	"errors"
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
	if name == subst.Placeholder {
		return nil, fmt.Errorf("%s is the placeholder of templates", name)
	}
	return &schemaRef{name: name, prefix: subst.QuoteIdent(name) + "."}, nil
}

// activateExtension makes the uses of the objects of the extension get the
// schema ref: the contrib objects the library knows and the names the caller
// gave. A name that an active extension has taken stays with the first one.
// An extension that is active already keeps its schema.
func (r *Rewriter) activateExtension(ext string, ref *schemaRef) {
	if r.activeExt[ext] != nil {
		return
	}
	// the names point to a schema of the extension's own, which moveExtension
	// changes for all of them
	ref = &schemaRef{name: ref.name, prefix: ref.prefix}
	r.activeExt[ext] = ref
	r.reg.journal(func() { delete(r.activeExt, ext) })
	objs := contribObjects[ext]
	extra := r.extraObjects[ext]
	put := func(m map[string]*schemaRef, names []string) {
		for _, n := range names {
			if _, taken := m[n]; !taken {
				m[n] = ref
				r.reg.journal(func() { delete(m, n) })
			}
		}
	}
	put(r.ext.funcs, objs.funcs)
	put(r.ext.funcs, extra)
	put(r.ext.types, objs.types)
	put(r.ext.types, extra)
	put(r.ext.rels, objs.rels)
}

// moveExtension makes the uses of the objects of the extension get the schema
// ref from now on, whether it is active or not: CREATE EXTENSION names the
// schema where the extension is.
func (r *Rewriter) moveExtension(ext string, ref *schemaRef) {
	cur := r.activeExt[ext]
	if cur == nil {
		r.activateExtension(ext, ref)
		return
	}
	old := *cur
	*cur = *ref
	r.reg.journal(func() { *cur = old })
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

// initExtensions checks the extensions named in the options and activates
// those of Extensions.
func (r *Rewriter) initExtensions(opts Options) error {
	schemas := map[string]string{}
	for key, schema := range opts.Extensions {
		ext := asciiLower(key)
		if ext == "" {
			return errors.New("Extensions: an empty extension name")
		}
		if _, dup := schemas[ext]; dup {
			return fmt.Errorf("Extensions: extension %s is given twice", ext)
		}
		schemas[ext] = schema
	}
	for key, names := range opts.ExtensionObjects {
		ext := asciiLower(key)
		if ext == "" {
			return errors.New("ExtensionObjects: an empty extension name")
		}
		if _, dup := r.extraObjects[ext]; dup {
			return fmt.Errorf("ExtensionObjects: extension %s is given twice", ext)
		}
		if _, ok := schemas[ext]; !ok && !opts.ExtensionsInSchema {
			return fmt.Errorf("ExtensionObjects: extension %s is not in Extensions and ExtensionsInSchema is off, so its names would never be used", ext)
		}
		list := make([]string, 0, len(names))
		for _, n := range names {
			name, err := optionName(n)
			if err != nil {
				return fmt.Errorf("ExtensionObjects of %s: %w", ext, err)
			}
			list = append(list, name)
		}
		r.extraObjects[ext] = list
	}
	for _, ext := range extensionNames(schemas) {
		if !r.knowsExtension(ext) {
			return fmt.Errorf("Extensions: the library does not know the objects of extension %s; give their names in ExtensionObjects", ext)
		}
		ref, err := r.schemaRefOf(schemas[ext])
		if err != nil {
			return fmt.Errorf("schema of extension %s: %w", ext, err)
		}
		r.configuredExt[ext] = ref
		r.activateExtension(ext, ref)
	}
	return nil
}

// optionName parses a name of the options as SQL writes it: unquoted it is
// folded to lower case, in double quotes it is taken exactly.
func optionName(s string) (string, error) {
	parts, ok := splitQualifiedName(s)
	switch {
	case !ok:
		return "", fmt.Errorf("%q is not a name", s)
	case len(parts) > 1:
		return "", fmt.Errorf("%q has a schema; give the name alone", s)
	}
	return parts[0], nil
}
