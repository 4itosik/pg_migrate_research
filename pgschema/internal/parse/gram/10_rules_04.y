/* gram.y lines 5160-7042 */
/*****************************************************************************
 *
 * ALTER EXTENSION name UPDATE [ TO version ]
 *
 *****************************************************************************/

AlterExtensionStmt: ALTER EXTENSION name UPDATE alter_extension_opt_list
				{ /*C
					AlterExtensionStmt *n = makeNode(AlterExtensionStmt);

					n->extname = $3;
					n->options = $5;
					$$ = (Node *) n;
				*/ }
		;

alter_extension_opt_list:
			alter_extension_opt_list alter_extension_opt_item
				{ $$ = append($1, $2) }
			| /* EMPTY */
				{ $$ = nil }
		;

alter_extension_opt_item:
			TO NonReservedWord_or_Sconst
				{ /*C
					$$ = makeDefElem("new_version", (Node *) makeString($2), @1);
				*/ }
		;

/*****************************************************************************
 *
 * ALTER EXTENSION name ADD/DROP object-identifier
 *
 *****************************************************************************/

AlterExtensionContentsStmt:
			ALTER EXTENSION name add_drop object_type_name name
				{ /*C
					AlterExtensionContentsStmt *n = makeNode(AlterExtensionContentsStmt);

					n->extname = $3;
					n->action = $4;
					n->objtype = $5;
					n->object = (Node *) makeString($6);
					$$ = (Node *) n;
				*/ }
			| ALTER EXTENSION name add_drop object_type_any_name any_name
				{ /*C
					AlterExtensionContentsStmt *n = makeNode(AlterExtensionContentsStmt);

					n->extname = $3;
					n->action = $4;
					n->objtype = $5;
					n->object = (Node *) $6;
					$$ = (Node *) n;
				*/ }
			| ALTER EXTENSION name add_drop AGGREGATE aggregate_with_argtypes
				{ /*C
					AlterExtensionContentsStmt *n = makeNode(AlterExtensionContentsStmt);

					n->extname = $3;
					n->action = $4;
					n->objtype = OBJECT_AGGREGATE;
					n->object = (Node *) $6;
					$$ = (Node *) n;
				*/ }
			| ALTER EXTENSION name add_drop CAST '(' Typename AS Typename ')'
				{ /*C
					AlterExtensionContentsStmt *n = makeNode(AlterExtensionContentsStmt);

					n->extname = $3;
					n->action = $4;
					n->objtype = OBJECT_CAST;
					n->object = (Node *) list_make2($7, $9);
					$$ = (Node *) n;
				*/ }
			| ALTER EXTENSION name add_drop DOMAIN_P Typename
				{ /*C
					AlterExtensionContentsStmt *n = makeNode(AlterExtensionContentsStmt);

					n->extname = $3;
					n->action = $4;
					n->objtype = OBJECT_DOMAIN;
					n->object = (Node *) $6;
					$$ = (Node *) n;
				*/ }
			| ALTER EXTENSION name add_drop FUNCTION function_with_argtypes
				{ /*C
					AlterExtensionContentsStmt *n = makeNode(AlterExtensionContentsStmt);

					n->extname = $3;
					n->action = $4;
					n->objtype = OBJECT_FUNCTION;
					n->object = (Node *) $6;
					$$ = (Node *) n;
				*/ }
			| ALTER EXTENSION name add_drop OPERATOR operator_with_argtypes
				{ /*C
					AlterExtensionContentsStmt *n = makeNode(AlterExtensionContentsStmt);

					n->extname = $3;
					n->action = $4;
					n->objtype = OBJECT_OPERATOR;
					n->object = (Node *) $6;
					$$ = (Node *) n;
				*/ }
			| ALTER EXTENSION name add_drop OPERATOR CLASS any_name USING name
				{ /*C
					AlterExtensionContentsStmt *n = makeNode(AlterExtensionContentsStmt);

					n->extname = $3;
					n->action = $4;
					n->objtype = OBJECT_OPCLASS;
					n->object = (Node *) lcons(makeString($9), $7);
					$$ = (Node *) n;
				*/ }
			| ALTER EXTENSION name add_drop OPERATOR FAMILY any_name USING name
				{ /*C
					AlterExtensionContentsStmt *n = makeNode(AlterExtensionContentsStmt);

					n->extname = $3;
					n->action = $4;
					n->objtype = OBJECT_OPFAMILY;
					n->object = (Node *) lcons(makeString($9), $7);
					$$ = (Node *) n;
				*/ }
			| ALTER EXTENSION name add_drop PROCEDURE function_with_argtypes
				{ /*C
					AlterExtensionContentsStmt *n = makeNode(AlterExtensionContentsStmt);

					n->extname = $3;
					n->action = $4;
					n->objtype = OBJECT_PROCEDURE;
					n->object = (Node *) $6;
					$$ = (Node *) n;
				*/ }
			| ALTER EXTENSION name add_drop ROUTINE function_with_argtypes
				{ /*C
					AlterExtensionContentsStmt *n = makeNode(AlterExtensionContentsStmt);

					n->extname = $3;
					n->action = $4;
					n->objtype = OBJECT_ROUTINE;
					n->object = (Node *) $6;
					$$ = (Node *) n;
				*/ }
			| ALTER EXTENSION name add_drop TRANSFORM FOR Typename LANGUAGE name
				{ /*C
					AlterExtensionContentsStmt *n = makeNode(AlterExtensionContentsStmt);

					n->extname = $3;
					n->action = $4;
					n->objtype = OBJECT_TRANSFORM;
					n->object = (Node *) list_make2($7, makeString($9));
					$$ = (Node *) n;
				*/ }
			| ALTER EXTENSION name add_drop TYPE_P Typename
				{ /*C
					AlterExtensionContentsStmt *n = makeNode(AlterExtensionContentsStmt);

					n->extname = $3;
					n->action = $4;
					n->objtype = OBJECT_TYPE;
					n->object = (Node *) $6;
					$$ = (Node *) n;
				*/ }
		;

/*****************************************************************************
 *
 *		QUERY:
 *             CREATE FOREIGN DATA WRAPPER name options
 *
 *****************************************************************************/

CreateFdwStmt: CREATE FOREIGN DATA_P WRAPPER name opt_fdw_options create_generic_options
				{ /*C
					CreateFdwStmt *n = makeNode(CreateFdwStmt);

					n->fdwname = $5;
					n->func_options = $6;
					n->options = $7;
					$$ = (Node *) n;
				*/ }
		;

fdw_option:
			HANDLER handler_name				{ /*C $$ = makeDefElem("handler", (Node *) $2, @1); */ }
			| NO HANDLER						{ /*C $$ = makeDefElem("handler", NULL, @1); */ }
			| VALIDATOR handler_name			{ /*C $$ = makeDefElem("validator", (Node *) $2, @1); */ }
			| NO VALIDATOR						{ /*C $$ = makeDefElem("validator", NULL, @1); */ }
		;

fdw_options:
			fdw_option							{ $$ = []Node{$1} }
			| fdw_options fdw_option			{ $$ = append($1, $2) }
		;

opt_fdw_options:
			fdw_options							{ $$ = $1 }
			| /*EMPTY*/							{ $$ = nil }
		;

/*****************************************************************************
 *
 *		QUERY :
 *				ALTER FOREIGN DATA WRAPPER name options
 *
 ****************************************************************************/

AlterFdwStmt: ALTER FOREIGN DATA_P WRAPPER name opt_fdw_options alter_generic_options
				{ /*C
					AlterFdwStmt *n = makeNode(AlterFdwStmt);

					n->fdwname = $5;
					n->func_options = $6;
					n->options = $7;
					$$ = (Node *) n;
				*/ }
			| ALTER FOREIGN DATA_P WRAPPER name fdw_options
				{ /*C
					AlterFdwStmt *n = makeNode(AlterFdwStmt);

					n->fdwname = $5;
					n->func_options = $6;
					n->options = NIL;
					$$ = (Node *) n;
				*/ }
		;

/* Options definition for CREATE FDW, SERVER and USER MAPPING */
create_generic_options:
			OPTIONS '(' generic_option_list ')'			{ $$ = $3 }
			| /*EMPTY*/									{ $$ = nil }
		;

generic_option_list:
			generic_option_elem
				{ $$ = []Node{$1} }
			| generic_option_list ',' generic_option_elem
				{ $$ = append($1, $3) }
		;

/* Options definition for ALTER FDW, SERVER and USER MAPPING */
alter_generic_options:
			OPTIONS	'(' alter_generic_option_list ')'		{ $$ = $3 }
		;

alter_generic_option_list:
			alter_generic_option_elem
				{ $$ = []Node{$1} }
			| alter_generic_option_list ',' alter_generic_option_elem
				{ $$ = append($1, $3) }
		;

alter_generic_option_elem:
			generic_option_elem
				{ $$ = $1 }
			| SET generic_option_elem
				{ /*C
					$$ = $2;
					$$->defaction = DEFELEM_SET;
				*/ }
			| ADD_P generic_option_elem
				{ /*C
					$$ = $2;
					$$->defaction = DEFELEM_ADD;
				*/ }
			| DROP generic_option_name
				{ /*C
					$$ = makeDefElemExtended(NULL, $2, NULL, DEFELEM_DROP, @2);
				*/ }
		;

generic_option_elem:
			generic_option_name generic_option_arg
				{ /*C
					$$ = makeDefElem($1, $2, @1);
				*/ }
		;

generic_option_name:
				ColLabel			{ $$ = $1 }
		;

/* We could use def_arg here, but the spec only requires string literals */
generic_option_arg:
				Sconst				{ /*C $$ = (Node *) makeString($1); */ }
		;

/*****************************************************************************
 *
 *		QUERY:
 *             CREATE SERVER name [TYPE] [VERSION] [OPTIONS]
 *
 *****************************************************************************/

CreateForeignServerStmt: CREATE SERVER name opt_type opt_foreign_server_version
						 FOREIGN DATA_P WRAPPER name create_generic_options
				{ /*C
					CreateForeignServerStmt *n = makeNode(CreateForeignServerStmt);

					n->servername = $3;
					n->servertype = $4;
					n->version = $5;
					n->fdwname = $9;
					n->options = $10;
					n->if_not_exists = false;
					$$ = (Node *) n;
				*/ }
				| CREATE SERVER IF_P NOT EXISTS name opt_type opt_foreign_server_version
						 FOREIGN DATA_P WRAPPER name create_generic_options
				{ /*C
					CreateForeignServerStmt *n = makeNode(CreateForeignServerStmt);

					n->servername = $6;
					n->servertype = $7;
					n->version = $8;
					n->fdwname = $12;
					n->options = $13;
					n->if_not_exists = true;
					$$ = (Node *) n;
				*/ }
		;

opt_type:
			TYPE_P Sconst			{ $$ = $2 }
			| /*EMPTY*/				{ $$ = "" }
		;


foreign_server_version:
			VERSION_P Sconst		{ $$ = $2 }
		|	VERSION_P NULL_P		{ $$ = "" }
		;

opt_foreign_server_version:
			foreign_server_version	{ $$ = $1 }
			| /*EMPTY*/				{ $$ = "" }
		;

/*****************************************************************************
 *
 *		QUERY :
 *				ALTER SERVER name [VERSION] [OPTIONS]
 *
 ****************************************************************************/

AlterForeignServerStmt: ALTER SERVER name foreign_server_version alter_generic_options
				{ /*C
					AlterForeignServerStmt *n = makeNode(AlterForeignServerStmt);

					n->servername = $3;
					n->version = $4;
					n->options = $5;
					n->has_version = true;
					$$ = (Node *) n;
				*/ }
			| ALTER SERVER name foreign_server_version
				{ /*C
					AlterForeignServerStmt *n = makeNode(AlterForeignServerStmt);

					n->servername = $3;
					n->version = $4;
					n->has_version = true;
					$$ = (Node *) n;
				*/ }
			| ALTER SERVER name alter_generic_options
				{ /*C
					AlterForeignServerStmt *n = makeNode(AlterForeignServerStmt);

					n->servername = $3;
					n->options = $4;
					$$ = (Node *) n;
				*/ }
		;

/*****************************************************************************
 *
 *		QUERY:
 *             CREATE FOREIGN TABLE relname (...) SERVER name (...)
 *
 *****************************************************************************/

CreateForeignTableStmt:
		CREATE FOREIGN TABLE qualified_name
			'(' OptTableElementList ')'
			OptInherit SERVER name create_generic_options
				{ /*C
					CreateForeignTableStmt *n = makeNode(CreateForeignTableStmt);

					$4->relpersistence = RELPERSISTENCE_PERMANENT;
					n->base.relation = $4;
					n->base.tableElts = $6;
					n->base.inhRelations = $8;
					n->base.ofTypename = NULL;
					n->base.constraints = NIL;
					n->base.options = NIL;
					n->base.oncommit = ONCOMMIT_NOOP;
					n->base.tablespacename = NULL;
					n->base.if_not_exists = false;
					/* FDW-specific data * /
					n->servername = $10;
					n->options = $11;
					$$ = (Node *) n;
				*/ }
		| CREATE FOREIGN TABLE IF_P NOT EXISTS qualified_name
			'(' OptTableElementList ')'
			OptInherit SERVER name create_generic_options
				{ /*C
					CreateForeignTableStmt *n = makeNode(CreateForeignTableStmt);

					$7->relpersistence = RELPERSISTENCE_PERMANENT;
					n->base.relation = $7;
					n->base.tableElts = $9;
					n->base.inhRelations = $11;
					n->base.ofTypename = NULL;
					n->base.constraints = NIL;
					n->base.options = NIL;
					n->base.oncommit = ONCOMMIT_NOOP;
					n->base.tablespacename = NULL;
					n->base.if_not_exists = true;
					/* FDW-specific data * /
					n->servername = $13;
					n->options = $14;
					$$ = (Node *) n;
				*/ }
		| CREATE FOREIGN TABLE qualified_name
			PARTITION OF qualified_name OptTypedTableElementList PartitionBoundSpec
			SERVER name create_generic_options
				{ /*C
					CreateForeignTableStmt *n = makeNode(CreateForeignTableStmt);

					$4->relpersistence = RELPERSISTENCE_PERMANENT;
					n->base.relation = $4;
					n->base.inhRelations = list_make1($7);
					n->base.tableElts = $8;
					n->base.partbound = $9;
					n->base.ofTypename = NULL;
					n->base.constraints = NIL;
					n->base.options = NIL;
					n->base.oncommit = ONCOMMIT_NOOP;
					n->base.tablespacename = NULL;
					n->base.if_not_exists = false;
					/* FDW-specific data * /
					n->servername = $11;
					n->options = $12;
					$$ = (Node *) n;
				*/ }
		| CREATE FOREIGN TABLE IF_P NOT EXISTS qualified_name
			PARTITION OF qualified_name OptTypedTableElementList PartitionBoundSpec
			SERVER name create_generic_options
				{ /*C
					CreateForeignTableStmt *n = makeNode(CreateForeignTableStmt);

					$7->relpersistence = RELPERSISTENCE_PERMANENT;
					n->base.relation = $7;
					n->base.inhRelations = list_make1($10);
					n->base.tableElts = $11;
					n->base.partbound = $12;
					n->base.ofTypename = NULL;
					n->base.constraints = NIL;
					n->base.options = NIL;
					n->base.oncommit = ONCOMMIT_NOOP;
					n->base.tablespacename = NULL;
					n->base.if_not_exists = true;
					/* FDW-specific data * /
					n->servername = $14;
					n->options = $15;
					$$ = (Node *) n;
				*/ }
		;

/*****************************************************************************
 *
 *		QUERY:
 *				IMPORT FOREIGN SCHEMA remote_schema
 *				[ { LIMIT TO | EXCEPT } ( table_list ) ]
 *				FROM SERVER server_name INTO local_schema [ OPTIONS (...) ]
 *
 ****************************************************************************/

ImportForeignSchemaStmt:
		IMPORT_P FOREIGN SCHEMA name import_qualification
		  FROM SERVER name INTO name create_generic_options
			{ /*C
				ImportForeignSchemaStmt *n = makeNode(ImportForeignSchemaStmt);

				n->server_name = $8;
				n->remote_schema = $4;
				n->local_schema = $10;
				n->list_type = $5->type;
				n->table_list = $5->table_names;
				n->options = $11;
				$$ = (Node *) n;
			*/ }
		;

import_qualification_type:
		LIMIT TO				{ /*C $$ = FDW_IMPORT_SCHEMA_LIMIT_TO; */ }
		| EXCEPT				{ /*C $$ = FDW_IMPORT_SCHEMA_EXCEPT; */ }
		;

import_qualification:
		import_qualification_type '(' relation_expr_list ')'
			{ /*C
				ImportQual *n = (ImportQual *) palloc(sizeof(ImportQual));

				n->type = $1;
				n->table_names = $3;
				$$ = n;
			*/ }
		| /*EMPTY*/
			{ /*C
				ImportQual *n = (ImportQual *) palloc(sizeof(ImportQual));
				n->type = FDW_IMPORT_SCHEMA_ALL;
				n->table_names = NIL;
				$$ = n;
			*/ }
		;

/*****************************************************************************
 *
 *		QUERY:
 *             CREATE USER MAPPING FOR auth_ident SERVER name [OPTIONS]
 *
 *****************************************************************************/

CreateUserMappingStmt: CREATE USER MAPPING FOR auth_ident SERVER name create_generic_options
				{ /*C
					CreateUserMappingStmt *n = makeNode(CreateUserMappingStmt);

					n->user = $5;
					n->servername = $7;
					n->options = $8;
					n->if_not_exists = false;
					$$ = (Node *) n;
				*/ }
				| CREATE USER MAPPING IF_P NOT EXISTS FOR auth_ident SERVER name create_generic_options
				{ /*C
					CreateUserMappingStmt *n = makeNode(CreateUserMappingStmt);

					n->user = $8;
					n->servername = $10;
					n->options = $11;
					n->if_not_exists = true;
					$$ = (Node *) n;
				*/ }
		;

/* User mapping authorization identifier */
auth_ident: RoleSpec			{ $$ = $1 }
			| USER				{ /*C $$ = makeRoleSpec(ROLESPEC_CURRENT_USER, @1); */ }
		;

/*****************************************************************************
 *
 *		QUERY :
 *				DROP USER MAPPING FOR auth_ident SERVER name
 *
 * XXX you'd think this should have a CASCADE/RESTRICT option, even if it's
 * only pro forma; but the SQL standard doesn't show one.
 ****************************************************************************/

DropUserMappingStmt: DROP USER MAPPING FOR auth_ident SERVER name
				{ /*C
					DropUserMappingStmt *n = makeNode(DropUserMappingStmt);

					n->user = $5;
					n->servername = $7;
					n->missing_ok = false;
					$$ = (Node *) n;
				*/ }
				|  DROP USER MAPPING IF_P EXISTS FOR auth_ident SERVER name
				{ /*C
					DropUserMappingStmt *n = makeNode(DropUserMappingStmt);

					n->user = $7;
					n->servername = $9;
					n->missing_ok = true;
					$$ = (Node *) n;
				*/ }
		;

/*****************************************************************************
 *
 *		QUERY :
 *				ALTER USER MAPPING FOR auth_ident SERVER name OPTIONS
 *
 ****************************************************************************/

AlterUserMappingStmt: ALTER USER MAPPING FOR auth_ident SERVER name alter_generic_options
				{ /*C
					AlterUserMappingStmt *n = makeNode(AlterUserMappingStmt);

					n->user = $5;
					n->servername = $7;
					n->options = $8;
					$$ = (Node *) n;
				*/ }
		;

/*****************************************************************************
 *
 *		QUERIES:
 *				CREATE POLICY name ON table
 *					[AS { PERMISSIVE | RESTRICTIVE } ]
 *					[FOR { SELECT | INSERT | UPDATE | DELETE } ]
 *					[TO role, ...]
 *					[USING (qual)] [WITH CHECK (with check qual)]
 *				ALTER POLICY name ON table [TO role, ...]
 *					[USING (qual)] [WITH CHECK (with check qual)]
 *
 *****************************************************************************/

CreatePolicyStmt:
			CREATE POLICY name ON qualified_name RowSecurityDefaultPermissive
				RowSecurityDefaultForCmd RowSecurityDefaultToRole
				RowSecurityOptionalExpr RowSecurityOptionalWithCheck
				{ /*C
					CreatePolicyStmt *n = makeNode(CreatePolicyStmt);

					n->policy_name = $3;
					n->table = $5;
					n->permissive = $6;
					n->cmd_name = $7;
					n->roles = $8;
					n->qual = $9;
					n->with_check = $10;
					$$ = (Node *) n;
				*/ }
		;

AlterPolicyStmt:
			ALTER POLICY name ON qualified_name RowSecurityOptionalToRole
				RowSecurityOptionalExpr RowSecurityOptionalWithCheck
				{ /*C
					AlterPolicyStmt *n = makeNode(AlterPolicyStmt);

					n->policy_name = $3;
					n->table = $5;
					n->roles = $6;
					n->qual = $7;
					n->with_check = $8;
					$$ = (Node *) n;
				*/ }
		;

RowSecurityOptionalExpr:
			USING '(' a_expr ')'	{ $$ = $3 }
			| /* EMPTY */			{ $$ = nil }
		;

RowSecurityOptionalWithCheck:
			WITH CHECK '(' a_expr ')'		{ $$ = $4 }
			| /* EMPTY */					{ $$ = nil }
		;

RowSecurityDefaultToRole:
			TO role_list			{ $$ = $2 }
			| /* EMPTY */			{ /*C $$ = list_make1(makeRoleSpec(ROLESPEC_PUBLIC, -1)); */ }
		;

RowSecurityOptionalToRole:
			TO role_list			{ $$ = $2 }
			| /* EMPTY */			{ $$ = nil }
		;

RowSecurityDefaultPermissive:
			AS IDENT
				{ /*C
					if (strcmp($2, "permissive") == 0)
						$$ = true;
					else if (strcmp($2, "restrictive") == 0)
						$$ = false;
					else
						ereport(ERROR,
								(errcode(ERRCODE_SYNTAX_ERROR),
								 errmsg("unrecognized row security option \"%s\"", $2),
								 errhint("Only PERMISSIVE or RESTRICTIVE policies are supported currently."),
								 parser_errposition(@2)));

				*/ }
			| /* EMPTY */			{ $$ = true }
		;

RowSecurityDefaultForCmd:
			FOR row_security_cmd	{ $$ = $2 }
			| /* EMPTY */			{ $$ = "all" }
		;

row_security_cmd:
			ALL				{ $$ = "all" }
		|	SELECT			{ $$ = "select" }
		|	INSERT			{ $$ = "insert" }
		|	UPDATE			{ $$ = "update" }
		|	DELETE_P		{ $$ = "delete" }
		;

/*****************************************************************************
 *
 *		QUERY:
 *             CREATE ACCESS METHOD name HANDLER handler_name
 *
 *****************************************************************************/

CreateAmStmt: CREATE ACCESS METHOD name TYPE_P am_type HANDLER handler_name
				{ /*C
					CreateAmStmt *n = makeNode(CreateAmStmt);

					n->amname = $4;
					n->handler_name = $8;
					n->amtype = $6;
					$$ = (Node *) n;
				*/ }
		;

am_type:
			INDEX			{ /*C $$ = AMTYPE_INDEX; */ }
		|	TABLE			{ /*C $$ = AMTYPE_TABLE; */ }
		;

/*****************************************************************************
 *
 *		QUERIES :
 *				CREATE TRIGGER ...
 *
 *****************************************************************************/

CreateTrigStmt:
			CREATE opt_or_replace TRIGGER name TriggerActionTime TriggerEvents ON
			qualified_name TriggerReferencing TriggerForSpec TriggerWhen
			EXECUTE FUNCTION_or_PROCEDURE func_name '(' TriggerFuncArgs ')'
				{ /*C
					CreateTrigStmt *n = makeNode(CreateTrigStmt);

					n->replace = $2;
					n->isconstraint = false;
					n->trigname = $4;
					n->relation = $8;
					n->funcname = $14;
					n->args = $16;
					n->row = $10;
					n->timing = $5;
					n->events = intVal(linitial($6));
					n->columns = (List *) lsecond($6);
					n->whenClause = $11;
					n->transitionRels = $9;
					n->deferrable = false;
					n->initdeferred = false;
					n->constrrel = NULL;
					$$ = (Node *) n;
				*/ }
		  | CREATE opt_or_replace CONSTRAINT TRIGGER name AFTER TriggerEvents ON
			qualified_name OptConstrFromTable ConstraintAttributeSpec
			FOR EACH ROW TriggerWhen
			EXECUTE FUNCTION_or_PROCEDURE func_name '(' TriggerFuncArgs ')'
				{ /*C
					CreateTrigStmt *n = makeNode(CreateTrigStmt);

					n->replace = $2;
					if (n->replace) /* not supported, see CreateTrigger * /
						ereport(ERROR,
								(errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
								 errmsg("CREATE OR REPLACE CONSTRAINT TRIGGER is not supported")));
					n->isconstraint = true;
					n->trigname = $5;
					n->relation = $9;
					n->funcname = $18;
					n->args = $20;
					n->row = true;
					n->timing = TRIGGER_TYPE_AFTER;
					n->events = intVal(linitial($7));
					n->columns = (List *) lsecond($7);
					n->whenClause = $15;
					n->transitionRels = NIL;
					processCASbits($11, @11, "TRIGGER",
								   &n->deferrable, &n->initdeferred, NULL,
								   NULL, yyscanner);
					n->constrrel = $10;
					$$ = (Node *) n;
				*/ }
		;

TriggerActionTime:
			BEFORE								{ /*C $$ = TRIGGER_TYPE_BEFORE; */ }
			| AFTER								{ /*C $$ = TRIGGER_TYPE_AFTER; */ }
			| INSTEAD OF						{ /*C $$ = TRIGGER_TYPE_INSTEAD; */ }
		;

TriggerEvents:
			TriggerOneEvent
				{ $$ = $1 }
			| TriggerEvents OR TriggerOneEvent
				{ /*C
					int			events1 = intVal(linitial($1));
					int			events2 = intVal(linitial($3));
					List	   *columns1 = (List *) lsecond($1);
					List	   *columns2 = (List *) lsecond($3);

					if (events1 & events2)
						parser_yyerror("duplicate trigger events specified");
					/*
					 * concat'ing the columns lists loses information about
					 * which columns went with which event, but so long as
					 * only UPDATE carries columns and we disallow multiple
					 * UPDATE items, it doesn't matter.  Command execution
					 * should just ignore the columns for non-UPDATE events.
					 * /
					$$ = list_make2(makeInteger(events1 | events2),
									list_concat(columns1, columns2));
				*/ }
		;

TriggerOneEvent:
			INSERT
				{ /*C $$ = list_make2(makeInteger(TRIGGER_TYPE_INSERT), NIL); */ }
			| DELETE_P
				{ /*C $$ = list_make2(makeInteger(TRIGGER_TYPE_DELETE), NIL); */ }
			| UPDATE
				{ /*C $$ = list_make2(makeInteger(TRIGGER_TYPE_UPDATE), NIL); */ }
			| UPDATE OF columnList
				{ /*C $$ = list_make2(makeInteger(TRIGGER_TYPE_UPDATE), $3); */ }
			| TRUNCATE
				{ /*C $$ = list_make2(makeInteger(TRIGGER_TYPE_TRUNCATE), NIL); */ }
		;

TriggerReferencing:
			REFERENCING TriggerTransitions			{ $$ = $2 }
			| /*EMPTY*/								{ $$ = nil }
		;

TriggerTransitions:
			TriggerTransition						{ $$ = []Node{$1} }
			| TriggerTransitions TriggerTransition	{ $$ = append($1, $2) }
		;

TriggerTransition:
			TransitionOldOrNew TransitionRowOrTable opt_as TransitionRelName
				{ /*C
					TriggerTransition *n = makeNode(TriggerTransition);

					n->name = $4;
					n->isNew = $1;
					n->isTable = $2;
					$$ = (Node *) n;
				*/ }
		;

TransitionOldOrNew:
			NEW										{ $$ = true }
			| OLD									{ $$ = false }
		;

TransitionRowOrTable:
			TABLE									{ $$ = true }
			/*
			 * According to the standard, lack of a keyword here implies ROW.
			 * Support for that would require prohibiting ROW entirely here,
			 * reserving the keyword ROW, and/or requiring AS (instead of
			 * allowing it to be optional, as the standard specifies) as the
			 * next token.  Requiring ROW seems cleanest and easiest to
			 * explain.
			 */
			| ROW									{ $$ = false }
		;

TransitionRelName:
			ColId									{ $$ = $1 }
		;

TriggerForSpec:
			FOR TriggerForOptEach TriggerForType
				{ $$ = $3 }
			| /* EMPTY */
				{ /*C
					/*
					 * If ROW/STATEMENT not specified, default to
					 * STATEMENT, per SQL
					 * /
					$$ = false;
				*/ }
		;

TriggerForOptEach:
			EACH
			| /*EMPTY*/
		;

TriggerForType:
			ROW										{ $$ = true }
			| STATEMENT								{ $$ = false }
		;

TriggerWhen:
			WHEN '(' a_expr ')'						{ $$ = $3 }
			| /*EMPTY*/								{ $$ = nil }
		;

FUNCTION_or_PROCEDURE:
			FUNCTION
		|	PROCEDURE
		;

TriggerFuncArgs:
			TriggerFuncArg							{ $$ = []Node{$1} }
			| TriggerFuncArgs ',' TriggerFuncArg	{ $$ = append($1, $3) }
			| /*EMPTY*/								{ $$ = nil }
		;

TriggerFuncArg:
			Iconst
				{ /*C
					$$ = (Node *) makeString(psprintf("%d", $1));
				*/ }
			| FCONST								{ /*C $$ = (Node *) makeString($1); */ }
			| Sconst								{ /*C $$ = (Node *) makeString($1); */ }
			| ColLabel								{ /*C $$ = (Node *) makeString($1); */ }
		;

OptConstrFromTable:
			FROM qualified_name						{ $$ = $2 }
			| /*EMPTY*/								{ $$ = nil }
		;

ConstraintAttributeSpec:
			/*EMPTY*/
				{ $$ = 0 }
			| ConstraintAttributeSpec ConstraintAttributeElem
				{ /*C
					/*
					 * We must complain about conflicting options.
					 * We could, but choose not to, complain about redundant
					 * options (ie, where $2's bit is already set in $1).
					 * /
					int		newspec = $1 | $2;

					/* special message for this case * /
					if ((newspec & (CAS_NOT_DEFERRABLE | CAS_INITIALLY_DEFERRED)) == (CAS_NOT_DEFERRABLE | CAS_INITIALLY_DEFERRED))
						ereport(ERROR,
								(errcode(ERRCODE_SYNTAX_ERROR),
								 errmsg("constraint declared INITIALLY DEFERRED must be DEFERRABLE"),
								 parser_errposition(@2)));
					/* generic message for other conflicts * /
					if ((newspec & (CAS_NOT_DEFERRABLE | CAS_DEFERRABLE)) == (CAS_NOT_DEFERRABLE | CAS_DEFERRABLE) ||
						(newspec & (CAS_INITIALLY_IMMEDIATE | CAS_INITIALLY_DEFERRED)) == (CAS_INITIALLY_IMMEDIATE | CAS_INITIALLY_DEFERRED))
						ereport(ERROR,
								(errcode(ERRCODE_SYNTAX_ERROR),
								 errmsg("conflicting constraint properties"),
								 parser_errposition(@2)));
					$$ = newspec;
				*/ }
		;

ConstraintAttributeElem:
			NOT DEFERRABLE					{ /*C $$ = CAS_NOT_DEFERRABLE; */ }
			| DEFERRABLE					{ /*C $$ = CAS_DEFERRABLE; */ }
			| INITIALLY IMMEDIATE			{ /*C $$ = CAS_INITIALLY_IMMEDIATE; */ }
			| INITIALLY DEFERRED			{ /*C $$ = CAS_INITIALLY_DEFERRED; */ }
			| NOT VALID						{ /*C $$ = CAS_NOT_VALID; */ }
			| NO INHERIT					{ /*C $$ = CAS_NO_INHERIT; */ }
		;


/*****************************************************************************
 *
 *		QUERIES :
 *				CREATE EVENT TRIGGER ...
 *				ALTER EVENT TRIGGER ...
 *
 *****************************************************************************/

CreateEventTrigStmt:
			CREATE EVENT TRIGGER name ON ColLabel
			EXECUTE FUNCTION_or_PROCEDURE func_name '(' ')'
				{ /*C
					CreateEventTrigStmt *n = makeNode(CreateEventTrigStmt);

					n->trigname = $4;
					n->eventname = $6;
					n->whenclause = NULL;
					n->funcname = $9;
					$$ = (Node *) n;
				*/ }
		  | CREATE EVENT TRIGGER name ON ColLabel
			WHEN event_trigger_when_list
			EXECUTE FUNCTION_or_PROCEDURE func_name '(' ')'
				{ /*C
					CreateEventTrigStmt *n = makeNode(CreateEventTrigStmt);

					n->trigname = $4;
					n->eventname = $6;
					n->whenclause = $8;
					n->funcname = $11;
					$$ = (Node *) n;
				*/ }
		;

event_trigger_when_list:
		  event_trigger_when_item
			{ $$ = []Node{$1} }
		| event_trigger_when_list AND event_trigger_when_item
			{ $$ = append($1, $3) }
		;

event_trigger_when_item:
		ColId IN_P '(' event_trigger_value_list ')'
			{ /*C $$ = makeDefElem($1, (Node *) $4, @1); */ }
		;

event_trigger_value_list:
		  SCONST
			{ /*C $$ = list_make1(makeString($1)); */ }
		| event_trigger_value_list ',' SCONST
			{ /*C $$ = lappend($1, makeString($3)); */ }
		;

AlterEventTrigStmt:
			ALTER EVENT TRIGGER name enable_trigger
				{ /*C
					AlterEventTrigStmt *n = makeNode(AlterEventTrigStmt);

					n->trigname = $4;
					n->tgenabled = $5;
					$$ = (Node *) n;
				*/ }
		;

enable_trigger:
			ENABLE_P					{ /*C $$ = TRIGGER_FIRES_ON_ORIGIN; */ }
			| ENABLE_P REPLICA			{ /*C $$ = TRIGGER_FIRES_ON_REPLICA; */ }
			| ENABLE_P ALWAYS			{ /*C $$ = TRIGGER_FIRES_ALWAYS; */ }
			| DISABLE_P					{ /*C $$ = TRIGGER_DISABLED; */ }
		;

/*****************************************************************************
 *
 *		QUERY :
 *				CREATE ASSERTION ...
 *
 *****************************************************************************/

CreateAssertionStmt:
			CREATE ASSERTION any_name CHECK '(' a_expr ')' ConstraintAttributeSpec
				{ /*C
					ereport(ERROR,
							(errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
							 errmsg("CREATE ASSERTION is not yet implemented")));

					$$ = NULL;
				*/ }
		;


/*****************************************************************************
 *
 *		QUERY :
 *				define (aggregate,operator,type)
 *
 *****************************************************************************/

DefineStmt:
			CREATE opt_or_replace AGGREGATE func_name aggr_args definition
				{ /*C
					DefineStmt *n = makeNode(DefineStmt);

					n->kind = OBJECT_AGGREGATE;
					n->oldstyle = false;
					n->replace = $2;
					n->defnames = $4;
					n->args = $5;
					n->definition = $6;
					$$ = (Node *) n;
				*/ }
			| CREATE opt_or_replace AGGREGATE func_name old_aggr_definition
				{ /*C
					/* old-style (pre-8.2) syntax for CREATE AGGREGATE * /
					DefineStmt *n = makeNode(DefineStmt);

					n->kind = OBJECT_AGGREGATE;
					n->oldstyle = true;
					n->replace = $2;
					n->defnames = $4;
					n->args = NIL;
					n->definition = $5;
					$$ = (Node *) n;
				*/ }
			| CREATE OPERATOR any_operator definition
				{ /*C
					DefineStmt *n = makeNode(DefineStmt);

					n->kind = OBJECT_OPERATOR;
					n->oldstyle = false;
					n->defnames = $3;
					n->args = NIL;
					n->definition = $4;
					$$ = (Node *) n;
				*/ }
			| CREATE TYPE_P any_name definition
				{ /*C
					DefineStmt *n = makeNode(DefineStmt);

					n->kind = OBJECT_TYPE;
					n->oldstyle = false;
					n->defnames = $3;
					n->args = NIL;
					n->definition = $4;
					$$ = (Node *) n;
				*/ }
			| CREATE TYPE_P any_name
				{ /*C
					/* Shell type (identified by lack of definition) * /
					DefineStmt *n = makeNode(DefineStmt);

					n->kind = OBJECT_TYPE;
					n->oldstyle = false;
					n->defnames = $3;
					n->args = NIL;
					n->definition = NIL;
					$$ = (Node *) n;
				*/ }
			| CREATE TYPE_P any_name AS '(' OptTableFuncElementList ')'
				{ /*C
					CompositeTypeStmt *n = makeNode(CompositeTypeStmt);

					/* can't use qualified_name, sigh * /
					n->typevar = makeRangeVarFromAnyName($3, @3, yyscanner);
					n->coldeflist = $6;
					$$ = (Node *) n;
				*/ }
			| CREATE TYPE_P any_name AS ENUM_P '(' opt_enum_val_list ')'
				{ /*C
					CreateEnumStmt *n = makeNode(CreateEnumStmt);

					n->typeName = $3;
					n->vals = $7;
					$$ = (Node *) n;
				*/ }
			| CREATE TYPE_P any_name AS RANGE definition
				{ /*C
					CreateRangeStmt *n = makeNode(CreateRangeStmt);

					n->typeName = $3;
					n->params = $6;
					$$ = (Node *) n;
				*/ }
			| CREATE TEXT_P SEARCH PARSER any_name definition
				{ /*C
					DefineStmt *n = makeNode(DefineStmt);

					n->kind = OBJECT_TSPARSER;
					n->args = NIL;
					n->defnames = $5;
					n->definition = $6;
					$$ = (Node *) n;
				*/ }
			| CREATE TEXT_P SEARCH DICTIONARY any_name definition
				{ /*C
					DefineStmt *n = makeNode(DefineStmt);

					n->kind = OBJECT_TSDICTIONARY;
					n->args = NIL;
					n->defnames = $5;
					n->definition = $6;
					$$ = (Node *) n;
				*/ }
			| CREATE TEXT_P SEARCH TEMPLATE any_name definition
				{ /*C
					DefineStmt *n = makeNode(DefineStmt);

					n->kind = OBJECT_TSTEMPLATE;
					n->args = NIL;
					n->defnames = $5;
					n->definition = $6;
					$$ = (Node *) n;
				*/ }
			| CREATE TEXT_P SEARCH CONFIGURATION any_name definition
				{ /*C
					DefineStmt *n = makeNode(DefineStmt);

					n->kind = OBJECT_TSCONFIGURATION;
					n->args = NIL;
					n->defnames = $5;
					n->definition = $6;
					$$ = (Node *) n;
				*/ }
			| CREATE COLLATION any_name definition
				{ /*C
					DefineStmt *n = makeNode(DefineStmt);

					n->kind = OBJECT_COLLATION;
					n->args = NIL;
					n->defnames = $3;
					n->definition = $4;
					$$ = (Node *) n;
				*/ }
			| CREATE COLLATION IF_P NOT EXISTS any_name definition
				{ /*C
					DefineStmt *n = makeNode(DefineStmt);

					n->kind = OBJECT_COLLATION;
					n->args = NIL;
					n->defnames = $6;
					n->definition = $7;
					n->if_not_exists = true;
					$$ = (Node *) n;
				*/ }
			| CREATE COLLATION any_name FROM any_name
				{ /*C
					DefineStmt *n = makeNode(DefineStmt);

					n->kind = OBJECT_COLLATION;
					n->args = NIL;
					n->defnames = $3;
					n->definition = list_make1(makeDefElem("from", (Node *) $5, @5));
					$$ = (Node *) n;
				*/ }
			| CREATE COLLATION IF_P NOT EXISTS any_name FROM any_name
				{ /*C
					DefineStmt *n = makeNode(DefineStmt);

					n->kind = OBJECT_COLLATION;
					n->args = NIL;
					n->defnames = $6;
					n->definition = list_make1(makeDefElem("from", (Node *) $8, @8));
					n->if_not_exists = true;
					$$ = (Node *) n;
				*/ }
		;

definition: '(' def_list ')'						{ $$ = $2 }
		;

def_list:	def_elem								{ $$ = []Node{$1} }
			| def_list ',' def_elem					{ $$ = append($1, $3) }
		;

def_elem:	ColLabel '=' def_arg
				{ /*C
					$$ = makeDefElem($1, (Node *) $3, @1);
				*/ }
			| ColLabel
				{ /*C
					$$ = makeDefElem($1, NULL, @1);
				*/ }
		;

/* Note: any simple identifier will be returned as a type name! */
def_arg:	func_type						{ $$ = $1 }
			| reserved_keyword				{ /*C $$ = (Node *) makeString(pstrdup($1)); */ }
			| qual_all_Op					{ /*C $$ = (Node *) $1; */ }
			| NumericOnly					{ $$ = $1 }
			| Sconst						{ /*C $$ = (Node *) makeString($1); */ }
			| NONE							{ /*C $$ = (Node *) makeString(pstrdup($1)); */ }
		;

old_aggr_definition: '(' old_aggr_list ')'			{ $$ = $2 }
		;

old_aggr_list: old_aggr_elem						{ $$ = []Node{$1} }
			| old_aggr_list ',' old_aggr_elem		{ $$ = append($1, $3) }
		;

/*
 * Must use IDENT here to avoid reduce/reduce conflicts; fortunately none of
 * the item names needed in old aggregate definitions are likely to become
 * SQL keywords.
 */
old_aggr_elem:  IDENT '=' def_arg
				{ /*C
					$$ = makeDefElem($1, (Node *) $3, @1);
				*/ }
		;

opt_enum_val_list:
		enum_val_list							{ $$ = $1 }
		| /*EMPTY*/								{ $$ = nil }
		;

enum_val_list:	Sconst
				{ /*C $$ = list_make1(makeString($1)); */ }
			| enum_val_list ',' Sconst
				{ /*C $$ = lappend($1, makeString($3)); */ }
		;

/*****************************************************************************
 *
 *	ALTER TYPE enumtype ADD ...
 *
 *****************************************************************************/

AlterEnumStmt:
		ALTER TYPE_P any_name ADD_P VALUE_P opt_if_not_exists Sconst
			{ /*C
				AlterEnumStmt *n = makeNode(AlterEnumStmt);

				n->typeName = $3;
				n->oldVal = NULL;
				n->newVal = $7;
				n->newValNeighbor = NULL;
				n->newValIsAfter = true;
				n->skipIfNewValExists = $6;
				$$ = (Node *) n;
			*/ }
		 | ALTER TYPE_P any_name ADD_P VALUE_P opt_if_not_exists Sconst BEFORE Sconst
			{ /*C
				AlterEnumStmt *n = makeNode(AlterEnumStmt);

				n->typeName = $3;
				n->oldVal = NULL;
				n->newVal = $7;
				n->newValNeighbor = $9;
				n->newValIsAfter = false;
				n->skipIfNewValExists = $6;
				$$ = (Node *) n;
			*/ }
		 | ALTER TYPE_P any_name ADD_P VALUE_P opt_if_not_exists Sconst AFTER Sconst
			{ /*C
				AlterEnumStmt *n = makeNode(AlterEnumStmt);

				n->typeName = $3;
				n->oldVal = NULL;
				n->newVal = $7;
				n->newValNeighbor = $9;
				n->newValIsAfter = true;
				n->skipIfNewValExists = $6;
				$$ = (Node *) n;
			*/ }
		 | ALTER TYPE_P any_name RENAME VALUE_P Sconst TO Sconst
			{ /*C
				AlterEnumStmt *n = makeNode(AlterEnumStmt);

				n->typeName = $3;
				n->oldVal = $6;
				n->newVal = $8;
				n->newValNeighbor = NULL;
				n->newValIsAfter = false;
				n->skipIfNewValExists = false;
				$$ = (Node *) n;
			*/ }
		 | ALTER TYPE_P any_name DROP VALUE_P Sconst
			{ /*C
				/*
				 * The following problems must be solved before this can be
				 * implemented:
				 *
				 * - There must be no instance of the target value in
				 *   any table.
				 *
				 * - The value must not appear in any catalog metadata,
				 *   such as stored view expressions or column defaults.
				 *
				 * - The value must not appear in any non-leaf page of a
				 *   btree (and similar issues with other index types).
				 *   This is problematic because a value could persist
				 *   there long after it's gone from user-visible data.
				 *
				 * - Concurrent sessions must not be able to insert the
				 *   value while the preceding conditions are being checked.
				 *
				 * - Possibly more...
				 * /
				ereport(ERROR,
						(errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
						 errmsg("dropping an enum value is not implemented"),
						 parser_errposition(@4)));
			*/ }
		 ;

opt_if_not_exists: IF_P NOT EXISTS              { $$ = true }
		| /* EMPTY */                          { $$ = false }
		;


/*****************************************************************************
 *
 *		QUERIES :
 *				CREATE OPERATOR CLASS ...
 *				CREATE OPERATOR FAMILY ...
 *				ALTER OPERATOR FAMILY ...
 *				DROP OPERATOR CLASS ...
 *				DROP OPERATOR FAMILY ...
 *
 *****************************************************************************/

CreateOpClassStmt:
			CREATE OPERATOR CLASS any_name opt_default FOR TYPE_P Typename
			USING name opt_opfamily AS opclass_item_list
				{ /*C
					CreateOpClassStmt *n = makeNode(CreateOpClassStmt);

					n->opclassname = $4;
					n->isDefault = $5;
					n->datatype = $8;
					n->amname = $10;
					n->opfamilyname = $11;
					n->items = $13;
					$$ = (Node *) n;
				*/ }
		;

opclass_item_list:
			opclass_item							{ $$ = []Node{$1} }
			| opclass_item_list ',' opclass_item	{ $$ = append($1, $3) }
		;

opclass_item:
			OPERATOR Iconst any_operator opclass_purpose opt_recheck
				{ /*C
					CreateOpClassItem *n = makeNode(CreateOpClassItem);
					ObjectWithArgs *owa = makeNode(ObjectWithArgs);

					owa->objname = $3;
					owa->objargs = NIL;
					n->itemtype = OPCLASS_ITEM_OPERATOR;
					n->name = owa;
					n->number = $2;
					n->order_family = $4;
					$$ = (Node *) n;
				*/ }
			| OPERATOR Iconst operator_with_argtypes opclass_purpose
			  opt_recheck
				{ /*C
					CreateOpClassItem *n = makeNode(CreateOpClassItem);

					n->itemtype = OPCLASS_ITEM_OPERATOR;
					n->name = $3;
					n->number = $2;
					n->order_family = $4;
					$$ = (Node *) n;
				*/ }
			| FUNCTION Iconst function_with_argtypes
				{ /*C
					CreateOpClassItem *n = makeNode(CreateOpClassItem);

					n->itemtype = OPCLASS_ITEM_FUNCTION;
					n->name = $3;
					n->number = $2;
					$$ = (Node *) n;
				*/ }
			| FUNCTION Iconst '(' type_list ')' function_with_argtypes
				{ /*C
					CreateOpClassItem *n = makeNode(CreateOpClassItem);

					n->itemtype = OPCLASS_ITEM_FUNCTION;
					n->name = $6;
					n->number = $2;
					n->class_args = $4;
					$$ = (Node *) n;
				*/ }
			| STORAGE Typename
				{ /*C
					CreateOpClassItem *n = makeNode(CreateOpClassItem);

					n->itemtype = OPCLASS_ITEM_STORAGETYPE;
					n->storedtype = $2;
					$$ = (Node *) n;
				*/ }
		;

opt_default:	DEFAULT						{ $$ = true }
			| /*EMPTY*/						{ $$ = false }
		;

opt_opfamily:	FAMILY any_name				{ $$ = $2 }
			| /*EMPTY*/						{ $$ = nil }
		;

opclass_purpose: FOR SEARCH					{ $$ = nil }
			| FOR ORDER BY any_name			{ $$ = $4 }
			| /*EMPTY*/						{ $$ = nil }
		;

opt_recheck:	RECHECK
				{ /*C
					/*
					 * RECHECK no longer does anything in opclass definitions,
					 * but we still accept it to ease porting of old database
					 * dumps.
					 * /
					ereport(NOTICE,
							(errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
							 errmsg("RECHECK is no longer required"),
							 errhint("Update your data type."),
							 parser_errposition(@1)));
					$$ = true;
				*/ }
			| /*EMPTY*/						{ $$ = false }
		;


CreateOpFamilyStmt:
			CREATE OPERATOR FAMILY any_name USING name
				{ /*C
					CreateOpFamilyStmt *n = makeNode(CreateOpFamilyStmt);

					n->opfamilyname = $4;
					n->amname = $6;
					$$ = (Node *) n;
				*/ }
		;

AlterOpFamilyStmt:
			ALTER OPERATOR FAMILY any_name USING name ADD_P opclass_item_list
				{ /*C
					AlterOpFamilyStmt *n = makeNode(AlterOpFamilyStmt);

					n->opfamilyname = $4;
					n->amname = $6;
					n->isDrop = false;
					n->items = $8;
					$$ = (Node *) n;
				*/ }
			| ALTER OPERATOR FAMILY any_name USING name DROP opclass_drop_list
				{ /*C
					AlterOpFamilyStmt *n = makeNode(AlterOpFamilyStmt);

					n->opfamilyname = $4;
					n->amname = $6;
					n->isDrop = true;
					n->items = $8;
					$$ = (Node *) n;
				*/ }
		;

opclass_drop_list:
			opclass_drop							{ $$ = []Node{$1} }
			| opclass_drop_list ',' opclass_drop	{ $$ = append($1, $3) }
		;

opclass_drop:
			OPERATOR Iconst '(' type_list ')'
				{ /*C
					CreateOpClassItem *n = makeNode(CreateOpClassItem);

					n->itemtype = OPCLASS_ITEM_OPERATOR;
					n->number = $2;
					n->class_args = $4;
					$$ = (Node *) n;
				*/ }
			| FUNCTION Iconst '(' type_list ')'
				{ /*C
					CreateOpClassItem *n = makeNode(CreateOpClassItem);

					n->itemtype = OPCLASS_ITEM_FUNCTION;
					n->number = $2;
					n->class_args = $4;
					$$ = (Node *) n;
				*/ }
		;


DropOpClassStmt:
			DROP OPERATOR CLASS any_name USING name opt_drop_behavior
				{ /*C
					DropStmt *n = makeNode(DropStmt);

					n->objects = list_make1(lcons(makeString($6), $4));
					n->removeType = OBJECT_OPCLASS;
					n->behavior = $7;
					n->missing_ok = false;
					n->concurrent = false;
					$$ = (Node *) n;
				*/ }
			| DROP OPERATOR CLASS IF_P EXISTS any_name USING name opt_drop_behavior
				{ /*C
					DropStmt *n = makeNode(DropStmt);

					n->objects = list_make1(lcons(makeString($8), $6));
					n->removeType = OBJECT_OPCLASS;
					n->behavior = $9;
					n->missing_ok = true;
					n->concurrent = false;
					$$ = (Node *) n;
				*/ }
		;

DropOpFamilyStmt:
			DROP OPERATOR FAMILY any_name USING name opt_drop_behavior
				{ /*C
					DropStmt *n = makeNode(DropStmt);

					n->objects = list_make1(lcons(makeString($6), $4));
					n->removeType = OBJECT_OPFAMILY;
					n->behavior = $7;
					n->missing_ok = false;
					n->concurrent = false;
					$$ = (Node *) n;
				*/ }
			| DROP OPERATOR FAMILY IF_P EXISTS any_name USING name opt_drop_behavior
				{ /*C
					DropStmt *n = makeNode(DropStmt);

					n->objects = list_make1(lcons(makeString($8), $6));
					n->removeType = OBJECT_OPFAMILY;
					n->behavior = $9;
					n->missing_ok = true;
					n->concurrent = false;
					$$ = (Node *) n;
				*/ }
		;


/*****************************************************************************
 *
 *		QUERY:
 *
 *		DROP OWNED BY username [, username ...] [ RESTRICT | CASCADE ]
 *		REASSIGN OWNED BY username [, username ...] TO username
 *
 *****************************************************************************/
DropOwnedStmt:
			DROP OWNED BY role_list opt_drop_behavior
				{ /*C
					DropOwnedStmt *n = makeNode(DropOwnedStmt);

					n->roles = $4;
					n->behavior = $5;
					$$ = (Node *) n;
				*/ }
		;

ReassignOwnedStmt:
			REASSIGN OWNED BY role_list TO RoleSpec
				{ /*C
					ReassignOwnedStmt *n = makeNode(ReassignOwnedStmt);

					n->roles = $4;
					n->newrole = $6;
					$$ = (Node *) n;
				*/ }
		;

/*****************************************************************************
 *
 *		QUERY:
 *
 *		DROP itemtype [ IF EXISTS ] itemname [, itemname ...]
 *           [ RESTRICT | CASCADE ]
 *
 *****************************************************************************/

DropStmt:	DROP object_type_any_name IF_P EXISTS any_name_list opt_drop_behavior
				{ /*C
					DropStmt *n = makeNode(DropStmt);

					n->removeType = $2;
					n->missing_ok = true;
					n->objects = $5;
					n->behavior = $6;
					n->concurrent = false;
					$$ = (Node *) n;
				*/ }
			| DROP object_type_any_name any_name_list opt_drop_behavior
				{ /*C
					DropStmt *n = makeNode(DropStmt);

					n->removeType = $2;
					n->missing_ok = false;
					n->objects = $3;
					n->behavior = $4;
					n->concurrent = false;
					$$ = (Node *) n;
				*/ }
			| DROP drop_type_name IF_P EXISTS name_list opt_drop_behavior
				{ /*C
					DropStmt *n = makeNode(DropStmt);

					n->removeType = $2;
					n->missing_ok = true;
					n->objects = $5;
					n->behavior = $6;
					n->concurrent = false;
					$$ = (Node *) n;
				*/ }
			| DROP drop_type_name name_list opt_drop_behavior
				{ /*C
					DropStmt *n = makeNode(DropStmt);

					n->removeType = $2;
					n->missing_ok = false;
					n->objects = $3;
					n->behavior = $4;
					n->concurrent = false;
					$$ = (Node *) n;
				*/ }
			| DROP object_type_name_on_any_name name ON any_name opt_drop_behavior
				{ /*C
					DropStmt *n = makeNode(DropStmt);

					n->removeType = $2;
					n->objects = list_make1(lappend($5, makeString($3)));
					n->behavior = $6;
					n->missing_ok = false;
					n->concurrent = false;
					$$ = (Node *) n;
				*/ }
			| DROP object_type_name_on_any_name IF_P EXISTS name ON any_name opt_drop_behavior
				{ /*C
					DropStmt *n = makeNode(DropStmt);

					n->removeType = $2;
					n->objects = list_make1(lappend($7, makeString($5)));
					n->behavior = $8;
					n->missing_ok = true;
					n->concurrent = false;
					$$ = (Node *) n;
				*/ }
			| DROP TYPE_P type_name_list opt_drop_behavior
				{ /*C
					DropStmt *n = makeNode(DropStmt);

					n->removeType = OBJECT_TYPE;
					n->missing_ok = false;
					n->objects = $3;
					n->behavior = $4;
					n->concurrent = false;
					$$ = (Node *) n;
				*/ }
			| DROP TYPE_P IF_P EXISTS type_name_list opt_drop_behavior
				{ /*C
					DropStmt *n = makeNode(DropStmt);

					n->removeType = OBJECT_TYPE;
					n->missing_ok = true;
					n->objects = $5;
					n->behavior = $6;
					n->concurrent = false;
					$$ = (Node *) n;
				*/ }
			| DROP DOMAIN_P type_name_list opt_drop_behavior
				{ /*C
					DropStmt *n = makeNode(DropStmt);

					n->removeType = OBJECT_DOMAIN;
					n->missing_ok = false;
					n->objects = $3;
					n->behavior = $4;
					n->concurrent = false;
					$$ = (Node *) n;
				*/ }
			| DROP DOMAIN_P IF_P EXISTS type_name_list opt_drop_behavior
				{ /*C
					DropStmt *n = makeNode(DropStmt);

					n->removeType = OBJECT_DOMAIN;
					n->missing_ok = true;
					n->objects = $5;
					n->behavior = $6;
					n->concurrent = false;
					$$ = (Node *) n;
				*/ }
			| DROP INDEX CONCURRENTLY any_name_list opt_drop_behavior
				{ /*C
					DropStmt *n = makeNode(DropStmt);

					n->removeType = OBJECT_INDEX;
					n->missing_ok = false;
					n->objects = $4;
					n->behavior = $5;
					n->concurrent = true;
					$$ = (Node *) n;
				*/ }
			| DROP INDEX CONCURRENTLY IF_P EXISTS any_name_list opt_drop_behavior
				{ /*C
					DropStmt *n = makeNode(DropStmt);

					n->removeType = OBJECT_INDEX;
					n->missing_ok = true;
					n->objects = $6;
					n->behavior = $7;
					n->concurrent = true;
					$$ = (Node *) n;
				*/ }
		;

/* object types taking any_name/any_name_list */
object_type_any_name:
			TABLE									{ $$ = int32(OBJECT_TABLE) }
			| SEQUENCE								{ $$ = int32(OBJECT_SEQUENCE) }
			| VIEW									{ $$ = int32(OBJECT_VIEW) }
			| MATERIALIZED VIEW						{ $$ = int32(OBJECT_MATVIEW) }
			| INDEX									{ $$ = int32(OBJECT_INDEX) }
			| FOREIGN TABLE							{ $$ = int32(OBJECT_FOREIGN_TABLE) }
			| COLLATION								{ $$ = int32(OBJECT_COLLATION) }
			| CONVERSION_P							{ $$ = int32(OBJECT_CONVERSION) }
			| STATISTICS							{ $$ = int32(OBJECT_STATISTIC_EXT) }
			| TEXT_P SEARCH PARSER					{ $$ = int32(OBJECT_TSPARSER) }
			| TEXT_P SEARCH DICTIONARY				{ $$ = int32(OBJECT_TSDICTIONARY) }
			| TEXT_P SEARCH TEMPLATE				{ $$ = int32(OBJECT_TSTEMPLATE) }
			| TEXT_P SEARCH CONFIGURATION			{ $$ = int32(OBJECT_TSCONFIGURATION) }
		;

/*
 * object types taking name/name_list
 *
 * DROP handles some of them separately
 */

object_type_name:
			drop_type_name							{ $$ = $1 }
			| DATABASE								{ $$ = int32(OBJECT_DATABASE) }
			| ROLE									{ $$ = int32(OBJECT_ROLE) }
			| SUBSCRIPTION							{ $$ = int32(OBJECT_SUBSCRIPTION) }
			| TABLESPACE							{ $$ = int32(OBJECT_TABLESPACE) }
		;

drop_type_name:
			ACCESS METHOD							{ $$ = int32(OBJECT_ACCESS_METHOD) }
			| EVENT TRIGGER							{ $$ = int32(OBJECT_EVENT_TRIGGER) }
			| EXTENSION								{ $$ = int32(OBJECT_EXTENSION) }
			| FOREIGN DATA_P WRAPPER				{ $$ = int32(OBJECT_FDW) }
			| opt_procedural LANGUAGE				{ $$ = int32(OBJECT_LANGUAGE) }
			| PUBLICATION							{ $$ = int32(OBJECT_PUBLICATION) }
			| SCHEMA								{ $$ = int32(OBJECT_SCHEMA) }
			| SERVER								{ $$ = int32(OBJECT_FOREIGN_SERVER) }
		;

/* object types attached to a table */
object_type_name_on_any_name:
			POLICY									{ $$ = int32(OBJECT_POLICY) }
			| RULE									{ $$ = int32(OBJECT_RULE) }
			| TRIGGER								{ $$ = int32(OBJECT_TRIGGER) }
		;

any_name_list:
			any_name								{ /*C $$ = list_make1($1); */ }
			| any_name_list ',' any_name			{ /*C $$ = lappend($1, $3); */ }
		;

any_name:	ColId						{ /*C $$ = list_make1(makeString($1)); */ }
			| ColId attrs				{ /*C $$ = lcons(makeString($1), $2); */ }
		;

attrs:		'.' attr_name
					{ /*C $$ = list_make1(makeString($2)); */ }
			| attrs '.' attr_name
					{ /*C $$ = lappend($1, makeString($3)); */ }
		;

type_name_list:
			Typename								{ $$ = []Node{$1} }
			| type_name_list ',' Typename			{ $$ = append($1, $3) }
		;

/*****************************************************************************
 *
 *		QUERY:
 *				truncate table relname1, relname2, ...
 *
 *****************************************************************************/

TruncateStmt:
			TRUNCATE opt_table relation_expr_list opt_restart_seqs opt_drop_behavior
				{ /*C
					TruncateStmt *n = makeNode(TruncateStmt);

					n->relations = $3;
					n->restart_seqs = $4;
					n->behavior = $5;
					$$ = (Node *) n;
				*/ }
		;

opt_restart_seqs:
			CONTINUE_P IDENTITY_P		{ $$ = false }
			| RESTART IDENTITY_P		{ $$ = true }
			| /* EMPTY */				{ $$ = false }
		;

