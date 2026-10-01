// Package mgrewrite is the same schema-qualifying rewriter as poc/pgquery,
// built on the pure Go PostgreSQL parser of multigres
// (github.com/multigres/multigres/go/common/parser, a goyacc port of gram.y
// and pl_gram.y).
//
// The multigres AST keeps no reliable source locations for names, so this
// rewriter changes the AST and regenerates the whole migration with the
// deparser of the library (SqlString). Comments and formatting are lost.
package mgrewrite

import (
	"errors"
	"fmt"
	"reflect"
	"strings"

	"github.com/multigres/multigres/go/common/parser"
	"github.com/multigres/multigres/go/common/parser/ast"
	"github.com/multigres/multigres/go/common/parser/ast/plpgsqlast"
	"github.com/multigres/multigres/go/common/parser/plpgsql"
)

// Options configures a Rewriter.
type Options struct {
	Schema           string
	ExcludeRelations []string
}

// Rewriter rewrites migrations of one schema.
type Rewriter struct {
	schema  string
	exclude map[string]bool
	reg     *registry
}

type registry struct {
	relations, types, functions, temp, transition map[string]bool
}

// New creates a Rewriter.
func New(opts Options) (*Rewriter, error) {
	if opts.Schema == "" {
		return nil, errors.New("schema is required")
	}
	r := &Rewriter{schema: opts.Schema, exclude: map[string]bool{}, reg: &registry{
		relations: map[string]bool{}, types: map[string]bool{}, functions: map[string]bool{},
		temp: map[string]bool{}, transition: map[string]bool{},
	}}
	for _, n := range opts.ExcludeRelations {
		r.exclude[n] = true
	}
	return r, nil
}

// Learn registers the objects created by a migration.
func (r *Rewriter) Learn(sql string) error {
	stmts, err := parser.ParseSQL(sql)
	if err != nil {
		return err
	}
	w := &walker{r: r, learnOnly: true}
	for _, s := range stmts {
		w.walk(s)
	}
	return nil
}

// Rewrite returns the regenerated migration with qualified names.
func (r *Rewriter) Rewrite(sql string) (string, []string, error) {
	if err := r.Learn(sql); err != nil {
		return "", nil, err
	}
	stmts, err := parser.ParseSQL(sql)
	if err != nil {
		return "", nil, err
	}
	w := &walker{r: r}
	for _, s := range stmts {
		w.walk(s)
		if w.err != nil {
			return "", nil, w.err
		}
	}
	out := deparse(stmts, ";\n")
	again, err := parser.ParseSQL(out)
	if err != nil {
		return "", nil, fmt.Errorf("deparsed SQL does not parse: %w", err)
	}
	if deparse(again, ";\n") != out {
		w.warns = append(w.warns, "deparse is not a fixpoint (parse(deparse(x)) != x)")
	}
	return out, dedupe(w.warns), nil
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

// deparse regenerates statements: a migration file gets ";\n" after every
// statement, an embedded body is joined with "; ".
func deparse(stmts []ast.Stmt, sep string) string {
	parts := make([]string, len(stmts))
	for i, s := range stmts {
		parts[i] = s.SqlString()
	}
	if sep == ";\n" {
		return strings.Join(parts, sep) + sep
	}
	return strings.Join(parts, sep)
}

// ---- walker ----------------------------------------------------------------

type walker struct {
	r         *Rewriter
	inBody    bool
	learnOnly bool
	warns     []string
	err       error
	scopes    []map[string]bool
}

func (w *walker) fail(format string, args ...any) {
	if w.err == nil {
		w.err = fmt.Errorf(format, args...)
	}
}

func (w *walker) warn(format string, args ...any) {
	if !w.learnOnly {
		w.warns = append(w.warns, fmt.Sprintf(format, args...))
	}
}

func (w *walker) walk(n ast.Node) {
	if w.err != nil || isNil(n) {
		return
	}
	if w.handle(n) {
		return
	}
	w.children(n)
}

func isNil(n any) bool {
	if n == nil {
		return true
	}
	v := reflect.ValueOf(n)
	return (v.Kind() == reflect.Ptr || v.Kind() == reflect.Interface) && v.IsNil()
}

// children visits all exported fields that hold AST nodes.
func (w *walker) children(n ast.Node, skip ...string) {
	v := reflect.ValueOf(n)
	if v.Kind() == reflect.Ptr {
		v = v.Elem()
	}
	if v.Kind() != reflect.Struct {
		return
	}
	t := v.Type()
next:
	for i := 0; i < v.NumField(); i++ {
		sf := t.Field(i)
		if sf.Anonymous || !sf.IsExported() {
			continue
		}
		for _, s := range skip {
			if sf.Name == s {
				continue next
			}
		}
		w.value(v.Field(i))
	}
}

func (w *walker) value(f reflect.Value) {
	switch f.Kind() {
	case reflect.Interface, reflect.Ptr:
		if f.IsNil() {
			return
		}
		if node, ok := f.Interface().(ast.Node); ok {
			w.walk(node)
		}
	case reflect.Slice:
		for j := 0; j < f.Len(); j++ {
			w.value(f.Index(j))
		}
	}
}

func (w *walker) handle(n ast.Node) bool {
	switch n := n.(type) {
	case *ast.RangeVar:
		w.rangeVar(n, true)
	case *ast.TypeName:
		w.typeName(n, false)
	case *ast.FuncCall:
		w.funcCall(n)
	case *ast.TypeCast:
		w.typeCast(n)

	case *ast.SelectStmt:
		w.with(n.WithClause, func() { w.children(n, "WithClause") })
		return true
	case *ast.InsertStmt:
		w.rangeVar(n.Relation, false)
		w.with(n.WithClause, func() { w.children(n, "Relation", "WithClause") })
		return true
	case *ast.UpdateStmt:
		w.rangeVar(n.Relation, false)
		w.with(n.WithClause, func() { w.children(n, "Relation", "WithClause") })
		return true
	case *ast.DeleteStmt:
		w.rangeVar(n.Relation, false)
		w.with(n.WithClause, func() { w.children(n, "Relation", "WithClause") })
		return true
	case *ast.MergeStmt:
		w.rangeVar(n.Relation, false)
		w.with(n.WithClause, func() { w.children(n, "Relation", "WithClause") })
		return true

	case *ast.LockingClause:
		return true // FOR UPDATE OF t names FROM items and must stay unqualified
	case *ast.CreateStmt:
		w.register(n.Relation, w.r.reg.relations)
	case *ast.IntoClause:
		w.register(n.Rel, w.r.reg.relations)
	case *ast.ViewStmt:
		w.register(n.View, w.r.reg.relations)
	case *ast.CreateSeqStmt:
		w.register(n.Sequence, w.r.reg.relations)
		w.ownedBy(n.Options)
	case *ast.AlterSeqStmt:
		w.ownedBy(n.Options)
	case *ast.CompositeTypeStmt:
		w.register(n.Typevar, w.r.reg.relations)
		w.register(n.Typevar, w.r.reg.types)
	case *ast.CreateEnumStmt:
		w.defName(n.TypeName, w.r.reg.types)
	case *ast.CreateRangeStmt:
		w.defName(n.TypeName, w.r.reg.types)
	case *ast.CreateDomainStmt:
		w.defName(n.Domainname, w.r.reg.types)
	case *ast.AlterEnumStmt:
		w.defName(n.TypeName, nil)
	case *ast.AlterDomainStmt:
		w.defName(n.TypeName, nil)
	case *ast.AlterTypeStmt:
		w.defName(n.TypeName, nil)
	case *ast.DefineStmt:
		switch n.Kind {
		case ast.OBJECT_TYPE:
			w.defName(n.DefNames, w.r.reg.types)
		case ast.OBJECT_AGGREGATE:
			w.defName(n.DefNames, w.r.reg.functions)
		case ast.OBJECT_COLLATION:
			w.defName(n.DefNames, nil)
		}
	case *ast.CreateStatsStmt:
		w.defName(n.DefNames, nil)
	case *ast.AlterStatsStmt:
		w.defName(n.DefNames, nil)

	case *ast.CreateFunctionStmt:
		w.createFunction(n)
	case *ast.DoStmt:
		w.doStmt(n)
	case *ast.CreateTriggerStmt:
		if n.Transitions != nil {
			for _, it := range n.Transitions.Items {
				if t, ok := it.(*ast.TriggerTransition); ok {
					w.r.reg.transition[t.Name] = true
				}
			}
		}
		w.usedFunction(n.Funcname)
	case *ast.CreateEventTrigStmt:
		w.usedFunction(n.FuncName)
	case *ast.CreateCastStmt:
		if n.Func != nil {
			w.objectWithArgs(n.Func, false)
		}
	case *ast.AlterFunctionStmt:
		w.objectWithArgs(n.Func, true)

	case *ast.DropStmt:
		if n.Objects != nil && len(n.Objects.Items) > 0 {
			if _, flat := n.Objects.Items[0].(*ast.String); flat {
				// multigres keeps DROP TRIGGER/RULE/POLICY ... ON t as a flat
				// [t, name] list, unlike PostgreSQL's list of lists
				w.objectRef(n.RemoveType, n.Objects)
				break
			}
			for _, o := range n.Objects.Items {
				w.objectRef(n.RemoveType, o)
			}
		}
	case *ast.CommentStmt:
		w.objectRef(n.Objtype, n.Object)
	case *ast.RenameStmt:
		switch {
		case isRelationType(n.RenameType):
			if n.Relation != nil && (n.Relation.SchemaName == "" || n.Relation.SchemaName == w.r.schema) {
				w.r.reg.relations[n.Newname] = true
			}
		case n.RenameType == ast.OBJECT_TYPE || n.RenameType == ast.OBJECT_DOMAIN:
			w.r.reg.types[n.Newname] = true
			w.objectRef(n.RenameType, n.Object)
		case isFunctionType(n.RenameType):
			w.r.reg.functions[n.Newname] = true
			w.objectRef(n.RenameType, n.Object)
		}
	case *ast.AlterOwnerStmt:
		w.objectRef(n.ObjectType, n.Object)
	case *ast.AlterObjectSchemaStmt:
		w.objectRef(n.ObjectType, n.Object)
	case *ast.GrantStmt:
		if n.Targtype == ast.ACL_TARGET_OBJECT && !isRelationType(n.Objtype) && n.Objects != nil {
			for _, o := range n.Objects.Items {
				w.objectRef(n.Objtype, o)
			}
		}
	case *ast.CreateExtensionStmt:
		if defElem(n.Options, "schema") == nil {
			w.warn("CREATE EXTENSION without SCHEMA: %s", n.Extname)
		}
	case *ast.VariableSetStmt:
		if strings.EqualFold(n.Name, "search_path") {
			w.warn("migration changes search_path")
		}
	}
	return false
}

// ---- rules (same as poc/pgquery) ---------------------------------------------

func (w *walker) shouldQualifyRelation(name string, cteCheck bool) bool {
	switch {
	case name == "":
		return false
	case cteCheck && w.inCTE(name):
		return false
	case w.r.reg.temp[name], strings.HasPrefix(name, "pg_"), w.r.exclude[name]:
		return false
	case w.inBody && w.r.reg.transition[name]:
		return false
	}
	return true
}

func (w *walker) isType(name string) bool { return w.r.reg.types[name] || w.r.reg.relations[name] }

func (w *walker) rangeVar(rv *ast.RangeVar, cteCheck bool) {
	if rv == nil || rv.SchemaName != "" || rv.CatalogName != "" {
		return
	}
	if rv.RelPersistence == 't' {
		w.r.reg.temp[rv.RelName] = true
		return
	}
	if !w.learnOnly && w.shouldQualifyRelation(rv.RelName, cteCheck) {
		rv.SchemaName = w.r.schema
	}
}

func (w *walker) register(rv *ast.RangeVar, set map[string]bool) {
	if rv == nil {
		return
	}
	if rv.RelPersistence == 't' {
		w.r.reg.temp[rv.RelName] = true
		return
	}
	if rv.SchemaName == "" || rv.SchemaName == w.r.schema {
		set[rv.RelName] = true
	}
}

func (w *walker) typeName(tn *ast.TypeName, definition bool) {
	names := strs(tn.Names)
	if len(names) == 0 || w.learnOnly {
		return
	}
	if tn.PctType {
		if len(names) == 2 && w.shouldQualifyRelation(names[0], false) {
			w.qualify(tn.Names)
		}
		return
	}
	if len(names) == 1 && (definition || w.isType(names[0])) {
		w.qualify(tn.Names)
	}
}

var relationArgFunctions = map[string]bool{
	"nextval": true, "currval": true, "setval": true, "pg_get_serial_sequence": true,
	"to_regclass": true, "pg_relation_size": true, "pg_total_relation_size": true,
	"pg_table_size": true, "pg_indexes_size": true,
}

func (w *walker) funcCall(fc *ast.FuncCall) {
	names := strs(fc.Funcname)
	if len(names) == 0 {
		return
	}
	base := names[len(names)-1]
	if (len(names) == 1 || names[0] == "pg_catalog") && relationArgFunctions[base] && fc.Args != nil && len(fc.Args.Items) > 0 {
		arg := fc.Args.Items[0]
		if tc, ok := arg.(*ast.TypeCast); ok {
			arg = tc.Arg
		}
		w.literal(arg, func(n string) bool { return w.shouldQualifyRelation(n, false) })
	}
	if len(names) == 1 && w.r.reg.functions[base] && !w.learnOnly {
		w.qualify(fc.Funcname)
	}
}

func (w *walker) typeCast(tc *ast.TypeCast) {
	if tc.TypeName == nil {
		return
	}
	names := strs(tc.TypeName.Names)
	if len(names) == 0 {
		return
	}
	switch names[len(names)-1] {
	case "regclass":
		w.literal(tc.Arg, func(n string) bool { return w.shouldQualifyRelation(n, false) })
	case "regtype":
		w.literal(tc.Arg, w.isType)
	case "regproc", "regprocedure":
		w.literal(tc.Arg, func(n string) bool { return w.r.reg.functions[n] })
	}
}

func (w *walker) literal(n ast.Node, qualify func(string) bool) {
	c, ok := n.(*ast.A_Const)
	if !ok || w.learnOnly {
		return
	}
	s, ok := c.Val.(*ast.String)
	if !ok || strings.HasPrefix(s.SVal, w.r.schema+".") {
		return
	}
	head := s.SVal
	if i := strings.IndexByte(head, '('); i >= 0 {
		head = head[:i]
	}
	head = strings.TrimSpace(head)
	if strings.ContainsAny(head, `."`) || !qualify(strings.ToLower(head)) {
		return
	}
	s.SVal = quoteIdent(w.r.schema) + "." + strings.TrimSpace(s.SVal)
}

func (w *walker) usedFunction(l *ast.NodeList) {
	names := strs(l)
	if len(names) == 1 && w.r.reg.functions[names[0]] && !w.learnOnly {
		w.qualify(l)
	}
}

func (w *walker) defName(l *ast.NodeList, set map[string]bool) {
	names := strs(l)
	if len(names) == 0 {
		return
	}
	if set != nil && (len(names) == 1 || (len(names) == 2 && names[0] == w.r.schema)) {
		set[names[len(names)-1]] = true
	}
	if len(names) == 1 && !w.learnOnly {
		w.qualify(l)
	}
}

func (w *walker) objectRef(objtype ast.ObjectType, obj ast.Node) {
	if w.learnOnly || isNil(obj) {
		return
	}
	switch o := obj.(type) {
	case *ast.TypeName:
		w.typeName(o, true)
		return
	case *ast.ObjectWithArgs:
		w.objectWithArgs(o, true)
		return
	case *ast.NodeList:
		parts := strs(o)
		if len(parts) == 0 {
			return
		}
		switch {
		case objtype == ast.OBJECT_TRIGGER || objtype == ast.OBJECT_POLICY || objtype == ast.OBJECT_RULE || objtype == ast.OBJECT_TABCONSTRAINT:
			if len(parts) == 2 && w.shouldQualifyRelation(parts[0], false) {
				w.qualify(o)
			}
		case objtype == ast.OBJECT_COLUMN:
			if len(parts) == 2 && w.shouldQualifyRelation(parts[0], false) {
				w.qualify(o)
			}
		case isRelationType(objtype):
			if len(parts) == 1 && w.shouldQualifyRelation(parts[0], false) {
				w.qualify(o)
			}
		case objtype == ast.OBJECT_TYPE, objtype == ast.OBJECT_DOMAIN, objtype == ast.OBJECT_STATISTIC_EXT, objtype == ast.OBJECT_COLLATION:
			if len(parts) == 1 {
				w.qualify(o)
			}
		}
	}
}

func (w *walker) objectWithArgs(o *ast.ObjectWithArgs, definition bool) {
	names := strs(o.Objname)
	if len(names) == 1 && !w.learnOnly && (definition || w.r.reg.functions[names[0]]) {
		w.qualify(o.Objname)
	}
}

func (w *walker) ownedBy(opts *ast.NodeList) {
	d := defElem(opts, "owned_by")
	if d == nil || w.learnOnly {
		return
	}
	if l, ok := d.Arg.(*ast.NodeList); ok {
		if parts := strs(l); len(parts) == 2 && w.shouldQualifyRelation(parts[0], false) {
			w.qualify(l)
		}
	}
}

// ---- CTE scopes -------------------------------------------------------------

func (w *walker) inCTE(name string) bool {
	for _, s := range w.scopes {
		if s[name] {
			return true
		}
	}
	return false
}

func (w *walker) push(names []string) {
	s := map[string]bool{}
	for _, n := range names {
		s[n] = true
	}
	w.scopes = append(w.scopes, s)
}

func (w *walker) pop() { w.scopes = w.scopes[:len(w.scopes)-1] }

func (w *walker) with(wc *ast.WithClause, rest func()) {
	if wc == nil || wc.Ctes == nil {
		rest()
		return
	}
	var names []string
	for _, c := range wc.Ctes.Items {
		if cte, ok := c.(*ast.CommonTableExpr); ok {
			names = append(names, cte.Ctename)
		}
	}
	if wc.Recursive {
		w.push(names)
		for _, c := range wc.Ctes.Items {
			w.walk(c)
		}
		rest()
		w.pop()
		return
	}
	for i, c := range wc.Ctes.Items {
		w.push(names[:i])
		w.walk(c)
		w.pop()
	}
	w.push(names)
	rest()
	w.pop()
}

// ---- helpers -----------------------------------------------------------------

func strs(l *ast.NodeList) []string {
	if l == nil {
		return nil
	}
	out := make([]string, 0, len(l.Items))
	for _, it := range l.Items {
		s, ok := it.(*ast.String)
		if !ok {
			return nil
		}
		out = append(out, s.SVal)
	}
	return out
}

func (w *walker) qualify(l *ast.NodeList) {
	l.Items = append([]ast.Node{ast.NewString(w.r.schema)}, l.Items...)
}

func defElem(opts *ast.NodeList, name string) *ast.DefElem {
	if opts == nil {
		return nil
	}
	for _, o := range opts.Items {
		if d, ok := o.(*ast.DefElem); ok && d.Defname == name {
			return d
		}
	}
	return nil
}

func isRelationType(t ast.ObjectType) bool {
	switch t {
	case ast.OBJECT_TABLE, ast.OBJECT_VIEW, ast.OBJECT_MATVIEW, ast.OBJECT_SEQUENCE, ast.OBJECT_INDEX, ast.OBJECT_FOREIGN_TABLE:
		return true
	}
	return false
}

func isFunctionType(t ast.ObjectType) bool {
	switch t {
	case ast.OBJECT_FUNCTION, ast.OBJECT_PROCEDURE, ast.OBJECT_ROUTINE, ast.OBJECT_AGGREGATE:
		return true
	}
	return false
}

func quoteIdent(s string) string {
	for i, c := range s {
		if !(c == '_' || (c >= 'a' && c <= 'z') || (i > 0 && c >= '0' && c <= '9')) {
			return `"` + strings.ReplaceAll(s, `"`, `""`) + `"`
		}
	}
	return s
}

// ---- function bodies ----------------------------------------------------------

func (w *walker) createFunction(n *ast.CreateFunctionStmt) {
	w.defName(n.FuncName, w.r.reg.functions)
	as := defElem(n.Options, "as")
	if as == nil {
		return
	}
	var str *ast.String
	switch a := as.Arg.(type) {
	case *ast.String:
		str = a
	case *ast.NodeList:
		if len(a.Items) == 1 {
			str, _ = a.Items[0].(*ast.String)
		}
	}
	if str == nil {
		return
	}
	lang := "sql"
	if d := defElem(n.Options, "language"); d != nil {
		if s, ok := d.Arg.(*ast.String); ok {
			lang = strings.ToLower(s.SVal)
		}
	}
	var body string
	var err error
	switch lang {
	case "sql":
		body, err = w.sqlBody(str.SVal)
	case "plpgsql":
		body, err = w.plpgsqlBody(str.SVal, functionSeed(n))
	default:
		w.warn("LANGUAGE %s body is not rewritten", lang)
		return
	}
	if err != nil {
		w.fail("function %s: %v", strings.Join(strs(n.FuncName), "."), err)
		return
	}
	if !w.learnOnly {
		str.SVal = body
	}
}

func (w *walker) doStmt(n *ast.DoStmt) {
	as := defElem(n.Args, "as")
	if as == nil {
		return
	}
	str, ok := as.Arg.(*ast.String)
	if !ok {
		return
	}
	if d := defElem(n.Args, "language"); d != nil {
		if s, ok := d.Arg.(*ast.String); ok && !strings.EqualFold(s.SVal, "plpgsql") {
			w.warn("DO block in LANGUAGE %s is not rewritten", s.SVal)
			return
		}
	}
	body, err := w.plpgsqlBody(str.SVal, nil)
	if err != nil {
		w.fail("DO block: %v", err)
		return
	}
	if !w.learnOnly {
		str.SVal = body
	}
}

func functionSeed(n *ast.CreateFunctionStmt) *plpgsql.ParseSeed {
	seed := &plpgsql.ParseSeed{}
	if n.Parameters != nil {
		for i, p := range n.Parameters.Items {
			fp, ok := p.(*ast.FunctionParameter)
			if !ok {
				continue
			}
			seed.Scalars = append(seed.Scalars, fmt.Sprintf("$%d", i+1))
			if fp.Name != "" {
				seed.Scalars = append(seed.Scalars, strings.ToLower(fp.Name))
			}
		}
	}
	if n.ReturnType != nil {
		if names := strs(n.ReturnType.Names); len(names) > 0 {
			switch names[len(names)-1] {
			case "trigger":
				seed.Records = append(seed.Records, "new", "old")
				seed.Scalars = append(seed.Scalars, "tg_name", "tg_when", "tg_level", "tg_op", "tg_relid",
					"tg_relname", "tg_table_name", "tg_table_schema", "tg_nargs", "tg_argv")
			case "event_trigger":
				seed.Scalars = append(seed.Scalars, "tg_event", "tg_tag")
			}
		}
	}
	return seed
}

func (w *walker) sqlBody(body string) (string, error) {
	stmts, err := parser.ParseSQL(body)
	if err != nil {
		return "", err
	}
	sub := &walker{r: w.r, inBody: true, learnOnly: w.learnOnly}
	for _, s := range stmts {
		sub.walk(s)
	}
	w.warns = append(w.warns, sub.warns...)
	if sub.err != nil {
		return "", sub.err
	}
	return deparse(stmts, "; "), nil
}

// plpgsqlBody parses the body with the multigres PL/pgSQL parser, rewrites
// every embedded query and the declared types, and deparses the function.
func (w *walker) plpgsqlBody(body string, seed *plpgsql.ParseSeed) (string, error) {
	fn, err := plpgsql.ParsePLpgSQLSeeded(body, seed)
	if err != nil {
		return "", fmt.Errorf("PL/pgSQL parse error: %w", err)
	}
	vars := map[string]bool{}
	seen := map[uintptr]bool{} // datums are shared between statements
	var walkErr error
	var visit func(v reflect.Value)
	visit = func(v reflect.Value) {
		if walkErr != nil {
			return
		}
		switch v.Kind() {
		case reflect.Ptr, reflect.Interface:
			if v.IsNil() {
				return
			}
			if v.Kind() == reflect.Ptr {
				if seen[v.Pointer()] {
					return
				}
				seen[v.Pointer()] = true
			}
			switch n := v.Interface().(type) {
			case *plpgsqlast.PLpgSQL_stmt_perform:
				// multigres keeps the text after PERFORM, PostgreSQL turns it into SELECT
				if n.Expr != nil {
					q, err := w.rewriteExpr("SELECT "+n.Expr.Query, plpgsqlast.RAW_PARSE_DEFAULT)
					if err != nil {
						walkErr = fmt.Errorf("%q: %w", n.Expr.Query, err)
						return
					}
					if !w.learnOnly {
						n.Expr.Query = strings.TrimPrefix(q, "SELECT ")
					}
					seen[reflect.ValueOf(n.Expr).Pointer()] = true
				}
			case *plpgsqlast.PLpgSQL_expr:
				q, err := w.rewriteExpr(n.Query, n.ParseMode)
				if err != nil {
					walkErr = fmt.Errorf("%q: %w", n.Query, err)
					return
				}
				if !w.learnOnly {
					n.Query = q
				}
				return
			case *plpgsqlast.PLpgSQL_stmt_dynexecute, *plpgsqlast.PLpgSQL_stmt_dynfors:
				w.warn("dynamic SQL (EXECUTE) inside a function body or DO block is not rewritten")
			case *plpgsqlast.PLpgSQL_var:
				vars[strings.ToLower(n.Refname)] = true
				w.declType(n.DataType, vars)
			case *plpgsqlast.PLpgSQL_rec:
				vars[strings.ToLower(n.Refname)] = true
				w.declType(n.DataType, vars)
			}
			visit(v.Elem())
		case reflect.Struct:
			t := v.Type()
			for i := 0; i < v.NumField(); i++ {
				if t.Field(i).IsExported() {
					visit(v.Field(i))
				}
			}
		case reflect.Slice:
			for i := 0; i < v.Len(); i++ {
				visit(v.Index(i))
			}
		}
	}
	visit(reflect.ValueOf(fn))
	if walkErr != nil {
		return "", walkErr
	}
	return fn.SqlString(), nil
}

func (w *walker) declType(t *plpgsqlast.PLpgSQL_type, vars map[string]bool) {
	if t == nil || w.learnOnly {
		return
	}
	name := strings.TrimSpace(t.TypeName)
	upper := strings.ToUpper(name)
	var parts []string
	switch {
	case strings.HasSuffix(upper, "%ROWTYPE"):
		parts = strings.Split(name[:len(name)-8], ".")
		if len(parts) != 1 || !w.shouldQualifyRelation(strings.ToLower(parts[0]), false) {
			return
		}
	case strings.HasSuffix(upper, "%TYPE"):
		parts = strings.Split(name[:len(name)-5], ".")
		if len(parts) != 2 || vars[strings.ToLower(parts[0])] || !w.shouldQualifyRelation(strings.ToLower(parts[0]), false) {
			return
		}
	default:
		base := name
		if i := strings.IndexAny(base, "[("); i >= 0 {
			base = base[:i]
		}
		if strings.Contains(base, ".") || !w.isType(strings.ToLower(strings.TrimSpace(base))) {
			return
		}
	}
	t.TypeName = quoteIdent(w.r.schema) + "." + name
}

// rewriteExpr rewrites the query of a PLpgSQL_expr and deparses it.
func (w *walker) rewriteExpr(q string, mode plpgsqlast.RawParseMode) (string, error) {
	const prefix = "SELECT "
	switch mode {
	case plpgsqlast.RAW_PARSE_DEFAULT:
		return w.sqlBody(q)
	case plpgsqlast.RAW_PARSE_PLPGSQL_EXPR:
		out, err := w.sqlBody(prefix + q)
		if err != nil {
			return "", err
		}
		if !strings.HasPrefix(out, prefix) {
			return "", fmt.Errorf("unexpected deparse %q", out)
		}
		return out[len(prefix):], nil
	case plpgsqlast.RAW_PARSE_PLPGSQL_ASSIGN1, plpgsqlast.RAW_PARSE_PLPGSQL_ASSIGN2, plpgsqlast.RAW_PARSE_PLPGSQL_ASSIGN3:
		i := strings.Index(q, ":=")
		op := 2
		if i < 0 {
			i, op = strings.Index(q, "="), 1
		}
		if i < 0 {
			return "", errors.New("assignment operator not found")
		}
		rhs, err := w.rewriteExpr(q[i+op:], plpgsqlast.RAW_PARSE_PLPGSQL_EXPR)
		if err != nil {
			return "", err
		}
		return strings.TrimSpace(q[:i]) + " := " + rhs, nil
	}
	return q, nil
}
