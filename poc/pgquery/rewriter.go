// Package pgqrewrite qualifies unqualified object names in PostgreSQL
// migrations with a target schema. It is a proof of concept built on
// github.com/wasilibs/go-pgquery: libpg_query (the parser of PostgreSQL
// itself) compiled to WebAssembly and executed by wazero, so no cgo is needed.
//
// The rewriter never regenerates SQL. It finds the names to qualify in the
// parse tree and inserts "schema." into the original text at the token
// offsets reported by the parser, so comments, formatting and quoting stay as
// written. Every rewrite is verified: the output is parsed again and its tree
// must equal the input tree with the intended names qualified.
//
// Rules:
//   - names of objects being created, altered, dropped, commented or granted
//     are always qualified;
//   - relation references are qualified unless they are CTE names in scope,
//     temporary tables, trigger transition tables, pg_* catalogs or excluded
//     by Options.ExcludeRelations;
//   - type and function references are qualified only when the type or
//     function is created by the migrations (built-in and extension objects
//     stay as they are);
//   - string literals that name relations (nextval('seq'), 'tbl'::regclass,
//     pg_get_serial_sequence('tbl', ...)) are qualified inside the literal;
//   - SQL inside SQL and PL/pgSQL function bodies and DO blocks is rewritten
//     with the same rules; dynamic SQL (EXECUTE) is reported as a warning.
package pgqrewrite

import (
	"errors"
	"fmt"
	"strings"

	pg "github.com/pganalyze/pg_query_go/v6"
	pgquery "github.com/wasilibs/go-pgquery"
	"google.golang.org/protobuf/encoding/protojson"
	"google.golang.org/protobuf/proto"
	"google.golang.org/protobuf/reflect/protoreflect"
)

// Options configures a Rewriter.
type Options struct {
	// Schema is the target schema, e.g. "auth".
	Schema string
	// ExcludeRelations lists relation names that live in other schemas and
	// are referenced without a schema on purpose.
	ExcludeRelations []string
}

// Rewriter rewrites migrations of one schema. It remembers the objects
// created by the migrations it has seen (Learn or Rewrite), because type and
// function references are qualified only for known objects.
type Rewriter struct {
	schema  string
	prefix  string
	exclude map[string]bool
	reg     *registry
}

// New creates a Rewriter.
func New(opts Options) (*Rewriter, error) {
	if opts.Schema == "" {
		return nil, errors.New("schema is required")
	}
	r := &Rewriter{
		schema:  opts.Schema,
		prefix:  quoteIdent(opts.Schema) + ".",
		exclude: map[string]bool{},
		reg:     newRegistry(),
	}
	for _, n := range opts.ExcludeRelations {
		r.exclude[n] = true
	}
	return r, nil
}

// Learn registers the objects created by a migration without rewriting it.
func (r *Rewriter) Learn(sql string) error {
	_, err := r.analyze(sql, false, true)
	return err
}

// Rewrite returns the migration with schema-qualified names and warnings
// about constructs that cannot be rewritten statically.
func (r *Rewriter) Rewrite(sql string) (string, []string, error) {
	if err := r.Learn(sql); err != nil {
		return "", nil, err
	}
	a, err := r.analyze(sql, false, false)
	if err != nil {
		return "", nil, err
	}
	out, err := applyEdits(sql, a.edits)
	if err != nil {
		return "", nil, err
	}
	warns := a.warns
	if err := r.checkPLpgSQL(out); err != nil {
		// Every embedded statement has been verified already, so a body
		// libpg_query cannot compile without a catalog is only reported.
		warns = append(warns, fmt.Sprintf("libpg_query cannot re-check the rewritten PL/pgSQL: %v", err))
	}
	return out, dedupe(warns), nil
}

type analysis struct {
	edits []edit
	warns []string
}

// analyze parses src, collects edits and verifies them.
func (r *Rewriter) analyze(src string, inBody, learnOnly bool) (*analysis, error) {
	tree, err := pgquery.Parse(src)
	if err != nil {
		return nil, err
	}
	toks, err := scanTokens(src)
	if err != nil {
		return nil, err
	}
	w := &walker{r: r, src: src, toks: toks, inBody: inBody, learnOnly: learnOnly, done: map[proto.Message]bool{}}
	for _, raw := range tree.Stmts {
		w.beginStmt(raw)
		w.visit(raw.Stmt.ProtoReflect())
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
	if err := verify(tree, out); err != nil {
		return nil, err
	}
	return &analysis{edits: w.edits, warns: w.warns}, nil
}

// verify parses the output and compares it with the input tree in which the
// walker has already qualified the names it edited.
func verify(want *pg.ParseResult, out string) error {
	got, err := pgquery.Parse(out)
	if err != nil {
		return fmt.Errorf("verification: rewritten SQL does not parse: %w", err)
	}
	clearLocations(want.ProtoReflect())
	clearLocations(got.ProtoReflect())
	if proto.Equal(want, got) {
		return nil
	}
	if len(want.Stmts) != len(got.Stmts) {
		return fmt.Errorf("verification: statement count changed from %d to %d", len(want.Stmts), len(got.Stmts))
	}
	for i := range want.Stmts {
		if !proto.Equal(want.Stmts[i], got.Stmts[i]) {
			w, _ := protojson.Marshal(want.Stmts[i])
			g, _ := protojson.Marshal(got.Stmts[i])
			return fmt.Errorf("verification: statement %d differs:\nwant %s\ngot  %s", i+1, w, g)
		}
	}
	return errors.New("verification: trees differ")
}

func clearLocations(m protoreflect.Message) {
	var clear []protoreflect.FieldDescriptor
	m.Range(func(fd protoreflect.FieldDescriptor, v protoreflect.Value) bool {
		switch {
		case fd.Name() == "location" || fd.Name() == "stmt_location" || fd.Name() == "stmt_len":
			clear = append(clear, fd)
		case fd.Kind() == protoreflect.MessageKind && fd.IsList():
			l := v.List()
			for i := 0; i < l.Len(); i++ {
				clearLocations(l.Get(i).Message())
			}
		case fd.Kind() == protoreflect.MessageKind && !fd.IsMap():
			clearLocations(v.Message())
		}
		return true
	})
	for _, fd := range clear {
		m.Clear(fd)
	}
}

// checkPLpgSQL makes sure every PL/pgSQL body of sql still parses. Composite
// variables are declared as "record" for the check, as in plpgsqlBody.
func (r *Rewriter) checkPLpgSQL(sql string) error {
	tree, err := pgquery.Parse(sql)
	if err != nil {
		return err
	}
	parse := func(body string, wrap func(body string) string) error {
		_, err := pgquery.ParsePlPgSqlToJSON(wrap(body))
		if err == nil {
			return nil
		}
		if mod, subs, ok := (&walker{r: r}).recordDecls(body); ok && len(subs) > 0 {
			if _, err2 := pgquery.ParsePlPgSqlToJSON(wrap(mod)); err2 == nil {
				return nil
			}
		}
		return err
	}
	for _, raw := range tree.Stmts {
		start := int(raw.StmtLocation)
		end := len(sql)
		if raw.StmtLen > 0 {
			end = start + int(raw.StmtLen)
		}
		text := sql[start:end]
		switch s := raw.Stmt.Node.(type) {
		case *pg.Node_CreateFunctionStmt:
			n := s.CreateFunctionStmt
			as := defElem(n.Options, "as")
			items := as.GetArg().GetList().GetItems()
			if language(n.Options, "sql") != "plpgsql" || len(items) != 1 {
				continue
			}
			toks, err := scanTokens(text)
			if err != nil {
				return err
			}
			i := toks.findToken(toks.firstFrom(int(as.Location)-start), toks.len(), pg.Token_SCONST)
			if i < 0 {
				return fmt.Errorf("cannot locate function body literal")
			}
			lit := toks.list[i]
			wrap := func(body string) string { return text[:lit.Start] + dollarQuote(body) + text[lit.End:] }
			if err := parse(items[0].GetString_().GetSval(), wrap); err != nil {
				return err
			}
		case *pg.Node_DoStmt:
			if language(s.DoStmt.Args, "plpgsql") == "plpgsql" {
				body := defElem(s.DoStmt.Args, "as").GetArg().GetString_().GetSval()
				if err := parse(body, func(b string) string { return doWrapper + dollarQuote(b) }); err != nil {
					return err
				}
			}
		}
	}
	return nil
}

const doWrapper = "CREATE FUNCTION pg_temp.__do_block() RETURNS void LANGUAGE plpgsql AS "

// language returns the LANGUAGE option or def (plpgsql for DO, sql for
// functions with a SQL-standard body).
func language(opts []*pg.Node, def string) string {
	if d := defElem(opts, "language"); d != nil {
		return strings.ToLower(d.GetArg().GetString_().GetSval())
	}
	return def
}

func defElem(opts []*pg.Node, name string) *pg.DefElem {
	for _, o := range opts {
		if d := o.GetDefElem(); d != nil && d.Defname == name {
			return d
		}
	}
	return nil
}

func dedupe(in []string) []string {
	seen := map[string]bool{}
	var out []string
	for _, s := range in {
		if !seen[s] {
			seen[s] = true
			out = append(out, s)
		}
	}
	return out
}
