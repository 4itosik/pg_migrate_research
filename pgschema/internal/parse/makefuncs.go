package parse

// Ports of the functions of src/backend/nodes/makefuncs.c and of the value
// constructors of src/backend/nodes/value.c that the grammar uses. Names
// follow the C functions. A C null char pointer is an empty string and a
// null pointer is nil.

import . "github.com/4itosik/pg_migrate_research/pgschema/internal/ast"

// makeString is makeString; loc is the position of the name in the text
// (a field the library adds to String), -1 when it is not known.
func makeString(s string, loc int32) *String { return &String{Sval: s, Loc: loc} }

func makeInteger(i int32) *Integer { return &Integer{Ival: i} }

func makeFloat(s string) *Float { return &Float{Fval: s} }

func makeBoolean(b bool) *Boolean { return &Boolean{Boolval: b} }

func makeBitString(s string) *BitString { return &BitString{Bsval: s} }

func makeSimpleA_Expr(kind A_Expr_Kind, name string, lexpr, rexpr Node, location int32) *A_Expr {
	return &A_Expr{Kind: kind, Name: []Node{makeString(name, -1)}, Lexpr: lexpr, Rexpr: rexpr, Location: location}
}

func makeA_Expr(kind A_Expr_Kind, name []Node, lexpr, rexpr Node, location int32) *A_Expr {
	return &A_Expr{Kind: kind, Name: name, Lexpr: lexpr, Rexpr: rexpr, Location: location}
}

func makeBoolExpr(op BoolExprType, args []Node, location int32) *BoolExpr {
	return &BoolExpr{Boolop: op, Args: args, Location: location}
}

// relpersistencePermanent is RELPERSISTENCE_PERMANENT, the character 'p'.
const (
	relpersistencePermanent = "p"
	relpersistenceUnlogged  = "u"
	relpersistenceTemp      = "t"
)

func makeRangeVar(schemaname, relname string, location int32) *RangeVar {
	return &RangeVar{Schemaname: schemaname, Relname: relname, Inh: true, Relpersistence: relpersistencePermanent, Location: location}
}

func makeTypeName(typnam string) *TypeName {
	return makeTypeNameFromNameList([]Node{makeString(typnam, -1)})
}

func makeTypeNameFromNameList(names []Node) *TypeName {
	return &TypeName{Names: names, Typemod: -1, Location: -1}
}

func makeFuncCall(name, args []Node, format CoercionForm, location int32) *FuncCall {
	return &FuncCall{Funcname: name, Args: args, Funcformat: format, Location: location}
}

func makeDefElem(name string, arg Node, location int32) *DefElem {
	return &DefElem{Defname: name, Arg: arg, Defaction: DEFELEM_UNSPEC, Location: location}
}

func makeDefElemExtended(nameSpace, name string, arg Node, action DefElemAction, location int32) *DefElem {
	return &DefElem{Defnamespace: nameSpace, Defname: name, Arg: arg, Defaction: action, Location: location}
}

func makeStringConst(str string, location int32) Node {
	return &A_Const{Val: &String{Sval: str, Loc: -1}, Location: location}
}

func makeGroupingSet(kind GroupingSetKind, content []Node, location int32) *GroupingSet {
	return &GroupingSet{Kind: kind, Content: content, Location: location}
}

func makeJsonFormat(t JsonFormatType, enc JsonEncoding, location int32) *JsonFormat {
	return &JsonFormat{FormatType: t, Encoding: enc, Location: location}
}

func makeJsonKeyValue(key, value Node) Node {
	return &JsonKeyValue{Key: key, Value: as[*JsonValueExpr](value)}
}

func makeJsonIsPredicate(expr Node, format *JsonFormat, itemType JsonValueType, uniqueKeys bool, location int32) Node {
	return &JsonIsPredicate{Expr: expr, Format: format, ItemType: itemType, UniqueKeys: uniqueKeys, Location: location}
}

func makeJsonTablePathSpec(str, name string, stringLocation, nameLocation int32) *JsonTablePathSpec {
	return &JsonTablePathSpec{
		String:       makeStringConst(str, stringLocation),
		Name:         name,
		NameLocation: nameLocation,
		Location:     stringLocation,
	}
}

func makeJsonValueExpr(raw, formatted Node, format *JsonFormat) *JsonValueExpr {
	return &JsonValueExpr{RawExpr: raw, FormattedExpr: formatted, Format: format}
}

func makeJsonBehavior(btype JsonBehaviorType, expr Node, location int32) *JsonBehavior {
	return &JsonBehavior{Btype: btype, Expr: expr, Location: location}
}

func makeVacuumRelation(relation *RangeVar, oid uint32, vaCols []Node) *VacuumRelation {
	return &VacuumRelation{Relation: relation, Oid: oid, VaCols: vaCols}
}
