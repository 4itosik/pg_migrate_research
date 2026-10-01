// Package antlrrewrite is the same schema-qualifying rewriter as poc/pgquery,
// built on the ANTLR4 PostgreSQL grammar of Bytebase
// (github.com/bytebase/parser/postgresql, pure Go).
//
// ANTLR gives a concrete parse tree with exact tokens, so the rewriter
// inserts "schema." through a TokenStreamRewriter and keeps comments and
// formatting. The price is that every name is a grammar rule whose meaning
// depends on the parent rule, so the rules below are spelled out per
// statement kind.
package antlrrewrite

import (
	"errors"
	"fmt"
	"strings"

	"github.com/antlr4-go/antlr/v4"
	pg "github.com/bytebase/parser/postgresql"
)

// Options configures a Rewriter.
type Options struct {
	Schema           string
	ExcludeRelations []string
}

// Rewriter rewrites migrations of one schema.
type Rewriter struct {
	schema, prefix string
	exclude        map[string]bool
	relations      map[string]bool
	types          map[string]bool
	functions      map[string]bool
	temp           map[string]bool
	transition     map[string]bool
}

// New creates a Rewriter.
func New(opts Options) (*Rewriter, error) {
	if opts.Schema == "" {
		return nil, errors.New("schema is required")
	}
	r := &Rewriter{
		schema: opts.Schema, prefix: quoteIdent(opts.Schema) + ".", exclude: map[string]bool{},
		relations: map[string]bool{}, types: map[string]bool{}, functions: map[string]bool{},
		temp: map[string]bool{}, transition: map[string]bool{},
	}
	for _, n := range opts.ExcludeRelations {
		r.exclude[n] = true
	}
	return r, nil
}

// Learn registers the objects created by a migration.
func (r *Rewriter) Learn(sql string) error {
	_, _, err := r.rewrite(sql, false, true, nil)
	return err
}

// Rewrite returns the migration with qualified names.
func (r *Rewriter) Rewrite(sql string) (string, []string, error) {
	if err := r.Learn(sql); err != nil {
		return "", nil, err
	}
	out, warns, err := r.rewrite(sql, false, false, nil)
	if err != nil {
		return "", nil, err
	}
	if _, err := parse(out, false); err != nil {
		return "", nil, fmt.Errorf("rewritten SQL does not parse: %w", err)
	}
	return out, dedupe(warns), nil
}

// rewrite parses text (SQL or a PL/pgSQL body), walks it and applies the
// insertions with a TokenStreamRewriter.
func (r *Rewriter) rewrite(text string, plpgsql, learnOnly bool, vars map[string]bool) (string, []string, error) {
	p, err := parse(text, plpgsql)
	if err != nil {
		return "", nil, err
	}
	l := &listener{
		r: r, rw: antlr.NewTokenStreamRewriter(p.stream), stream: p.stream,
		inBody: vars != nil, plpgsql: plpgsql, learnOnly: learnOnly, vars: vars, done: map[int]bool{},
	}
	if l.vars == nil {
		l.vars = map[string]bool{}
	}
	antlr.ParseTreeWalkerDefault.Walk(l, p.tree)
	if l.err != nil {
		return "", nil, l.err
	}
	if learnOnly {
		return text, nil, nil
	}
	return l.rw.GetTextDefault(), l.warns, nil
}

type parsed struct {
	stream *antlr.CommonTokenStream
	tree   antlr.ParseTree
}

type errListener struct {
	*antlr.DefaultErrorListener
	err error
}

func (e *errListener) SyntaxError(_ antlr.Recognizer, _ any, line, column int, msg string, _ antlr.RecognitionException) {
	if e.err == nil {
		e.err = fmt.Errorf("syntax error at %d:%d: %s", line, column, msg)
	}
}

func parse(text string, plpgsql bool) (*parsed, error) {
	el := &errListener{DefaultErrorListener: antlr.NewDefaultErrorListener()}
	lexer := pg.NewPostgreSQLLexer(antlr.NewInputStream(text))
	lexer.RemoveErrorListeners()
	lexer.AddErrorListener(el)
	stream := antlr.NewCommonTokenStream(lexer, antlr.TokenDefaultChannel)
	p := pg.NewPostgreSQLParser(stream)
	p.RemoveErrorListeners()
	p.AddErrorListener(el)
	var tree antlr.ParseTree
	if plpgsql {
		tree = p.Plsqlroot()
	} else {
		tree = p.Root()
	}
	if el.err != nil {
		return nil, el.err
	}
	return &parsed{stream: stream, tree: tree}, nil
}

// ---- listener ---------------------------------------------------------------

type frame struct {
	names map[string]bool
	owner antlr.Tree
}

type listener struct {
	*pg.BasePostgreSQLParserListener
	r         *Rewriter
	rw        *antlr.TokenStreamRewriter
	stream    *antlr.CommonTokenStream
	inBody    bool // function body or DO block
	plpgsql   bool // walking PL/pgSQL: INTO targets are variables
	learnOnly bool
	vars      map[string]bool // PL/pgSQL variables and parameters
	warns     []string
	err       error
	frames    []frame // CTE scopes
	done      map[int]bool
}

func (l *listener) fail(format string, args ...any) {
	if l.err == nil {
		l.err = fmt.Errorf(format, args...)
	}
}

func (l *listener) warn(format string, args ...any) {
	if !l.learnOnly {
		l.warns = append(l.warns, fmt.Sprintf(format, args...))
	}
}

// insert puts the schema prefix before a token.
func (l *listener) insert(tok antlr.Token) {
	if l.learnOnly || l.done[tok.GetTokenIndex()] {
		return
	}
	l.done[tok.GetTokenIndex()] = true
	l.rw.InsertBeforeDefault(tok.GetTokenIndex(), l.r.prefix)
}

func (l *listener) shouldQualifyRelation(name string, cteCheck bool) bool {
	switch {
	case name == "":
		return false
	case cteCheck && l.inCTE(name):
		return false
	case l.r.temp[name], strings.HasPrefix(name, "pg_"), l.r.exclude[name]:
		return false
	case l.inBody && l.r.transition[name]:
		return false
	}
	return true
}

func (l *listener) isType(name string) bool { return l.r.types[name] || l.r.relations[name] }

// ---- CTE scopes -------------------------------------------------------------

func (l *listener) inCTE(name string) bool {
	for _, f := range l.frames {
		if f.names[name] {
			return true
		}
	}
	return false
}

func cteNames(list pg.ICte_listContext) []string {
	var names []string
	for _, c := range list.AllCommon_table_expr() {
		names = append(names, normIdent(c.Name().GetText()))
	}
	return names
}

// EnterCommon_table_expr: a non-recursive CTE sees only the CTEs before it.
func (l *listener) EnterCommon_table_expr(ctx *pg.Common_table_exprContext) {
	list, _ := ctx.GetParent().(*pg.Cte_listContext)
	if list == nil {
		return
	}
	names := cteNames(list)
	with, _ := list.GetParent().(*pg.With_clauseContext)
	if with == nil || with.RECURSIVE() == nil {
		for i, c := range list.AllCommon_table_expr() {
			if c == ctx {
				names = names[:i]
				break
			}
		}
	}
	l.push(names, ctx)
}

// ExitWith_clause: the rest of the statement sees all CTEs.
func (l *listener) ExitWith_clause(ctx *pg.With_clauseContext) {
	owner := ctx.GetParent()
	if _, ok := owner.(*pg.Opt_with_clauseContext); ok {
		owner = owner.GetParent()
	}
	l.push(cteNames(ctx.Cte_list()), owner)
}

func (l *listener) push(names []string, owner antlr.Tree) {
	f := frame{names: map[string]bool{}, owner: owner}
	for _, n := range names {
		f.names[n] = true
	}
	l.frames = append(l.frames, f)
}

func (l *listener) ExitEveryRule(ctx antlr.ParserRuleContext) {
	for len(l.frames) > 0 && l.frames[len(l.frames)-1].owner == ctx {
		l.frames = l.frames[:len(l.frames)-1]
	}
}

// ---- relations ------------------------------------------------------------------

var catalogRelations = map[string]bool{
	"pg_type": true, "pg_class": true, "pg_proc": true, "pg_namespace": true, "pg_tables": true,
	"pg_views": true, "pg_indexes": true, "pg_sequences": true, "pg_constraint": true, "pg_trigger": true,
}

func (l *listener) EnterQualified_name(ctx *pg.Qualified_nameContext) {
	name := normIdent(ctx.Colid().GetText())
	if ctx.Indirection() != nil {
		if name == "information_schema" {
			l.warn("lookup in system catalogs by name, check that it takes the target schema into account")
		}
		return
	}
	if catalogRelations[name] {
		l.warn("lookup in system catalogs by name, check that it takes the target schema into account")
	}
	cteCheck := true
	switch p := ctx.GetParent().(type) {
	case *pg.TypenameContext: // name%ROWTYPE, handled in EnterTypename
		return
	case *pg.Qualified_name_listContext:
		if _, ok := p.GetParent().(*pg.Locked_rels_listContext); ok {
			return // FOR UPDATE OF <from item>
		}
	case *pg.ReindexstmtContext:
		if t := p.Reindex_target_type(); t != nil && (t.SCHEMA() != nil || t.DATABASE() != nil || t.SYSTEM_P() != nil) {
			return // REINDEX SCHEMA <schema>
		}
	case *pg.OpttempTableNameContext: // SELECT ... INTO
		if l.plpgsql {
			return // PL/pgSQL: INTO <variable>
		}
		if p.TEMP() != nil || p.TEMPORARY() != nil {
			l.r.temp[name] = true
			return
		}
		l.r.relations[name] = true
		cteCheck = false
	case *pg.CreatestmtContext:
		if ctx == p.Qualified_name(0) {
			if isTemp(p.Opttemp()) {
				l.r.temp[name] = true
				return
			}
			l.r.relations[name] = true
		}
		cteCheck = false
	case *pg.Create_as_targetContext:
		temp := false
		switch c := p.GetParent().(type) {
		case *pg.CreateasstmtContext:
			temp = isTemp(c.Opttemp())
		case *pg.ExecutestmtContext: // CREATE TEMP TABLE t AS EXECUTE
			temp = isTemp(c.Opttemp())
		}
		if temp {
			l.r.temp[name] = true
			return
		}
		l.r.relations[name] = true
	case *pg.Create_mv_targetContext:
		l.r.relations[name] = true
	case *pg.ViewstmtContext:
		if isTemp(p.Opttemp()) {
			l.r.temp[name] = true
			return
		}
		l.r.relations[name] = true
	case *pg.CreateseqstmtContext:
		if isTemp(p.Opttemp()) {
			l.r.temp[name] = true
			return
		}
		l.r.relations[name] = true
	case *pg.Insert_targetContext:
		cteCheck = false
	case *pg.Relation_exprContext:
		if rp, ok := p.GetParent().(*pg.Relation_expr_opt_aliasContext); ok {
			switch rp.GetParent().(type) {
			case *pg.UpdatestmtContext, *pg.DeletestmtContext:
				cteCheck = false // DML target is never a CTE
			}
		}
	case *pg.MergestmtContext:
		cteCheck = ctx != p.Qualified_name(0)
	}
	if l.shouldQualifyRelation(name, cteCheck) {
		l.insert(ctx.GetStart())
	}
}

func isTemp(t pg.IOpttempContext) bool {
	return t != nil && (t.TEMP() != nil || t.TEMPORARY() != nil)
}

// ---- any_name: types, domains, statistics, DROP/COMMENT targets -----------------

func (l *listener) EnterAny_name(ctx *pg.Any_nameContext) {
	first := normIdent(ctx.Colid().GetText())
	parts := 1
	if ctx.Attrs() != nil {
		parts += len(ctx.Attrs().AllAttr_name())
	}
	parent := ctx.GetParent()
	if list, ok := parent.(*pg.Any_name_listContext); ok {
		parent = list.GetParent()
	}
	switch p := parent.(type) {
	case *pg.DropstmtContext:
		switch {
		case p.Object_type_any_name() != nil:
			l.anyNameOf(ctx, p.Object_type_any_name(), first, parts)
		case p.INDEX() != nil: // DROP INDEX CONCURRENTLY
			l.relationName(ctx, first, parts)
		case p.Object_type_name_on_any_name() != nil: // DROP TRIGGER t ON <table>
			l.relationName(ctx, first, parts)
		}
	case *pg.CommentstmtContext:
		switch {
		case p.Object_type_any_name() != nil:
			l.anyNameOf(ctx, p.Object_type_any_name(), first, parts)
		case p.COLUMN() != nil && parts == 2: // table.column
			l.relationName(ctx, first, 1)
		case p.CONSTRAINT() != nil && p.DOMAIN_P() != nil:
			l.defName(ctx, parts)
		case p.CONSTRAINT() != nil || p.Object_type_name_on_any_name() != nil: // ... ON <table>
			l.relationName(ctx, first, parts)
		}
	case *pg.Privilege_targetContext: // GRANT ... ON TYPE / DOMAIN
		l.defName(ctx, parts)
	case *pg.DefinestmtContext:
		if p.TYPE_P() != nil {
			l.register(l.r.types, first, parts)
		}
		if p.COLLATION() == nil || ctx == p.Any_name(0) {
			l.defName(ctx, parts)
		}
	case *pg.CreatedomainstmtContext:
		l.register(l.r.types, first, parts)
		l.defName(ctx, parts)
	case *pg.AlterenumstmtContext, *pg.AlterdomainstmtContext, *pg.AltertypestmtContext,
		*pg.CreatestatsstmtContext, *pg.AlterstatsstmtContext, *pg.AlterownerstmtContext, *pg.AlterobjectschemastmtContext:
		l.defName(ctx, parts)
	case *pg.RenamestmtContext:
		if p.TYPE_P() != nil || p.DOMAIN_P() != nil {
			l.r.types[normIdent(p.Name(0).GetText())] = true
		}
		if p.TYPE_P() != nil || p.DOMAIN_P() != nil || p.STATISTICS() != nil || p.COLLATION() != nil {
			l.defName(ctx, parts)
		}
	case *pg.SeqoptelemContext: // OWNED BY table.column
		if p.OWNED() != nil && parts == 2 {
			l.relationName(ctx, first, 1)
		}
	case *pg.CreatestmtContext: // CREATE TABLE ... OF type
		if parts == 1 && l.isType(first) {
			l.insert(ctx.GetStart())
		}
	case *pg.Alter_table_cmdContext: // ALTER TABLE ... OF type
		if p.OF() != nil && parts == 1 && l.isType(first) {
			l.insert(ctx.GetStart())
		}
	case *pg.AltercompositetypestmtContext: // ALTER TYPE t ADD/DROP/ALTER ATTRIBUTE
		l.defName(ctx, parts)
	}
}

func (l *listener) anyNameOf(ctx *pg.Any_nameContext, kind pg.IObject_type_any_nameContext, first string, parts int) {
	switch {
	case kind.TABLE() != nil, kind.SEQUENCE() != nil, kind.VIEW() != nil, kind.INDEX() != nil:
		l.relationName(ctx, first, parts)
	default: // COLLATION, CONVERSION, STATISTICS, TEXT SEARCH ...
		l.defName(ctx, parts)
	}
}

func (l *listener) relationName(ctx antlr.ParserRuleContext, first string, parts int) {
	if parts == 1 && l.shouldQualifyRelation(first, false) {
		l.insert(ctx.GetStart())
	}
}

func (l *listener) defName(ctx antlr.ParserRuleContext, parts int) {
	if parts == 1 {
		l.insert(ctx.GetStart())
	}
}

func (l *listener) register(set map[string]bool, first string, parts int) {
	if parts == 1 {
		set[first] = true
	}
}

// ---- functions --------------------------------------------------------------------

var relationArgFunctions = map[string]bool{
	"nextval": true, "currval": true, "setval": true, "pg_get_serial_sequence": true, "to_regclass": true,
	"pg_relation_size": true, "pg_total_relation_size": true, "pg_table_size": true, "pg_indexes_size": true,
}

func funcNameParts(ctx *pg.Func_nameContext) (string, int) {
	if ctx.Indirection() != nil {
		return normIdent(ctx.Colid().GetText()), 1 + len(ctx.Indirection().AllIndirection_el())
	}
	return normIdent(ctx.GetText()), 1
}

func (l *listener) EnterFunc_name(ctx *pg.Func_nameContext) {
	name, parts := funcNameParts(ctx)
	if parts != 1 {
		return
	}
	switch p := ctx.GetParent().(type) {
	case *pg.Func_applicationContext:
		if l.r.functions[name] {
			l.insert(ctx.GetStart())
		}
	case *pg.CreatefunctionstmtContext:
		l.r.functions[name] = true
		l.insert(ctx.GetStart())
	case *pg.DefinestmtContext: // CREATE AGGREGATE
		l.r.functions[name] = true
		l.insert(ctx.GetStart())
	case *pg.Aggregate_with_argtypesContext:
		l.insert(ctx.GetStart())
	case *pg.Function_with_argtypesContext:
		if l.isCast(p) {
			if l.r.functions[name] {
				l.insert(ctx.GetStart())
			}
			return
		}
		l.insert(ctx.GetStart())
	case *pg.CreatetrigstmtContext, *pg.CreateeventtrigstmtContext:
		if l.r.functions[name] {
			l.insert(ctx.GetStart())
		}
	case *pg.AexprconstContext: // type 'literal'
		if l.isType(name) {
			l.insert(ctx.GetStart())
		}
	}
}

func (l *listener) isCast(ctx antlr.Tree) bool {
	_, ok := ctx.GetParent().(*pg.CreatecaststmtContext)
	return ok
}

// EnterFunction_with_argtypes handles "DROP FUNCTION f" without arguments.
func (l *listener) EnterFunction_with_argtypes(ctx *pg.Function_with_argtypesContext) {
	if ctx.Func_name() == nil && ctx.Colid() != nil && ctx.Indirection() == nil && !l.isCast(ctx) {
		l.insert(ctx.GetStart())
	}
}

func (l *listener) EnterRenamestmt(ctx *pg.RenamestmtContext) {
	if ctx.FUNCTION() != nil || ctx.PROCEDURE() != nil || ctx.ROUTINE() != nil || ctx.AGGREGATE() != nil {
		if n := ctx.Name(0); n != nil {
			l.r.functions[normIdent(n.GetText())] = true
		}
	}
	if (ctx.TABLE() != nil || ctx.VIEW() != nil || ctx.SEQUENCE() != nil || ctx.INDEX() != nil) && len(ctx.AllName()) == 1 {
		l.r.relations[normIdent(ctx.Name(0).GetText())] = true
	}
}

func (l *listener) EnterFunc_application(ctx *pg.Func_applicationContext) {
	name, parts := funcNameParts(ctx.Func_name().(*pg.Func_nameContext))
	if parts != 1 || !relationArgFunctions[name] || ctx.Func_arg_list() == nil {
		return
	}
	args := ctx.Func_arg_list().AllFunc_arg_expr()
	if len(args) > 0 {
		l.literal(args[0], func(n string) bool { return l.shouldQualifyRelation(n, false) })
	}
}

// EnterA_expr_typecast handles 'name'::regclass.
func (l *listener) EnterA_expr_typecast(ctx *pg.A_expr_typecastContext) {
	casts := ctx.AllTypename()
	if len(casts) == 0 {
		return
	}
	switch strings.TrimPrefix(strings.ToLower(casts[0].GetText()), "pg_catalog.") {
	case "regclass":
		l.literal(ctx.C_expr(), func(n string) bool { return l.shouldQualifyRelation(n, false) })
	case "regtype":
		l.literal(ctx.C_expr(), l.isType)
	case "regproc", "regprocedure":
		l.literal(ctx.C_expr(), func(n string) bool { return l.r.functions[n] })
	}
}

// literal qualifies a single string-constant expression.
func (l *listener) literal(ctx antlr.ParserRuleContext, qualify func(string) bool) {
	start, stop := ctx.GetStart(), ctx.GetStop()
	if start.GetTokenIndex() != stop.GetTokenIndex() || start.GetTokenType() != pg.PostgreSQLParserStringConstant || l.learnOnly {
		return
	}
	idx := start.GetTokenIndex()
	if l.done[idx] {
		return
	}
	raw := start.GetText()
	val := strings.ReplaceAll(raw[1:len(raw)-1], "''", "'")
	name := strings.TrimSpace(val)
	head := name
	if i := strings.IndexByte(head, '('); i >= 0 { // regprocedure: f(int)
		head = head[:i]
	}
	if strings.ContainsAny(head, `."`) || !qualify(strings.ToLower(head)) {
		return
	}
	l.done[idx] = true
	l.rw.ReplaceDefault(idx, idx, quoteLiteral(l.r.prefix+name))
}

// ---- types --------------------------------------------------------------------------

func (l *listener) EnterGenerictype(ctx *pg.GenerictypeContext) {
	if ctx.Attrs() != nil || ctx.Type_function_name() == nil {
		return
	}
	// The grammar parses "ADD CONSTRAINT c CHECK (...)" as a column named
	// CONSTRAINT of type c; c is a constraint name, not a type.
	for p := ctx.GetParent(); p != nil; p = p.GetParent() {
		if cd, ok := p.(*pg.ColumnDefContext); ok {
			if strings.EqualFold(cd.Colid().GetText(), "constraint") {
				return
			}
			break
		}
	}
	name := normIdent(ctx.Type_function_name().GetText())
	if l.isType(name) || l.typeDefinition(ctx) {
		l.insert(ctx.GetStart())
	}
}

// typeDefinition reports whether a type name is the target of DROP TYPE,
// DROP DOMAIN or COMMENT ON TYPE/DOMAIN.
func (l *listener) typeDefinition(ctx antlr.Tree) bool {
	for p := ctx.GetParent(); p != nil; p = p.GetParent() {
		switch s := p.(type) {
		case *pg.DropstmtContext:
			return s.TYPE_P() != nil || s.DOMAIN_P() != nil
		case *pg.CommentstmtContext:
			return s.TYPE_P() != nil || s.DOMAIN_P() != nil
		case *pg.StmtContext, *pg.Func_argContext, *pg.Func_typeContext:
			return false
		}
	}
	return false
}

// EnterTypename handles name%ROWTYPE and table.column%TYPE.
func (l *listener) EnterTypename(ctx *pg.TypenameContext) {
	if ctx.PERCENT() == nil || ctx.Qualified_name() == nil {
		return
	}
	q := ctx.Qualified_name().(*pg.Qualified_nameContext)
	name := normIdent(q.Colid().GetText())
	switch {
	case ctx.ROWTYPE() != nil && q.Indirection() == nil:
		if l.shouldQualifyRelation(name, false) {
			l.insert(q.GetStart())
		}
	case ctx.TYPE_P() != nil && q.Indirection() != nil && len(q.Indirection().AllIndirection_el()) == 1:
		if !l.vars[name] && l.shouldQualifyRelation(name, false) {
			l.insert(q.GetStart())
		}
	}
}

// EnterFunc_type handles table.column%TYPE in function signatures.
func (l *listener) EnterFunc_type(ctx *pg.Func_typeContext) {
	if ctx.PERCENT() == nil || ctx.Type_function_name() == nil || ctx.Attrs() == nil || len(ctx.Attrs().AllAttr_name()) != 1 {
		return
	}
	if name := normIdent(ctx.Type_function_name().GetText()); l.shouldQualifyRelation(name, false) {
		l.insert(ctx.Type_function_name().GetStart())
	}
}

// ---- triggers, warnings -----------------------------------------------------------

func (l *listener) EnterTriggertransition(ctx *pg.TriggertransitionContext) {
	if ctx.Transitionrelname() != nil {
		l.r.transition[normIdent(ctx.Transitionrelname().GetText())] = true
	}
}

func (l *listener) EnterCreateextensionstmt(ctx *pg.CreateextensionstmtContext) {
	if !strings.Contains(strings.ToLower(ctx.GetText()), "schema") {
		l.warn("CREATE EXTENSION without SCHEMA")
	}
}

func (l *listener) EnterGeneric_set(ctx *pg.Generic_setContext) {
	if strings.EqualFold(ctx.Var_name().GetText(), "search_path") {
		l.warn("migration changes search_path")
	}
}

func (l *listener) EnterStmt_dynexecute(*pg.Stmt_dynexecuteContext) {
	l.warn("dynamic SQL (EXECUTE) inside a function body or DO block is not rewritten")
}

// EnterDecl_statement collects PL/pgSQL variable names: v.c%TYPE refers to
// a variable, not to a table.
func (l *listener) EnterDecl_statement(ctx *pg.Decl_statementContext) {
	l.vars[normIdent(ctx.Decl_varname().GetText())] = true
}

// ---- function bodies and DO blocks ---------------------------------------------

func (l *listener) EnterCreatefunctionstmt(ctx *pg.CreatefunctionstmtContext) {
	lang := ""
	var body pg.ISconstContext
	for _, it := range ctx.Createfunc_opt_list().AllCreatefunc_opt_item() {
		if it.LANGUAGE() != nil {
			lang = strings.ToLower(strings.Trim(it.Nonreservedword_or_sconst().GetText(), `'"`))
		}
		if it.AS() != nil && it.Func_as() != nil && len(it.Func_as().AllSconst()) == 1 {
			body = it.Func_as().Sconst(0)
		}
	}
	if body == nil {
		return
	}
	vars := map[string]bool{}
	if ctx.Func_args_with_defaults().Func_args_with_defaults_list() != nil {
		for _, a := range ctx.Func_args_with_defaults().Func_args_with_defaults_list().AllFunc_arg_with_default() {
			if pn := a.Func_arg().Param_name(); pn != nil {
				vars[normIdent(pn.GetText())] = true
			}
		}
	}
	if rt := ctx.Func_return(); rt != nil && strings.EqualFold(rt.GetText(), "trigger") {
		vars["new"], vars["old"] = true, true
	}
	switch lang {
	case "sql", "plpgsql":
		l.body(body, lang == "plpgsql", vars)
	default:
		l.warn("function body in LANGUAGE %s is not rewritten", lang)
	}
}

func (l *listener) EnterDostmt(ctx *pg.DostmtContext) {
	var body pg.ISconstContext
	for _, it := range ctx.Dostmt_opt_list().AllDostmt_opt_item() {
		if it.LANGUAGE() != nil && !strings.EqualFold(strings.Trim(it.Nonreservedword_or_sconst().GetText(), `'"`), "plpgsql") {
			l.warn("DO block in a language other than plpgsql is not rewritten")
			return
		}
		if it.Sconst() != nil {
			body = it.Sconst()
		}
	}
	if body != nil {
		l.body(body, true, map[string]bool{})
	}
}

// body rewrites a function body or DO block with a nested parser and puts the
// result back into the string constant, keeping a dollar-quote tag if
// possible.
func (l *listener) body(sc pg.ISconstContext, plpgsql bool, vars map[string]bool) {
	start, stop := sc.GetStart(), sc.GetStop()
	raw := l.stream.GetTextFromInterval(antlr.NewInterval(start.GetTokenIndex(), stop.GetTokenIndex()))
	var text, tag string
	switch start.GetTokenType() {
	case pg.PostgreSQLParserBeginDollarStringConstant:
		tag = start.GetText()
		text = raw[len(tag) : len(raw)-len(tag)]
	case pg.PostgreSQLParserStringConstant:
		text = strings.ReplaceAll(raw[1:len(raw)-1], "''", "'")
	default:
		l.warn("function body in an escape string is not rewritten")
		return
	}
	for k := range l.vars {
		vars[k] = true
	}
	out, warns, err := l.r.rewrite(text, plpgsql, l.learnOnly, vars)
	if err != nil {
		l.fail("function body: %v", err)
		return
	}
	l.warns = append(l.warns, warns...)
	if l.learnOnly || out == text {
		return
	}
	if tag == "" || strings.Contains(out, tag) {
		tag = "$$"
		for i := 0; strings.Contains(out, tag); i++ {
			tag = fmt.Sprintf("$body%d$", i)
		}
	}
	l.rw.ReplaceDefault(start.GetTokenIndex(), stop.GetTokenIndex(), tag+out+tag)
}

// ---- helpers ------------------------------------------------------------------------

func normIdent(s string) string {
	if strings.HasPrefix(s, `"`) && strings.HasSuffix(s, `"`) && len(s) >= 2 {
		return strings.ReplaceAll(s[1:len(s)-1], `""`, `"`)
	}
	return strings.ToLower(s)
}

func quoteIdent(s string) string {
	for i, c := range s {
		if !(c == '_' || (c >= 'a' && c <= 'z') || (i > 0 && c >= '0' && c <= '9')) {
			return `"` + strings.ReplaceAll(s, `"`, `""`) + `"`
		}
	}
	return s
}

func quoteLiteral(s string) string { return `'` + strings.ReplaceAll(s, `'`, `''`) + `'` }

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
