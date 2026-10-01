package pgqrewrite

import (
	"fmt"
	"strings"

	pg "github.com/pganalyze/pg_query_go/v6"
	"google.golang.org/protobuf/proto"
	"google.golang.org/protobuf/reflect/protoreflect"
)

// walker visits the parse tree of one SQL text, collects edits and applies
// the same changes to the tree for verification.
type walker struct {
	r         *Rewriter
	src       string
	toks      *tokens
	inBody    bool // inside a function body or DO block
	learnOnly bool

	edits []edit
	warns []string
	err   error

	scopes []map[string]bool // CTE names visible at the current node
	done   map[proto.Message]bool

	stmtStart, stmtEnd int
	tokStart, tokEnd   int
	catalogRef         bool
}

func (w *walker) beginStmt(raw *pg.RawStmt) {
	w.stmtStart = int(raw.StmtLocation)
	w.stmtEnd = len(w.src)
	if raw.StmtLen > 0 {
		w.stmtEnd = w.stmtStart + int(raw.StmtLen)
	}
	w.tokStart = w.toks.firstFrom(w.stmtStart)
	w.tokEnd = w.toks.firstFrom(w.stmtEnd)
	w.catalogRef = false
}

func (w *walker) endStmt() {
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

func (w *walker) warn(format string, args ...any) {
	if !w.learnOnly {
		w.warns = append(w.warns, fmt.Sprintf(format, args...))
	}
}

// visit dispatches on the node type and descends into the children.
func (w *walker) visit(m protoreflect.Message) {
	if w.err != nil || !m.IsValid() {
		return
	}
	if _, ok := m.Interface().(*pg.Node); ok {
		if fd := m.WhichOneof(m.Descriptor().Oneofs().Get(0)); fd != nil {
			w.visit(m.Get(fd).Message())
		}
		return
	}
	if w.handle(m) {
		return
	}
	w.children(m)
}

// children visits all message fields of m except the skipped ones.
func (w *walker) children(m protoreflect.Message, skip ...protoreflect.Name) {
	fields := m.Descriptor().Fields()
next:
	for i := 0; i < fields.Len(); i++ {
		fd := fields.Get(i)
		if fd.Kind() != protoreflect.MessageKind {
			continue
		}
		for _, s := range skip {
			if fd.Name() == s {
				continue next
			}
		}
		if fd.IsList() {
			l := m.Get(fd).List()
			for j := 0; j < l.Len(); j++ {
				w.visit(l.Get(j).Message())
			}
		} else if m.Has(fd) {
			w.visit(m.Get(fd).Message())
		}
	}
}

// handle processes node types with special rules. It returns true when the
// handler has visited the children itself.
func (w *walker) handle(m protoreflect.Message) bool {
	switch n := m.Interface().(type) {
	case *pg.RangeVar:
		w.rangeVar(n, true)
	case *pg.TypeName:
		w.typeName(n, false)
	case *pg.FuncCall:
		w.funcCall(n)
	case *pg.TypeCast:
		w.typeCast(n)

	case *pg.SelectStmt:
		w.withClause(n.WithClause, func() { w.children(m, "with_clause") })
		return true
	case *pg.InsertStmt:
		w.rangeVar(n.Relation, false) // a DML target is never a CTE
		w.withClause(n.WithClause, func() { w.children(m, "relation", "with_clause") })
		return true
	case *pg.UpdateStmt:
		w.rangeVar(n.Relation, false)
		w.withClause(n.WithClause, func() { w.children(m, "relation", "with_clause") })
		return true
	case *pg.DeleteStmt:
		w.rangeVar(n.Relation, false)
		w.withClause(n.WithClause, func() { w.children(m, "relation", "with_clause") })
		return true
	case *pg.MergeStmt:
		w.rangeVar(n.Relation, false)
		w.withClause(n.WithClause, func() { w.children(m, "relation", "with_clause") })
		return true

	case *pg.LockingClause:
		// FOR UPDATE OF t names FROM items and must stay unqualified
		for _, r := range n.LockedRels {
			if rv := r.GetRangeVar(); rv != nil {
				w.done[rv] = true
			}
		}
	case *pg.CreateStmt:
		w.register(n.Relation, kindRelation)
	case *pg.IntoClause:
		w.register(n.Rel, kindRelation)
	case *pg.ViewStmt:
		w.register(n.View, kindRelation)
	case *pg.CreateSeqStmt:
		w.register(n.Sequence, kindRelation)
		w.ownedBy(n.Options)
	case *pg.AlterSeqStmt:
		w.ownedBy(n.Options)
	case *pg.IndexStmt:
		if n.Idxname != "" && n.Relation != nil && (n.Relation.Schemaname == "" || n.Relation.Schemaname == w.r.schema) {
			w.r.reg.add(kindRelation, n.Idxname)
		}
	case *pg.CompositeTypeStmt:
		w.register(n.Typevar, kindRelation)
		w.register(n.Typevar, kindType)
	case *pg.CreateEnumStmt:
		w.defName(&n.TypeName, kindType, pg.Token_TYPE_P)
	case *pg.CreateRangeStmt:
		w.defName(&n.TypeName, kindType, pg.Token_TYPE_P)
	case *pg.CreateDomainStmt:
		w.defName(&n.Domainname, kindType, pg.Token_DOMAIN_P)
	case *pg.AlterEnumStmt:
		w.defName(&n.TypeName, kindNone, pg.Token_TYPE_P)
	case *pg.AlterDomainStmt:
		w.defName(&n.TypeName, kindNone, pg.Token_DOMAIN_P)
	case *pg.AlterTypeStmt:
		w.defName(&n.TypeName, kindNone, pg.Token_TYPE_P)
	case *pg.DefineStmt:
		switch n.Kind {
		case pg.ObjectType_OBJECT_TYPE:
			w.defName(&n.Defnames, kindType, pg.Token_TYPE_P)
		case pg.ObjectType_OBJECT_AGGREGATE:
			w.defName(&n.Defnames, kindFunction, pg.Token_AGGREGATE)
		case pg.ObjectType_OBJECT_COLLATION, pg.ObjectType_OBJECT_TSPARSER, pg.ObjectType_OBJECT_TSDICTIONARY,
			pg.ObjectType_OBJECT_TSTEMPLATE, pg.ObjectType_OBJECT_TSCONFIGURATION:
			w.defName(&n.Defnames, kindNone, anchorsFor(n.Kind)...)
		default:
			w.warn("%s is not rewritten: %s", n.Kind, snippet(w.stmtText()))
		}
	case *pg.CreateStatsStmt:
		w.defName(&n.Defnames, kindNone, pg.Token_STATISTICS)
	case *pg.AlterStatsStmt:
		w.defName(&n.Defnames, kindNone, pg.Token_STATISTICS)

	case *pg.CreateFunctionStmt:
		w.createFunction(n)
	case *pg.DoStmt:
		w.doStmt(n)
	case *pg.CreateTrigStmt:
		for _, tr := range n.TransitionRels {
			if t := tr.GetTriggerTransition(); t != nil {
				w.r.reg.transition[t.Name] = true
			}
		}
		w.usedFunctionName(&n.Funcname, pg.Token_EXECUTE)
	case *pg.CreateEventTrigStmt:
		w.usedFunctionName(&n.Funcname, pg.Token_EXECUTE)
	case *pg.CreateCastStmt:
		if n.Func != nil && !w.learnOnly {
			if c := w.after(pg.Token_FUNCTION); c >= 0 {
				w.objectWithArgs(n.Func, false, &c)
			}
		}
	case *pg.AlterFunctionStmt:
		if !w.learnOnly {
			if c := w.after(anchorsFor(n.Objtype)...); c >= 0 {
				w.objectWithArgs(n.Func, true, &c)
			}
		}

	case *pg.DropStmt:
		w.objectList(n.RemoveType, n.Objects)
	case *pg.CommentStmt:
		w.objectList(n.Objtype, []*pg.Node{n.Object})
	case *pg.RenameStmt:
		w.renameStmt(n)
	case *pg.AlterOwnerStmt:
		if n.Object != nil {
			w.objectList(n.ObjectType, []*pg.Node{n.Object})
		}
	case *pg.AlterObjectSchemaStmt:
		if n.Object != nil {
			w.objectList(n.ObjectType, []*pg.Node{n.Object})
		}
	case *pg.GrantStmt:
		if n.Targtype == pg.GrantTargetType_ACL_TARGET_OBJECT && !isRelationType(n.Objtype) {
			w.objectList(n.Objtype, n.Objects)
		}

	case *pg.CreateConversionStmt:
		w.defName(&n.ConversionName, kindNone, pg.Token_CONVERSION_P)
	case *pg.CreateOpClassStmt, *pg.CreateOpFamilyStmt, *pg.AlterOpFamilyStmt:
		w.warn("operator classes and families are not rewritten: %s", snippet(w.stmtText()))
	case *pg.CreateExtensionStmt:
		if defElem(n.Options, "schema") == nil {
			w.warn("CREATE EXTENSION without SCHEMA creates objects in the first schema of search_path: %s", snippet(w.stmtText()))
		}
	case *pg.VariableSetStmt:
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
	switch {
	case name == "":
		return false
	case cteCheck && w.inCTE(name):
		return false
	case w.r.reg.temp[name]:
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

func (w *walker) rangeVar(rv *pg.RangeVar, cteCheck bool) {
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
		w.r.reg.temp[rv.Relname] = true
		return
	}
	if !w.shouldQualifyRelation(rv.Relname, cteCheck) || w.learnOnly {
		return
	}
	if w.qualifyAt(int(rv.Location), rv.Relname) {
		rv.Schemaname = w.r.schema
	}
}

// register remembers a created relation or type.
func (w *walker) register(rv *pg.RangeVar, kind objKind) {
	if rv == nil {
		return
	}
	if rv.Relpersistence == "t" {
		w.r.reg.temp[rv.Relname] = true
		return
	}
	if rv.Schemaname == "" || rv.Schemaname == w.r.schema {
		w.r.reg.add(kind, rv.Relname)
	}
}

// relationLiteral qualifies a string literal that names a relation:
// nextval('seq'), 'tbl'::regclass, pg_get_serial_sequence('tbl', 'col').
func (w *walker) relationLiteral(n *pg.Node) {
	if tc := n.GetTypeCast(); tc != nil {
		n = tc.Arg
	}
	w.literal(n, func(name string) bool { return w.shouldQualifyRelation(name, false) })
}

func (w *walker) literal(n *pg.Node, qualify func(name string) bool) {
	c := n.GetAConst()
	if c == nil || c.GetSval() == nil || w.done[c] || w.learnOnly {
		return
	}
	w.done[c] = true
	val := c.GetSval().Sval
	head := val
	if i := strings.IndexByte(head, '('); i >= 0 { // regprocedure: f(int)
		head = head[:i]
	}
	parts, ok := splitQualifiedName(head)
	if !ok || len(parts) != 1 || !qualify(parts[0]) {
		return
	}
	i := w.toks.at(int(c.Location))
	if i < 0 || !w.toks.is(i, pg.Token_SCONST) {
		w.fail("cannot locate string literal %q", val)
		return
	}
	newVal := w.r.prefix + strings.TrimSpace(val)
	tok := w.toks.list[i]
	w.edits = append(w.edits, edit{start: int(tok.Start), end: int(tok.End), text: quoteLiteral(newVal)})
	c.GetSval().Sval = newVal
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

// withClause visits the CTEs with PostgreSQL visibility rules and then calls
// rest with all CTE names in scope. A non-recursive CTE sees only the CTEs
// defined before it.
func (w *walker) withClause(wc *pg.WithClause, rest func()) {
	if wc == nil {
		rest()
		return
	}
	var names []string
	for _, c := range wc.Ctes {
		if cte := c.GetCommonTableExpr(); cte != nil {
			names = append(names, cte.Ctename)
		}
	}
	if wc.Recursive {
		w.push(names)
		for _, c := range wc.Ctes {
			w.visit(c.ProtoReflect())
		}
		rest()
		w.pop()
		return
	}
	for i, c := range wc.Ctes {
		w.push(names[:i])
		w.visit(c.ProtoReflect())
		w.pop()
	}
	w.push(names)
	rest()
	w.pop()
}

// ---- types and functions ---------------------------------------------------

func (w *walker) typeName(tn *pg.TypeName, definition bool) {
	if tn == nil || w.done[tn] {
		return
	}
	w.done[tn] = true
	names := strs(tn.Names)
	if len(names) == 0 || w.learnOnly {
		return
	}
	if tn.PctType { // table.column%TYPE
		if len(names) == 2 && w.shouldQualifyRelation(names[0], false) && w.qualifyAt(int(tn.Location), names[0]) {
			tn.Names = prepend(tn.Names, w.schemaNode())
		}
		return
	}
	if len(names) != 1 || !(definition || w.r.reg.isType(names[0])) {
		return
	}
	if tn.Location < 0 { // e.g. COMMENT ON CONSTRAINT c ON DOMAIN d
		if idx := w.locate(names, w.tokStart); idx >= 0 {
			w.qualifyTok(idx)
			tn.Names = prepend(tn.Names, w.schemaNode())
		}
		return
	}
	if w.qualifyAt(int(tn.Location), names[0]) {
		tn.Names = prepend(tn.Names, w.schemaNode())
	}
}

var relationArgFunctions = map[string]bool{
	"nextval": true, "currval": true, "setval": true, "pg_get_serial_sequence": true,
	"to_regclass": true, "pg_relation_size": true, "pg_total_relation_size": true,
	"pg_table_size": true, "pg_indexes_size": true,
}

func (w *walker) funcCall(fc *pg.FuncCall) {
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
			w.warn("current_schema() returns the first schema of search_path, not %s: %s", w.r.schema, snippet(w.stmtText()))
		case base == "set_config" && len(fc.Args) > 0 && strings.EqualFold(fc.Args[0].GetAConst().GetSval().GetSval(), "search_path"):
			w.warn("migration changes search_path: %s", snippet(w.stmtText()))
		}
	}
	if len(names) == 1 && w.r.reg.functions[base] && !w.learnOnly && w.qualifyAt(int(fc.Location), base) {
		fc.Funcname = prepend(fc.Funcname, w.schemaNode())
	}
}

func (w *walker) typeCast(tc *pg.TypeCast) {
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
		w.literal(tc.Arg, w.r.reg.isType)
	case "regproc", "regprocedure":
		w.literal(tc.Arg, func(n string) bool { return w.r.reg.functions[n] })
	}
}

// usedFunctionName qualifies a location-less function name (trigger function)
// if the function is created by the migrations.
func (w *walker) usedFunctionName(names *[]*pg.Node, anchor pg.Token) {
	parts := strs(*names)
	if len(parts) != 1 || !w.r.reg.functions[parts[0]] || w.learnOnly {
		return
	}
	from := w.after(anchor)
	if from < 0 {
		return
	}
	if idx := w.locate(parts, from); idx >= 0 {
		w.qualifyTok(idx)
		*names = prepend(*names, w.schemaNode())
	}
}

// ---- location-less names ---------------------------------------------------

// defName handles the name of an object defined by the statement (CREATE
// TYPE/DOMAIN/FUNCTION, ALTER TYPE, ...). The parser keeps no location for
// such names, so the name is found in the statement tokens after the anchor
// keyword.
func (w *walker) defName(names *[]*pg.Node, kind objKind, anchors ...pg.Token) {
	parts := strs(*names)
	if len(parts) == 0 {
		return
	}
	if len(parts) == 1 || (len(parts) == 2 && parts[0] == w.r.schema) {
		w.r.reg.add(kind, parts[len(parts)-1])
	}
	if len(parts) != 1 || w.learnOnly {
		return
	}
	from := w.after(anchors...)
	if from < 0 {
		return
	}
	if idx := w.locate(parts, from); idx >= 0 {
		w.qualifyTok(idx)
		*names = prepend(*names, w.schemaNode())
	}
}

// objectList handles object names of DROP, COMMENT ON, GRANT, ALTER ... OWNER
// and SET SCHEMA.
func (w *walker) objectList(objtype pg.ObjectType, objects []*pg.Node) {
	if w.learnOnly {
		return
	}
	anchors := anchorsFor(objtype)
	if anchors == nil {
		switch objtype {
		case pg.ObjectType_OBJECT_OPCLASS, pg.ObjectType_OBJECT_OPFAMILY, pg.ObjectType_OBJECT_OPERATOR,
			pg.ObjectType_OBJECT_AMOP, pg.ObjectType_OBJECT_AMPROC:
			w.warn("%s is not rewritten: %s", objtype, snippet(w.stmtText()))
		}
		return
	}
	cursor := w.after(anchors...)
	if cursor < 0 {
		return
	}
	for _, obj := range objects {
		if w.err != nil {
			return
		}
		w.objectRef(objtype, obj, &cursor)
	}
}

func (w *walker) objectRef(objtype pg.ObjectType, obj *pg.Node, cursor *int) {
	if tn := obj.GetTypeName(); tn != nil { // DROP/COMMENT ON TYPE, DOMAIN
		w.typeName(tn, true)
		return
	}
	if o := obj.GetObjectWithArgs(); o != nil { // functions
		w.objectWithArgs(o, true, cursor)
		return
	}
	list := obj.GetList()
	if list == nil {
		return
	}
	parts := strs(list.Items)
	if len(parts) == 0 {
		return
	}
	switch objtype {
	case pg.ObjectType_OBJECT_TRIGGER, pg.ObjectType_OBJECT_POLICY, pg.ObjectType_OBJECT_RULE, pg.ObjectType_OBJECT_TABCONSTRAINT:
		// name ON table: the list is [table..., name]
		table := parts[:len(parts)-1]
		i := w.locate(parts[len(parts)-1:], *cursor)
		if i < 0 {
			return
		}
		on := w.toks.findToken(i+1, w.tokEnd, pg.Token_ON)
		if on < 0 {
			w.fail("ON not found: %s", snippet(w.stmtText()))
			return
		}
		idx := w.locate(table, on+1)
		if idx < 0 {
			return
		}
		*cursor = idx + 2*len(table) - 1
		if len(table) == 1 && w.shouldQualifyRelation(table[0], false) {
			w.qualifyTok(idx)
			list.Items = prepend(list.Items, w.schemaNode())
		}
		return
	}
	idx := w.locate(parts, *cursor)
	if idx < 0 {
		return
	}
	*cursor = idx + 2*len(parts) - 1
	var qualify bool
	switch {
	case objtype == pg.ObjectType_OBJECT_COLUMN: // table.column
		qualify = len(parts) == 2 && w.shouldQualifyRelation(parts[0], false)
	case isRelationType(objtype):
		qualify = len(parts) == 1 && w.shouldQualifyRelation(parts[0], false)
	default: // types, domains, statistics, collations: always ours
		qualify = len(parts) == 1
	}
	if qualify {
		w.qualifyTok(idx)
		list.Items = prepend(list.Items, w.schemaNode())
	}
}

func (w *walker) objectWithArgs(o *pg.ObjectWithArgs, definition bool, cursor *int) {
	parts := strs(o.Objname)
	if len(parts) == 0 || w.done[o] {
		return
	}
	w.done[o] = true
	idx := w.locate(parts, *cursor)
	if idx < 0 {
		return
	}
	*cursor = idx + 2*len(parts) - 1
	if len(parts) == 1 && (definition || w.r.reg.functions[parts[0]]) {
		w.qualifyTok(idx)
		o.Objname = prepend(o.Objname, w.schemaNode())
	}
}

func (w *walker) renameStmt(n *pg.RenameStmt) {
	switch {
	case isRelationType(n.RenameType):
		if n.Relation != nil && (n.Relation.Schemaname == "" || n.Relation.Schemaname == w.r.schema) {
			w.r.reg.add(kindRelation, n.Newname)
		}
	case n.RenameType == pg.ObjectType_OBJECT_TYPE || n.RenameType == pg.ObjectType_OBJECT_DOMAIN:
		w.r.reg.add(kindType, n.Newname)
		w.objectList(n.RenameType, []*pg.Node{n.Object})
	case isFunctionType(n.RenameType):
		w.r.reg.add(kindFunction, n.Newname)
		w.objectList(n.RenameType, []*pg.Node{n.Object})
	case n.RenameType == pg.ObjectType_OBJECT_DOMCONSTRAINT: // ALTER DOMAIN d RENAME CONSTRAINT
		w.objectList(pg.ObjectType_OBJECT_DOMAIN, []*pg.Node{n.Object})
	case anchorsFor(n.RenameType) != nil && n.Object.GetList() != nil: // statistics, collations, text search
		w.objectList(n.RenameType, []*pg.Node{n.Object})
	}
}

// ownedBy qualifies the table of CREATE/ALTER SEQUENCE ... OWNED BY table.column.
func (w *walker) ownedBy(opts []*pg.Node) {
	d := defElem(opts, "owned_by")
	if d == nil || w.learnOnly {
		return
	}
	list := d.GetArg().GetList()
	if list == nil {
		return
	}
	parts := strs(list.Items)
	if len(parts) != 2 || !w.shouldQualifyRelation(parts[0], false) {
		return
	}
	if idx := w.locate(parts, w.toks.firstFrom(int(d.Location))); idx >= 0 {
		w.qualifyTok(idx)
		list.Items = prepend(list.Items, w.schemaNode())
	}
}

func isRelationType(t pg.ObjectType) bool {
	switch t {
	case pg.ObjectType_OBJECT_TABLE, pg.ObjectType_OBJECT_VIEW, pg.ObjectType_OBJECT_MATVIEW,
		pg.ObjectType_OBJECT_SEQUENCE, pg.ObjectType_OBJECT_INDEX, pg.ObjectType_OBJECT_FOREIGN_TABLE:
		return true
	}
	return false
}

func isFunctionType(t pg.ObjectType) bool {
	switch t {
	case pg.ObjectType_OBJECT_FUNCTION, pg.ObjectType_OBJECT_PROCEDURE,
		pg.ObjectType_OBJECT_ROUTINE, pg.ObjectType_OBJECT_AGGREGATE:
		return true
	}
	return false
}

// anchorsFor returns the keyword after which object names of the type start.
func anchorsFor(t pg.ObjectType) []pg.Token {
	switch t {
	case pg.ObjectType_OBJECT_TABLE, pg.ObjectType_OBJECT_FOREIGN_TABLE:
		return []pg.Token{pg.Token_TABLE}
	case pg.ObjectType_OBJECT_VIEW, pg.ObjectType_OBJECT_MATVIEW:
		return []pg.Token{pg.Token_VIEW}
	case pg.ObjectType_OBJECT_SEQUENCE:
		return []pg.Token{pg.Token_SEQUENCE}
	case pg.ObjectType_OBJECT_INDEX:
		return []pg.Token{pg.Token_INDEX}
	case pg.ObjectType_OBJECT_COLUMN:
		return []pg.Token{pg.Token_COLUMN}
	case pg.ObjectType_OBJECT_TYPE:
		return []pg.Token{pg.Token_TYPE_P}
	case pg.ObjectType_OBJECT_DOMAIN:
		return []pg.Token{pg.Token_DOMAIN_P}
	case pg.ObjectType_OBJECT_FUNCTION:
		return []pg.Token{pg.Token_FUNCTION}
	case pg.ObjectType_OBJECT_PROCEDURE:
		return []pg.Token{pg.Token_PROCEDURE}
	case pg.ObjectType_OBJECT_ROUTINE:
		return []pg.Token{pg.Token_ROUTINE}
	case pg.ObjectType_OBJECT_AGGREGATE:
		return []pg.Token{pg.Token_AGGREGATE}
	case pg.ObjectType_OBJECT_TRIGGER:
		return []pg.Token{pg.Token_TRIGGER}
	case pg.ObjectType_OBJECT_POLICY:
		return []pg.Token{pg.Token_POLICY}
	case pg.ObjectType_OBJECT_RULE:
		return []pg.Token{pg.Token_RULE}
	case pg.ObjectType_OBJECT_TABCONSTRAINT:
		return []pg.Token{pg.Token_CONSTRAINT}
	case pg.ObjectType_OBJECT_STATISTIC_EXT:
		return []pg.Token{pg.Token_STATISTICS}
	case pg.ObjectType_OBJECT_COLLATION:
		return []pg.Token{pg.Token_COLLATION}
	case pg.ObjectType_OBJECT_CONVERSION:
		return []pg.Token{pg.Token_CONVERSION_P}
	case pg.ObjectType_OBJECT_TSPARSER:
		return []pg.Token{pg.Token_PARSER}
	case pg.ObjectType_OBJECT_TSDICTIONARY:
		return []pg.Token{pg.Token_DICTIONARY}
	case pg.ObjectType_OBJECT_TSTEMPLATE:
		return []pg.Token{pg.Token_TEMPLATE}
	case pg.ObjectType_OBJECT_TSCONFIGURATION:
		return []pg.Token{pg.Token_CONFIGURATION}
	}
	return nil
}

// ---- edits -----------------------------------------------------------------

// after returns the token index following the first anchor keyword of the
// current statement.
func (w *walker) after(anchors ...pg.Token) int {
	i := w.toks.findToken(w.tokStart, w.tokEnd, anchors...)
	if i < 0 {
		w.fail("keyword %v not found in statement: %s", anchors, snippet(w.stmtText()))
		return -1
	}
	return i + 1
}

// locate finds a location-less name in the current statement.
func (w *walker) locate(parts []string, from int) int {
	idx := w.toks.findName(parts, from, w.tokEnd)
	if idx < 0 {
		w.fail("cannot locate %q in statement: %s", strings.Join(parts, "."), snippet(w.stmtText()))
	}
	return idx
}

// qualifyAt inserts the schema before the identifier at byte offset loc,
// after checking that the parser location points at the expected name.
func (w *walker) qualifyAt(loc int, name string) bool {
	i := w.toks.at(loc)
	if i < 0 {
		w.fail("no token at offset %d for %q", loc, name)
		return false
	}
	if id, ok := w.toks.ident(i); !ok || id != name {
		w.fail("token at offset %d is %q, expected %q", loc, w.toks.text(i), name)
		return false
	}
	w.qualifyTok(i)
	return true
}

func (w *walker) qualifyTok(i int) {
	pos := int(w.toks.list[i].Start)
	w.edits = append(w.edits, edit{start: pos, end: pos, text: w.r.prefix})
}

func (w *walker) schemaNode() *pg.Node { return pg.MakeStrNode(w.r.schema) }

func prepend(list []*pg.Node, n *pg.Node) []*pg.Node {
	return append([]*pg.Node{n}, list...)
}
