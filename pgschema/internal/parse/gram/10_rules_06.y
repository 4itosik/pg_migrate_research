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
				{ /*C
					AlterFunctionStmt *n = makeNode(AlterFunctionStmt);

					n->objtype = OBJECT_FUNCTION;
					n->func = $3;
					n->actions = $4;
					$$ = (Node *) n;
				*/ }
			| ALTER PROCEDURE function_with_argtypes alterfunc_opt_list opt_restrict
				{ /*C
					AlterFunctionStmt *n = makeNode(AlterFunctionStmt);

					n->objtype = OBJECT_PROCEDURE;
					n->func = $3;
					n->actions = $4;
					$$ = (Node *) n;
				*/ }
			| ALTER ROUTINE function_with_argtypes alterfunc_opt_list opt_restrict
				{ /*C
					AlterFunctionStmt *n = makeNode(AlterFunctionStmt);

					n->objtype = OBJECT_ROUTINE;
					n->func = $3;
					n->actions = $4;
					$$ = (Node *) n;
				*/ }
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
				{ /*C
					DropStmt *n = makeNode(DropStmt);

					n->removeType = OBJECT_FUNCTION;
					n->objects = $3;
					n->behavior = $4;
					n->missing_ok = false;
					n->concurrent = false;
					$$ = (Node *) n;
				*/ }
			| DROP FUNCTION IF_P EXISTS function_with_argtypes_list opt_drop_behavior
				{ /*C
					DropStmt *n = makeNode(DropStmt);

					n->removeType = OBJECT_FUNCTION;
					n->objects = $5;
					n->behavior = $6;
					n->missing_ok = true;
					n->concurrent = false;
					$$ = (Node *) n;
				*/ }
			| DROP PROCEDURE function_with_argtypes_list opt_drop_behavior
				{ /*C
					DropStmt *n = makeNode(DropStmt);

					n->removeType = OBJECT_PROCEDURE;
					n->objects = $3;
					n->behavior = $4;
					n->missing_ok = false;
					n->concurrent = false;
					$$ = (Node *) n;
				*/ }
			| DROP PROCEDURE IF_P EXISTS function_with_argtypes_list opt_drop_behavior
				{ /*C
					DropStmt *n = makeNode(DropStmt);

					n->removeType = OBJECT_PROCEDURE;
					n->objects = $5;
					n->behavior = $6;
					n->missing_ok = true;
					n->concurrent = false;
					$$ = (Node *) n;
				*/ }
			| DROP ROUTINE function_with_argtypes_list opt_drop_behavior
				{ /*C
					DropStmt *n = makeNode(DropStmt);

					n->removeType = OBJECT_ROUTINE;
					n->objects = $3;
					n->behavior = $4;
					n->missing_ok = false;
					n->concurrent = false;
					$$ = (Node *) n;
				*/ }
			| DROP ROUTINE IF_P EXISTS function_with_argtypes_list opt_drop_behavior
				{ /*C
					DropStmt *n = makeNode(DropStmt);

					n->removeType = OBJECT_ROUTINE;
					n->objects = $5;
					n->behavior = $6;
					n->missing_ok = true;
					n->concurrent = false;
					$$ = (Node *) n;
				*/ }
		;

RemoveAggrStmt:
			DROP AGGREGATE aggregate_with_argtypes_list opt_drop_behavior
				{ /*C
					DropStmt *n = makeNode(DropStmt);

					n->removeType = OBJECT_AGGREGATE;
					n->objects = $3;
					n->behavior = $4;
					n->missing_ok = false;
					n->concurrent = false;
					$$ = (Node *) n;
				*/ }
			| DROP AGGREGATE IF_P EXISTS aggregate_with_argtypes_list opt_drop_behavior
				{ /*C
					DropStmt *n = makeNode(DropStmt);

					n->removeType = OBJECT_AGGREGATE;
					n->objects = $5;
					n->behavior = $6;
					n->missing_ok = true;
					n->concurrent = false;
					$$ = (Node *) n;
				*/ }
		;

RemoveOperStmt:
			DROP OPERATOR operator_with_argtypes_list opt_drop_behavior
				{ /*C
					DropStmt *n = makeNode(DropStmt);

					n->removeType = OBJECT_OPERATOR;
					n->objects = $3;
					n->behavior = $4;
					n->missing_ok = false;
					n->concurrent = false;
					$$ = (Node *) n;
				*/ }
			| DROP OPERATOR IF_P EXISTS operator_with_argtypes_list opt_drop_behavior
				{ /*C
					DropStmt *n = makeNode(DropStmt);

					n->removeType = OBJECT_OPERATOR;
					n->objects = $5;
					n->behavior = $6;
					n->missing_ok = true;
					n->concurrent = false;
					$$ = (Node *) n;
				*/ }
		;

oper_argtypes:
			'(' Typename ')'
				{ /*C
				   ereport(ERROR,
						   (errcode(ERRCODE_SYNTAX_ERROR),
							errmsg("missing argument"),
							errhint("Use NONE to denote the missing argument of a unary operator."),
							parser_errposition(@3)));
				*/ }
			| '(' Typename ',' Typename ')'
					{ /*C $$ = list_make2($2, $4); */ }
			| '(' NONE ',' Typename ')'					/* left unary */
					{ /*C $$ = list_make2(NULL, $4); */ }
			| '(' Typename ',' NONE ')'					/* right unary */
					{ /*C $$ = list_make2($2, NULL); */ }
		;

any_operator:
			all_Op
					{ /*C $$ = list_make1(makeString($1)); */ }
			| ColId '.' any_operator
					{ /*C $$ = lcons(makeString($1), $3); */ }
		;

operator_with_argtypes_list:
			operator_with_argtypes					{ $$ = []Node{$1} }
			| operator_with_argtypes_list ',' operator_with_argtypes
													{ $$ = append($1, $3) }
		;

operator_with_argtypes:
			any_operator oper_argtypes
				{ /*C
					ObjectWithArgs *n = makeNode(ObjectWithArgs);

					n->objname = $1;
					n->objargs = $2;
					$$ = n;
				*/ }
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
				{ /*C
					DoStmt *n = makeNode(DoStmt);

					n->args = $2;
					$$ = (Node *) n;
				*/ }
		;

dostmt_opt_list:
			dostmt_opt_item						{ $$ = []Node{$1} }
			| dostmt_opt_list dostmt_opt_item	{ $$ = append($1, $2) }
		;

dostmt_opt_item:
			Sconst
				{ /*C
					$$ = makeDefElem("as", (Node *) makeString($1), @1);
				*/ }
			| LANGUAGE NonReservedWord_or_Sconst
				{ /*C
					$$ = makeDefElem("language", (Node *) makeString($2), @1);
				*/ }
		;

/*****************************************************************************
 *
 *		CREATE CAST / DROP CAST
 *
 *****************************************************************************/

CreateCastStmt: CREATE CAST '(' Typename AS Typename ')'
					WITH FUNCTION function_with_argtypes cast_context
				{ /*C
					CreateCastStmt *n = makeNode(CreateCastStmt);

					n->sourcetype = $4;
					n->targettype = $6;
					n->func = $10;
					n->context = (CoercionContext) $11;
					n->inout = false;
					$$ = (Node *) n;
				*/ }
			| CREATE CAST '(' Typename AS Typename ')'
					WITHOUT FUNCTION cast_context
				{ /*C
					CreateCastStmt *n = makeNode(CreateCastStmt);

					n->sourcetype = $4;
					n->targettype = $6;
					n->func = NULL;
					n->context = (CoercionContext) $10;
					n->inout = false;
					$$ = (Node *) n;
				*/ }
			| CREATE CAST '(' Typename AS Typename ')'
					WITH INOUT cast_context
				{ /*C
					CreateCastStmt *n = makeNode(CreateCastStmt);

					n->sourcetype = $4;
					n->targettype = $6;
					n->func = NULL;
					n->context = (CoercionContext) $10;
					n->inout = true;
					$$ = (Node *) n;
				*/ }
		;

cast_context:  AS IMPLICIT_P					{ /*C $$ = COERCION_IMPLICIT; */ }
		| AS ASSIGNMENT							{ /*C $$ = COERCION_ASSIGNMENT; */ }
		| /*EMPTY*/								{ /*C $$ = COERCION_EXPLICIT; */ }
		;


DropCastStmt: DROP CAST opt_if_exists '(' Typename AS Typename ')' opt_drop_behavior
				{ /*C
					DropStmt *n = makeNode(DropStmt);

					n->removeType = OBJECT_CAST;
					n->objects = list_make1(list_make2($5, $7));
					n->behavior = $9;
					n->missing_ok = $3;
					n->concurrent = false;
					$$ = (Node *) n;
				*/ }
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
				{ /*C
					CreateTransformStmt *n = makeNode(CreateTransformStmt);

					n->replace = $2;
					n->type_name = $5;
					n->lang = $7;
					n->fromsql = linitial($9);
					n->tosql = lsecond($9);
					$$ = (Node *) n;
				*/ }
		;

transform_element_list: FROM SQL_P WITH FUNCTION function_with_argtypes ',' TO SQL_P WITH FUNCTION function_with_argtypes
				{ /*C
					$$ = list_make2($5, $11);
				*/ }
				| TO SQL_P WITH FUNCTION function_with_argtypes ',' FROM SQL_P WITH FUNCTION function_with_argtypes
				{ /*C
					$$ = list_make2($11, $5);
				*/ }
				| FROM SQL_P WITH FUNCTION function_with_argtypes
				{ /*C
					$$ = list_make2($5, NULL);
				*/ }
				| TO SQL_P WITH FUNCTION function_with_argtypes
				{ /*C
					$$ = list_make2(NULL, $5);
				*/ }
		;


DropTransformStmt: DROP TRANSFORM opt_if_exists FOR Typename LANGUAGE name opt_drop_behavior
				{ /*C
					DropStmt *n = makeNode(DropStmt);

					n->removeType = OBJECT_TRANSFORM;
					n->objects = list_make1(list_make2($5, makeString($7)));
					n->behavior = $8;
					n->missing_ok = $3;
					$$ = (Node *) n;
				*/ }
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
				{ /*C
					ReindexStmt *n = makeNode(ReindexStmt);

					n->kind = $3;
					n->relation = $5;
					n->name = NULL;
					n->params = $2;
					if ($4)
						n->params = lappend(n->params,
											makeDefElem("concurrently", NULL, @4));
					$$ = (Node *) n;
				*/ }
			| REINDEX opt_reindex_option_list SCHEMA opt_concurrently name
				{ /*C
					ReindexStmt *n = makeNode(ReindexStmt);

					n->kind = REINDEX_OBJECT_SCHEMA;
					n->relation = NULL;
					n->name = $5;
					n->params = $2;
					if ($4)
						n->params = lappend(n->params,
											makeDefElem("concurrently", NULL, @4));
					$$ = (Node *) n;
				*/ }
			| REINDEX opt_reindex_option_list reindex_target_all opt_concurrently opt_single_name
				{ /*C
					ReindexStmt *n = makeNode(ReindexStmt);

					n->kind = $3;
					n->relation = NULL;
					n->name = $5;
					n->params = $2;
					if ($4)
						n->params = lappend(n->params,
											makeDefElem("concurrently", NULL, @4));
					$$ = (Node *) n;
				*/ }
		;
reindex_target_relation:
			INDEX					{ /*C $$ = REINDEX_OBJECT_INDEX; */ }
			| TABLE					{ /*C $$ = REINDEX_OBJECT_TABLE; */ }
		;
reindex_target_all:
			SYSTEM_P				{ /*C $$ = REINDEX_OBJECT_SYSTEM; */ }
			| DATABASE				{ /*C $$ = REINDEX_OBJECT_DATABASE; */ }
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
				{ /*C
					AlterTableSpaceOptionsStmt *n =
						makeNode(AlterTableSpaceOptionsStmt);

					n->tablespacename = $3;
					n->options = $5;
					n->isReset = false;
					$$ = (Node *) n;
				*/ }
			| ALTER TABLESPACE name RESET reloptions
				{ /*C
					AlterTableSpaceOptionsStmt *n =
						makeNode(AlterTableSpaceOptionsStmt);

					n->tablespacename = $3;
					n->options = $5;
					n->isReset = true;
					$$ = (Node *) n;
				*/ }
		;

/*****************************************************************************
 *
 * ALTER THING name RENAME TO newname
 *
 *****************************************************************************/

RenameStmt: ALTER AGGREGATE aggregate_with_argtypes RENAME TO name
				{ /*C
					RenameStmt *n = makeNode(RenameStmt);

					n->renameType = OBJECT_AGGREGATE;
					n->object = (Node *) $3;
					n->newname = $6;
					n->missing_ok = false;
					$$ = (Node *) n;
				*/ }
			| ALTER COLLATION any_name RENAME TO name
				{ /*C
					RenameStmt *n = makeNode(RenameStmt);

					n->renameType = OBJECT_COLLATION;
					n->object = (Node *) $3;
					n->newname = $6;
					n->missing_ok = false;
					$$ = (Node *) n;
				*/ }
			| ALTER CONVERSION_P any_name RENAME TO name
				{ /*C
					RenameStmt *n = makeNode(RenameStmt);

					n->renameType = OBJECT_CONVERSION;
					n->object = (Node *) $3;
					n->newname = $6;
					n->missing_ok = false;
					$$ = (Node *) n;
				*/ }
			| ALTER DATABASE name RENAME TO name
				{ /*C
					RenameStmt *n = makeNode(RenameStmt);

					n->renameType = OBJECT_DATABASE;
					n->subname = $3;
					n->newname = $6;
					n->missing_ok = false;
					$$ = (Node *) n;
				*/ }
			| ALTER DOMAIN_P any_name RENAME TO name
				{ /*C
					RenameStmt *n = makeNode(RenameStmt);

					n->renameType = OBJECT_DOMAIN;
					n->object = (Node *) $3;
					n->newname = $6;
					n->missing_ok = false;
					$$ = (Node *) n;
				*/ }
			| ALTER DOMAIN_P any_name RENAME CONSTRAINT name TO name
				{ /*C
					RenameStmt *n = makeNode(RenameStmt);

					n->renameType = OBJECT_DOMCONSTRAINT;
					n->object = (Node *) $3;
					n->subname = $6;
					n->newname = $8;
					$$ = (Node *) n;
				*/ }
			| ALTER FOREIGN DATA_P WRAPPER name RENAME TO name
				{ /*C
					RenameStmt *n = makeNode(RenameStmt);

					n->renameType = OBJECT_FDW;
					n->object = (Node *) makeString($5);
					n->newname = $8;
					n->missing_ok = false;
					$$ = (Node *) n;
				*/ }
			| ALTER FUNCTION function_with_argtypes RENAME TO name
				{ /*C
					RenameStmt *n = makeNode(RenameStmt);

					n->renameType = OBJECT_FUNCTION;
					n->object = (Node *) $3;
					n->newname = $6;
					n->missing_ok = false;
					$$ = (Node *) n;
				*/ }
			| ALTER GROUP_P RoleId RENAME TO RoleId
				{ /*C
					RenameStmt *n = makeNode(RenameStmt);

					n->renameType = OBJECT_ROLE;
					n->subname = $3;
					n->newname = $6;
					n->missing_ok = false;
					$$ = (Node *) n;
				*/ }
			| ALTER opt_procedural LANGUAGE name RENAME TO name
				{ /*C
					RenameStmt *n = makeNode(RenameStmt);

					n->renameType = OBJECT_LANGUAGE;
					n->object = (Node *) makeString($4);
					n->newname = $7;
					n->missing_ok = false;
					$$ = (Node *) n;
				*/ }
			| ALTER OPERATOR CLASS any_name USING name RENAME TO name
				{ /*C
					RenameStmt *n = makeNode(RenameStmt);

					n->renameType = OBJECT_OPCLASS;
					n->object = (Node *) lcons(makeString($6), $4);
					n->newname = $9;
					n->missing_ok = false;
					$$ = (Node *) n;
				*/ }
			| ALTER OPERATOR FAMILY any_name USING name RENAME TO name
				{ /*C
					RenameStmt *n = makeNode(RenameStmt);

					n->renameType = OBJECT_OPFAMILY;
					n->object = (Node *) lcons(makeString($6), $4);
					n->newname = $9;
					n->missing_ok = false;
					$$ = (Node *) n;
				*/ }
			| ALTER POLICY name ON qualified_name RENAME TO name
				{ /*C
					RenameStmt *n = makeNode(RenameStmt);

					n->renameType = OBJECT_POLICY;
					n->relation = $5;
					n->subname = $3;
					n->newname = $8;
					n->missing_ok = false;
					$$ = (Node *) n;
				*/ }
			| ALTER POLICY IF_P EXISTS name ON qualified_name RENAME TO name
				{ /*C
					RenameStmt *n = makeNode(RenameStmt);

					n->renameType = OBJECT_POLICY;
					n->relation = $7;
					n->subname = $5;
					n->newname = $10;
					n->missing_ok = true;
					$$ = (Node *) n;
				*/ }
			| ALTER PROCEDURE function_with_argtypes RENAME TO name
				{ /*C
					RenameStmt *n = makeNode(RenameStmt);

					n->renameType = OBJECT_PROCEDURE;
					n->object = (Node *) $3;
					n->newname = $6;
					n->missing_ok = false;
					$$ = (Node *) n;
				*/ }
			| ALTER PUBLICATION name RENAME TO name
				{ /*C
					RenameStmt *n = makeNode(RenameStmt);

					n->renameType = OBJECT_PUBLICATION;
					n->object = (Node *) makeString($3);
					n->newname = $6;
					n->missing_ok = false;
					$$ = (Node *) n;
				*/ }
			| ALTER ROUTINE function_with_argtypes RENAME TO name
				{ /*C
					RenameStmt *n = makeNode(RenameStmt);

					n->renameType = OBJECT_ROUTINE;
					n->object = (Node *) $3;
					n->newname = $6;
					n->missing_ok = false;
					$$ = (Node *) n;
				*/ }
			| ALTER SCHEMA name RENAME TO name
				{ /*C
					RenameStmt *n = makeNode(RenameStmt);

					n->renameType = OBJECT_SCHEMA;
					n->subname = $3;
					n->newname = $6;
					n->missing_ok = false;
					$$ = (Node *) n;
				*/ }
			| ALTER SERVER name RENAME TO name
				{ /*C
					RenameStmt *n = makeNode(RenameStmt);

					n->renameType = OBJECT_FOREIGN_SERVER;
					n->object = (Node *) makeString($3);
					n->newname = $6;
					n->missing_ok = false;
					$$ = (Node *) n;
				*/ }
			| ALTER SUBSCRIPTION name RENAME TO name
				{ /*C
					RenameStmt *n = makeNode(RenameStmt);

					n->renameType = OBJECT_SUBSCRIPTION;
					n->object = (Node *) makeString($3);
					n->newname = $6;
					n->missing_ok = false;
					$$ = (Node *) n;
				*/ }
			| ALTER TABLE relation_expr RENAME TO name
				{ /*C
					RenameStmt *n = makeNode(RenameStmt);

					n->renameType = OBJECT_TABLE;
					n->relation = $3;
					n->subname = NULL;
					n->newname = $6;
					n->missing_ok = false;
					$$ = (Node *) n;
				*/ }
			| ALTER TABLE IF_P EXISTS relation_expr RENAME TO name
				{ /*C
					RenameStmt *n = makeNode(RenameStmt);

					n->renameType = OBJECT_TABLE;
					n->relation = $5;
					n->subname = NULL;
					n->newname = $8;
					n->missing_ok = true;
					$$ = (Node *) n;
				*/ }
			| ALTER SEQUENCE qualified_name RENAME TO name
				{ /*C
					RenameStmt *n = makeNode(RenameStmt);

					n->renameType = OBJECT_SEQUENCE;
					n->relation = $3;
					n->subname = NULL;
					n->newname = $6;
					n->missing_ok = false;
					$$ = (Node *) n;
				*/ }
			| ALTER SEQUENCE IF_P EXISTS qualified_name RENAME TO name
				{ /*C
					RenameStmt *n = makeNode(RenameStmt);

					n->renameType = OBJECT_SEQUENCE;
					n->relation = $5;
					n->subname = NULL;
					n->newname = $8;
					n->missing_ok = true;
					$$ = (Node *) n;
				*/ }
			| ALTER VIEW qualified_name RENAME TO name
				{ /*C
					RenameStmt *n = makeNode(RenameStmt);

					n->renameType = OBJECT_VIEW;
					n->relation = $3;
					n->subname = NULL;
					n->newname = $6;
					n->missing_ok = false;
					$$ = (Node *) n;
				*/ }
			| ALTER VIEW IF_P EXISTS qualified_name RENAME TO name
				{ /*C
					RenameStmt *n = makeNode(RenameStmt);

					n->renameType = OBJECT_VIEW;
					n->relation = $5;
					n->subname = NULL;
					n->newname = $8;
					n->missing_ok = true;
					$$ = (Node *) n;
				*/ }
			| ALTER MATERIALIZED VIEW qualified_name RENAME TO name
				{ /*C
					RenameStmt *n = makeNode(RenameStmt);

					n->renameType = OBJECT_MATVIEW;
					n->relation = $4;
					n->subname = NULL;
					n->newname = $7;
					n->missing_ok = false;
					$$ = (Node *) n;
				*/ }
			| ALTER MATERIALIZED VIEW IF_P EXISTS qualified_name RENAME TO name
				{ /*C
					RenameStmt *n = makeNode(RenameStmt);

					n->renameType = OBJECT_MATVIEW;
					n->relation = $6;
					n->subname = NULL;
					n->newname = $9;
					n->missing_ok = true;
					$$ = (Node *) n;
				*/ }
			| ALTER INDEX qualified_name RENAME TO name
				{ /*C
					RenameStmt *n = makeNode(RenameStmt);

					n->renameType = OBJECT_INDEX;
					n->relation = $3;
					n->subname = NULL;
					n->newname = $6;
					n->missing_ok = false;
					$$ = (Node *) n;
				*/ }
			| ALTER INDEX IF_P EXISTS qualified_name RENAME TO name
				{ /*C
					RenameStmt *n = makeNode(RenameStmt);

					n->renameType = OBJECT_INDEX;
					n->relation = $5;
					n->subname = NULL;
					n->newname = $8;
					n->missing_ok = true;
					$$ = (Node *) n;
				*/ }
			| ALTER FOREIGN TABLE relation_expr RENAME TO name
				{ /*C
					RenameStmt *n = makeNode(RenameStmt);

					n->renameType = OBJECT_FOREIGN_TABLE;
					n->relation = $4;
					n->subname = NULL;
					n->newname = $7;
					n->missing_ok = false;
					$$ = (Node *) n;
				*/ }
			| ALTER FOREIGN TABLE IF_P EXISTS relation_expr RENAME TO name
				{ /*C
					RenameStmt *n = makeNode(RenameStmt);

					n->renameType = OBJECT_FOREIGN_TABLE;
					n->relation = $6;
					n->subname = NULL;
					n->newname = $9;
					n->missing_ok = true;
					$$ = (Node *) n;
				*/ }
			| ALTER TABLE relation_expr RENAME opt_column name TO name
				{ /*C
					RenameStmt *n = makeNode(RenameStmt);

					n->renameType = OBJECT_COLUMN;
					n->relationType = OBJECT_TABLE;
					n->relation = $3;
					n->subname = $6;
					n->newname = $8;
					n->missing_ok = false;
					$$ = (Node *) n;
				*/ }
			| ALTER TABLE IF_P EXISTS relation_expr RENAME opt_column name TO name
				{ /*C
					RenameStmt *n = makeNode(RenameStmt);

					n->renameType = OBJECT_COLUMN;
					n->relationType = OBJECT_TABLE;
					n->relation = $5;
					n->subname = $8;
					n->newname = $10;
					n->missing_ok = true;
					$$ = (Node *) n;
				*/ }
			| ALTER VIEW qualified_name RENAME opt_column name TO name
				{ /*C
					RenameStmt *n = makeNode(RenameStmt);

					n->renameType = OBJECT_COLUMN;
					n->relationType = OBJECT_VIEW;
					n->relation = $3;
					n->subname = $6;
					n->newname = $8;
					n->missing_ok = false;
					$$ = (Node *) n;
				*/ }
			| ALTER VIEW IF_P EXISTS qualified_name RENAME opt_column name TO name
				{ /*C
					RenameStmt *n = makeNode(RenameStmt);

					n->renameType = OBJECT_COLUMN;
					n->relationType = OBJECT_VIEW;
					n->relation = $5;
					n->subname = $8;
					n->newname = $10;
					n->missing_ok = true;
					$$ = (Node *) n;
				*/ }
			| ALTER MATERIALIZED VIEW qualified_name RENAME opt_column name TO name
				{ /*C
					RenameStmt *n = makeNode(RenameStmt);

					n->renameType = OBJECT_COLUMN;
					n->relationType = OBJECT_MATVIEW;
					n->relation = $4;
					n->subname = $7;
					n->newname = $9;
					n->missing_ok = false;
					$$ = (Node *) n;
				*/ }
			| ALTER MATERIALIZED VIEW IF_P EXISTS qualified_name RENAME opt_column name TO name
				{ /*C
					RenameStmt *n = makeNode(RenameStmt);

					n->renameType = OBJECT_COLUMN;
					n->relationType = OBJECT_MATVIEW;
					n->relation = $6;
					n->subname = $9;
					n->newname = $11;
					n->missing_ok = true;
					$$ = (Node *) n;
				*/ }
			| ALTER TABLE relation_expr RENAME CONSTRAINT name TO name
				{ /*C
					RenameStmt *n = makeNode(RenameStmt);

					n->renameType = OBJECT_TABCONSTRAINT;
					n->relation = $3;
					n->subname = $6;
					n->newname = $8;
					n->missing_ok = false;
					$$ = (Node *) n;
				*/ }
			| ALTER TABLE IF_P EXISTS relation_expr RENAME CONSTRAINT name TO name
				{ /*C
					RenameStmt *n = makeNode(RenameStmt);

					n->renameType = OBJECT_TABCONSTRAINT;
					n->relation = $5;
					n->subname = $8;
					n->newname = $10;
					n->missing_ok = true;
					$$ = (Node *) n;
				*/ }
			| ALTER FOREIGN TABLE relation_expr RENAME opt_column name TO name
				{ /*C
					RenameStmt *n = makeNode(RenameStmt);

					n->renameType = OBJECT_COLUMN;
					n->relationType = OBJECT_FOREIGN_TABLE;
					n->relation = $4;
					n->subname = $7;
					n->newname = $9;
					n->missing_ok = false;
					$$ = (Node *) n;
				*/ }
			| ALTER FOREIGN TABLE IF_P EXISTS relation_expr RENAME opt_column name TO name
				{ /*C
					RenameStmt *n = makeNode(RenameStmt);

					n->renameType = OBJECT_COLUMN;
					n->relationType = OBJECT_FOREIGN_TABLE;
					n->relation = $6;
					n->subname = $9;
					n->newname = $11;
					n->missing_ok = true;
					$$ = (Node *) n;
				*/ }
			| ALTER RULE name ON qualified_name RENAME TO name
				{ /*C
					RenameStmt *n = makeNode(RenameStmt);

					n->renameType = OBJECT_RULE;
					n->relation = $5;
					n->subname = $3;
					n->newname = $8;
					n->missing_ok = false;
					$$ = (Node *) n;
				*/ }
			| ALTER TRIGGER name ON qualified_name RENAME TO name
				{ /*C
					RenameStmt *n = makeNode(RenameStmt);

					n->renameType = OBJECT_TRIGGER;
					n->relation = $5;
					n->subname = $3;
					n->newname = $8;
					n->missing_ok = false;
					$$ = (Node *) n;
				*/ }
			| ALTER EVENT TRIGGER name RENAME TO name
				{ /*C
					RenameStmt *n = makeNode(RenameStmt);

					n->renameType = OBJECT_EVENT_TRIGGER;
					n->object = (Node *) makeString($4);
					n->newname = $7;
					$$ = (Node *) n;
				*/ }
			| ALTER ROLE RoleId RENAME TO RoleId
				{ /*C
					RenameStmt *n = makeNode(RenameStmt);

					n->renameType = OBJECT_ROLE;
					n->subname = $3;
					n->newname = $6;
					n->missing_ok = false;
					$$ = (Node *) n;
				*/ }
			| ALTER USER RoleId RENAME TO RoleId
				{ /*C
					RenameStmt *n = makeNode(RenameStmt);

					n->renameType = OBJECT_ROLE;
					n->subname = $3;
					n->newname = $6;
					n->missing_ok = false;
					$$ = (Node *) n;
				*/ }
			| ALTER TABLESPACE name RENAME TO name
				{ /*C
					RenameStmt *n = makeNode(RenameStmt);

					n->renameType = OBJECT_TABLESPACE;
					n->subname = $3;
					n->newname = $6;
					n->missing_ok = false;
					$$ = (Node *) n;
				*/ }
			| ALTER STATISTICS any_name RENAME TO name
				{ /*C
					RenameStmt *n = makeNode(RenameStmt);

					n->renameType = OBJECT_STATISTIC_EXT;
					n->object = (Node *) $3;
					n->newname = $6;
					n->missing_ok = false;
					$$ = (Node *) n;
				*/ }
			| ALTER TEXT_P SEARCH PARSER any_name RENAME TO name
				{ /*C
					RenameStmt *n = makeNode(RenameStmt);

					n->renameType = OBJECT_TSPARSER;
					n->object = (Node *) $5;
					n->newname = $8;
					n->missing_ok = false;
					$$ = (Node *) n;
				*/ }
			| ALTER TEXT_P SEARCH DICTIONARY any_name RENAME TO name
				{ /*C
					RenameStmt *n = makeNode(RenameStmt);

					n->renameType = OBJECT_TSDICTIONARY;
					n->object = (Node *) $5;
					n->newname = $8;
					n->missing_ok = false;
					$$ = (Node *) n;
				*/ }
			| ALTER TEXT_P SEARCH TEMPLATE any_name RENAME TO name
				{ /*C
					RenameStmt *n = makeNode(RenameStmt);

					n->renameType = OBJECT_TSTEMPLATE;
					n->object = (Node *) $5;
					n->newname = $8;
					n->missing_ok = false;
					$$ = (Node *) n;
				*/ }
			| ALTER TEXT_P SEARCH CONFIGURATION any_name RENAME TO name
				{ /*C
					RenameStmt *n = makeNode(RenameStmt);

					n->renameType = OBJECT_TSCONFIGURATION;
					n->object = (Node *) $5;
					n->newname = $8;
					n->missing_ok = false;
					$$ = (Node *) n;
				*/ }
			| ALTER TYPE_P any_name RENAME TO name
				{ /*C
					RenameStmt *n = makeNode(RenameStmt);

					n->renameType = OBJECT_TYPE;
					n->object = (Node *) $3;
					n->newname = $6;
					n->missing_ok = false;
					$$ = (Node *) n;
				*/ }
			| ALTER TYPE_P any_name RENAME ATTRIBUTE name TO name opt_drop_behavior
				{ /*C
					RenameStmt *n = makeNode(RenameStmt);

					n->renameType = OBJECT_ATTRIBUTE;
					n->relationType = OBJECT_TYPE;
					n->relation = makeRangeVarFromAnyName($3, @3, yyscanner);
					n->subname = $6;
					n->newname = $8;
					n->behavior = $9;
					n->missing_ok = false;
					$$ = (Node *) n;
				*/ }
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
				{ /*C
					AlterObjectDependsStmt *n = makeNode(AlterObjectDependsStmt);

					n->objectType = OBJECT_FUNCTION;
					n->object = (Node *) $3;
					n->extname = makeString($8);
					n->remove = $4;
					$$ = (Node *) n;
				*/ }
			| ALTER PROCEDURE function_with_argtypes opt_no DEPENDS ON EXTENSION name
				{ /*C
					AlterObjectDependsStmt *n = makeNode(AlterObjectDependsStmt);

					n->objectType = OBJECT_PROCEDURE;
					n->object = (Node *) $3;
					n->extname = makeString($8);
					n->remove = $4;
					$$ = (Node *) n;
				*/ }
			| ALTER ROUTINE function_with_argtypes opt_no DEPENDS ON EXTENSION name
				{ /*C
					AlterObjectDependsStmt *n = makeNode(AlterObjectDependsStmt);

					n->objectType = OBJECT_ROUTINE;
					n->object = (Node *) $3;
					n->extname = makeString($8);
					n->remove = $4;
					$$ = (Node *) n;
				*/ }
			| ALTER TRIGGER name ON qualified_name opt_no DEPENDS ON EXTENSION name
				{ /*C
					AlterObjectDependsStmt *n = makeNode(AlterObjectDependsStmt);

					n->objectType = OBJECT_TRIGGER;
					n->relation = $5;
					n->object = (Node *) list_make1(makeString($3));
					n->extname = makeString($10);
					n->remove = $6;
					$$ = (Node *) n;
				*/ }
			| ALTER MATERIALIZED VIEW qualified_name opt_no DEPENDS ON EXTENSION name
				{ /*C
					AlterObjectDependsStmt *n = makeNode(AlterObjectDependsStmt);

					n->objectType = OBJECT_MATVIEW;
					n->relation = $4;
					n->extname = makeString($9);
					n->remove = $5;
					$$ = (Node *) n;
				*/ }
			| ALTER INDEX qualified_name opt_no DEPENDS ON EXTENSION name
				{ /*C
					AlterObjectDependsStmt *n = makeNode(AlterObjectDependsStmt);

					n->objectType = OBJECT_INDEX;
					n->relation = $3;
					n->extname = makeString($8);
					n->remove = $4;
					$$ = (Node *) n;
				*/ }
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
				{ /*C
					AlterObjectSchemaStmt *n = makeNode(AlterObjectSchemaStmt);

					n->objectType = OBJECT_AGGREGATE;
					n->object = (Node *) $3;
					n->newschema = $6;
					n->missing_ok = false;
					$$ = (Node *) n;
				*/ }
			| ALTER COLLATION any_name SET SCHEMA name
				{ /*C
					AlterObjectSchemaStmt *n = makeNode(AlterObjectSchemaStmt);

					n->objectType = OBJECT_COLLATION;
					n->object = (Node *) $3;
					n->newschema = $6;
					n->missing_ok = false;
					$$ = (Node *) n;
				*/ }
			| ALTER CONVERSION_P any_name SET SCHEMA name
				{ /*C
					AlterObjectSchemaStmt *n = makeNode(AlterObjectSchemaStmt);

					n->objectType = OBJECT_CONVERSION;
					n->object = (Node *) $3;
					n->newschema = $6;
					n->missing_ok = false;
					$$ = (Node *) n;
				*/ }
			| ALTER DOMAIN_P any_name SET SCHEMA name
				{ /*C
					AlterObjectSchemaStmt *n = makeNode(AlterObjectSchemaStmt);

					n->objectType = OBJECT_DOMAIN;
					n->object = (Node *) $3;
					n->newschema = $6;
					n->missing_ok = false;
					$$ = (Node *) n;
				*/ }
			| ALTER EXTENSION name SET SCHEMA name
				{ /*C
					AlterObjectSchemaStmt *n = makeNode(AlterObjectSchemaStmt);

					n->objectType = OBJECT_EXTENSION;
					n->object = (Node *) makeString($3);
					n->newschema = $6;
					n->missing_ok = false;
					$$ = (Node *) n;
				*/ }
			| ALTER FUNCTION function_with_argtypes SET SCHEMA name
				{ /*C
					AlterObjectSchemaStmt *n = makeNode(AlterObjectSchemaStmt);

					n->objectType = OBJECT_FUNCTION;
					n->object = (Node *) $3;
					n->newschema = $6;
					n->missing_ok = false;
					$$ = (Node *) n;
				*/ }
			| ALTER OPERATOR operator_with_argtypes SET SCHEMA name
				{ /*C
					AlterObjectSchemaStmt *n = makeNode(AlterObjectSchemaStmt);

					n->objectType = OBJECT_OPERATOR;
					n->object = (Node *) $3;
					n->newschema = $6;
					n->missing_ok = false;
					$$ = (Node *) n;
				*/ }
			| ALTER OPERATOR CLASS any_name USING name SET SCHEMA name
				{ /*C
					AlterObjectSchemaStmt *n = makeNode(AlterObjectSchemaStmt);

					n->objectType = OBJECT_OPCLASS;
					n->object = (Node *) lcons(makeString($6), $4);
					n->newschema = $9;
					n->missing_ok = false;
					$$ = (Node *) n;
				*/ }
			| ALTER OPERATOR FAMILY any_name USING name SET SCHEMA name
				{ /*C
					AlterObjectSchemaStmt *n = makeNode(AlterObjectSchemaStmt);

					n->objectType = OBJECT_OPFAMILY;
					n->object = (Node *) lcons(makeString($6), $4);
					n->newschema = $9;
					n->missing_ok = false;
					$$ = (Node *) n;
				*/ }
			| ALTER PROCEDURE function_with_argtypes SET SCHEMA name
				{ /*C
					AlterObjectSchemaStmt *n = makeNode(AlterObjectSchemaStmt);

					n->objectType = OBJECT_PROCEDURE;
					n->object = (Node *) $3;
					n->newschema = $6;
					n->missing_ok = false;
					$$ = (Node *) n;
				*/ }
			| ALTER ROUTINE function_with_argtypes SET SCHEMA name
				{ /*C
					AlterObjectSchemaStmt *n = makeNode(AlterObjectSchemaStmt);

					n->objectType = OBJECT_ROUTINE;
					n->object = (Node *) $3;
					n->newschema = $6;
					n->missing_ok = false;
					$$ = (Node *) n;
				*/ }
			| ALTER TABLE relation_expr SET SCHEMA name
				{ /*C
					AlterObjectSchemaStmt *n = makeNode(AlterObjectSchemaStmt);

					n->objectType = OBJECT_TABLE;
					n->relation = $3;
					n->newschema = $6;
					n->missing_ok = false;
					$$ = (Node *) n;
				*/ }
			| ALTER TABLE IF_P EXISTS relation_expr SET SCHEMA name
				{ /*C
					AlterObjectSchemaStmt *n = makeNode(AlterObjectSchemaStmt);

					n->objectType = OBJECT_TABLE;
					n->relation = $5;
					n->newschema = $8;
					n->missing_ok = true;
					$$ = (Node *) n;
				*/ }
			| ALTER STATISTICS any_name SET SCHEMA name
				{ /*C
					AlterObjectSchemaStmt *n = makeNode(AlterObjectSchemaStmt);

					n->objectType = OBJECT_STATISTIC_EXT;
					n->object = (Node *) $3;
					n->newschema = $6;
					n->missing_ok = false;
					$$ = (Node *) n;
				*/ }
			| ALTER TEXT_P SEARCH PARSER any_name SET SCHEMA name
				{ /*C
					AlterObjectSchemaStmt *n = makeNode(AlterObjectSchemaStmt);

					n->objectType = OBJECT_TSPARSER;
					n->object = (Node *) $5;
					n->newschema = $8;
					n->missing_ok = false;
					$$ = (Node *) n;
				*/ }
			| ALTER TEXT_P SEARCH DICTIONARY any_name SET SCHEMA name
				{ /*C
					AlterObjectSchemaStmt *n = makeNode(AlterObjectSchemaStmt);

					n->objectType = OBJECT_TSDICTIONARY;
					n->object = (Node *) $5;
					n->newschema = $8;
					n->missing_ok = false;
					$$ = (Node *) n;
				*/ }
			| ALTER TEXT_P SEARCH TEMPLATE any_name SET SCHEMA name
				{ /*C
					AlterObjectSchemaStmt *n = makeNode(AlterObjectSchemaStmt);

					n->objectType = OBJECT_TSTEMPLATE;
					n->object = (Node *) $5;
					n->newschema = $8;
					n->missing_ok = false;
					$$ = (Node *) n;
				*/ }
			| ALTER TEXT_P SEARCH CONFIGURATION any_name SET SCHEMA name
				{ /*C
					AlterObjectSchemaStmt *n = makeNode(AlterObjectSchemaStmt);

					n->objectType = OBJECT_TSCONFIGURATION;
					n->object = (Node *) $5;
					n->newschema = $8;
					n->missing_ok = false;
					$$ = (Node *) n;
				*/ }
			| ALTER SEQUENCE qualified_name SET SCHEMA name
				{ /*C
					AlterObjectSchemaStmt *n = makeNode(AlterObjectSchemaStmt);

					n->objectType = OBJECT_SEQUENCE;
					n->relation = $3;
					n->newschema = $6;
					n->missing_ok = false;
					$$ = (Node *) n;
				*/ }
			| ALTER SEQUENCE IF_P EXISTS qualified_name SET SCHEMA name
				{ /*C
					AlterObjectSchemaStmt *n = makeNode(AlterObjectSchemaStmt);

					n->objectType = OBJECT_SEQUENCE;
					n->relation = $5;
					n->newschema = $8;
					n->missing_ok = true;
					$$ = (Node *) n;
				*/ }
			| ALTER VIEW qualified_name SET SCHEMA name
				{ /*C
					AlterObjectSchemaStmt *n = makeNode(AlterObjectSchemaStmt);

					n->objectType = OBJECT_VIEW;
					n->relation = $3;
					n->newschema = $6;
					n->missing_ok = false;
					$$ = (Node *) n;
				*/ }
			| ALTER VIEW IF_P EXISTS qualified_name SET SCHEMA name
				{ /*C
					AlterObjectSchemaStmt *n = makeNode(AlterObjectSchemaStmt);

					n->objectType = OBJECT_VIEW;
					n->relation = $5;
					n->newschema = $8;
					n->missing_ok = true;
					$$ = (Node *) n;
				*/ }
			| ALTER MATERIALIZED VIEW qualified_name SET SCHEMA name
				{ /*C
					AlterObjectSchemaStmt *n = makeNode(AlterObjectSchemaStmt);

					n->objectType = OBJECT_MATVIEW;
					n->relation = $4;
					n->newschema = $7;
					n->missing_ok = false;
					$$ = (Node *) n;
				*/ }
			| ALTER MATERIALIZED VIEW IF_P EXISTS qualified_name SET SCHEMA name
				{ /*C
					AlterObjectSchemaStmt *n = makeNode(AlterObjectSchemaStmt);

					n->objectType = OBJECT_MATVIEW;
					n->relation = $6;
					n->newschema = $9;
					n->missing_ok = true;
					$$ = (Node *) n;
				*/ }
			| ALTER FOREIGN TABLE relation_expr SET SCHEMA name
				{ /*C
					AlterObjectSchemaStmt *n = makeNode(AlterObjectSchemaStmt);

					n->objectType = OBJECT_FOREIGN_TABLE;
					n->relation = $4;
					n->newschema = $7;
					n->missing_ok = false;
					$$ = (Node *) n;
				*/ }
			| ALTER FOREIGN TABLE IF_P EXISTS relation_expr SET SCHEMA name
				{ /*C
					AlterObjectSchemaStmt *n = makeNode(AlterObjectSchemaStmt);

					n->objectType = OBJECT_FOREIGN_TABLE;
					n->relation = $6;
					n->newschema = $9;
					n->missing_ok = true;
					$$ = (Node *) n;
				*/ }
			| ALTER TYPE_P any_name SET SCHEMA name
				{ /*C
					AlterObjectSchemaStmt *n = makeNode(AlterObjectSchemaStmt);

					n->objectType = OBJECT_TYPE;
					n->object = (Node *) $3;
					n->newschema = $6;
					n->missing_ok = false;
					$$ = (Node *) n;
				*/ }
		;

/*****************************************************************************
 *
 * ALTER OPERATOR name SET define
 *
 *****************************************************************************/

AlterOperatorStmt:
			ALTER OPERATOR operator_with_argtypes SET '(' operator_def_list ')'
				{ /*C
					AlterOperatorStmt *n = makeNode(AlterOperatorStmt);

					n->opername = $3;
					n->options = $6;
					$$ = (Node *) n;
				*/ }
		;

operator_def_list:	operator_def_elem								{ $$ = []Node{$1} }
			| operator_def_list ',' operator_def_elem				{ $$ = append($1, $3) }
		;

operator_def_elem: ColLabel '=' NONE
						{ /*C $$ = makeDefElem($1, NULL, @1); */ }
				   | ColLabel '=' operator_def_arg
						{ /*C $$ = makeDefElem($1, (Node *) $3, @1); */ }
				   | ColLabel
						{ /*C $$ = makeDefElem($1, NULL, @1); */ }
		;

/* must be similar enough to def_arg to avoid reduce/reduce conflicts */
operator_def_arg:
			func_type						{ $$ = $1 }
			| reserved_keyword				{ /*C $$ = (Node *) makeString(pstrdup($1)); */ }
			| qual_all_Op					{ /*C $$ = (Node *) $1; */ }
			| NumericOnly					{ $$ = $1 }
			| Sconst						{ /*C $$ = (Node *) makeString($1); */ }
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
				{ /*C
					AlterTypeStmt *n = makeNode(AlterTypeStmt);

					n->typeName = $3;
					n->options = $6;
					$$ = (Node *) n;
				*/ }
		;

/*****************************************************************************
 *
 * ALTER THING name OWNER TO newname
 *
 *****************************************************************************/

AlterOwnerStmt: ALTER AGGREGATE aggregate_with_argtypes OWNER TO RoleSpec
				{ /*C
					AlterOwnerStmt *n = makeNode(AlterOwnerStmt);

					n->objectType = OBJECT_AGGREGATE;
					n->object = (Node *) $3;
					n->newowner = $6;
					$$ = (Node *) n;
				*/ }
			| ALTER COLLATION any_name OWNER TO RoleSpec
				{ /*C
					AlterOwnerStmt *n = makeNode(AlterOwnerStmt);

					n->objectType = OBJECT_COLLATION;
					n->object = (Node *) $3;
					n->newowner = $6;
					$$ = (Node *) n;
				*/ }
			| ALTER CONVERSION_P any_name OWNER TO RoleSpec
				{ /*C
					AlterOwnerStmt *n = makeNode(AlterOwnerStmt);

					n->objectType = OBJECT_CONVERSION;
					n->object = (Node *) $3;
					n->newowner = $6;
					$$ = (Node *) n;
				*/ }
			| ALTER DATABASE name OWNER TO RoleSpec
				{ /*C
					AlterOwnerStmt *n = makeNode(AlterOwnerStmt);

					n->objectType = OBJECT_DATABASE;
					n->object = (Node *) makeString($3);
					n->newowner = $6;
					$$ = (Node *) n;
				*/ }
			| ALTER DOMAIN_P any_name OWNER TO RoleSpec
				{ /*C
					AlterOwnerStmt *n = makeNode(AlterOwnerStmt);

					n->objectType = OBJECT_DOMAIN;
					n->object = (Node *) $3;
					n->newowner = $6;
					$$ = (Node *) n;
				*/ }
			| ALTER FUNCTION function_with_argtypes OWNER TO RoleSpec
				{ /*C
					AlterOwnerStmt *n = makeNode(AlterOwnerStmt);

					n->objectType = OBJECT_FUNCTION;
					n->object = (Node *) $3;
					n->newowner = $6;
					$$ = (Node *) n;
				*/ }
			| ALTER opt_procedural LANGUAGE name OWNER TO RoleSpec
				{ /*C
					AlterOwnerStmt *n = makeNode(AlterOwnerStmt);

					n->objectType = OBJECT_LANGUAGE;
					n->object = (Node *) makeString($4);
					n->newowner = $7;
					$$ = (Node *) n;
				*/ }
			| ALTER LARGE_P OBJECT_P NumericOnly OWNER TO RoleSpec
				{ /*C
					AlterOwnerStmt *n = makeNode(AlterOwnerStmt);

					n->objectType = OBJECT_LARGEOBJECT;
					n->object = (Node *) $4;
					n->newowner = $7;
					$$ = (Node *) n;
				*/ }
			| ALTER OPERATOR operator_with_argtypes OWNER TO RoleSpec
				{ /*C
					AlterOwnerStmt *n = makeNode(AlterOwnerStmt);

					n->objectType = OBJECT_OPERATOR;
					n->object = (Node *) $3;
					n->newowner = $6;
					$$ = (Node *) n;
				*/ }
			| ALTER OPERATOR CLASS any_name USING name OWNER TO RoleSpec
				{ /*C
					AlterOwnerStmt *n = makeNode(AlterOwnerStmt);

					n->objectType = OBJECT_OPCLASS;
					n->object = (Node *) lcons(makeString($6), $4);
					n->newowner = $9;
					$$ = (Node *) n;
				*/ }
			| ALTER OPERATOR FAMILY any_name USING name OWNER TO RoleSpec
				{ /*C
					AlterOwnerStmt *n = makeNode(AlterOwnerStmt);

					n->objectType = OBJECT_OPFAMILY;
					n->object = (Node *) lcons(makeString($6), $4);
					n->newowner = $9;
					$$ = (Node *) n;
				*/ }
			| ALTER PROCEDURE function_with_argtypes OWNER TO RoleSpec
				{ /*C
					AlterOwnerStmt *n = makeNode(AlterOwnerStmt);

					n->objectType = OBJECT_PROCEDURE;
					n->object = (Node *) $3;
					n->newowner = $6;
					$$ = (Node *) n;
				*/ }
			| ALTER ROUTINE function_with_argtypes OWNER TO RoleSpec
				{ /*C
					AlterOwnerStmt *n = makeNode(AlterOwnerStmt);

					n->objectType = OBJECT_ROUTINE;
					n->object = (Node *) $3;
					n->newowner = $6;
					$$ = (Node *) n;
				*/ }
			| ALTER SCHEMA name OWNER TO RoleSpec
				{ /*C
					AlterOwnerStmt *n = makeNode(AlterOwnerStmt);

					n->objectType = OBJECT_SCHEMA;
					n->object = (Node *) makeString($3);
					n->newowner = $6;
					$$ = (Node *) n;
				*/ }
			| ALTER TYPE_P any_name OWNER TO RoleSpec
				{ /*C
					AlterOwnerStmt *n = makeNode(AlterOwnerStmt);

					n->objectType = OBJECT_TYPE;
					n->object = (Node *) $3;
					n->newowner = $6;
					$$ = (Node *) n;
				*/ }
			| ALTER TABLESPACE name OWNER TO RoleSpec
				{ /*C
					AlterOwnerStmt *n = makeNode(AlterOwnerStmt);

					n->objectType = OBJECT_TABLESPACE;
					n->object = (Node *) makeString($3);
					n->newowner = $6;
					$$ = (Node *) n;
				*/ }
			| ALTER STATISTICS any_name OWNER TO RoleSpec
				{ /*C
					AlterOwnerStmt *n = makeNode(AlterOwnerStmt);

					n->objectType = OBJECT_STATISTIC_EXT;
					n->object = (Node *) $3;
					n->newowner = $6;
					$$ = (Node *) n;
				*/ }
			| ALTER TEXT_P SEARCH DICTIONARY any_name OWNER TO RoleSpec
				{ /*C
					AlterOwnerStmt *n = makeNode(AlterOwnerStmt);

					n->objectType = OBJECT_TSDICTIONARY;
					n->object = (Node *) $5;
					n->newowner = $8;
					$$ = (Node *) n;
				*/ }
			| ALTER TEXT_P SEARCH CONFIGURATION any_name OWNER TO RoleSpec
				{ /*C
					AlterOwnerStmt *n = makeNode(AlterOwnerStmt);

					n->objectType = OBJECT_TSCONFIGURATION;
					n->object = (Node *) $5;
					n->newowner = $8;
					$$ = (Node *) n;
				*/ }
			| ALTER FOREIGN DATA_P WRAPPER name OWNER TO RoleSpec
				{ /*C
					AlterOwnerStmt *n = makeNode(AlterOwnerStmt);

					n->objectType = OBJECT_FDW;
					n->object = (Node *) makeString($5);
					n->newowner = $8;
					$$ = (Node *) n;
				*/ }
			| ALTER SERVER name OWNER TO RoleSpec
				{ /*C
					AlterOwnerStmt *n = makeNode(AlterOwnerStmt);

					n->objectType = OBJECT_FOREIGN_SERVER;
					n->object = (Node *) makeString($3);
					n->newowner = $6;
					$$ = (Node *) n;
				*/ }
			| ALTER EVENT TRIGGER name OWNER TO RoleSpec
				{ /*C
					AlterOwnerStmt *n = makeNode(AlterOwnerStmt);

					n->objectType = OBJECT_EVENT_TRIGGER;
					n->object = (Node *) makeString($4);
					n->newowner = $7;
					$$ = (Node *) n;
				*/ }
			| ALTER PUBLICATION name OWNER TO RoleSpec
				{ /*C
					AlterOwnerStmt *n = makeNode(AlterOwnerStmt);

					n->objectType = OBJECT_PUBLICATION;
					n->object = (Node *) makeString($3);
					n->newowner = $6;
					$$ = (Node *) n;
				*/ }
			| ALTER SUBSCRIPTION name OWNER TO RoleSpec
				{ /*C
					AlterOwnerStmt *n = makeNode(AlterOwnerStmt);

					n->objectType = OBJECT_SUBSCRIPTION;
					n->object = (Node *) makeString($3);
					n->newowner = $6;
					$$ = (Node *) n;
				*/ }
		;

