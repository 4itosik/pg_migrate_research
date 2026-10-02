/* gram.y lines 8805-10508 */
/*****************************************************************************
 * ALTER FUNCTION / ALTER PROCEDURE / ALTER ROUTINE
 *
 * RENAME and OWNER subcommands are already provided by the generic
 * ALTER infrastructure, here we just specify alterations that can
 * only be applied to functions.
 *
 *****************************************************************************/
AlterFunctionStmt:
			ALTER FUNCTION function_with_argtypes alterfunc_opt_list opt_restrict
				{
					n := &AlterFunctionStmt{}

					n.Objtype = OBJECT_FUNCTION
					n.Func = as[*ObjectWithArgs]($3)
					n.Actions = $4
					$$ = n
				}
			| ALTER PROCEDURE function_with_argtypes alterfunc_opt_list opt_restrict
				{
					n := &AlterFunctionStmt{}

					n.Objtype = OBJECT_PROCEDURE
					n.Func = as[*ObjectWithArgs]($3)
					n.Actions = $4
					$$ = n
				}
			| ALTER ROUTINE function_with_argtypes alterfunc_opt_list opt_restrict
				{
					n := &AlterFunctionStmt{}

					n.Objtype = OBJECT_ROUTINE
					n.Func = as[*ObjectWithArgs]($3)
					n.Actions = $4
					$$ = n
				}
		;

alterfunc_opt_list:
			/* At least one option must be specified */
			common_func_opt_item					{ $$ = []Node{$1} }
			| alterfunc_opt_list common_func_opt_item { $$ = append($1, $2) }
		;

/* Ignored, merely for SQL compliance */
opt_restrict:
			RESTRICT
			| /* EMPTY */
		;


/*****************************************************************************
 *
 *		QUERY:
 *
 *		DROP FUNCTION funcname (arg1, arg2, ...) [ RESTRICT | CASCADE ]
 *		DROP PROCEDURE procname (arg1, arg2, ...) [ RESTRICT | CASCADE ]
 *		DROP ROUTINE routname (arg1, arg2, ...) [ RESTRICT | CASCADE ]
 *		DROP AGGREGATE aggname (arg1, ...) [ RESTRICT | CASCADE ]
 *		DROP OPERATOR opname (leftoperand_typ, rightoperand_typ) [ RESTRICT | CASCADE ]
 *
 *****************************************************************************/

RemoveFuncStmt:
			DROP FUNCTION function_with_argtypes_list opt_drop_behavior
				{
					n := &DropStmt{}

					n.RemoveType = OBJECT_FUNCTION
					n.Objects = $3
					n.Behavior = DropBehavior($4)
					n.MissingOk = false
					n.Concurrent = false
					$$ = n
				}
			| DROP FUNCTION IF_P EXISTS function_with_argtypes_list opt_drop_behavior
				{
					n := &DropStmt{}

					n.RemoveType = OBJECT_FUNCTION
					n.Objects = $5
					n.Behavior = DropBehavior($6)
					n.MissingOk = true
					n.Concurrent = false
					$$ = n
				}
			| DROP PROCEDURE function_with_argtypes_list opt_drop_behavior
				{
					n := &DropStmt{}

					n.RemoveType = OBJECT_PROCEDURE
					n.Objects = $3
					n.Behavior = DropBehavior($4)
					n.MissingOk = false
					n.Concurrent = false
					$$ = n
				}
			| DROP PROCEDURE IF_P EXISTS function_with_argtypes_list opt_drop_behavior
				{
					n := &DropStmt{}

					n.RemoveType = OBJECT_PROCEDURE
					n.Objects = $5
					n.Behavior = DropBehavior($6)
					n.MissingOk = true
					n.Concurrent = false
					$$ = n
				}
			| DROP ROUTINE function_with_argtypes_list opt_drop_behavior
				{
					n := &DropStmt{}

					n.RemoveType = OBJECT_ROUTINE
					n.Objects = $3
					n.Behavior = DropBehavior($4)
					n.MissingOk = false
					n.Concurrent = false
					$$ = n
				}
			| DROP ROUTINE IF_P EXISTS function_with_argtypes_list opt_drop_behavior
				{
					n := &DropStmt{}

					n.RemoveType = OBJECT_ROUTINE
					n.Objects = $5
					n.Behavior = DropBehavior($6)
					n.MissingOk = true
					n.Concurrent = false
					$$ = n
				}
		;

RemoveAggrStmt:
			DROP AGGREGATE aggregate_with_argtypes_list opt_drop_behavior
				{
					n := &DropStmt{}

					n.RemoveType = OBJECT_AGGREGATE
					n.Objects = $3
					n.Behavior = DropBehavior($4)
					n.MissingOk = false
					n.Concurrent = false
					$$ = n
				}
			| DROP AGGREGATE IF_P EXISTS aggregate_with_argtypes_list opt_drop_behavior
				{
					n := &DropStmt{}

					n.RemoveType = OBJECT_AGGREGATE
					n.Objects = $5
					n.Behavior = DropBehavior($6)
					n.MissingOk = true
					n.Concurrent = false
					$$ = n
				}
		;

RemoveOperStmt:
			DROP OPERATOR operator_with_argtypes_list opt_drop_behavior
				{
					n := &DropStmt{}

					n.RemoveType = OBJECT_OPERATOR
					n.Objects = $3
					n.Behavior = DropBehavior($4)
					n.MissingOk = false
					n.Concurrent = false
					$$ = n
				}
			| DROP OPERATOR IF_P EXISTS operator_with_argtypes_list opt_drop_behavior
				{
					n := &DropStmt{}

					n.RemoveType = OBJECT_OPERATOR
					n.Objects = $5
					n.Behavior = DropBehavior($6)
					n.MissingOk = true
					n.Concurrent = false
					$$ = n
				}
		;

oper_argtypes:
			'(' Typename ')'
				{
					// errhint: Use NONE to denote the missing argument of a unary operator.
					p.fail(@3, "missing argument")
				}
			| '(' Typename ',' Typename ')'
					{ $$ = []Node{$2, $4} }
			| '(' NONE ',' Typename ')'					/* left unary */
					{ $$ = []Node{nil, $4} }
			| '(' Typename ',' NONE ')'					/* right unary */
					{ $$ = []Node{$2, nil} }
		;

any_operator:
			all_Op
					{ $$ = []Node{makeString($1, @1)} }
			| ColId '.' any_operator
					{ $$ = append([]Node{makeString($1, @1)}, $3...) }
		;

operator_with_argtypes_list:
			operator_with_argtypes					{ $$ = []Node{$1} }
			| operator_with_argtypes_list ',' operator_with_argtypes
													{ $$ = append($1, $3) }
		;

operator_with_argtypes:
			any_operator oper_argtypes
				{
					n := &ObjectWithArgs{}

					n.Objname = $1
					n.Objargs = $2
					$$ = n
				}
		;

/*****************************************************************************
 *
 *		DO <anonymous code block> [ LANGUAGE language ]
 *
 * We use a DefElem list for future extensibility, and to allow flexibility
 * in the clause order.
 *
 *****************************************************************************/

DoStmt: DO dostmt_opt_list
				{
					n := &DoStmt{}

					n.Args = $2
					$$ = n
				}
		;

dostmt_opt_list:
			dostmt_opt_item						{ $$ = []Node{$1} }
			| dostmt_opt_list dostmt_opt_item	{ $$ = append($1, $2) }
		;

dostmt_opt_item:
			Sconst
				{ $$ = makeDefElem("as", makeString($1, @1), @1) }
			| LANGUAGE NonReservedWord_or_Sconst
				{ $$ = makeDefElem("language", makeString($2, @2), @1) }
		;

/*****************************************************************************
 *
 *		CREATE CAST / DROP CAST
 *
 *****************************************************************************/

CreateCastStmt: CREATE CAST '(' Typename AS Typename ')'
					WITH FUNCTION function_with_argtypes cast_context
				{
					n := &CreateCastStmt{}

					n.Sourcetype = as[*TypeName]($4)
					n.Targettype = as[*TypeName]($6)
					n.Func = as[*ObjectWithArgs]($10)
					n.Context = CoercionContext($11)
					n.Inout = false
					$$ = n
				}
			| CREATE CAST '(' Typename AS Typename ')'
					WITHOUT FUNCTION cast_context
				{
					n := &CreateCastStmt{}

					n.Sourcetype = as[*TypeName]($4)
					n.Targettype = as[*TypeName]($6)
					n.Func = nil
					n.Context = CoercionContext($10)
					n.Inout = false
					$$ = n
				}
			| CREATE CAST '(' Typename AS Typename ')'
					WITH INOUT cast_context
				{
					n := &CreateCastStmt{}

					n.Sourcetype = as[*TypeName]($4)
					n.Targettype = as[*TypeName]($6)
					n.Func = nil
					n.Context = CoercionContext($10)
					n.Inout = true
					$$ = n
				}
		;

cast_context:  AS IMPLICIT_P					{ $$ = int32(COERCION_IMPLICIT) }
		| AS ASSIGNMENT							{ $$ = int32(COERCION_ASSIGNMENT) }
		| /*EMPTY*/								{ $$ = int32(COERCION_EXPLICIT) }
		;


DropCastStmt: DROP CAST opt_if_exists '(' Typename AS Typename ')' opt_drop_behavior
				{
					n := &DropStmt{}

					n.RemoveType = OBJECT_CAST
					n.Objects = []Node{listNode([]Node{$5, $7})}
					n.Behavior = DropBehavior($9)
					n.MissingOk = $3
					n.Concurrent = false
					$$ = n
				}
		;

opt_if_exists: IF_P EXISTS						{ $$ = true }
		| /*EMPTY*/								{ $$ = false }
		;


/*****************************************************************************
 *
 *		CREATE TRANSFORM / DROP TRANSFORM
 *
 *****************************************************************************/

CreateTransformStmt: CREATE opt_or_replace TRANSFORM FOR Typename LANGUAGE name '(' transform_element_list ')'
				{
					n := &CreateTransformStmt{}

					n.Replace = $2
					n.TypeName = as[*TypeName]($5)
					n.Lang = $7
					n.Fromsql = as[*ObjectWithArgs]($9[0])
					n.Tosql = as[*ObjectWithArgs]($9[1])
					$$ = n
				}
		;

transform_element_list: FROM SQL_P WITH FUNCTION function_with_argtypes ',' TO SQL_P WITH FUNCTION function_with_argtypes
				{ $$ = []Node{$5, $11} }
				| TO SQL_P WITH FUNCTION function_with_argtypes ',' FROM SQL_P WITH FUNCTION function_with_argtypes
				{ $$ = []Node{$11, $5} }
				| FROM SQL_P WITH FUNCTION function_with_argtypes
				{ $$ = []Node{$5, nil} }
				| TO SQL_P WITH FUNCTION function_with_argtypes
				{ $$ = []Node{nil, $5} }
		;


DropTransformStmt: DROP TRANSFORM opt_if_exists FOR Typename LANGUAGE name opt_drop_behavior
				{
					n := &DropStmt{}

					n.RemoveType = OBJECT_TRANSFORM
					n.Objects = []Node{listNode([]Node{$5, makeString($7, @7)})}
					n.Behavior = DropBehavior($8)
					n.MissingOk = $3
					$$ = n
				}
		;


/*****************************************************************************
 *
 *		QUERY:
 *
 *		REINDEX [ (options) ] {INDEX | TABLE | SCHEMA} [CONCURRENTLY] <name>
 *		REINDEX [ (options) ] {DATABASE | SYSTEM} [CONCURRENTLY] [<name>]
 *****************************************************************************/

ReindexStmt:
			REINDEX opt_reindex_option_list reindex_target_relation opt_concurrently qualified_name
				{
					n := &ReindexStmt{}

					n.Kind = ReindexObjectType($3)
					n.Relation = as[*RangeVar]($5)
					n.Name = ""
					n.Params = $2
					if $4 {
						n.Params = append(n.Params, makeDefElem("concurrently", nil, @4))
					}
					$$ = n
				}
			| REINDEX opt_reindex_option_list SCHEMA opt_concurrently name
				{
					n := &ReindexStmt{}

					n.Kind = REINDEX_OBJECT_SCHEMA
					n.Relation = nil
					n.Name = $5
					n.Params = $2
					if $4 {
						n.Params = append(n.Params, makeDefElem("concurrently", nil, @4))
					}
					$$ = n
				}
			| REINDEX opt_reindex_option_list reindex_target_all opt_concurrently opt_single_name
				{
					n := &ReindexStmt{}

					n.Kind = ReindexObjectType($3)
					n.Relation = nil
					n.Name = $5
					n.Params = $2
					if $4 {
						n.Params = append(n.Params, makeDefElem("concurrently", nil, @4))
					}
					$$ = n
				}
		;
reindex_target_relation:
			INDEX					{ $$ = int32(REINDEX_OBJECT_INDEX) }
			| TABLE					{ $$ = int32(REINDEX_OBJECT_TABLE) }
		;
reindex_target_all:
			SYSTEM_P				{ $$ = int32(REINDEX_OBJECT_SYSTEM) }
			| DATABASE				{ $$ = int32(REINDEX_OBJECT_DATABASE) }
		;
opt_reindex_option_list:
			'(' utility_option_list ')'				{ $$ = $2 }
			| /* EMPTY */							{ $$ = nil }
		;

/*****************************************************************************
 *
 * ALTER TABLESPACE
 *
 *****************************************************************************/

AlterTblSpcStmt:
			ALTER TABLESPACE name SET reloptions
				{
					n := &AlterTableSpaceOptionsStmt{}

					n.Tablespacename = $3
					n.Options = $5
					n.IsReset = false
					$$ = n
				}
			| ALTER TABLESPACE name RESET reloptions
				{
					n := &AlterTableSpaceOptionsStmt{}

					n.Tablespacename = $3
					n.Options = $5
					n.IsReset = true
					$$ = n
				}
		;

/*****************************************************************************
 *
 * ALTER THING name RENAME TO newname
 *
 *****************************************************************************/

RenameStmt: ALTER AGGREGATE aggregate_with_argtypes RENAME TO name
				{
					n := &RenameStmt{}

					n.RenameType = OBJECT_AGGREGATE
					n.Object = $3
					n.Newname = $6
					n.MissingOk = false
					$$ = n
				}
			| ALTER COLLATION any_name RENAME TO name
				{
					n := &RenameStmt{}

					n.RenameType = OBJECT_COLLATION
					n.Object = listNode($3)
					n.Newname = $6
					n.MissingOk = false
					$$ = n
				}
			| ALTER CONVERSION_P any_name RENAME TO name
				{
					n := &RenameStmt{}

					n.RenameType = OBJECT_CONVERSION
					n.Object = listNode($3)
					n.Newname = $6
					n.MissingOk = false
					$$ = n
				}
			| ALTER DATABASE name RENAME TO name
				{
					n := &RenameStmt{}

					n.RenameType = OBJECT_DATABASE
					n.Subname = $3
					n.Newname = $6
					n.MissingOk = false
					$$ = n
				}
			| ALTER DOMAIN_P any_name RENAME TO name
				{
					n := &RenameStmt{}

					n.RenameType = OBJECT_DOMAIN
					n.Object = listNode($3)
					n.Newname = $6
					n.MissingOk = false
					$$ = n
				}
			| ALTER DOMAIN_P any_name RENAME CONSTRAINT name TO name
				{
					n := &RenameStmt{}

					n.RenameType = OBJECT_DOMCONSTRAINT
					n.Object = listNode($3)
					n.Subname = $6
					n.Newname = $8
					$$ = n
				}
			| ALTER FOREIGN DATA_P WRAPPER name RENAME TO name
				{
					n := &RenameStmt{}

					n.RenameType = OBJECT_FDW
					n.Object = makeString($5, @5)
					n.Newname = $8
					n.MissingOk = false
					$$ = n
				}
			| ALTER FUNCTION function_with_argtypes RENAME TO name
				{
					n := &RenameStmt{}

					n.RenameType = OBJECT_FUNCTION
					n.Object = $3
					n.Newname = $6
					n.MissingOk = false
					$$ = n
				}
			| ALTER GROUP_P RoleId RENAME TO RoleId
				{
					n := &RenameStmt{}

					n.RenameType = OBJECT_ROLE
					n.Subname = $3
					n.Newname = $6
					n.MissingOk = false
					$$ = n
				}
			| ALTER opt_procedural LANGUAGE name RENAME TO name
				{
					n := &RenameStmt{}

					n.RenameType = OBJECT_LANGUAGE
					n.Object = makeString($4, @4)
					n.Newname = $7
					n.MissingOk = false
					$$ = n
				}
			| ALTER OPERATOR CLASS any_name USING name RENAME TO name
				{
					n := &RenameStmt{}

					n.RenameType = OBJECT_OPCLASS
					n.Object = listNode(append([]Node{makeString($6, @6)}, $4...))
					n.Newname = $9
					n.MissingOk = false
					$$ = n
				}
			| ALTER OPERATOR FAMILY any_name USING name RENAME TO name
				{
					n := &RenameStmt{}

					n.RenameType = OBJECT_OPFAMILY
					n.Object = listNode(append([]Node{makeString($6, @6)}, $4...))
					n.Newname = $9
					n.MissingOk = false
					$$ = n
				}
			| ALTER POLICY name ON qualified_name RENAME TO name
				{
					n := &RenameStmt{}

					n.RenameType = OBJECT_POLICY
					n.Relation = as[*RangeVar]($5)
					n.Subname = $3
					n.Newname = $8
					n.MissingOk = false
					$$ = n
				}
			| ALTER POLICY IF_P EXISTS name ON qualified_name RENAME TO name
				{
					n := &RenameStmt{}

					n.RenameType = OBJECT_POLICY
					n.Relation = as[*RangeVar]($7)
					n.Subname = $5
					n.Newname = $10
					n.MissingOk = true
					$$ = n
				}
			| ALTER PROCEDURE function_with_argtypes RENAME TO name
				{
					n := &RenameStmt{}

					n.RenameType = OBJECT_PROCEDURE
					n.Object = $3
					n.Newname = $6
					n.MissingOk = false
					$$ = n
				}
			| ALTER PUBLICATION name RENAME TO name
				{
					n := &RenameStmt{}

					n.RenameType = OBJECT_PUBLICATION
					n.Object = makeString($3, @3)
					n.Newname = $6
					n.MissingOk = false
					$$ = n
				}
			| ALTER ROUTINE function_with_argtypes RENAME TO name
				{
					n := &RenameStmt{}

					n.RenameType = OBJECT_ROUTINE
					n.Object = $3
					n.Newname = $6
					n.MissingOk = false
					$$ = n
				}
			| ALTER SCHEMA name RENAME TO name
				{
					n := &RenameStmt{}

					n.RenameType = OBJECT_SCHEMA
					n.Subname = $3
					n.Newname = $6
					n.MissingOk = false
					$$ = n
				}
			| ALTER SERVER name RENAME TO name
				{
					n := &RenameStmt{}

					n.RenameType = OBJECT_FOREIGN_SERVER
					n.Object = makeString($3, @3)
					n.Newname = $6
					n.MissingOk = false
					$$ = n
				}
			| ALTER SUBSCRIPTION name RENAME TO name
				{
					n := &RenameStmt{}

					n.RenameType = OBJECT_SUBSCRIPTION
					n.Object = makeString($3, @3)
					n.Newname = $6
					n.MissingOk = false
					$$ = n
				}
			| ALTER TABLE relation_expr RENAME TO name
				{
					n := &RenameStmt{}

					n.RenameType = OBJECT_TABLE
					n.Relation = as[*RangeVar]($3)
					n.Subname = ""
					n.Newname = $6
					n.MissingOk = false
					$$ = n
				}
			| ALTER TABLE IF_P EXISTS relation_expr RENAME TO name
				{
					n := &RenameStmt{}

					n.RenameType = OBJECT_TABLE
					n.Relation = as[*RangeVar]($5)
					n.Subname = ""
					n.Newname = $8
					n.MissingOk = true
					$$ = n
				}
			| ALTER SEQUENCE qualified_name RENAME TO name
				{
					n := &RenameStmt{}

					n.RenameType = OBJECT_SEQUENCE
					n.Relation = as[*RangeVar]($3)
					n.Subname = ""
					n.Newname = $6
					n.MissingOk = false
					$$ = n
				}
			| ALTER SEQUENCE IF_P EXISTS qualified_name RENAME TO name
				{
					n := &RenameStmt{}

					n.RenameType = OBJECT_SEQUENCE
					n.Relation = as[*RangeVar]($5)
					n.Subname = ""
					n.Newname = $8
					n.MissingOk = true
					$$ = n
				}
			| ALTER VIEW qualified_name RENAME TO name
				{
					n := &RenameStmt{}

					n.RenameType = OBJECT_VIEW
					n.Relation = as[*RangeVar]($3)
					n.Subname = ""
					n.Newname = $6
					n.MissingOk = false
					$$ = n
				}
			| ALTER VIEW IF_P EXISTS qualified_name RENAME TO name
				{
					n := &RenameStmt{}

					n.RenameType = OBJECT_VIEW
					n.Relation = as[*RangeVar]($5)
					n.Subname = ""
					n.Newname = $8
					n.MissingOk = true
					$$ = n
				}
			| ALTER MATERIALIZED VIEW qualified_name RENAME TO name
				{
					n := &RenameStmt{}

					n.RenameType = OBJECT_MATVIEW
					n.Relation = as[*RangeVar]($4)
					n.Subname = ""
					n.Newname = $7
					n.MissingOk = false
					$$ = n
				}
			| ALTER MATERIALIZED VIEW IF_P EXISTS qualified_name RENAME TO name
				{
					n := &RenameStmt{}

					n.RenameType = OBJECT_MATVIEW
					n.Relation = as[*RangeVar]($6)
					n.Subname = ""
					n.Newname = $9
					n.MissingOk = true
					$$ = n
				}
			| ALTER INDEX qualified_name RENAME TO name
				{
					n := &RenameStmt{}

					n.RenameType = OBJECT_INDEX
					n.Relation = as[*RangeVar]($3)
					n.Subname = ""
					n.Newname = $6
					n.MissingOk = false
					$$ = n
				}
			| ALTER INDEX IF_P EXISTS qualified_name RENAME TO name
				{
					n := &RenameStmt{}

					n.RenameType = OBJECT_INDEX
					n.Relation = as[*RangeVar]($5)
					n.Subname = ""
					n.Newname = $8
					n.MissingOk = true
					$$ = n
				}
			| ALTER FOREIGN TABLE relation_expr RENAME TO name
				{
					n := &RenameStmt{}

					n.RenameType = OBJECT_FOREIGN_TABLE
					n.Relation = as[*RangeVar]($4)
					n.Subname = ""
					n.Newname = $7
					n.MissingOk = false
					$$ = n
				}
			| ALTER FOREIGN TABLE IF_P EXISTS relation_expr RENAME TO name
				{
					n := &RenameStmt{}

					n.RenameType = OBJECT_FOREIGN_TABLE
					n.Relation = as[*RangeVar]($6)
					n.Subname = ""
					n.Newname = $9
					n.MissingOk = true
					$$ = n
				}
			| ALTER TABLE relation_expr RENAME opt_column name TO name
				{
					n := &RenameStmt{}

					n.RenameType = OBJECT_COLUMN
					n.RelationType = OBJECT_TABLE
					n.Relation = as[*RangeVar]($3)
					n.Subname = $6
					n.Newname = $8
					n.MissingOk = false
					$$ = n
				}
			| ALTER TABLE IF_P EXISTS relation_expr RENAME opt_column name TO name
				{
					n := &RenameStmt{}

					n.RenameType = OBJECT_COLUMN
					n.RelationType = OBJECT_TABLE
					n.Relation = as[*RangeVar]($5)
					n.Subname = $8
					n.Newname = $10
					n.MissingOk = true
					$$ = n
				}
			| ALTER VIEW qualified_name RENAME opt_column name TO name
				{
					n := &RenameStmt{}

					n.RenameType = OBJECT_COLUMN
					n.RelationType = OBJECT_VIEW
					n.Relation = as[*RangeVar]($3)
					n.Subname = $6
					n.Newname = $8
					n.MissingOk = false
					$$ = n
				}
			| ALTER VIEW IF_P EXISTS qualified_name RENAME opt_column name TO name
				{
					n := &RenameStmt{}

					n.RenameType = OBJECT_COLUMN
					n.RelationType = OBJECT_VIEW
					n.Relation = as[*RangeVar]($5)
					n.Subname = $8
					n.Newname = $10
					n.MissingOk = true
					$$ = n
				}
			| ALTER MATERIALIZED VIEW qualified_name RENAME opt_column name TO name
				{
					n := &RenameStmt{}

					n.RenameType = OBJECT_COLUMN
					n.RelationType = OBJECT_MATVIEW
					n.Relation = as[*RangeVar]($4)
					n.Subname = $7
					n.Newname = $9
					n.MissingOk = false
					$$ = n
				}
			| ALTER MATERIALIZED VIEW IF_P EXISTS qualified_name RENAME opt_column name TO name
				{
					n := &RenameStmt{}

					n.RenameType = OBJECT_COLUMN
					n.RelationType = OBJECT_MATVIEW
					n.Relation = as[*RangeVar]($6)
					n.Subname = $9
					n.Newname = $11
					n.MissingOk = true
					$$ = n
				}
			| ALTER TABLE relation_expr RENAME CONSTRAINT name TO name
				{
					n := &RenameStmt{}

					n.RenameType = OBJECT_TABCONSTRAINT
					n.Relation = as[*RangeVar]($3)
					n.Subname = $6
					n.Newname = $8
					n.MissingOk = false
					$$ = n
				}
			| ALTER TABLE IF_P EXISTS relation_expr RENAME CONSTRAINT name TO name
				{
					n := &RenameStmt{}

					n.RenameType = OBJECT_TABCONSTRAINT
					n.Relation = as[*RangeVar]($5)
					n.Subname = $8
					n.Newname = $10
					n.MissingOk = true
					$$ = n
				}
			| ALTER FOREIGN TABLE relation_expr RENAME opt_column name TO name
				{
					n := &RenameStmt{}

					n.RenameType = OBJECT_COLUMN
					n.RelationType = OBJECT_FOREIGN_TABLE
					n.Relation = as[*RangeVar]($4)
					n.Subname = $7
					n.Newname = $9
					n.MissingOk = false
					$$ = n
				}
			| ALTER FOREIGN TABLE IF_P EXISTS relation_expr RENAME opt_column name TO name
				{
					n := &RenameStmt{}

					n.RenameType = OBJECT_COLUMN
					n.RelationType = OBJECT_FOREIGN_TABLE
					n.Relation = as[*RangeVar]($6)
					n.Subname = $9
					n.Newname = $11
					n.MissingOk = true
					$$ = n
				}
			| ALTER RULE name ON qualified_name RENAME TO name
				{
					n := &RenameStmt{}

					n.RenameType = OBJECT_RULE
					n.Relation = as[*RangeVar]($5)
					n.Subname = $3
					n.Newname = $8
					n.MissingOk = false
					$$ = n
				}
			| ALTER TRIGGER name ON qualified_name RENAME TO name
				{
					n := &RenameStmt{}

					n.RenameType = OBJECT_TRIGGER
					n.Relation = as[*RangeVar]($5)
					n.Subname = $3
					n.Newname = $8
					n.MissingOk = false
					$$ = n
				}
			| ALTER EVENT TRIGGER name RENAME TO name
				{
					n := &RenameStmt{}

					n.RenameType = OBJECT_EVENT_TRIGGER
					n.Object = makeString($4, @4)
					n.Newname = $7
					$$ = n
				}
			| ALTER ROLE RoleId RENAME TO RoleId
				{
					n := &RenameStmt{}

					n.RenameType = OBJECT_ROLE
					n.Subname = $3
					n.Newname = $6
					n.MissingOk = false
					$$ = n
				}
			| ALTER USER RoleId RENAME TO RoleId
				{
					n := &RenameStmt{}

					n.RenameType = OBJECT_ROLE
					n.Subname = $3
					n.Newname = $6
					n.MissingOk = false
					$$ = n
				}
			| ALTER TABLESPACE name RENAME TO name
				{
					n := &RenameStmt{}

					n.RenameType = OBJECT_TABLESPACE
					n.Subname = $3
					n.Newname = $6
					n.MissingOk = false
					$$ = n
				}
			| ALTER STATISTICS any_name RENAME TO name
				{
					n := &RenameStmt{}

					n.RenameType = OBJECT_STATISTIC_EXT
					n.Object = listNode($3)
					n.Newname = $6
					n.MissingOk = false
					$$ = n
				}
			| ALTER TEXT_P SEARCH PARSER any_name RENAME TO name
				{
					n := &RenameStmt{}

					n.RenameType = OBJECT_TSPARSER
					n.Object = listNode($5)
					n.Newname = $8
					n.MissingOk = false
					$$ = n
				}
			| ALTER TEXT_P SEARCH DICTIONARY any_name RENAME TO name
				{
					n := &RenameStmt{}

					n.RenameType = OBJECT_TSDICTIONARY
					n.Object = listNode($5)
					n.Newname = $8
					n.MissingOk = false
					$$ = n
				}
			| ALTER TEXT_P SEARCH TEMPLATE any_name RENAME TO name
				{
					n := &RenameStmt{}

					n.RenameType = OBJECT_TSTEMPLATE
					n.Object = listNode($5)
					n.Newname = $8
					n.MissingOk = false
					$$ = n
				}
			| ALTER TEXT_P SEARCH CONFIGURATION any_name RENAME TO name
				{
					n := &RenameStmt{}

					n.RenameType = OBJECT_TSCONFIGURATION
					n.Object = listNode($5)
					n.Newname = $8
					n.MissingOk = false
					$$ = n
				}
			| ALTER TYPE_P any_name RENAME TO name
				{
					n := &RenameStmt{}

					n.RenameType = OBJECT_TYPE
					n.Object = listNode($3)
					n.Newname = $6
					n.MissingOk = false
					$$ = n
				}
			| ALTER TYPE_P any_name RENAME ATTRIBUTE name TO name opt_drop_behavior
				{
					n := &RenameStmt{}

					n.RenameType = OBJECT_ATTRIBUTE
					n.RelationType = OBJECT_TYPE
					n.Relation = p.makeRangeVarFromAnyName($3, @3)
					n.Subname = $6
					n.Newname = $8
					n.Behavior = DropBehavior($9)
					n.MissingOk = false
					$$ = n
				}
		;

opt_column: COLUMN
			| /*EMPTY*/
		;

opt_set_data: SET DATA_P							{ $$ = 1 }
			| /*EMPTY*/								{ $$ = 0 }
		;

/*****************************************************************************
 *
 * ALTER THING name DEPENDS ON EXTENSION name
 *
 *****************************************************************************/

AlterObjectDependsStmt:
			ALTER FUNCTION function_with_argtypes opt_no DEPENDS ON EXTENSION name
				{
					n := &AlterObjectDependsStmt{}

					n.ObjectType = OBJECT_FUNCTION
					n.Object = $3
					n.Extname = makeString($8, @8)
					n.Remove = $4
					$$ = n
				}
			| ALTER PROCEDURE function_with_argtypes opt_no DEPENDS ON EXTENSION name
				{
					n := &AlterObjectDependsStmt{}

					n.ObjectType = OBJECT_PROCEDURE
					n.Object = $3
					n.Extname = makeString($8, @8)
					n.Remove = $4
					$$ = n
				}
			| ALTER ROUTINE function_with_argtypes opt_no DEPENDS ON EXTENSION name
				{
					n := &AlterObjectDependsStmt{}

					n.ObjectType = OBJECT_ROUTINE
					n.Object = $3
					n.Extname = makeString($8, @8)
					n.Remove = $4
					$$ = n
				}
			| ALTER TRIGGER name ON qualified_name opt_no DEPENDS ON EXTENSION name
				{
					n := &AlterObjectDependsStmt{}

					n.ObjectType = OBJECT_TRIGGER
					n.Relation = as[*RangeVar]($5)
					n.Object = listNode([]Node{makeString($3, @3)})
					n.Extname = makeString($10, @10)
					n.Remove = $6
					$$ = n
				}
			| ALTER MATERIALIZED VIEW qualified_name opt_no DEPENDS ON EXTENSION name
				{
					n := &AlterObjectDependsStmt{}

					n.ObjectType = OBJECT_MATVIEW
					n.Relation = as[*RangeVar]($4)
					n.Extname = makeString($9, @9)
					n.Remove = $5
					$$ = n
				}
			| ALTER INDEX qualified_name opt_no DEPENDS ON EXTENSION name
				{
					n := &AlterObjectDependsStmt{}

					n.ObjectType = OBJECT_INDEX
					n.Relation = as[*RangeVar]($3)
					n.Extname = makeString($8, @8)
					n.Remove = $4
					$$ = n
				}
		;

opt_no:		NO				{ $$ = true }
			| /* EMPTY */	{ $$ = false }
		;

/*****************************************************************************
 *
 * ALTER THING name SET SCHEMA name
 *
 *****************************************************************************/

AlterObjectSchemaStmt:
			ALTER AGGREGATE aggregate_with_argtypes SET SCHEMA name
				{
					n := &AlterObjectSchemaStmt{}

					n.ObjectType = OBJECT_AGGREGATE
					n.Object = $3
					n.Newschema = $6
					n.MissingOk = false
					$$ = n
				}
			| ALTER COLLATION any_name SET SCHEMA name
				{
					n := &AlterObjectSchemaStmt{}

					n.ObjectType = OBJECT_COLLATION
					n.Object = listNode($3)
					n.Newschema = $6
					n.MissingOk = false
					$$ = n
				}
			| ALTER CONVERSION_P any_name SET SCHEMA name
				{
					n := &AlterObjectSchemaStmt{}

					n.ObjectType = OBJECT_CONVERSION
					n.Object = listNode($3)
					n.Newschema = $6
					n.MissingOk = false
					$$ = n
				}
			| ALTER DOMAIN_P any_name SET SCHEMA name
				{
					n := &AlterObjectSchemaStmt{}

					n.ObjectType = OBJECT_DOMAIN
					n.Object = listNode($3)
					n.Newschema = $6
					n.MissingOk = false
					$$ = n
				}
			| ALTER EXTENSION name SET SCHEMA name
				{
					n := &AlterObjectSchemaStmt{}

					n.ObjectType = OBJECT_EXTENSION
					n.Object = makeString($3, @3)
					n.Newschema = $6
					n.MissingOk = false
					$$ = n
				}
			| ALTER FUNCTION function_with_argtypes SET SCHEMA name
				{
					n := &AlterObjectSchemaStmt{}

					n.ObjectType = OBJECT_FUNCTION
					n.Object = $3
					n.Newschema = $6
					n.MissingOk = false
					$$ = n
				}
			| ALTER OPERATOR operator_with_argtypes SET SCHEMA name
				{
					n := &AlterObjectSchemaStmt{}

					n.ObjectType = OBJECT_OPERATOR
					n.Object = $3
					n.Newschema = $6
					n.MissingOk = false
					$$ = n
				}
			| ALTER OPERATOR CLASS any_name USING name SET SCHEMA name
				{
					n := &AlterObjectSchemaStmt{}

					n.ObjectType = OBJECT_OPCLASS
					n.Object = listNode(append([]Node{makeString($6, @6)}, $4...))
					n.Newschema = $9
					n.MissingOk = false
					$$ = n
				}
			| ALTER OPERATOR FAMILY any_name USING name SET SCHEMA name
				{
					n := &AlterObjectSchemaStmt{}

					n.ObjectType = OBJECT_OPFAMILY
					n.Object = listNode(append([]Node{makeString($6, @6)}, $4...))
					n.Newschema = $9
					n.MissingOk = false
					$$ = n
				}
			| ALTER PROCEDURE function_with_argtypes SET SCHEMA name
				{
					n := &AlterObjectSchemaStmt{}

					n.ObjectType = OBJECT_PROCEDURE
					n.Object = $3
					n.Newschema = $6
					n.MissingOk = false
					$$ = n
				}
			| ALTER ROUTINE function_with_argtypes SET SCHEMA name
				{
					n := &AlterObjectSchemaStmt{}

					n.ObjectType = OBJECT_ROUTINE
					n.Object = $3
					n.Newschema = $6
					n.MissingOk = false
					$$ = n
				}
			| ALTER TABLE relation_expr SET SCHEMA name
				{
					n := &AlterObjectSchemaStmt{}

					n.ObjectType = OBJECT_TABLE
					n.Relation = as[*RangeVar]($3)
					n.Newschema = $6
					n.MissingOk = false
					$$ = n
				}
			| ALTER TABLE IF_P EXISTS relation_expr SET SCHEMA name
				{
					n := &AlterObjectSchemaStmt{}

					n.ObjectType = OBJECT_TABLE
					n.Relation = as[*RangeVar]($5)
					n.Newschema = $8
					n.MissingOk = true
					$$ = n
				}
			| ALTER STATISTICS any_name SET SCHEMA name
				{
					n := &AlterObjectSchemaStmt{}

					n.ObjectType = OBJECT_STATISTIC_EXT
					n.Object = listNode($3)
					n.Newschema = $6
					n.MissingOk = false
					$$ = n
				}
			| ALTER TEXT_P SEARCH PARSER any_name SET SCHEMA name
				{
					n := &AlterObjectSchemaStmt{}

					n.ObjectType = OBJECT_TSPARSER
					n.Object = listNode($5)
					n.Newschema = $8
					n.MissingOk = false
					$$ = n
				}
			| ALTER TEXT_P SEARCH DICTIONARY any_name SET SCHEMA name
				{
					n := &AlterObjectSchemaStmt{}

					n.ObjectType = OBJECT_TSDICTIONARY
					n.Object = listNode($5)
					n.Newschema = $8
					n.MissingOk = false
					$$ = n
				}
			| ALTER TEXT_P SEARCH TEMPLATE any_name SET SCHEMA name
				{
					n := &AlterObjectSchemaStmt{}

					n.ObjectType = OBJECT_TSTEMPLATE
					n.Object = listNode($5)
					n.Newschema = $8
					n.MissingOk = false
					$$ = n
				}
			| ALTER TEXT_P SEARCH CONFIGURATION any_name SET SCHEMA name
				{
					n := &AlterObjectSchemaStmt{}

					n.ObjectType = OBJECT_TSCONFIGURATION
					n.Object = listNode($5)
					n.Newschema = $8
					n.MissingOk = false
					$$ = n
				}
			| ALTER SEQUENCE qualified_name SET SCHEMA name
				{
					n := &AlterObjectSchemaStmt{}

					n.ObjectType = OBJECT_SEQUENCE
					n.Relation = as[*RangeVar]($3)
					n.Newschema = $6
					n.MissingOk = false
					$$ = n
				}
			| ALTER SEQUENCE IF_P EXISTS qualified_name SET SCHEMA name
				{
					n := &AlterObjectSchemaStmt{}

					n.ObjectType = OBJECT_SEQUENCE
					n.Relation = as[*RangeVar]($5)
					n.Newschema = $8
					n.MissingOk = true
					$$ = n
				}
			| ALTER VIEW qualified_name SET SCHEMA name
				{
					n := &AlterObjectSchemaStmt{}

					n.ObjectType = OBJECT_VIEW
					n.Relation = as[*RangeVar]($3)
					n.Newschema = $6
					n.MissingOk = false
					$$ = n
				}
			| ALTER VIEW IF_P EXISTS qualified_name SET SCHEMA name
				{
					n := &AlterObjectSchemaStmt{}

					n.ObjectType = OBJECT_VIEW
					n.Relation = as[*RangeVar]($5)
					n.Newschema = $8
					n.MissingOk = true
					$$ = n
				}
			| ALTER MATERIALIZED VIEW qualified_name SET SCHEMA name
				{
					n := &AlterObjectSchemaStmt{}

					n.ObjectType = OBJECT_MATVIEW
					n.Relation = as[*RangeVar]($4)
					n.Newschema = $7
					n.MissingOk = false
					$$ = n
				}
			| ALTER MATERIALIZED VIEW IF_P EXISTS qualified_name SET SCHEMA name
				{
					n := &AlterObjectSchemaStmt{}

					n.ObjectType = OBJECT_MATVIEW
					n.Relation = as[*RangeVar]($6)
					n.Newschema = $9
					n.MissingOk = true
					$$ = n
				}
			| ALTER FOREIGN TABLE relation_expr SET SCHEMA name
				{
					n := &AlterObjectSchemaStmt{}

					n.ObjectType = OBJECT_FOREIGN_TABLE
					n.Relation = as[*RangeVar]($4)
					n.Newschema = $7
					n.MissingOk = false
					$$ = n
				}
			| ALTER FOREIGN TABLE IF_P EXISTS relation_expr SET SCHEMA name
				{
					n := &AlterObjectSchemaStmt{}

					n.ObjectType = OBJECT_FOREIGN_TABLE
					n.Relation = as[*RangeVar]($6)
					n.Newschema = $9
					n.MissingOk = true
					$$ = n
				}
			| ALTER TYPE_P any_name SET SCHEMA name
				{
					n := &AlterObjectSchemaStmt{}

					n.ObjectType = OBJECT_TYPE
					n.Object = listNode($3)
					n.Newschema = $6
					n.MissingOk = false
					$$ = n
				}
		;

/*****************************************************************************
 *
 * ALTER OPERATOR name SET define
 *
 *****************************************************************************/

AlterOperatorStmt:
			ALTER OPERATOR operator_with_argtypes SET '(' operator_def_list ')'
				{
					n := &AlterOperatorStmt{}

					n.Opername = as[*ObjectWithArgs]($3)
					n.Options = $6
					$$ = n
				}
		;

operator_def_list:	operator_def_elem								{ $$ = []Node{$1} }
			| operator_def_list ',' operator_def_elem				{ $$ = append($1, $3) }
		;

operator_def_elem: ColLabel '=' NONE
						{ $$ = makeDefElem($1, nil, @1) }
				   | ColLabel '=' operator_def_arg
						{ $$ = makeDefElem($1, $3, @1) }
				   | ColLabel
						{ $$ = makeDefElem($1, nil, @1) }
		;

/* must be similar enough to def_arg to avoid reduce/reduce conflicts */
operator_def_arg:
			func_type						{ $$ = $1 }
			| reserved_keyword				{ $$ = makeString($1, @1) }
			| qual_all_Op					{ $$ = listNode($1) }
			| NumericOnly					{ $$ = $1 }
			| Sconst						{ $$ = makeString($1, @1) }
		;

/*****************************************************************************
 *
 * ALTER TYPE name SET define
 *
 * We repurpose ALTER OPERATOR's version of "definition" here
 *
 *****************************************************************************/

AlterTypeStmt:
			ALTER TYPE_P any_name SET '(' operator_def_list ')'
				{
					n := &AlterTypeStmt{}

					n.TypeName = $3
					n.Options = $6
					$$ = n
				}
		;

/*****************************************************************************
 *
 * ALTER THING name OWNER TO newname
 *
 *****************************************************************************/

AlterOwnerStmt: ALTER AGGREGATE aggregate_with_argtypes OWNER TO RoleSpec
				{
					n := &AlterOwnerStmt{}

					n.ObjectType = OBJECT_AGGREGATE
					n.Object = $3
					n.Newowner = as[*RoleSpec]($6)
					$$ = n
				}
			| ALTER COLLATION any_name OWNER TO RoleSpec
				{
					n := &AlterOwnerStmt{}

					n.ObjectType = OBJECT_COLLATION
					n.Object = listNode($3)
					n.Newowner = as[*RoleSpec]($6)
					$$ = n
				}
			| ALTER CONVERSION_P any_name OWNER TO RoleSpec
				{
					n := &AlterOwnerStmt{}

					n.ObjectType = OBJECT_CONVERSION
					n.Object = listNode($3)
					n.Newowner = as[*RoleSpec]($6)
					$$ = n
				}
			| ALTER DATABASE name OWNER TO RoleSpec
				{
					n := &AlterOwnerStmt{}

					n.ObjectType = OBJECT_DATABASE
					n.Object = makeString($3, @3)
					n.Newowner = as[*RoleSpec]($6)
					$$ = n
				}
			| ALTER DOMAIN_P any_name OWNER TO RoleSpec
				{
					n := &AlterOwnerStmt{}

					n.ObjectType = OBJECT_DOMAIN
					n.Object = listNode($3)
					n.Newowner = as[*RoleSpec]($6)
					$$ = n
				}
			| ALTER FUNCTION function_with_argtypes OWNER TO RoleSpec
				{
					n := &AlterOwnerStmt{}

					n.ObjectType = OBJECT_FUNCTION
					n.Object = $3
					n.Newowner = as[*RoleSpec]($6)
					$$ = n
				}
			| ALTER opt_procedural LANGUAGE name OWNER TO RoleSpec
				{
					n := &AlterOwnerStmt{}

					n.ObjectType = OBJECT_LANGUAGE
					n.Object = makeString($4, @4)
					n.Newowner = as[*RoleSpec]($7)
					$$ = n
				}
			| ALTER LARGE_P OBJECT_P NumericOnly OWNER TO RoleSpec
				{
					n := &AlterOwnerStmt{}

					n.ObjectType = OBJECT_LARGEOBJECT
					n.Object = $4
					n.Newowner = as[*RoleSpec]($7)
					$$ = n
				}
			| ALTER OPERATOR operator_with_argtypes OWNER TO RoleSpec
				{
					n := &AlterOwnerStmt{}

					n.ObjectType = OBJECT_OPERATOR
					n.Object = $3
					n.Newowner = as[*RoleSpec]($6)
					$$ = n
				}
			| ALTER OPERATOR CLASS any_name USING name OWNER TO RoleSpec
				{
					n := &AlterOwnerStmt{}

					n.ObjectType = OBJECT_OPCLASS
					n.Object = listNode(append([]Node{makeString($6, @6)}, $4...))
					n.Newowner = as[*RoleSpec]($9)
					$$ = n
				}
			| ALTER OPERATOR FAMILY any_name USING name OWNER TO RoleSpec
				{
					n := &AlterOwnerStmt{}

					n.ObjectType = OBJECT_OPFAMILY
					n.Object = listNode(append([]Node{makeString($6, @6)}, $4...))
					n.Newowner = as[*RoleSpec]($9)
					$$ = n
				}
			| ALTER PROCEDURE function_with_argtypes OWNER TO RoleSpec
				{
					n := &AlterOwnerStmt{}

					n.ObjectType = OBJECT_PROCEDURE
					n.Object = $3
					n.Newowner = as[*RoleSpec]($6)
					$$ = n
				}
			| ALTER ROUTINE function_with_argtypes OWNER TO RoleSpec
				{
					n := &AlterOwnerStmt{}

					n.ObjectType = OBJECT_ROUTINE
					n.Object = $3
					n.Newowner = as[*RoleSpec]($6)
					$$ = n
				}
			| ALTER SCHEMA name OWNER TO RoleSpec
				{
					n := &AlterOwnerStmt{}

					n.ObjectType = OBJECT_SCHEMA
					n.Object = makeString($3, @3)
					n.Newowner = as[*RoleSpec]($6)
					$$ = n
				}
			| ALTER TYPE_P any_name OWNER TO RoleSpec
				{
					n := &AlterOwnerStmt{}

					n.ObjectType = OBJECT_TYPE
					n.Object = listNode($3)
					n.Newowner = as[*RoleSpec]($6)
					$$ = n
				}
			| ALTER TABLESPACE name OWNER TO RoleSpec
				{
					n := &AlterOwnerStmt{}

					n.ObjectType = OBJECT_TABLESPACE
					n.Object = makeString($3, @3)
					n.Newowner = as[*RoleSpec]($6)
					$$ = n
				}
			| ALTER STATISTICS any_name OWNER TO RoleSpec
				{
					n := &AlterOwnerStmt{}

					n.ObjectType = OBJECT_STATISTIC_EXT
					n.Object = listNode($3)
					n.Newowner = as[*RoleSpec]($6)
					$$ = n
				}
			| ALTER TEXT_P SEARCH DICTIONARY any_name OWNER TO RoleSpec
				{
					n := &AlterOwnerStmt{}

					n.ObjectType = OBJECT_TSDICTIONARY
					n.Object = listNode($5)
					n.Newowner = as[*RoleSpec]($8)
					$$ = n
				}
			| ALTER TEXT_P SEARCH CONFIGURATION any_name OWNER TO RoleSpec
				{
					n := &AlterOwnerStmt{}

					n.ObjectType = OBJECT_TSCONFIGURATION
					n.Object = listNode($5)
					n.Newowner = as[*RoleSpec]($8)
					$$ = n
				}
			| ALTER FOREIGN DATA_P WRAPPER name OWNER TO RoleSpec
				{
					n := &AlterOwnerStmt{}

					n.ObjectType = OBJECT_FDW
					n.Object = makeString($5, @5)
					n.Newowner = as[*RoleSpec]($8)
					$$ = n
				}
			| ALTER SERVER name OWNER TO RoleSpec
				{
					n := &AlterOwnerStmt{}

					n.ObjectType = OBJECT_FOREIGN_SERVER
					n.Object = makeString($3, @3)
					n.Newowner = as[*RoleSpec]($6)
					$$ = n
				}
			| ALTER EVENT TRIGGER name OWNER TO RoleSpec
				{
					n := &AlterOwnerStmt{}

					n.ObjectType = OBJECT_EVENT_TRIGGER
					n.Object = makeString($4, @4)
					n.Newowner = as[*RoleSpec]($7)
					$$ = n
				}
			| ALTER PUBLICATION name OWNER TO RoleSpec
				{
					n := &AlterOwnerStmt{}

					n.ObjectType = OBJECT_PUBLICATION
					n.Object = makeString($3, @3)
					n.Newowner = as[*RoleSpec]($6)
					$$ = n
				}
			| ALTER SUBSCRIPTION name OWNER TO RoleSpec
				{
					n := &AlterOwnerStmt{}

					n.ObjectType = OBJECT_SUBSCRIPTION
					n.Object = makeString($3, @3)
					n.Newowner = as[*RoleSpec]($6)
					$$ = n
				}
		;

