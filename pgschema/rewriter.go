package pgschema

import (
	"errors"
	"fmt"
	"strings"

	"github.com/4itosik/pg_migrate_research/pgschema/internal/ast"
	"github.com/4itosik/pg_migrate_research/pgschema/internal/parse"
	"github.com/4itosik/pg_migrate_research/pgschema/subst"
)

// Options configures a Rewriter.
type Options struct {
	// Schema is the target schema, e.g. "auth".
	Schema string
	// Placeholder makes a template instead: the placeholder subst.Placeholder
	// stands where the schema would, and subst.Apply puts the schema in later,
	// with the same result as rewriting with the schema itself. Schema is then
	// ignored.
	Placeholder bool
	// ExcludeRelations lists relation names that live in other schemas and
	// are referenced without a schema on purpose. The names are SQL
	// identifiers as written in SQL: an unquoted name is folded to lower case
	// (Countries is countries), a name in double quotes is taken exactly
	// ("Countries"). A name with a schema is an error.
	ExcludeRelations []string
	// ExtensionsInSchema adds SCHEMA <schema> to CREATE EXTENSION statements
	// that have no SCHEMA clause, so that the extension's objects are created
	// in the target schema. Off by default: the extension then goes where the
	// server puts it (the first schema of search_path, usually public), shared
	// by the services of the database, and the statement gets a warning. An
	// extension exists once per database, so turn this on only if the
	// migrations of one service own it. After the CREATE EXTENSION the
	// unqualified uses of the functions and types of the extension get the
	// target schema (or the schema the statement names) if the library knows
	// their names: those of the contrib extensions and those of
	// ExtensionObjects; for another extension the statement gets a warning
	// that its uses are not rewritten.
	ExtensionsInSchema bool
	// Extensions says where the extensions are installed, by name: the value
	// is the schema, "" is the target schema. The unqualified uses in the
	// migrations of what such an extension provides, a function (crypt,
	// uuid_generate_v4) or a type (citext, hstore), get that schema. The
	// library knows the names of the extensions of PostgreSQL's contrib
	// (extensions_gen.go) without the names that the core has too
	// (gen_random_uuid, which belongs to the core since PostgreSQL 13); for
	// others, and for names it does not have, see ExtensionObjects. A
	// CREATE EXTENSION of such an extension that has no SCHEMA gets the
	// schema. An extension that is not listed is left as it was. The keys are
	// folded to lower case; an extension that the library does not know
	// (KnownExtensions) and that has no names in ExtensionObjects is an error.
	Extensions map[string]string
	// ExtensionObjects adds names of functions and types to the extensions
	// of Extensions (and to ExtensionsInSchema), by extension name. It is for
	// the extensions outside contrib. The keys are folded to lower case, the
	// names are SQL identifiers like those of ExcludeRelations. An extension
	// that is neither in Extensions nor covered by ExtensionsInSchema is an
	// error: its names would never be used.
	ExtensionObjects map[string][]string
}

// Rewriter qualifies the names in the migrations of one schema. It remembers
// the objects the migrations create (Learn or Rewrite), because type and
// function references are qualified only for known objects.
type Rewriter struct {
	schema      string
	prefix      string
	placeholder bool
	exclude     map[string]bool
	reg         *registry

	extensionsInSchema bool
	// extensions: the schema configured for an extension, the schema of each
	// active one (the names in ext point to it), the names the caller added
	configuredExt map[string]*schemaRef
	activeExt     map[string]*schemaRef
	ext           *extensionUse
	extraObjects  map[string][]string
}

// New creates a Rewriter. It returns an error for options that would be
// ignored or would not work: see Options.
func New(opts Options) (*Rewriter, error) {
	switch {
	case opts.Placeholder && opts.Schema != "":
		return nil, errors.New("Schema and Placeholder exclude each other: a template has the placeholder instead of the schema")
	case !opts.Placeholder && opts.Schema == subst.Placeholder:
		return nil, fmt.Errorf("schema %s is the placeholder of templates: set Placeholder instead", subst.Placeholder)
	}
	if opts.Placeholder {
		opts.Schema = subst.Placeholder
	}
	if opts.Schema == "" {
		return nil, errors.New("schema is required")
	}
	if !opts.Placeholder {
		if err := subst.ValidSchema(opts.Schema); err != nil {
			return nil, err
		}
	}
	r := &Rewriter{
		schema:      opts.Schema,
		prefix:      subst.QuoteIdent(opts.Schema) + ".",
		placeholder: opts.Placeholder,
		exclude:     map[string]bool{},
		reg:         newRegistry(),

		extensionsInSchema: opts.ExtensionsInSchema,
		configuredExt:      map[string]*schemaRef{},
		activeExt:          map[string]*schemaRef{},
		ext:                newExtensionUse(),
		extraObjects:       map[string][]string{},
	}
	if err := r.initExtensions(opts); err != nil {
		return nil, err
	}
	for _, n := range opts.ExcludeRelations {
		name, err := optionName(n)
		if err != nil {
			return nil, fmt.Errorf("ExcludeRelations: %w", err)
		}
		r.exclude[name] = true
	}
	return r, nil
}

// Learn registers the objects a migration creates, without rewriting it. Call
// it for every up migration before rewriting any of them: the type and
// function names a migration uses are qualified only when some migration
// creates them. With an error the Rewriter stays as it was.
func (r *Rewriter) Learn(sql string) (err error) {
	if err := r.checkInput(sql); err != nil {
		return err
	}
	tx := r.reg.begin()
	defer func() { r.reg.end(tx, err == nil) }()
	_, err = r.pass(sql, true)
	return err
}

// Rewrite returns the migration with schema-qualified names and warnings
// about constructs that cannot be rewritten statically. The result is the
// input with the schema inserted into the text: nothing else changes. It is
// parsed again and its tree must be the input tree with the intended names
// qualified, otherwise Rewrite returns an error instead of unverified SQL, and
// the Rewriter stays as it was: what the text creates is not learned.
func (r *Rewriter) Rewrite(sql string) (_ string, _ []string, err error) {
	if err := r.checkInput(sql); err != nil {
		return "", nil, err
	}
	tx := r.reg.begin()
	defer func() { r.reg.end(tx, err == nil) }()
	if _, err := r.pass(sql, true); err != nil {
		return "", nil, err
	}
	a, err := r.pass(sql, false)
	if err != nil {
		return "", nil, err
	}
	out, err := applyEdits(sql, a.edits)
	if err != nil {
		return "", nil, err
	}
	return out, dedupe(a.warns), nil
}

type analysis struct {
	edits []edit
	warns []string
}

// checkInput refuses a text that cannot be rewritten safely: in a template the
// placeholder must stand only where the rewriter put it, because subst.Apply
// replaces it everywhere, in comments and strings as well.
func (r *Rewriter) checkInput(sql string) error {
	if r.placeholder && strings.Contains(sql, subst.Placeholder) {
		return fmt.Errorf("the SQL already contains the placeholder %s, which would be replaced with the schema wherever it stands", subst.Placeholder)
	}
	return nil
}

// pass analyzes the text of a migration. The temporary relations it creates
// hide relations of the same name only in this text: they are forgotten before
// every pass.
func (r *Rewriter) pass(sql string, learnOnly bool) (*analysis, error) {
	r.reg.temp = map[string]bool{}
	return r.analyze(sql, false, learnOnly)
}

// analyze parses src, collects edits and verifies them. inBody is set for
// the text of a function body.
func (r *Rewriter) analyze(src string, inBody, learnOnly bool) (*analysis, error) {
	stmts, err := parse.Parse(src)
	if err != nil {
		return nil, err
	}
	w := &walker{r: r, src: src, inBody: inBody, learnOnly: learnOnly, done: map[ast.Node]bool{}, permanent: map[*ast.RangeVar]bool{}}
	for _, raw := range stmts {
		w.beginStmt(raw)
		w.visit(raw.Stmt)
		w.endStmt()
		if w.err != nil {
			if learnOnly {
				return &analysis{}, nil
			}
			return nil, w.err
		}
	}
	if learnOnly || len(w.edits) == 0 {
		return &analysis{warns: w.warns}, nil
	}
	out, err := applyEdits(src, w.edits)
	if err != nil {
		return nil, err
	}
	if err := verify(stmts, out); err != nil {
		return nil, err
	}
	return &analysis{edits: w.edits, warns: w.warns}, nil
}

// verify parses the output and compares it with the input tree in which the
// walker has already qualified the names it edited.
func verify(want []*ast.RawStmt, out string) error {
	got, err := parse.Parse(out)
	if err != nil {
		return fmt.Errorf("verification: the rewritten SQL does not parse: %w", err)
	}
	if len(want) != len(got) {
		return fmt.Errorf("verification: the number of statements changed from %d to %d", len(want), len(got))
	}
	for i := range want {
		// Equal first: it allocates nothing, Diff builds a path at every node
		// and is for the message only
		if ast.Equal(want[i], got[i]) {
			continue
		}
		return fmt.Errorf("verification: statement %d differs: %s", i+1, ast.Diff(want[i], got[i]))
	}
	return nil
}
