/* gram.y lines 5160-7042 */
/*****************************************************************************
 *
 * ALTER EXTENSION name UPDATE [ TO version ]
 *
 *****************************************************************************/

AlterExtensionStmt: ALTER EXTENSION name UPDATE alter_extension_opt_list
				{
					n := &AlterExtensionStmt{}

					n.Extname = $3
					n.Options = $5
					$$ = n
				}
		;

alter_extension_opt_list:
			alter_extension_opt_list alter_extension_opt_item
				{ $$ = append($1, $2) }
			| /* EMPTY */
				{ $$ = nil }
		;

alter_extension_opt_item:
			TO NonReservedWord_or_Sconst
				{
					$$ = makeDefElem("new_version", makeString($2, @2), @1)
				}
		;

/*****************************************************************************
 *
 * ALTER EXTENSION name ADD/DROP object-identifier
 *
 *****************************************************************************/

AlterExtensionContentsStmt:
			ALTER EXTENSION name add_drop object_type_name name
				{
					n := &AlterExtensionContentsStmt{}

					n.Extname = $3
					n.Action = $4
					n.Objtype = ObjectType($5)
					n.Object = makeString($6, @6)
					$$ = n
				}
			| ALTER EXTENSION name add_drop object_type_any_name any_name
				{
					n := &AlterExtensionContentsStmt{}

					n.Extname = $3
					n.Action = $4
					n.Objtype = ObjectType($5)
					n.Object = listNode($6)
					$$ = n
				}
			| ALTER EXTENSION name add_drop AGGREGATE aggregate_with_argtypes
				{
					n := &AlterExtensionContentsStmt{}

					n.Extname = $3
					n.Action = $4
					n.Objtype = OBJECT_AGGREGATE
					n.Object = $6
					$$ = n
				}
			| ALTER EXTENSION name add_drop CAST '(' Typename AS Typename ')'
				{
					n := &AlterExtensionContentsStmt{}

					n.Extname = $3
					n.Action = $4
					n.Objtype = OBJECT_CAST
					n.Object = listNode([]Node{$7, $9})
					$$ = n
				}
			| ALTER EXTENSION name add_drop DOMAIN_P Typename
				{
					n := &AlterExtensionContentsStmt{}

					n.Extname = $3
					n.Action = $4
					n.Objtype = OBJECT_DOMAIN
					n.Object = $6
					$$ = n
				}
			| ALTER EXTENSION name add_drop FUNCTION function_with_argtypes
				{
					n := &AlterExtensionContentsStmt{}

					n.Extname = $3
					n.Action = $4
					n.Objtype = OBJECT_FUNCTION
					n.Object = $6
					$$ = n
				}
			| ALTER EXTENSION name add_drop OPERATOR operator_with_argtypes
				{
					n := &AlterExtensionContentsStmt{}

					n.Extname = $3
					n.Action = $4
					n.Objtype = OBJECT_OPERATOR
					n.Object = $6
					$$ = n
				}
			| ALTER EXTENSION name add_drop OPERATOR CLASS any_name USING name
				{
					n := &AlterExtensionContentsStmt{}

					n.Extname = $3
					n.Action = $4
					n.Objtype = OBJECT_OPCLASS
					n.Object = listNode(append([]Node{makeString($9, @9)}, $7...))
					$$ = n
				}
			| ALTER EXTENSION name add_drop OPERATOR FAMILY any_name USING name
				{
					n := &AlterExtensionContentsStmt{}

					n.Extname = $3
					n.Action = $4
					n.Objtype = OBJECT_OPFAMILY
					n.Object = listNode(append([]Node{makeString($9, @9)}, $7...))
					$$ = n
				}
			| ALTER EXTENSION name add_drop PROCEDURE function_with_argtypes
				{
					n := &AlterExtensionContentsStmt{}

					n.Extname = $3
					n.Action = $4
					n.Objtype = OBJECT_PROCEDURE
					n.Object = $6
					$$ = n
				}
			| ALTER EXTENSION name add_drop ROUTINE function_with_argtypes
				{
					n := &AlterExtensionContentsStmt{}

					n.Extname = $3
					n.Action = $4
					n.Objtype = OBJECT_ROUTINE
					n.Object = $6
					$$ = n
				}
			| ALTER EXTENSION name add_drop TRANSFORM FOR Typename LANGUAGE name
				{
					n := &AlterExtensionContentsStmt{}

					n.Extname = $3
					n.Action = $4
					n.Objtype = OBJECT_TRANSFORM
					n.Object = listNode([]Node{$7, makeString($9, @9)})
					$$ = n
				}
			| ALTER EXTENSION name add_drop TYPE_P Typename
				{
					n := &AlterExtensionContentsStmt{}

					n.Extname = $3
					n.Action = $4
					n.Objtype = OBJECT_TYPE
					n.Object = $6
					$$ = n
				}
		;

/*****************************************************************************
 *
 *		QUERY:
 *             CREATE FOREIGN DATA WRAPPER name options
 *
 *****************************************************************************/

CreateFdwStmt: CREATE FOREIGN DATA_P WRAPPER name opt_fdw_options create_generic_options
				{
					n := &CreateFdwStmt{}

					n.Fdwname = $5
					n.FuncOptions = $6
					n.Options = $7
					$$ = n
				}
		;

fdw_option:
			HANDLER handler_name				{ $$ = makeDefElem("handler", listNode($2), @1) }
			| NO HANDLER						{ $$ = makeDefElem("handler", nil, @1) }
			| VALIDATOR handler_name			{ $$ = makeDefElem("validator", listNode($2), @1) }
			| NO VALIDATOR						{ $$ = makeDefElem("validator", nil, @1) }
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
				{
					n := &AlterFdwStmt{}

					n.Fdwname = $5
					n.FuncOptions = $6
					n.Options = $7
					$$ = n
				}
			| ALTER FOREIGN DATA_P WRAPPER name fdw_options
				{
					n := &AlterFdwStmt{}

					n.Fdwname = $5
					n.FuncOptions = $6
					n.Options = nil
					$$ = n
				}
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
				{
					$$ = $2
					as[*DefElem]($$).Defaction = DEFELEM_SET
				}
			| ADD_P generic_option_elem
				{
					$$ = $2
					as[*DefElem]($$).Defaction = DEFELEM_ADD
				}
			| DROP generic_option_name
				{
					$$ = makeDefElemExtended("", $2, nil, DEFELEM_DROP, @2)
				}
		;

generic_option_elem:
			generic_option_name generic_option_arg
				{
					$$ = makeDefElem($1, $2, @1)
				}
		;

generic_option_name:
				ColLabel			{ $$ = $1 }
		;

/* We could use def_arg here, but the spec only requires string literals */
generic_option_arg:
				Sconst				{ $$ = makeString($1, @1) }
		;

/*****************************************************************************
 *
 *		QUERY:
 *             CREATE SERVER name [TYPE] [VERSION] [OPTIONS]
 *
 *****************************************************************************/

CreateForeignServerStmt: CREATE SERVER name opt_type opt_foreign_server_version
						 FOREIGN DATA_P WRAPPER name create_generic_options
				{
					n := &CreateForeignServerStmt{}

					n.Servername = $3
					n.Servertype = $4
					n.Version = $5
					n.Fdwname = $9
					n.Options = $10
					n.IfNotExists = false
					$$ = n
				}
				| CREATE SERVER IF_P NOT EXISTS name opt_type opt_foreign_server_version
						 FOREIGN DATA_P WRAPPER name create_generic_options
				{
					n := &CreateForeignServerStmt{}

					n.Servername = $6
					n.Servertype = $7
					n.Version = $8
					n.Fdwname = $12
					n.Options = $13
					n.IfNotExists = true
					$$ = n
				}
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
				{
					n := &AlterForeignServerStmt{}

					n.Servername = $3
					n.Version = $4
					n.Options = $5
					n.HasVersion = true
					$$ = n
				}
			| ALTER SERVER name foreign_server_version
				{
					n := &AlterForeignServerStmt{}

					n.Servername = $3
					n.Version = $4
					n.HasVersion = true
					$$ = n
				}
			| ALTER SERVER name alter_generic_options
				{
					n := &AlterForeignServerStmt{}

					n.Servername = $3
					n.Options = $4
					$$ = n
				}
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
				{
					n := &CreateForeignTableStmt{}
					base := &CreateStmt{}
					rv := as[*RangeVar]($4)

					if rv != nil {
						rv.Relpersistence = relpersistencePermanent
					}
					base.Relation = rv
					base.TableElts = $6
					base.InhRelations = $8
					base.OfTypename = nil
					base.Constraints = nil
					base.Options = nil
					base.Oncommit = ONCOMMIT_NOOP
					base.Tablespacename = ""
					base.IfNotExists = false
					n.BaseStmt = base
					/* FDW-specific data */
					n.Servername = $10
					n.Options = $11
					$$ = n
				}
		| CREATE FOREIGN TABLE IF_P NOT EXISTS qualified_name
			'(' OptTableElementList ')'
			OptInherit SERVER name create_generic_options
				{
					n := &CreateForeignTableStmt{}
					base := &CreateStmt{}
					rv := as[*RangeVar]($7)

					if rv != nil {
						rv.Relpersistence = relpersistencePermanent
					}
					base.Relation = rv
					base.TableElts = $9
					base.InhRelations = $11
					base.OfTypename = nil
					base.Constraints = nil
					base.Options = nil
					base.Oncommit = ONCOMMIT_NOOP
					base.Tablespacename = ""
					base.IfNotExists = true
					n.BaseStmt = base
					/* FDW-specific data */
					n.Servername = $13
					n.Options = $14
					$$ = n
				}
		| CREATE FOREIGN TABLE qualified_name
			PARTITION OF qualified_name OptTypedTableElementList PartitionBoundSpec
			SERVER name create_generic_options
				{
					n := &CreateForeignTableStmt{}
					base := &CreateStmt{}
					rv := as[*RangeVar]($4)

					if rv != nil {
						rv.Relpersistence = relpersistencePermanent
					}
					base.Relation = rv
					base.InhRelations = []Node{$7}
					base.TableElts = $8
					base.Partbound = as[*PartitionBoundSpec]($9)
					base.OfTypename = nil
					base.Constraints = nil
					base.Options = nil
					base.Oncommit = ONCOMMIT_NOOP
					base.Tablespacename = ""
					base.IfNotExists = false
					n.BaseStmt = base
					/* FDW-specific data */
					n.Servername = $11
					n.Options = $12
					$$ = n
				}
		| CREATE FOREIGN TABLE IF_P NOT EXISTS qualified_name
			PARTITION OF qualified_name OptTypedTableElementList PartitionBoundSpec
			SERVER name create_generic_options
				{
					n := &CreateForeignTableStmt{}
					base := &CreateStmt{}
					rv := as[*RangeVar]($7)

					if rv != nil {
						rv.Relpersistence = relpersistencePermanent
					}
					base.Relation = rv
					base.InhRelations = []Node{$10}
					base.TableElts = $11
					base.Partbound = as[*PartitionBoundSpec]($12)
					base.OfTypename = nil
					base.Constraints = nil
					base.Options = nil
					base.Oncommit = ONCOMMIT_NOOP
					base.Tablespacename = ""
					base.IfNotExists = true
					n.BaseStmt = base
					/* FDW-specific data */
					n.Servername = $14
					n.Options = $15
					$$ = n
				}
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
			{
				n := &ImportForeignSchemaStmt{}

				n.ServerName = $8
				n.RemoteSchema = $4
				n.LocalSchema = $10
				n.ListType = as[*importQual]($5).typ
				n.TableList = as[*importQual]($5).tableNames
				n.Options = $11
				$$ = n
			}
		;

import_qualification_type:
		LIMIT TO				{ $$ = int32(FDW_IMPORT_SCHEMA_LIMIT_TO) }
		| EXCEPT				{ $$ = int32(FDW_IMPORT_SCHEMA_EXCEPT) }
		;

import_qualification:
		import_qualification_type '(' relation_expr_list ')'
			{
				n := &importQual{}

				n.typ = ImportForeignSchemaType($1)
				n.tableNames = $3
				$$ = n
			}
		| /*EMPTY*/
			{
				n := &importQual{}
				n.typ = FDW_IMPORT_SCHEMA_ALL
				n.tableNames = nil
				$$ = n
			}
		;

/*****************************************************************************
 *
 *		QUERY:
 *             CREATE USER MAPPING FOR auth_ident SERVER name [OPTIONS]
 *
 *****************************************************************************/

CreateUserMappingStmt: CREATE USER MAPPING FOR auth_ident SERVER name create_generic_options
				{
					n := &CreateUserMappingStmt{}

					n.User = as[*RoleSpec]($5)
					n.Servername = $7
					n.Options = $8
					n.IfNotExists = false
					$$ = n
				}
				| CREATE USER MAPPING IF_P NOT EXISTS FOR auth_ident SERVER name create_generic_options
				{
					n := &CreateUserMappingStmt{}

					n.User = as[*RoleSpec]($8)
					n.Servername = $10
					n.Options = $11
					n.IfNotExists = true
					$$ = n
				}
		;

/* User mapping authorization identifier */
auth_ident: RoleSpec			{ $$ = $1 }
			| USER				{ $$ = makeRoleSpec(ROLESPEC_CURRENT_USER, @1) }
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
				{
					n := &DropUserMappingStmt{}

					n.User = as[*RoleSpec]($5)
					n.Servername = $7
					n.MissingOk = false
					$$ = n
				}
				|  DROP USER MAPPING IF_P EXISTS FOR auth_ident SERVER name
				{
					n := &DropUserMappingStmt{}

					n.User = as[*RoleSpec]($7)
					n.Servername = $9
					n.MissingOk = true
					$$ = n
				}
		;

/*****************************************************************************
 *
 *		QUERY :
 *				ALTER USER MAPPING FOR auth_ident SERVER name OPTIONS
 *
 ****************************************************************************/

AlterUserMappingStmt: ALTER USER MAPPING FOR auth_ident SERVER name alter_generic_options
				{
					n := &AlterUserMappingStmt{}

					n.User = as[*RoleSpec]($5)
					n.Servername = $7
					n.Options = $8
					$$ = n
				}
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
				{
					n := &CreatePolicyStmt{}

					n.PolicyName = $3
					n.Table = as[*RangeVar]($5)
					n.Permissive = $6
					n.CmdName = $7
					n.Roles = $8
					n.Qual = $9
					n.WithCheck = $10
					$$ = n
				}
		;

AlterPolicyStmt:
			ALTER POLICY name ON qualified_name RowSecurityOptionalToRole
				RowSecurityOptionalExpr RowSecurityOptionalWithCheck
				{
					n := &AlterPolicyStmt{}

					n.PolicyName = $3
					n.Table = as[*RangeVar]($5)
					n.Roles = $6
					n.Qual = $7
					n.WithCheck = $8
					$$ = n
				}
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
			| /* EMPTY */			{ $$ = []Node{makeRoleSpec(ROLESPEC_PUBLIC, -1)} }
		;

RowSecurityOptionalToRole:
			TO role_list			{ $$ = $2 }
			| /* EMPTY */			{ $$ = nil }
		;

RowSecurityDefaultPermissive:
			AS IDENT
				{
					if $2 == "permissive" {
						$$ = true
					} else if $2 == "restrictive" {
						$$ = false
					} else {
						p.fail(@2, fmt.Sprintf("unrecognized row security option \"%s\"", $2))
					}
				}
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
				{
					n := &CreateAmStmt{}

					n.Amname = $4
					n.HandlerName = $8
					n.Amtype = $6
					$$ = n
				}
		;

am_type:
			INDEX			{ $$ = amtypeIndex }
		|	TABLE			{ $$ = amtypeTable }
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
				{
					n := &CreateTrigStmt{}

					n.Replace = $2
					n.Isconstraint = false
					n.Trigname = $4
					n.Relation = as[*RangeVar]($8)
					n.Funcname = $14
					n.Args = $16
					n.Row = $10
					n.Timing = $5
					n.Events = intVal($6[0])
					n.Columns = asList($6[1])
					n.WhenClause = $11
					n.TransitionRels = $9
					n.Deferrable = false
					n.Initdeferred = false
					n.Constrrel = nil
					$$ = n
				}
		  | CREATE opt_or_replace CONSTRAINT TRIGGER name AFTER TriggerEvents ON
			qualified_name OptConstrFromTable ConstraintAttributeSpec
			FOR EACH ROW TriggerWhen
			EXECUTE FUNCTION_or_PROCEDURE func_name '(' TriggerFuncArgs ')'
				{
					n := &CreateTrigStmt{}

					n.Replace = $2
					if n.Replace { /* not supported, see CreateTrigger */
						p.fail(-1, "CREATE OR REPLACE CONSTRAINT TRIGGER is not supported")
					}
					n.Isconstraint = true
					n.Trigname = $5
					n.Relation = as[*RangeVar]($9)
					n.Funcname = $18
					n.Args = $20
					n.Row = true
					n.Timing = triggerTypeAfter
					n.Events = intVal($7[0])
					n.Columns = asList($7[1])
					n.WhenClause = $15
					n.TransitionRels = nil
					p.processCASbits($11, @11, "TRIGGER",
								   &n.Deferrable, &n.Initdeferred, nil,
								   nil)
					n.Constrrel = as[*RangeVar]($10)
					$$ = n
				}
		;

TriggerActionTime:
			BEFORE								{ $$ = triggerTypeBefore }
			| AFTER								{ $$ = triggerTypeAfter }
			| INSTEAD OF						{ $$ = triggerTypeInstead }
		;

TriggerEvents:
			TriggerOneEvent
				{ $$ = $1 }
			| TriggerEvents OR TriggerOneEvent
				{
					events1 := intVal($1[0])
					events2 := intVal($3[0])
					columns1 := asList($1[1])
					columns2 := asList($3[1])

					if events1&events2 != 0 {
						p.yyerror("duplicate trigger events specified")
					}
					/*
					 * concat'ing the columns lists loses information about
					 * which columns went with which event, but so long as
					 * only UPDATE carries columns and we disallow multiple
					 * UPDATE items, it doesn't matter.  Command execution
					 * should just ignore the columns for non-UPDATE events.
					 */
					$$ = []Node{makeInteger(events1 | events2),
									listNode(append(columns1, columns2...))}
				}
		;

TriggerOneEvent:
			INSERT
				{ $$ = []Node{makeInteger(triggerTypeInsert), nil} }
			| DELETE_P
				{ $$ = []Node{makeInteger(triggerTypeDelete), nil} }
			| UPDATE
				{ $$ = []Node{makeInteger(triggerTypeUpdate), nil} }
			| UPDATE OF columnList
				{ $$ = []Node{makeInteger(triggerTypeUpdate), listNode($3)} }
			| TRUNCATE
				{ $$ = []Node{makeInteger(triggerTypeTruncate), nil} }
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
				{
					n := &TriggerTransition{}

					n.Name = $4
					n.IsNew = $1
					n.IsTable = $2
					$$ = n
				}
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
				{
					/*
					 * If ROW/STATEMENT not specified, default to
					 * STATEMENT, per SQL
					 */
					$$ = false
				}
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
				{
					$$ = makeString(fmt.Sprintf("%d", $1), @1)
				}
			| FCONST								{ $$ = makeString($1, @1) }
			| Sconst								{ $$ = makeString($1, @1) }
			| ColLabel								{ $$ = makeString($1, @1) }
		;

OptConstrFromTable:
			FROM qualified_name						{ $$ = $2 }
			| /*EMPTY*/								{ $$ = nil }
		;

ConstraintAttributeSpec:
			/*EMPTY*/
				{ $$ = 0 }
			| ConstraintAttributeSpec ConstraintAttributeElem
				{
					/*
					 * We must complain about conflicting options.
					 * We could, but choose not to, complain about redundant
					 * options (ie, where $2's bit is already set in $1).
					 */
					newspec := $1 | $2

					/* special message for this case */
					if (newspec & (casNotDeferrable | casInitiallyDeferred)) == (casNotDeferrable | casInitiallyDeferred) {
						p.fail(@2, "constraint declared INITIALLY DEFERRED must be DEFERRABLE")
					}
					/* generic message for other conflicts */
					if (newspec&(casNotDeferrable|casDeferrable)) == (casNotDeferrable|casDeferrable) ||
						(newspec&(casInitiallyImmediate|casInitiallyDeferred)) == (casInitiallyImmediate|casInitiallyDeferred) {
						p.fail(@2, "conflicting constraint properties")
					}
					$$ = newspec
				}
		;

ConstraintAttributeElem:
			NOT DEFERRABLE					{ $$ = casNotDeferrable }
			| DEFERRABLE					{ $$ = casDeferrable }
			| INITIALLY IMMEDIATE			{ $$ = casInitiallyImmediate }
			| INITIALLY DEFERRED			{ $$ = casInitiallyDeferred }
			| NOT VALID						{ $$ = casNotValid }
			| NO INHERIT					{ $$ = casNoInherit }
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
				{
					n := &CreateEventTrigStmt{}

					n.Trigname = $4
					n.Eventname = $6
					n.Whenclause = nil
					n.Funcname = $9
					$$ = n
				}
		  | CREATE EVENT TRIGGER name ON ColLabel
			WHEN event_trigger_when_list
			EXECUTE FUNCTION_or_PROCEDURE func_name '(' ')'
				{
					n := &CreateEventTrigStmt{}

					n.Trigname = $4
					n.Eventname = $6
					n.Whenclause = $8
					n.Funcname = $11
					$$ = n
				}
		;

event_trigger_when_list:
		  event_trigger_when_item
			{ $$ = []Node{$1} }
		| event_trigger_when_list AND event_trigger_when_item
			{ $$ = append($1, $3) }
		;

event_trigger_when_item:
		ColId IN_P '(' event_trigger_value_list ')'
			{ $$ = makeDefElem($1, listNode($4), @1) }
		;

event_trigger_value_list:
		  SCONST
			{ $$ = []Node{makeString($1, @1)} }
		| event_trigger_value_list ',' SCONST
			{ $$ = append($1, makeString($3, @3)) }
		;

AlterEventTrigStmt:
			ALTER EVENT TRIGGER name enable_trigger
				{
					n := &AlterEventTrigStmt{}

					n.Trigname = $4
					n.Tgenabled = $5
					$$ = n
				}
		;

enable_trigger:
			ENABLE_P					{ $$ = triggerFiresOnOrigin }
			| ENABLE_P REPLICA			{ $$ = triggerFiresOnReplica }
			| ENABLE_P ALWAYS			{ $$ = triggerFiresAlways }
			| DISABLE_P					{ $$ = triggerDisabled }
		;

/*****************************************************************************
 *
 *		QUERY :
 *				CREATE ASSERTION ...
 *
 *****************************************************************************/

CreateAssertionStmt:
			CREATE ASSERTION any_name CHECK '(' a_expr ')' ConstraintAttributeSpec
				{
					p.fail(-1, "CREATE ASSERTION is not yet implemented")

					$$ = nil
				}
		;


/*****************************************************************************
 *
 *		QUERY :
 *				define (aggregate,operator,type)
 *
 *****************************************************************************/

DefineStmt:
			CREATE opt_or_replace AGGREGATE func_name aggr_args definition
				{
					n := &DefineStmt{}

					n.Kind = OBJECT_AGGREGATE
					n.Oldstyle = false
					n.Replace = $2
					n.Defnames = $4
					n.Args = $5
					n.Definition = $6
					$$ = n
				}
			| CREATE opt_or_replace AGGREGATE func_name old_aggr_definition
				{
					/* old-style (pre-8.2) syntax for CREATE AGGREGATE */
					n := &DefineStmt{}

					n.Kind = OBJECT_AGGREGATE
					n.Oldstyle = true
					n.Replace = $2
					n.Defnames = $4
					n.Args = nil
					n.Definition = $5
					$$ = n
				}
			| CREATE OPERATOR any_operator definition
				{
					n := &DefineStmt{}

					n.Kind = OBJECT_OPERATOR
					n.Oldstyle = false
					n.Defnames = $3
					n.Args = nil
					n.Definition = $4
					$$ = n
				}
			| CREATE TYPE_P any_name definition
				{
					n := &DefineStmt{}

					n.Kind = OBJECT_TYPE
					n.Oldstyle = false
					n.Defnames = $3
					n.Args = nil
					n.Definition = $4
					$$ = n
				}
			| CREATE TYPE_P any_name
				{
					/* Shell type (identified by lack of definition) */
					n := &DefineStmt{}

					n.Kind = OBJECT_TYPE
					n.Oldstyle = false
					n.Defnames = $3
					n.Args = nil
					n.Definition = nil
					$$ = n
				}
			| CREATE TYPE_P any_name AS '(' OptTableFuncElementList ')'
				{
					n := &CompositeTypeStmt{}

					/* can't use qualified_name, sigh */
					n.Typevar = p.makeRangeVarFromAnyName($3, @3)
					n.Coldeflist = $6
					$$ = n
				}
			| CREATE TYPE_P any_name AS ENUM_P '(' opt_enum_val_list ')'
				{
					n := &CreateEnumStmt{}

					n.TypeName = $3
					n.Vals = $7
					$$ = n
				}
			| CREATE TYPE_P any_name AS RANGE definition
				{
					n := &CreateRangeStmt{}

					n.TypeName = $3
					n.Params = $6
					$$ = n
				}
			| CREATE TEXT_P SEARCH PARSER any_name definition
				{
					n := &DefineStmt{}

					n.Kind = OBJECT_TSPARSER
					n.Args = nil
					n.Defnames = $5
					n.Definition = $6
					$$ = n
				}
			| CREATE TEXT_P SEARCH DICTIONARY any_name definition
				{
					n := &DefineStmt{}

					n.Kind = OBJECT_TSDICTIONARY
					n.Args = nil
					n.Defnames = $5
					n.Definition = $6
					$$ = n
				}
			| CREATE TEXT_P SEARCH TEMPLATE any_name definition
				{
					n := &DefineStmt{}

					n.Kind = OBJECT_TSTEMPLATE
					n.Args = nil
					n.Defnames = $5
					n.Definition = $6
					$$ = n
				}
			| CREATE TEXT_P SEARCH CONFIGURATION any_name definition
				{
					n := &DefineStmt{}

					n.Kind = OBJECT_TSCONFIGURATION
					n.Args = nil
					n.Defnames = $5
					n.Definition = $6
					$$ = n
				}
			| CREATE COLLATION any_name definition
				{
					n := &DefineStmt{}

					n.Kind = OBJECT_COLLATION
					n.Args = nil
					n.Defnames = $3
					n.Definition = $4
					$$ = n
				}
			| CREATE COLLATION IF_P NOT EXISTS any_name definition
				{
					n := &DefineStmt{}

					n.Kind = OBJECT_COLLATION
					n.Args = nil
					n.Defnames = $6
					n.Definition = $7
					n.IfNotExists = true
					$$ = n
				}
			| CREATE COLLATION any_name FROM any_name
				{
					n := &DefineStmt{}

					n.Kind = OBJECT_COLLATION
					n.Args = nil
					n.Defnames = $3
					n.Definition = []Node{makeDefElem("from", listNode($5), @5)}
					$$ = n
				}
			| CREATE COLLATION IF_P NOT EXISTS any_name FROM any_name
				{
					n := &DefineStmt{}

					n.Kind = OBJECT_COLLATION
					n.Args = nil
					n.Defnames = $6
					n.Definition = []Node{makeDefElem("from", listNode($8), @8)}
					n.IfNotExists = true
					$$ = n
				}
		;

definition: '(' def_list ')'						{ $$ = $2 }
		;

def_list:	def_elem								{ $$ = []Node{$1} }
			| def_list ',' def_elem					{ $$ = append($1, $3) }
		;

def_elem:	ColLabel '=' def_arg
				{
					$$ = makeDefElem($1, $3, @1)
				}
			| ColLabel
				{
					$$ = makeDefElem($1, nil, @1)
				}
		;

/* Note: any simple identifier will be returned as a type name! */
def_arg:	func_type						{ $$ = $1 }
			| reserved_keyword				{ $$ = makeString($1, @1) }
			| qual_all_Op					{ $$ = listNode($1) }
			| NumericOnly					{ $$ = $1 }
			| Sconst						{ $$ = makeString($1, @1) }
			| NONE							{ $$ = makeString($1, @1) }
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
				{
					$$ = makeDefElem($1, $3, @1)
				}
		;

opt_enum_val_list:
		enum_val_list							{ $$ = $1 }
		| /*EMPTY*/								{ $$ = nil }
		;

enum_val_list:	Sconst
				{ $$ = []Node{makeString($1, @1)} }
			| enum_val_list ',' Sconst
				{ $$ = append($1, makeString($3, @3)) }
		;

/*****************************************************************************
 *
 *	ALTER TYPE enumtype ADD ...
 *
 *****************************************************************************/

AlterEnumStmt:
		ALTER TYPE_P any_name ADD_P VALUE_P opt_if_not_exists Sconst
			{
				n := &AlterEnumStmt{}

				n.TypeName = $3
				n.OldVal = ""
				n.NewVal = $7
				n.NewValNeighbor = ""
				n.NewValIsAfter = true
				n.SkipIfNewValExists = $6
				$$ = n
			}
		 | ALTER TYPE_P any_name ADD_P VALUE_P opt_if_not_exists Sconst BEFORE Sconst
			{
				n := &AlterEnumStmt{}

				n.TypeName = $3
				n.OldVal = ""
				n.NewVal = $7
				n.NewValNeighbor = $9
				n.NewValIsAfter = false
				n.SkipIfNewValExists = $6
				$$ = n
			}
		 | ALTER TYPE_P any_name ADD_P VALUE_P opt_if_not_exists Sconst AFTER Sconst
			{
				n := &AlterEnumStmt{}

				n.TypeName = $3
				n.OldVal = ""
				n.NewVal = $7
				n.NewValNeighbor = $9
				n.NewValIsAfter = true
				n.SkipIfNewValExists = $6
				$$ = n
			}
		 | ALTER TYPE_P any_name RENAME VALUE_P Sconst TO Sconst
			{
				n := &AlterEnumStmt{}

				n.TypeName = $3
				n.OldVal = $6
				n.NewVal = $8
				n.NewValNeighbor = ""
				n.NewValIsAfter = false
				n.SkipIfNewValExists = false
				$$ = n
			}
		 | ALTER TYPE_P any_name DROP VALUE_P Sconst
			{
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
				 */
				p.fail(@4, "dropping an enum value is not implemented")
			}
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
				{
					n := &CreateOpClassStmt{}

					n.Opclassname = $4
					n.IsDefault = $5
					n.Datatype = as[*TypeName]($8)
					n.Amname = $10
					n.Opfamilyname = $11
					n.Items = $13
					$$ = n
				}
		;

opclass_item_list:
			opclass_item							{ $$ = []Node{$1} }
			| opclass_item_list ',' opclass_item	{ $$ = append($1, $3) }
		;

opclass_item:
			OPERATOR Iconst any_operator opclass_purpose opt_recheck
				{
					n := &CreateOpClassItem{}
					owa := &ObjectWithArgs{}

					owa.Objname = $3
					owa.Objargs = nil
					n.Itemtype = opclassItemOperator
					n.Name = owa
					n.Number = $2
					n.OrderFamily = $4
					$$ = n
				}
			| OPERATOR Iconst operator_with_argtypes opclass_purpose
			  opt_recheck
				{
					n := &CreateOpClassItem{}

					n.Itemtype = opclassItemOperator
					n.Name = as[*ObjectWithArgs]($3)
					n.Number = $2
					n.OrderFamily = $4
					$$ = n
				}
			| FUNCTION Iconst function_with_argtypes
				{
					n := &CreateOpClassItem{}

					n.Itemtype = opclassItemFunction
					n.Name = as[*ObjectWithArgs]($3)
					n.Number = $2
					$$ = n
				}
			| FUNCTION Iconst '(' type_list ')' function_with_argtypes
				{
					n := &CreateOpClassItem{}

					n.Itemtype = opclassItemFunction
					n.Name = as[*ObjectWithArgs]($6)
					n.Number = $2
					n.ClassArgs = $4
					$$ = n
				}
			| STORAGE Typename
				{
					n := &CreateOpClassItem{}

					n.Itemtype = opclassItemStoragetype
					n.Storedtype = as[*TypeName]($2)
					$$ = n
				}
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
				{
					/*
					 * RECHECK no longer does anything in opclass definitions,
					 * but we still accept it to ease porting of old database
					 * dumps.
					 */
					/*
					 * C raises a NOTICE here ("RECHECK is no longer required");
					 * a NOTICE is no error, so the parser has nothing to report.
					 */
					$$ = true
				}
			| /*EMPTY*/						{ $$ = false }
		;


CreateOpFamilyStmt:
			CREATE OPERATOR FAMILY any_name USING name
				{
					n := &CreateOpFamilyStmt{}

					n.Opfamilyname = $4
					n.Amname = $6
					$$ = n
				}
		;

AlterOpFamilyStmt:
			ALTER OPERATOR FAMILY any_name USING name ADD_P opclass_item_list
				{
					n := &AlterOpFamilyStmt{}

					n.Opfamilyname = $4
					n.Amname = $6
					n.IsDrop = false
					n.Items = $8
					$$ = n
				}
			| ALTER OPERATOR FAMILY any_name USING name DROP opclass_drop_list
				{
					n := &AlterOpFamilyStmt{}

					n.Opfamilyname = $4
					n.Amname = $6
					n.IsDrop = true
					n.Items = $8
					$$ = n
				}
		;

opclass_drop_list:
			opclass_drop							{ $$ = []Node{$1} }
			| opclass_drop_list ',' opclass_drop	{ $$ = append($1, $3) }
		;

opclass_drop:
			OPERATOR Iconst '(' type_list ')'
				{
					n := &CreateOpClassItem{}

					n.Itemtype = opclassItemOperator
					n.Number = $2
					n.ClassArgs = $4
					$$ = n
				}
			| FUNCTION Iconst '(' type_list ')'
				{
					n := &CreateOpClassItem{}

					n.Itemtype = opclassItemFunction
					n.Number = $2
					n.ClassArgs = $4
					$$ = n
				}
		;


DropOpClassStmt:
			DROP OPERATOR CLASS any_name USING name opt_drop_behavior
				{
					n := &DropStmt{}

					n.Objects = []Node{listNode(append([]Node{makeString($6, @6)}, $4...))}
					n.RemoveType = OBJECT_OPCLASS
					n.Behavior = DropBehavior($7)
					n.MissingOk = false
					n.Concurrent = false
					$$ = n
				}
			| DROP OPERATOR CLASS IF_P EXISTS any_name USING name opt_drop_behavior
				{
					n := &DropStmt{}

					n.Objects = []Node{listNode(append([]Node{makeString($8, @8)}, $6...))}
					n.RemoveType = OBJECT_OPCLASS
					n.Behavior = DropBehavior($9)
					n.MissingOk = true
					n.Concurrent = false
					$$ = n
				}
		;

DropOpFamilyStmt:
			DROP OPERATOR FAMILY any_name USING name opt_drop_behavior
				{
					n := &DropStmt{}

					n.Objects = []Node{listNode(append([]Node{makeString($6, @6)}, $4...))}
					n.RemoveType = OBJECT_OPFAMILY
					n.Behavior = DropBehavior($7)
					n.MissingOk = false
					n.Concurrent = false
					$$ = n
				}
			| DROP OPERATOR FAMILY IF_P EXISTS any_name USING name opt_drop_behavior
				{
					n := &DropStmt{}

					n.Objects = []Node{listNode(append([]Node{makeString($8, @8)}, $6...))}
					n.RemoveType = OBJECT_OPFAMILY
					n.Behavior = DropBehavior($9)
					n.MissingOk = true
					n.Concurrent = false
					$$ = n
				}
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
				{
					n := &DropOwnedStmt{}

					n.Roles = $4
					n.Behavior = DropBehavior($5)
					$$ = n
				}
		;

ReassignOwnedStmt:
			REASSIGN OWNED BY role_list TO RoleSpec
				{
					n := &ReassignOwnedStmt{}

					n.Roles = $4
					n.Newrole = as[*RoleSpec]($6)
					$$ = n
				}
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
				{
					n := &DropStmt{}

					n.RemoveType = ObjectType($2)
					n.MissingOk = true
					n.Objects = $5
					n.Behavior = DropBehavior($6)
					n.Concurrent = false
					$$ = n
				}
			| DROP object_type_any_name any_name_list opt_drop_behavior
				{
					n := &DropStmt{}

					n.RemoveType = ObjectType($2)
					n.MissingOk = false
					n.Objects = $3
					n.Behavior = DropBehavior($4)
					n.Concurrent = false
					$$ = n
				}
			| DROP drop_type_name IF_P EXISTS name_list opt_drop_behavior
				{
					n := &DropStmt{}

					n.RemoveType = ObjectType($2)
					n.MissingOk = true
					n.Objects = $5
					n.Behavior = DropBehavior($6)
					n.Concurrent = false
					$$ = n
				}
			| DROP drop_type_name name_list opt_drop_behavior
				{
					n := &DropStmt{}

					n.RemoveType = ObjectType($2)
					n.MissingOk = false
					n.Objects = $3
					n.Behavior = DropBehavior($4)
					n.Concurrent = false
					$$ = n
				}
			| DROP object_type_name_on_any_name name ON any_name opt_drop_behavior
				{
					n := &DropStmt{}

					n.RemoveType = ObjectType($2)
					n.Objects = []Node{listNode(append($5, makeString($3, @3)))}
					n.Behavior = DropBehavior($6)
					n.MissingOk = false
					n.Concurrent = false
					$$ = n
				}
			| DROP object_type_name_on_any_name IF_P EXISTS name ON any_name opt_drop_behavior
				{
					n := &DropStmt{}

					n.RemoveType = ObjectType($2)
					n.Objects = []Node{listNode(append($7, makeString($5, @5)))}
					n.Behavior = DropBehavior($8)
					n.MissingOk = true
					n.Concurrent = false
					$$ = n
				}
			| DROP TYPE_P type_name_list opt_drop_behavior
				{
					n := &DropStmt{}

					n.RemoveType = OBJECT_TYPE
					n.MissingOk = false
					n.Objects = $3
					n.Behavior = DropBehavior($4)
					n.Concurrent = false
					$$ = n
				}
			| DROP TYPE_P IF_P EXISTS type_name_list opt_drop_behavior
				{
					n := &DropStmt{}

					n.RemoveType = OBJECT_TYPE
					n.MissingOk = true
					n.Objects = $5
					n.Behavior = DropBehavior($6)
					n.Concurrent = false
					$$ = n
				}
			| DROP DOMAIN_P type_name_list opt_drop_behavior
				{
					n := &DropStmt{}

					n.RemoveType = OBJECT_DOMAIN
					n.MissingOk = false
					n.Objects = $3
					n.Behavior = DropBehavior($4)
					n.Concurrent = false
					$$ = n
				}
			| DROP DOMAIN_P IF_P EXISTS type_name_list opt_drop_behavior
				{
					n := &DropStmt{}

					n.RemoveType = OBJECT_DOMAIN
					n.MissingOk = true
					n.Objects = $5
					n.Behavior = DropBehavior($6)
					n.Concurrent = false
					$$ = n
				}
			| DROP INDEX CONCURRENTLY any_name_list opt_drop_behavior
				{
					n := &DropStmt{}

					n.RemoveType = OBJECT_INDEX
					n.MissingOk = false
					n.Objects = $4
					n.Behavior = DropBehavior($5)
					n.Concurrent = true
					$$ = n
				}
			| DROP INDEX CONCURRENTLY IF_P EXISTS any_name_list opt_drop_behavior
				{
					n := &DropStmt{}

					n.RemoveType = OBJECT_INDEX
					n.MissingOk = true
					n.Objects = $6
					n.Behavior = DropBehavior($7)
					n.Concurrent = true
					$$ = n
				}
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
			any_name								{ $$ = []Node{listNode($1)} }
			| any_name_list ',' any_name			{ $$ = append($1, listNode($3)) }
		;

any_name:	ColId						{ $$ = []Node{makeString($1, @1)} }
			| ColId attrs				{ $$ = append([]Node{makeString($1, @1)}, $2...) }
		;

attrs:		'.' attr_name
					{ $$ = []Node{makeString($2, @2)} }
			| attrs '.' attr_name
					{ $$ = append($1, makeString($3, @3)) }
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
				{
					n := &TruncateStmt{}

					n.Relations = $3
					n.RestartSeqs = $4
					n.Behavior = DropBehavior($5)
					$$ = n
				}
		;

opt_restart_seqs:
			CONTINUE_P IDENTITY_P		{ $$ = false }
			| RESTART IDENTITY_P		{ $$ = true }
			| /* EMPTY */				{ $$ = false }
		;

