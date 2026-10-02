package pgschema

import (
	"fmt"
	"reflect"
	"strings"

	. "github.com/4itosik/pg_migrate_research/pgschema/internal/ast"
	"github.com/4itosik/pg_migrate_research/pgschema/internal/lex"
	"github.com/4itosik/pg_migrate_research/pgschema/subst"
)

// walker visits the parse tree of one SQL text, collects edits and applies
// the same changes to the tree, so that the result can be verified.
type walker struct {
	r         *Rewriter
	src       string
	inBody    bool // inside a function body or DO block
	learnOnly bool

	edits []edit
	warns []Warning // the lines count in src
	err   error

	scopes []map[string]bool // CTE names visible at the current node
	done   map[Node]bool

	// relations that a statement creates as permanent ones while a temporary
	// relation of the name exists: the CREATE gets the schema, the statements
	// after it no longer see the temporary one
	permanent map[*RangeVar]bool
	untemp    []string

	stmtStart, stmtEnd int
	catalogRef         bool
	triggerVars        []string // special variables of the function being rewritten
}

func (w *walker) beginStmt(raw *RawStmt) {
	w.stmtStart = int(raw.StmtLocation)
	w.stmtEnd = len(w.src)
	if raw.StmtLen > 0 {
		w.stmtEnd = w.stmtStart + int(raw.StmtLen)
	}
	w.catalogRef = false
}

func (w *walker) endStmt() {
	for _, name := range w.untemp {
		delete(w.r.reg.temp, name)
	}
	w.untemp = nil
	if w.catalogRef {
		w.warn("lookup in system catalogs by name, check that it takes the target schema into account: %s", snippet(w.stmtText()))
	}
}

func (w *walker) stmtText() string { return w.src[w.stmtStart:w.stmtEnd] }

func (w *walker) fail(format string, args ...any) {
	if w.err == nil {
		w.err = fmt.Errorf(format, args...)
	}
}

// failErr records err as the error of the walk, if it is the first.
func (w *walker) failErr(err error) {
	if w.err == nil {
		w.err = err
	}
}

// warn adds a warning about the statement.
func (w *walker) warn(format string, args ...any) { w.warnAt(-1, format, args...) }

// warnAt adds a warning about the place at byte offset loc of the text, -1
// for the statement.
func (w *walker) warnAt(loc int32, format string, args ...any) {
	if w.learnOnly {
		return
	}
	off := int(loc)
	if loc < 0 { // the first token: the statement starts after the white space and comments that follow the one before
		off = w.stmtStart
		if it, err := lex.NewScanner(w.src[w.stmtStart:w.stmtEnd]).Next(); err == nil && it.Tok != 0 {
			off += int(it.Start)
		}
	}
	line, _ := position(w.src, off)
	w.warns = append(w.warns, Warning{Line: line, Message: fmt.Sprintf(format, args...)})
}

func isNilNode(n Node) bool {
	if n == nil {
		return true
	}
	v := reflect.ValueOf(n)
	return v.Kind() == reflect.Pointer && v.IsNil()
}

// visit dispatches on the node type and descends into the children.
func (w *walker) visit(n Node) {
	if w.err != nil || isNilNode(n) {
		return
	}
	if w.handle(n) {
		return
	}
	n.Children(w.visit)
}

// children visits the children of n except the fields named in skip.
func (w *walker) children(n Node, skip ...string) {
	v := reflect.ValueOf(n).Elem()
	t := v.Type()
next:
	for i := 0; i < v.NumField(); i++ {
		for _, s := range skip {
			if t.Field(i).Name == s {
				continue next
			}
		}
		w.visitValue(v.Field(i))
	}
}

func (w *walker) visitValue(f reflect.Value) {
	switch f.Kind() {
	case reflect.Interface, reflect.Pointer:
		if f.IsNil() {
			return
		}
		if n, ok := f.Interface().(Node); ok {
			w.visit(n)
		}
	case reflect.Slice:
		for j := 0; j < f.Len(); j++ {
			w.visitValue(f.Index(j))
		}
	}
}

// handle processes the node types that have rules of their own. It returns
// true when it has visited the children itself.
func (w *walker) handle(node Node) bool {
	switch n := node.(type) {
	case *RangeVar:
		w.rangeVar(n, true)
	case *TypeName:
		w.typeName(n, false)
	case *FuncCall:
		w.funcCall(n)
	case *TypeCast:
		w.typeCast(n)

	case *SelectStmt:
		w.withClause(n.WithClause, func() { w.children(n, "WithClause") })
		return true
	case *InsertStmt:
		w.rangeVar(n.Relation, false) // a DML target is never a CTE
		w.withClause(n.WithClause, func() { w.children(n, "Relation", "WithClause") })
		return true
	case *UpdateStmt:
		w.rangeVar(n.Relation, false)
		w.withClause(n.WithClause, func() { w.children(n, "Relation", "WithClause") })
		return true
	case *DeleteStmt:
		w.rangeVar(n.Relation, false)
		w.withClause(n.WithClause, func() { w.children(n, "Relation", "WithClause") })
		return true
	case *MergeStmt:
		w.rangeVar(n.Relation, false)
		w.withClause(n.WithClause, func() { w.children(n, "Relation", "WithClause") })
		return true

	case *LockingClause:
		// FOR UPDATE OF t names FROM items and must stay unqualified
		for _, r := range n.LockedRels {
			if rv, ok := r.(*RangeVar); ok {
				w.done[rv] = true
			}
		}
	case *CreateStmt:
		w.register(n.Relation, kindRelation)
	case *IntoClause:
		w.register(n.Rel, kindRelation)
	case *ViewStmt:
		w.register(n.View, kindRelation)
	case *CreateSeqStmt:
		w.register(n.Sequence, kindRelation)
		w.ownedBy(n.Options)
	case *AlterSeqStmt:
		w.ownedBy(n.Options)
	case *IndexStmt:
		if n.Idxname != "" && n.Relation != nil && (n.Relation.Schemaname == "" || n.Relation.Schemaname == w.r.schema) {
			w.r.reg.add(kindRelation, n.Idxname)
		}
	case *CompositeTypeStmt:
		w.register(n.Typevar, kindRelation)
		w.register(n.Typevar, kindType)
	case *CreateEnumStmt:
		w.defName(&n.TypeName, kindType)
	case *CreateRangeStmt:
		w.defName(&n.TypeName, kindType)
		w.warn("the constructor functions of a range type are not qualified where they are called: %s", snippet(w.stmtText()))
	case *CreateDomainStmt:
		w.defName(&n.Domainname, kindType)
	case *AlterEnumStmt:
		w.defName(&n.TypeName, kindNone)
	case *AlterDomainStmt:
		w.defName(&n.TypeName, kindNone)
	case *AlterTypeStmt:
		w.defName(&n.TypeName, kindNone)
	case *DefineStmt:
		switch n.Kind {
		case OBJECT_TYPE:
			w.defName(&n.Defnames, kindType)
		case OBJECT_AGGREGATE:
			w.defName(&n.Defnames, kindFunction)
		case OBJECT_COLLATION, OBJECT_TSPARSER, OBJECT_TSDICTIONARY, OBJECT_TSTEMPLATE, OBJECT_TSCONFIGURATION:
			w.defName(&n.Defnames, kindNone)
			w.warn("%s created by a migration is not qualified where it is used (COLLATE, text search functions, ...): %s", objectLabel(n.Kind), snippet(w.stmtText()))
		default:
			w.warn("%s is not rewritten: %s", objectLabel(n.Kind), snippet(w.stmtText()))
		}
	case *CreateSchemaStmt:
		if len(n.SchemaElts) > 0 {
			w.warn("the elements of CREATE SCHEMA belong to the new schema and get the target schema, which the server rejects; create the objects in separate statements: %s", snippet(w.stmtText()))
		}
	case *CreateStatsStmt:
		w.defName(&n.Defnames, kindNone)
	case *AlterStatsStmt:
		w.defName(&n.Defnames, kindNone)

	case *CreateFunctionStmt:
		w.createFunction(n)
	case *DoStmt:
		w.doStmt(n)
	case *CreateTrigStmt:
		for _, tr := range n.TransitionRels {
			if t, ok := tr.(*TriggerTransition); ok {
				w.r.reg.addTransition(t.Name)
			}
		}
		w.usedFunctionName(&n.Funcname)
	case *CreateEventTrigStmt:
		w.usedFunctionName(&n.Funcname)
	case *CreateCastStmt:
		if n.Func != nil && !w.learnOnly {
			w.objectWithArgs(n.Func, false)
		}
	case *AlterFunctionStmt:
		if !w.learnOnly {
			w.objectWithArgs(n.Func, true)
		}

	case *DropStmt:
		w.objectList(n.RemoveType, n.Objects)
	case *CommentStmt:
		w.objectList(n.Objtype, []Node{n.Object})
	case *RenameStmt:
		w.renameStmt(n)
	case *AlterOwnerStmt:
		if n.Object != nil {
			w.objectList(n.ObjectType, []Node{n.Object})
		}
	case *AlterObjectSchemaStmt:
		if n.Object != nil {
			w.objectList(n.ObjectType, []Node{n.Object})
		}
	case *GrantStmt:
		if n.Targtype == ACL_TARGET_OBJECT && !isRelationType(n.Objtype) {
			w.objectList(n.Objtype, n.Objects)
		}

	case *CreateConversionStmt:
		w.defName(&n.ConversionName, kindNone)
	case *CreateOpClassStmt, *CreateOpFamilyStmt, *AlterOpFamilyStmt:
		w.warn("operator classes and families are not rewritten: %s", snippet(w.stmtText()))
	case *CreateExtensionStmt:
		w.createExtension(n)
	case *SecLabelStmt:
		w.warn("SECURITY LABEL is not rewritten, its object keeps the name as written: %s", snippet(w.stmtText()))
	case *AlterExtensionContentsStmt:
		w.warn("ALTER EXTENSION ... ADD or DROP is not rewritten, its object keeps the name as written: %s", snippet(w.stmtText()))
	case *VariableSetStmt:
		if strings.EqualFold(n.Name, "search_path") {
			w.warn("migration changes search_path: %s", snippet(w.stmtText()))
		}
	}
	return false
}

// ---- relations -------------------------------------------------------------

var catalogRelations = map[string]bool{
	"pg_type": true, "pg_class": true, "pg_proc": true, "pg_namespace": true,
	"pg_tables": true, "pg_views": true, "pg_matviews": true, "pg_indexes": true,
	"pg_sequences": true, "pg_constraint": true, "pg_trigger": true,
	"pg_attribute": true, "pg_enum": true,
}

func (w *walker) shouldQualifyRelation(name string, cteCheck bool) bool {
	return w.qualifiesRelation(name, cteCheck, true)
}

// qualifiesRelation is shouldQualifyRelation; temp says whether a temporary
// relation of the name hides it.
func (w *walker) qualifiesRelation(name string, cteCheck, temp bool) bool {
	switch {
	case name == "":
		return false
	case cteCheck && w.inCTE(name):
		return false
	case temp && w.r.reg.temp[name]:
		return false
	case strings.HasPrefix(name, "pg_"):
		return false
	case w.inBody && w.r.reg.transition[name]:
		return false
	case w.r.exclude[name]:
		return false
	}
	return true
}

func (w *walker) rangeVar(rv *RangeVar, cteCheck bool) {
	if rv == nil || w.done[rv] {
		return
	}
	w.done[rv] = true
	if rv.Schemaname == "information_schema" || (rv.Schemaname == "" && catalogRelations[rv.Relname]) {
		w.catalogRef = true
	}
	if rv.Schemaname != "" || rv.Catalogname != "" {
		return
	}
	if rv.Relpersistence == "t" {
		w.r.reg.addTemp(rv.Relname)
		return
	}
	if !w.qualifiesRelation(rv.Relname, cteCheck, !w.permanent[rv]) || w.learnOnly {
		return
	}
	ref := w.r.ext.rels[rv.Relname] // a table or view of an extension, else ours
	if ref == nil {
		ref = w.r.targetRef()
	}
	if w.qualifyAtRef(rv.Location, rv.Relname, ref) {
		rv.Schemaname = ref.name
	}
}

// register remembers a created relation or type.
func (w *walker) register(rv *RangeVar, kind objKind) {
	if rv == nil {
		return
	}
	if rv.Relpersistence == "t" {
		w.r.reg.addTemp(rv.Relname)
		return
	}
	if kind == kindRelation && w.r.reg.temp[rv.Relname] {
		w.permanent[rv] = true
		w.untemp = append(w.untemp, rv.Relname)
	}
	if rv.Schemaname == "" || rv.Schemaname == w.r.schema {
		w.created(kind, rv.Relname)
	}
}

// relationLiteral qualifies a string literal that names a relation:
// nextval('seq'), 'tbl'::regclass, pg_get_serial_sequence('tbl', 'col').
func (w *walker) relationLiteral(n Node) {
	w.literal(stringCastArg(n), func(name string) bool { return w.shouldQualifyRelation(name, false) })
}

func (w *walker) literal(n Node, qualify func(name string) bool) {
	c, ok := n.(*A_Const)
	if !ok || w.done[c] || w.learnOnly {
		return
	}
	str, ok := c.Val.(*String)
	if !ok {
		return
	}
	w.done[c] = true
	val := str.Sval
	head := val
	if i := strings.IndexByte(head, '('); i >= 0 { // regprocedure: f(int)
		head = head[:i]
	}
	parts, ok := splitQualifiedName(head)
	if !ok || len(parts) != 1 || !qualify(parts[0]) {
		return
	}
	it, err := w.tokenAt(c.Location)
	if err != nil || it.Tok != lex.SCONST {
		w.fail("cannot locate string literal %q", val)
		return
	}
	// the schema goes in front of the name, after any white space: an
	// insertion into the literal as written when its value is the text between
	// the delimiters, otherwise the literal is written again
	k := len(val) - len(strings.TrimLeft(val, " \t\n\r\f\v"))
	newVal := val[:k] + w.r.prefix + val[k:]
	raw := w.src[c.Location : int(c.Location)+int(it.End)]
	if start, ok := literalContentStart(raw, val); ok {
		pos := int(c.Location) + start + k
		w.edits = append(w.edits, edit{start: pos, end: pos, text: w.r.prefix})
	} else {
		w.edits = append(w.edits, edit{start: int(c.Location), end: int(c.Location) + int(it.End), text: quoteLiteral(newVal)})
	}
	str.Sval = newVal
}

// literalContentStart returns the offset in the text raw of a string literal
// at which its value starts, when the value is the text between the
// delimiters as it stands (no escapes, no doubled quotes): '...', E'...' or
// $tag$...$tag$.
func literalContentStart(raw, val string) (int, bool) {
	for _, q := range []string{"'", "E'", "e'"} {
		if strings.HasPrefix(raw, q) && len(raw) >= len(q)+1 && strings.HasSuffix(raw, "'") && raw[len(q):len(raw)-1] == val {
			return len(q), true
		}
	}
	if strings.HasPrefix(raw, "$") {
		if n := strings.IndexByte(raw[1:], '$') + 2; n >= 2 && len(raw) >= 2*n && raw[n:len(raw)-n] == val {
			return n, true
		}
	}
	return 0, false
}

// ---- CTE scopes ------------------------------------------------------------

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

// withClause visits the CTEs with PostgreSQL's visibility rules and then
// calls rest with all CTE names in scope. A non-recursive CTE sees only the
// CTEs defined before it.
func (w *walker) withClause(wc *WithClause, rest func()) {
	if wc == nil {
		rest()
		return
	}
	var names []string
	for _, c := range wc.Ctes {
		if cte, ok := c.(*CommonTableExpr); ok {
			names = append(names, cte.Ctename)
		}
	}
	if wc.Recursive {
		w.push(names)
		for _, c := range wc.Ctes {
			w.visit(c)
		}
		rest()
		w.pop()
		return
	}
	for i, c := range wc.Ctes {
		w.push(names[:i])
		w.visit(c)
		w.pop()
	}
	w.push(names)
	rest()
	w.pop()
}

// ---- types and functions ---------------------------------------------------

func (w *walker) typeName(tn *TypeName, definition bool) {
	if tn == nil || w.done[tn] {
		return
	}
	w.done[tn] = true
	names := strs(tn.Names)
	if len(names) == 0 || w.learnOnly {
		return
	}
	if tn.PctType { // table.column%TYPE
		if len(names) == 2 && w.shouldQualifyRelation(names[0], false) && w.qualifyAt(tn.Location, names[0]) {
			tn.Names = prepend(tn.Names, w.schemaNode())
		}
		return
	}
	if len(names) != 1 {
		return
	}
	ref := w.typeRef(names[0], definition, tn.Location)
	if ref == nil {
		return
	}
	loc := tn.Location
	if loc < 0 { // COMMENT ON CONSTRAINT c ON DOMAIN d: the position is that of the name
		if s, ok := tn.Names[0].(*String); ok {
			loc = s.Loc
		}
	}
	if w.qualifyAtRef(loc, names[0], ref) {
		tn.Names = prepend(tn.Names, refNode(ref))
	}
}

// typeRef is the schema a type name gets: the target schema for a type that a
// migration creates (or for the name of a type being defined), the schema of
// the extension for a type of an active extension, nil for any other. A type
// of the migrations that has the name of a type of pg_catalog gets nil: loc is
// the position of the use for the warning, -1 for the statement.
func (w *walker) typeRef(name string, definition bool, loc int32) *schemaRef {
	switch {
	case definition:
		return w.r.targetRef()
	case w.r.reg.isType(name):
		if w.builtinUse("type", name, loc) {
			return nil
		}
		return w.r.targetRef()
	}
	return w.r.ext.types[name]
}

// funcRef is the schema a function name gets, like typeRef.
func (w *walker) funcRef(name string, loc int32) *schemaRef {
	if w.r.reg.functions[name] {
		if w.builtinUse("function", name, loc) {
			return nil
		}
		return w.r.targetRef()
	}
	return w.r.ext.funcs[name]
}

// builtinUse reports whether a type or function of the migrations has the
// name of one of pg_catalog, and warns about the use if so. pg_catalog comes
// first in every search_path, so the unqualified name means the built-in (for
// a type that is exactly how PostgreSQL resolves it; for a function it keeps
// the calls of the built-in as they are) and is left unqualified.
func (w *walker) builtinUse(kind, name string, loc int32) bool {
	if kind == "type" && !isBuiltinType(name) || kind == "function" && !isBuiltinFunction(name) {
		return false
	}
	w.warnAt(loc, "%s is also a built-in %s of pg_catalog and is left unqualified, so it means the built-in; qualify it explicitly if the migration means its own %s: %s",
		name, kind, kind, snippet(w.stmtText()))
	return true
}

// created registers an object that a statement creates. A type (a relation is
// one too) or a function with the name of a built-in of pg_catalog gets the
// schema like any other, and a warning: its unqualified uses are left as they
// are (builtinUse).
func (w *walker) created(kind objKind, name string) {
	w.r.reg.add(kind, name)
	label := ""
	switch {
	case kind == kindFunction && isBuiltinFunction(name):
		label = "function"
	case (kind == kindType || kind == kindRelation) && isBuiltinType(name):
		label = "type"
	}
	if label != "" {
		w.warn("%s has the name of a built-in %s of pg_catalog: it is created in the target schema, but an unqualified use of the name means the built-in and is left unqualified (qualify it explicitly where the migration means its own %s): %s",
			name, label, label, snippet(w.stmtText()))
	}
}

var relationArgFunctions = map[string]bool{
	"nextval": true, "currval": true, "setval": true, "pg_get_serial_sequence": true,
	"to_regclass": true, "pg_relation_size": true, "pg_total_relation_size": true,
	"pg_table_size": true, "pg_indexes_size": true,
}

func (w *walker) funcCall(fc *FuncCall) {
	if w.done[fc] {
		return
	}
	w.done[fc] = true
	names := strs(fc.Funcname)
	if len(names) == 0 {
		return
	}
	base := names[len(names)-1]
	if len(names) == 1 || (len(names) == 2 && names[0] == "pg_catalog") {
		switch {
		case relationArgFunctions[base] && len(fc.Args) > 0:
			w.relationLiteral(fc.Args[0])
		case base == "current_schema" || base == "current_schemas":
			w.warnAt(fc.Location, "current_schema() returns the first schema of search_path, not %s: %s", w.r.schema, snippet(w.stmtText()))
		case base == "set_config" && len(fc.Args) > 0 && strings.EqualFold(constString(fc.Args[0]), "search_path"):
			w.warnAt(fc.Location, "migration changes search_path: %s", snippet(w.stmtText()))
		}
	}
	if len(names) == 1 && !w.learnOnly {
		if ref := w.funcRef(base, fc.Location); ref != nil && w.qualifyAtRef(fc.Location, base, ref) {
			fc.Funcname = prepend(fc.Funcname, refNode(ref))
		}
	}
}

func (w *walker) typeCast(tc *TypeCast) {
	if tc.TypeName == nil {
		return
	}
	names := strs(tc.TypeName.Names)
	if len(names) == 0 {
		return
	}
	switch names[len(names)-1] {
	case "regclass":
		w.literal(stringCastArg(tc.Arg), func(n string) bool { return w.shouldQualifyRelation(n, false) })
	case "regtype":
		w.literal(tc.Arg, func(n string) bool { return w.r.reg.isType(n) && !w.builtinUse("type", n, -1) })
	case "regproc", "regprocedure":
		w.literal(tc.Arg, func(n string) bool { return w.r.reg.functions[n] && !w.builtinUse("function", n, -1) })
	}
}

// stringCastArg looks through the casts of a string constant to text, varchar
// and regclass, as old pg_dump wrote them: nextval(('s'::text)::regclass),
// 's'::text::regclass.
func stringCastArg(n Node) Node {
	for {
		tc, ok := n.(*TypeCast)
		if !ok || tc.TypeName == nil {
			return n
		}
		names := strs(tc.TypeName.Names)
		if len(names) == 0 || len(names) > 2 || len(names) == 2 && names[0] != "pg_catalog" {
			return n
		}
		switch names[len(names)-1] {
		case "text", "varchar", "regclass":
			n = tc.Arg
		default:
			return n
		}
	}
}

// usedFunctionName qualifies a function name that the statement uses (the
// trigger function) if the function is created by the migrations.
func (w *walker) usedFunctionName(names *[]Node) {
	parts := strs(*names)
	if len(parts) != 1 || w.learnOnly {
		return
	}
	loc := int32(-1)
	if s, ok := (*names)[0].(*String); ok {
		loc = s.Loc
	}
	if ref := w.funcRef(parts[0], loc); ref != nil {
		w.qualifyFirstRef(names, ref)
	}
}

// ---- names with a position of their own -------------------------------------

// defName handles the name of an object the statement defines (CREATE
// TYPE/DOMAIN/..., ALTER TYPE, ...). The names are String nodes that carry
// their positions.
func (w *walker) defName(names *[]Node, kind objKind) {
	parts := strs(*names)
	if len(parts) == 0 {
		return
	}
	if len(parts) == 1 || (len(parts) == 2 && parts[0] == w.r.schema) {
		w.created(kind, parts[len(parts)-1])
	}
	if len(parts) != 1 || w.learnOnly {
		return
	}
	w.qualifyFirst(names)
}

// qualifyFirst qualifies the name list names: the schema goes before its
// first name, and the list gets the schema as a new first element.
func (w *walker) qualifyFirst(names *[]Node) bool { return w.qualifyFirstRef(names, w.r.targetRef()) }

// qualifyFirstRef is qualifyFirst with the schema ref.
func (w *walker) qualifyFirstRef(names *[]Node, ref *schemaRef) bool {
	if len(*names) == 0 {
		return false
	}
	first, ok := (*names)[0].(*String)
	if !ok || first.Loc < 0 {
		w.fail("no position for the name %q in: %s", strings.Join(strs(*names), "."), snippet(w.stmtText()))
		return false
	}
	if !w.qualifyAtRef(first.Loc, first.Sval, ref) {
		return false
	}
	*names = prepend(*names, refNode(ref))
	return true
}

// objectList handles the object names of DROP, COMMENT ON, GRANT, ALTER ...
// OWNER and SET SCHEMA.
func (w *walker) objectList(objtype ObjectType, objects []Node) {
	if w.learnOnly {
		return
	}
	if !namedObjectType(objtype) {
		switch objtype {
		case OBJECT_OPCLASS, OBJECT_OPFAMILY, OBJECT_OPERATOR, OBJECT_AMOP, OBJECT_AMPROC:
			w.warn("%s is not rewritten: %s", objectLabel(objtype), snippet(w.stmtText()))
		}
		return
	}
	for _, obj := range objects {
		if w.err != nil {
			return
		}
		w.objectRef(objtype, obj)
	}
}

func (w *walker) objectRef(objtype ObjectType, obj Node) {
	switch o := obj.(type) {
	case *TypeName: // DROP/COMMENT ON TYPE, DOMAIN
		w.typeName(o, true)
		return
	case *ObjectWithArgs: // functions
		w.objectWithArgs(o, true)
		return
	case *List:
		w.objectNames(objtype, o)
	}
}

// objectNames qualifies the object named by a list of names.
func (w *walker) objectNames(objtype ObjectType, list *List) {
	parts := strs(list.Items)
	if objtype == OBJECT_DOMCONSTRAINT { // CONSTRAINT c ON DOMAIN d: [d, c]
		if len(list.Items) == 2 {
			if tn, ok := list.Items[0].(*TypeName); ok {
				w.typeName(tn, true)
			}
		}
		return
	}
	switch objtype {
	case OBJECT_TRIGGER, OBJECT_POLICY, OBJECT_RULE, OBJECT_TABCONSTRAINT:
		// name ON table: the list is [table..., name]
		if len(list.Items) < 2 {
			return
		}
		table := list.Items[:len(list.Items)-1]
		tparts := strs(table)
		if len(tparts) == 1 && w.shouldQualifyRelation(tparts[0], false) {
			w.qualifyFirst(&list.Items)
		}
		return
	}
	if len(parts) == 0 {
		return
	}
	var qualify bool
	switch {
	case objtype == OBJECT_COLUMN: // table.column
		qualify = len(parts) == 2 && w.shouldQualifyRelation(parts[0], false)
	case isRelationType(objtype):
		qualify = len(parts) == 1 && w.shouldQualifyRelation(parts[0], false)
	default: // types, domains, statistics, collations: always ours
		qualify = len(parts) == 1
	}
	if qualify {
		w.qualifyFirst(&list.Items)
	}
}

func (w *walker) objectWithArgs(o *ObjectWithArgs, definition bool) {
	if o == nil || w.done[o] {
		return
	}
	parts := strs(o.Objname)
	if len(parts) == 0 {
		return
	}
	w.done[o] = true
	if len(parts) == 1 && (definition || w.r.reg.functions[parts[0]] && !w.builtinUse("function", parts[0], -1)) {
		w.qualifyFirst(&o.Objname)
	}
}

func (w *walker) renameStmt(n *RenameStmt) {
	switch {
	case isRelationType(n.RenameType):
		if n.Relation != nil && (n.Relation.Schemaname == "" || n.Relation.Schemaname == w.r.schema) {
			w.created(kindRelation, n.Newname)
		}
	case n.RenameType == OBJECT_TYPE || n.RenameType == OBJECT_DOMAIN:
		w.created(kindType, n.Newname)
		w.objectList(n.RenameType, []Node{n.Object})
	case isFunctionType(n.RenameType):
		w.created(kindFunction, n.Newname)
		w.objectList(n.RenameType, []Node{n.Object})
	case n.RenameType == OBJECT_DOMCONSTRAINT: // ALTER DOMAIN d RENAME CONSTRAINT
		w.objectList(OBJECT_DOMAIN, []Node{n.Object})
	case namedObjectType(n.RenameType):
		if _, ok := n.Object.(*List); ok { // statistics, collations, text search
			w.objectList(n.RenameType, []Node{n.Object})
		}
	}
}

// ownedBy qualifies the table of CREATE/ALTER SEQUENCE ... OWNED BY
// table.column.
func (w *walker) ownedBy(opts []Node) {
	d := defElem(opts, "owned_by")
	if d == nil || w.learnOnly {
		return
	}
	list, ok := d.Arg.(*List)
	if !ok {
		return
	}
	parts := strs(list.Items)
	if len(parts) != 2 || !w.shouldQualifyRelation(parts[0], false) {
		return
	}
	w.qualifyFirst(&list.Items)
}

func isRelationType(t ObjectType) bool {
	switch t {
	case OBJECT_TABLE, OBJECT_VIEW, OBJECT_MATVIEW, OBJECT_SEQUENCE, OBJECT_INDEX, OBJECT_FOREIGN_TABLE:
		return true
	}
	return false
}

func isFunctionType(t ObjectType) bool {
	switch t {
	case OBJECT_FUNCTION, OBJECT_PROCEDURE, OBJECT_ROUTINE, OBJECT_AGGREGATE:
		return true
	}
	return false
}

// namedObjectType reports whether objects of the type are qualified by the
// rewriter when a statement names them (DROP, COMMENT ON, ...).
func namedObjectType(t ObjectType) bool {
	switch t {
	case OBJECT_TABLE, OBJECT_FOREIGN_TABLE, OBJECT_VIEW, OBJECT_MATVIEW, OBJECT_SEQUENCE, OBJECT_INDEX,
		OBJECT_COLUMN, OBJECT_TYPE, OBJECT_DOMAIN, OBJECT_FUNCTION, OBJECT_PROCEDURE, OBJECT_ROUTINE,
		OBJECT_AGGREGATE, OBJECT_TRIGGER, OBJECT_POLICY, OBJECT_RULE, OBJECT_TABCONSTRAINT,
		OBJECT_DOMCONSTRAINT, OBJECT_STATISTIC_EXT, OBJECT_COLLATION, OBJECT_CONVERSION,
		OBJECT_TSPARSER, OBJECT_TSDICTIONARY, OBJECT_TSTEMPLATE, OBJECT_TSCONFIGURATION:
		return true
	}
	return false
}

// ---- edits -----------------------------------------------------------------

// tokenAt scans the token that starts at offset loc of the text.
func (w *walker) tokenAt(loc int32) (lex.Item, error) {
	if loc < 0 || int(loc) >= len(w.src) {
		return lex.Item{}, fmt.Errorf("no token at offset %d", loc)
	}
	it, err := lex.NewScanner(w.src[loc:]).Next()
	if err != nil || it.Tok == 0 {
		return lex.Item{}, fmt.Errorf("no token at offset %d", loc)
	}
	return it, nil
}

// qualifyAt inserts the schema before the identifier at byte offset loc,
// after checking that the position points at the expected name.
func (w *walker) qualifyAt(loc int32, name string) bool {
	return w.qualifyAtRef(loc, name, w.r.targetRef())
}

// qualifyAtRef is qualifyAt with the schema ref.
func (w *walker) qualifyAtRef(loc int32, name string, ref *schemaRef) bool {
	it, err := w.tokenAt(loc)
	if err != nil {
		w.fail("%v for %q in: %s", err, name, snippet(w.stmtText()))
		return false
	}
	// the value of U&"..." is not decoded by the scanner (the parser does it
	// with the UESCAPE clause), so its text cannot be compared with the name;
	// the check of the whole tree after the edit covers it
	ident := it.Tok == lex.IDENT || it.Tok == lex.UIDENT || (it.Kind != lex.NoKeyword && it.Kind != lex.ReservedKeyword)
	if !ident || (it.Tok != lex.UIDENT && it.Str != name) {
		w.fail("the token at offset %d is %q, expected %q", loc, w.src[int(loc)+int(it.Start):int(loc)+int(it.End)], name)
		return false
	}
	w.edits = append(w.edits, edit{start: int(loc), end: int(loc), text: ref.prefix})
	return true
}

func (w *walker) schemaNode() *String { return refNode(w.r.targetRef()) }

// refNode is the schema of ref as a name in a name list.
func refNode(ref *schemaRef) *String { return &String{Sval: ref.name, Loc: -1} }

func prepend(list []Node, n Node) []Node { return append([]Node{n}, list...) }

// strs returns the String values of a name list, or nil if the list holds
// anything else (A_Star, ...).
func strs(nodes []Node) []string {
	out := make([]string, 0, len(nodes))
	for _, n := range nodes {
		s, ok := n.(*String)
		if !ok {
			return nil
		}
		out = append(out, s.Sval)
	}
	return out
}

// constString is the value of a string constant, or "".
func constString(n Node) string {
	if c, ok := n.(*A_Const); ok {
		if s, ok := c.Val.(*String); ok {
			return s.Sval
		}
	}
	return ""
}

func defElem(opts []Node, name string) *DefElem {
	for _, o := range opts {
		if d, ok := o.(*DefElem); ok && d.Defname == name {
			return d
		}
	}
	return nil
}

// language returns the LANGUAGE option, or def (plpgsql for DO, sql for a
// function with a SQL-standard body).
func language(opts []Node, def string) string {
	if d := defElem(opts, "language"); d != nil {
		return strings.ToLower(constStringValue(d.Arg))
	}
	return def
}

// constStringValue is the Sval of a String node.
func constStringValue(n Node) string {
	if s, ok := n.(*String); ok {
		return s.Sval
	}
	return ""
}

// objectLabel words an object type for a warning: OBJECT_TSCONFIGURATION is
// "text search configuration", OBJECT_OPCLASS "operator class".
func objectLabel(t ObjectType) string {
	switch t {
	case OBJECT_TSPARSER:
		return "text search parser"
	case OBJECT_TSDICTIONARY:
		return "text search dictionary"
	case OBJECT_TSTEMPLATE:
		return "text search template"
	case OBJECT_TSCONFIGURATION:
		return "text search configuration"
	case OBJECT_OPCLASS:
		return "operator class"
	case OBJECT_OPFAMILY:
		return "operator family"
	}
	return strings.ToLower(strings.ReplaceAll(strings.TrimPrefix(t.String(), "OBJECT_"), "_", " "))
}

// createExtension decides what CREATE EXTENSION gets. A schema in the
// statement stays, and the extension is taken to be there when the uses of
// its objects are to be qualified, whatever schema the options give it. A statement without one gets the schema of
// the extension if it is configured, or the target schema under
// ExtensionsInSchema; otherwise it stays and a warning says where the objects
// go.
func (w *walker) createExtension(n *CreateExtensionStmt) {
	explicit := ""
	if d := defElem(n.Options, "schema"); d != nil {
		explicit = constStringValue(d.Arg)
	}
	ref, active := w.r.configuredExt[n.Extname]
	if !active && w.r.extensionsInSchema {
		ref, active = w.r.targetRef(), true
	}
	switch {
	case explicit != "":
		// the name comes from the SQL, any name can be quoted
		if active {
			w.r.moveExtension(n.Extname, &schemaRef{name: explicit, prefix: subst.QuoteIdent(explicit) + "."})
		}
		return
	case !active:
		w.warn("CREATE EXTENSION without SCHEMA creates objects in the first schema of search_path: %s", snippet(w.stmtText()))
		return
	}
	w.r.activateExtension(n.Extname, ref)
	if contribObjects[n.Extname].ops {
		w.warn("the operators of extension %s are found through the search_path, and the library does not rewrite operators: with the extension outside it the core's operators are used instead (citext = becomes text =): %s",
			n.Extname, snippet(w.stmtText()))
	}
	if !w.r.knowsExtension(n.Extname) {
		w.warn("the objects of extension %s are not known to the library, so their unqualified uses are not rewritten (give the names in ExtensionObjects): %s", n.Extname, snippet(w.stmtText()))
	}
	if w.learnOnly {
		return
	}
	end := -1
	sc := lex.NewScanner(w.src[w.stmtStart:w.stmtEnd])
	for {
		it, err := sc.Next()
		if err != nil {
			w.fail("cannot scan the statement: %v", err)
			return
		}
		if it.Tok == 0 {
			break
		}
		if it.Tok != ';' {
			end = int(it.End)
		}
	}
	if end < 0 {
		w.fail("cannot find the end of CREATE EXTENSION")
		return
	}
	// the options come in any order, so the end is as good a place as any; it
	// is the end of the last token, not of the statement, which may end with
	// a comment
	pos := w.stmtStart + end
	w.edits = append(w.edits, edit{start: pos, end: pos, text: " SCHEMA " + subst.QuoteIdent(ref.name)})
	n.Options = append(n.Options, &DefElem{Defname: "schema", Arg: refNode(ref), Defaction: DEFELEM_UNSPEC, Location: -1})
}
