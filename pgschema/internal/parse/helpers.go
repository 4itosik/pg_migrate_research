// This file is derived from PostgreSQL (src/backend/parser/gram.y).
//
// Portions Copyright (c) 1996-2024, PostgreSQL Global Development Group
// Portions Copyright (c) 1994, Regents of the University of California
//
// PostgreSQL License: see ../../LICENSE.PostgreSQL.

package parse

// Ports of the C functions at the end of gram.y. Where C passes yyscanner
// for error reporting, these are methods of *parser.

import (
	"strings"

	. "github.com/4itosik/pg_migrate_research/pgschema/internal/ast"
)

func makeRawStmt(stmt Node, stmtLocation int32) *RawStmt {
	return &RawStmt{Stmt: stmt, StmtLocation: stmtLocation}
}

// updateRawStmtEnd adjusts a RawStmt to reflect that it does not run to the
// end of the string.
func updateRawStmtEnd(rs *RawStmt, endLocation int32) {
	// if the length is already set, keep it: "select foo ;; select bar" has
	// the same last statement for more than one semicolon
	if rs.StmtLen > 0 {
		return
	}
	rs.StmtLen = endLocation - rs.StmtLocation
}

// makeColumnRef generates a ColumnRef node, with an A_Indirection node added
// if there is any subscripting in the indirection list. Any field selection
// at the start of the indirection list goes into the fields of the ColumnRef.
// location is the position of the first name; the name itself is the first
// field.
func (p *parser) makeColumnRef(colname string, indirection []Node, location int32) Node {
	c := &ColumnRef{Location: location}
	nfields := 0
	for i, l := range indirection {
		switch l.(type) {
		case *A_Indices:
			ind := &A_Indirection{}
			if nfields == 0 {
				// all indirection goes to A_Indirection
				c.Fields = []Node{makeString(colname, location)}
				ind.Indirection = p.checkIndirection(indirection)
			} else {
				// split the list in two
				ind.Indirection = p.checkIndirection(append([]Node(nil), indirection[nfields:]...))
				c.Fields = append([]Node{makeString(colname, location)}, indirection[:nfields]...)
			}
			ind.Arg = c
			return ind
		case *A_Star:
			// only allowed at the end of a ColumnRef
			if i < len(indirection)-1 {
				p.yyerror("improper use of \"*\"")
			}
		}
		nfields++
	}
	// no subscripting: all indirection is added to the field list
	c.Fields = append([]Node{makeString(colname, location)}, indirection...)
	return c
}

func makeTypeCast(arg Node, typename *TypeName, location int32) Node {
	return &TypeCast{Arg: arg, TypeName: typename, Location: location}
}

func makeStringConstCast(str string, location int32, typename *TypeName) Node {
	return makeTypeCast(makeStringConst(str, location), typename, -1)
}

func makeIntConst(val int32, location int32) Node {
	return &A_Const{Val: &Integer{Ival: val}, Location: location}
}

func makeFloatConst(str string, location int32) Node {
	return &A_Const{Val: &Float{Fval: str}, Location: location}
}

func makeBoolAConst(state bool, location int32) Node {
	return &A_Const{Val: &Boolean{Boolval: state}, Location: location}
}

func makeBitStringConst(str string, location int32) Node {
	return &A_Const{Val: &BitString{Bsval: str}, Location: location}
}

func makeNullAConst(location int32) Node {
	return &A_Const{Isnull: true, Location: location}
}

// makeAConst makes an A_Const from an Integer or Float node.
func makeAConst(v Node, location int32) Node {
	switch v := v.(type) {
	case *Float:
		return makeFloatConst(v.Fval, location)
	case *Integer:
		return makeIntConst(v.Ival, location)
	}
	return nil // currently not used
}

func makeRoleSpec(typ RoleSpecType, location int32) *RoleSpec {
	return &RoleSpec{Roletype: typ, Location: location}
}

// checkQualifiedName checks the result of the qualified_name production: it
// is easiest to let the production allow subscripts and '*', which are
// rejected here.
func (p *parser) checkQualifiedName(names []Node) {
	for _, n := range names {
		if _, ok := n.(*String); !ok {
			p.yyerror("syntax error")
		}
	}
}

// checkFuncName checks the result of the func_name production.
func (p *parser) checkFuncName(names []Node) []Node {
	for _, n := range names {
		if _, ok := n.(*String); !ok {
			p.yyerror("syntax error")
		}
	}
	return names
}

// checkIndirection checks the result of the indirection production: '*' is
// only allowed at the end of the list.
func (p *parser) checkIndirection(indirection []Node) []Node {
	for i, n := range indirection {
		if _, ok := n.(*A_Star); ok && i < len(indirection)-1 {
			p.yyerror("improper use of \"*\"")
		}
	}
	return indirection
}

// extractArgTypes extracts, from a list of FunctionParameter nodes, the
// argument types of the input parameters: what is needed to look up an
// existing function.
func extractArgTypes(parameters []Node) []Node {
	var result []Node
	for _, n := range parameters {
		prm := as[*FunctionParameter](n)
		if prm.Mode != FUNC_PARAM_OUT && prm.Mode != FUNC_PARAM_TABLE {
			result = append(result, prm.ArgType)
		}
	}
	return result
}

// extractAggrArgTypes is extractArgTypes for the output of aggr_args.
func extractAggrArgTypes(aggrargs []Node) []Node {
	return extractArgTypes(asList(aggrargs[0]))
}

// makeOrderedSetArgs builds the result of the aggr_args production for the
// case where both lists are nonempty.
func (p *parser) makeOrderedSetArgs(directargs, orderedargs []Node) []Node {
	lastd := as[*FunctionParameter](directargs[len(directargs)-1])
	// no restriction unless the last direct argument is VARIADIC
	if lastd.Mode == FUNC_PARAM_VARIADIC {
		firsto := as[*FunctionParameter](orderedargs[0])
		if len(orderedargs) != 1 || firsto.Mode != FUNC_PARAM_VARIADIC || !nodesEqual(lastd.ArgType, firsto.ArgType) {
			p.fail(exprLocation(firsto.ArgType), "an ordered-set aggregate with a VARIADIC direct argument must have one VARIADIC aggregated argument of the same data type")
		}
		// drop the duplicate VARIADIC argument from the internal form
		orderedargs = nil
	}
	ndirectargs := makeInteger(int32(len(directargs)))
	return []Node{listNode(append(directargs, orderedargs...)), ndirectargs}
}

// insertSelectOptions inserts ORDER BY, etc. into an already constructed
// SelectStmt.
func (p *parser) insertSelectOptions(stmt *SelectStmt, sortClause, lockingClause []Node, limitClause *selectLimit, withClause *WithClause) {
	// reject constructs like (SELECT foo ORDER BY bar) ORDER BY baz
	if sortClause != nil {
		if stmt.SortClause != nil {
			p.fail(exprLocation(sortClause[0]), "multiple ORDER BY clauses not allowed")
		}
		stmt.SortClause = sortClause
	}
	// multiple locking clauses are fine
	stmt.LockingClause = append(stmt.LockingClause, lockingClause...)
	if limitClause != nil && limitClause.limitOffset != nil {
		if stmt.LimitOffset != nil {
			p.fail(exprLocation(limitClause.limitOffset), "multiple OFFSET clauses not allowed")
		}
		stmt.LimitOffset = limitClause.limitOffset
	}
	if limitClause != nil && limitClause.limitCount != nil {
		if stmt.LimitCount != nil {
			p.fail(exprLocation(limitClause.limitCount), "multiple LIMIT clauses not allowed")
		}
		stmt.LimitCount = limitClause.limitCount
	}
	if limitClause != nil {
		if stmt.LimitOption != LIMIT_OPTION_DEFAULT {
			p.fail(-1, "multiple limit options not allowed")
		}
		if stmt.SortClause == nil && limitClause.limitOption == LIMIT_OPTION_WITH_TIES {
			p.fail(-1, "WITH TIES cannot be specified without ORDER BY clause")
		}
		if limitClause.limitOption == LIMIT_OPTION_WITH_TIES && stmt.LockingClause != nil {
			for _, lc := range stmt.LockingClause {
				if as[*LockingClause](lc).WaitPolicy == LockWaitSkip {
					p.fail(-1, "SKIP LOCKED and WITH TIES options cannot be used together")
				}
			}
		}
		stmt.LimitOption = limitClause.limitOption
	}
	if withClause != nil {
		if stmt.WithClause != nil {
			p.fail(exprLocation(withClause), "multiple WITH clauses not allowed")
		}
		stmt.WithClause = withClause
	}
}

func makeSetOp(op SetOperation, all bool, larg, rarg Node) Node {
	return &SelectStmt{Op: op, All: all, Larg: as[*SelectStmt](larg), Rarg: as[*SelectStmt](rarg)}
}

// systemFuncName builds a properly qualified reference to a built-in
// function: SystemFuncName.
func systemFuncName(name string) []Node {
	return []Node{makeString("pg_catalog", -1), makeString(name, -1)}
}

// systemTypeName builds a properly qualified reference to a built-in type:
// SystemTypeName. The typmod is defaulted and the location is -1; the caller
// may change them.
func systemTypeName(name string) *TypeName {
	return makeTypeNameFromNameList([]Node{makeString("pg_catalog", -1), makeString(name, -1)})
}

// doNegate handles negation of a numeric constant: "-123.456" stays a
// constant. Other operands get a unary minus.
func doNegate(n Node, location int32) Node {
	if con, ok := n.(*A_Const); ok {
		// report the constant's location as that of the '-' sign
		con.Location = location
		switch v := con.Val.(type) {
		case *Integer:
			v.Ival = -v.Ival
			return n
		case *Float:
			doNegateFloat(v)
			return n
		}
	}
	return makeSimpleA_Expr(AEXPR_OP, "-", nil, n, location)
}

func doNegateFloat(v *Float) {
	old := v.Fval
	old = strings.TrimPrefix(old, "+")
	if strings.HasPrefix(old, "-") {
		v.Fval = old[1:] // just strip the '-'
	} else {
		v.Fval = "-" + old
	}
}

func makeAndExpr(lexpr, rexpr Node, location int32) Node {
	// flatten "a AND b AND c ..." to a single BoolExpr on sight
	if b, ok := lexpr.(*BoolExpr); ok && b.Boolop == AND_EXPR {
		b.Args = append(b.Args, rexpr)
		return b
	}
	return makeBoolExpr(AND_EXPR, []Node{lexpr, rexpr}, location)
}

func makeOrExpr(lexpr, rexpr Node, location int32) Node {
	// flatten "a OR b OR c ..." to a single BoolExpr on sight
	if b, ok := lexpr.(*BoolExpr); ok && b.Boolop == OR_EXPR {
		b.Args = append(b.Args, rexpr)
		return b
	}
	return makeBoolExpr(OR_EXPR, []Node{lexpr, rexpr}, location)
}

func makeNotExpr(expr Node, location int32) Node {
	return makeBoolExpr(NOT_EXPR, []Node{expr}, location)
}

func makeAArrayExpr(elements []Node, location int32) Node {
	return &A_ArrayExpr{Elements: elements, Location: location}
}

func makeSQLValueFunction(op SQLValueFunctionOp, typmod int32, location int32) Node {
	return &SQLValueFunction{Op: op, Typmod: typmod, Location: location}
}

func makeXmlExpr(op XmlExprOp, name string, namedArgs, args []Node, location int32) Node {
	return &XmlExpr{Op: op, Name: name, NamedArgs: namedArgs, Args: args, Location: location}
}

// mergeTableFuncParameters merges the input and output parameters of a table
// function.
func (p *parser) mergeTableFuncParameters(funcArgs, columns []Node) []Node {
	// explicit OUT and INOUT parameters shouldn't be used in this syntax
	for _, n := range funcArgs {
		prm := as[*FunctionParameter](n)
		if prm.Mode != FUNC_PARAM_DEFAULT && prm.Mode != FUNC_PARAM_IN && prm.Mode != FUNC_PARAM_VARIADIC {
			p.fail(-1, "OUT and INOUT arguments aren't allowed in TABLE functions")
		}
	}
	return append(funcArgs, columns...)
}

// tableFuncTypeName determines the return type of a TABLE function: a single
// result column returns setof that column's type, otherwise setof record.
func tableFuncTypeName(columns []Node) *TypeName {
	var result *TypeName
	if len(columns) == 1 {
		c := *as[*FunctionParameter](columns[0]).ArgType // copyObject
		result = &c
	} else {
		result = systemTypeName("record")
	}
	result.Setof = true
	return result
}

// makeRangeVarFromAnyName converts a list of dotted names to a RangeVar. The
// AnyName refers to the any_name production.
func (p *parser) makeRangeVarFromAnyName(names []Node, position int32) *RangeVar {
	r := &RangeVar{}
	switch len(names) {
	case 1:
		r.Relname = strVal(names[0])
	case 2:
		r.Schemaname = strVal(names[0])
		r.Relname = strVal(names[1])
	case 3:
		r.Catalogname = strVal(names[0])
		r.Schemaname = strVal(names[1])
		r.Relname = strVal(names[2])
	default:
		p.fail(position, "improper qualified name (too many dotted names): "+nameListToString(names))
	}
	r.Relpersistence = relpersistencePermanent
	r.Location = position
	return r
}

// makeRangeVarFromQualifiedName converts a relation_name with a name and a
// name list to a RangeVar.
func (p *parser) makeRangeVarFromQualifiedName(name string, namelist []Node, location int32) *RangeVar {
	p.checkQualifiedName(namelist)
	r := makeRangeVar("", "", location)
	switch len(namelist) {
	case 1:
		r.Schemaname = name
		r.Relname = strVal(namelist[0])
	case 2:
		r.Catalogname = name
		r.Schemaname = strVal(namelist[0])
		r.Relname = strVal(namelist[1])
	default:
		p.fail(location, "improper qualified name (too many dotted names): "+nameListToString(append([]Node{makeString(name, -1)}, namelist...)))
	}
	return r
}

// splitColQualList separates the Constraint nodes from the COLLATE clauses
// of a ColQualList.
func (p *parser) splitColQualList(qualList []Node) (constraintList []Node, collClause *CollateClause) {
	for _, n := range qualList {
		switch v := n.(type) {
		case *Constraint:
			constraintList = append(constraintList, n)
		case *CollateClause:
			if collClause != nil {
				p.fail(v.Location, "multiple COLLATE clauses not allowed")
			}
			collClause = v
		default:
			p.fail(-1, "unexpected node type")
		}
	}
	return constraintList, collClause
}

// processCASbits processes the result of ConstraintAttributeSpec and sets the
// flags in the output command node. Pass nil for any flag the command does
// not support.
func (p *parser) processCASbits(casBits int32, location int32, constrType string, deferrable, initdeferred, notValid, noInherit *bool) {
	// defaults
	if deferrable != nil {
		*deferrable = false
	}
	if initdeferred != nil {
		*initdeferred = false
	}
	if notValid != nil {
		*notValid = false
	}
	if casBits&(casDeferrable|casInitiallyDeferred) != 0 {
		if deferrable != nil {
			*deferrable = true
		} else {
			p.fail(location, constrType+" constraints cannot be marked DEFERRABLE")
		}
	}
	if casBits&casInitiallyDeferred != 0 {
		if initdeferred != nil {
			*initdeferred = true
		} else {
			p.fail(location, constrType+" constraints cannot be marked DEFERRABLE")
		}
	}
	if casBits&casNotValid != 0 {
		if notValid != nil {
			*notValid = true
		} else {
			p.fail(location, constrType+" constraints cannot be marked NOT VALID")
		}
	}
	if casBits&casNoInherit != 0 {
		if noInherit != nil {
			*noInherit = true
		} else {
			p.fail(location, constrType+" constraints cannot be marked NO INHERIT")
		}
	}
}

// parsePartitionStrategy parses a user-supplied partition strategy string.
func (p *parser) parsePartitionStrategy(strategy string) PartitionStrategy {
	switch {
	case strings.EqualFold(strategy, "list"):
		return PARTITION_STRATEGY_LIST
	case strings.EqualFold(strategy, "range"):
		return PARTITION_STRATEGY_RANGE
	case strings.EqualFold(strategy, "hash"):
		return PARTITION_STRATEGY_HASH
	}
	p.fail(-1, "unrecognized partitioning strategy \""+strategy+"\"")
	return PARTITION_STRATEGY_LIST
}

// preprocessPubobjList processes a publication object list to check for
// errors and to convert PUBLICATIONOBJ_CONTINUATION into the right type.
func (p *parser) preprocessPubobjList(pubobjspecList []Node) {
	if len(pubobjspecList) == 0 {
		return
	}
	pubobj := as[*PublicationObjSpec](pubobjspecList[0])
	if pubobj.Pubobjtype == PUBLICATIONOBJ_CONTINUATION {
		p.fail(pubobj.Location, "invalid publication object list")
	}
	prevobjtype := PUBLICATIONOBJ_CONTINUATION
	for _, n := range pubobjspecList {
		pubobj = as[*PublicationObjSpec](n)
		if pubobj.Pubobjtype == PUBLICATIONOBJ_CONTINUATION {
			pubobj.Pubobjtype = prevobjtype
		}
		switch pubobj.Pubobjtype {
		case PUBLICATIONOBJ_TABLE:
			// a relation name or a pubtable must be set for this type
			if pubobj.Name == "" && pubobj.Pubtable == nil {
				p.fail(pubobj.Location, "invalid table name")
			}
			if pubobj.Name != "" {
				// convert it to PublicationTable
				pubobj.Pubtable = &PublicationTable{Relation: makeRangeVar("", pubobj.Name, pubobj.Location)}
				pubobj.Name = ""
			}
		case PUBLICATIONOBJ_TABLES_IN_SCHEMA, PUBLICATIONOBJ_TABLES_IN_CUR_SCHEMA:
			// a WHERE clause and a column list are not allowed on a schema
			if pubobj.Pubtable != nil && pubobj.Pubtable.WhereClause != nil {
				p.fail(pubobj.Location, "WHERE clause not allowed for schema")
			}
			if pubobj.Pubtable != nil && pubobj.Pubtable.Columns != nil {
				p.fail(pubobj.Location, "column specification not allowed for schema")
			}
			// the kind of schema object depends on whether name and pubtable are set
			switch {
			case pubobj.Name != "":
				pubobj.Pubobjtype = PUBLICATIONOBJ_TABLES_IN_SCHEMA
			case pubobj.Pubtable == nil:
				pubobj.Pubobjtype = PUBLICATIONOBJ_TABLES_IN_CUR_SCHEMA
			default:
				p.fail(pubobj.Location, "invalid schema name")
			}
		}
		prevobjtype = pubobj.Pubobjtype
	}
}

// makeRecursiveViewSelect converts
//
//	CREATE RECURSIVE VIEW relname (aliases) AS query
//
// to the WITH part of
//
//	CREATE VIEW relname (aliases) AS
//	    WITH RECURSIVE relname (aliases) AS (query)
//	    SELECT aliases FROM relname
func (p *parser) makeRecursiveViewSelect(relname string, aliases []Node, query Node) Node {
	cte := &CommonTableExpr{
		Ctename:         relname,
		Aliascolnames:   aliases,
		Ctematerialized: CTEMaterializeDefault,
		Ctequery:        query,
		Location:        -1,
	}
	w := &WithClause{Recursive: true, Ctes: []Node{cte}, Location: -1}
	// the target list of the new SELECT comes from the alias list
	var tl []Node
	for _, a := range aliases {
		tl = append(tl, &ResTarget{Val: p.makeColumnRef(strVal(a), nil, -1), Location: -1})
	}
	return &SelectStmt{WithClause: w, TargetList: tl, FromClause: []Node{makeRangeVar("", relname, -1)}}
}
