/* gram.y lines 911-2072 */

/*
 *	The target production for the whole parse.
 *
 * Ordinarily we parse a list of statements, but if we see one of the
 * special MODE_XXX symbols as first token, we parse something else.
 * The options here correspond to enum RawParseMode, which see for details.
 */
parse_toplevel:
			stmtmulti
			{ p.result = $1 }
			| MODE_TYPE_NAME Typename
			{ p.result = []Node{$2} }
			| MODE_PLPGSQL_EXPR PLpgSQL_Expr
			{ p.result = []Node{makeRawStmt($2, 0)} }
			| MODE_PLPGSQL_ASSIGN1 PLAssignStmt
			{
				n := as[*PLAssignStmt]($2)

				n.Nnames = 1
				p.result = []Node{makeRawStmt(n, 0)}
			}
			| MODE_PLPGSQL_ASSIGN2 PLAssignStmt
			{
				n := as[*PLAssignStmt]($2)

				n.Nnames = 2
				p.result = []Node{makeRawStmt(n, 0)}
			}
			| MODE_PLPGSQL_ASSIGN3 PLAssignStmt
			{
				n := as[*PLAssignStmt]($2)

				n.Nnames = 3
				p.result = []Node{makeRawStmt(n, 0)}
			}
		;

/*
 * At top level, we wrap each stmt with a RawStmt node carrying start location
 * and length of the stmt's text.  Notice that the start loc/len are driven
 * entirely from semicolon locations (@2).  It would seem natural to use
 * @1 or @3 to get the true start location of a stmt, but that doesn't work
 * for statements that can start with empty nonterminals (opt_with_clause is
 * the main offender here); as noted in the comments for YYLLOC_DEFAULT,
 * we'd get -1 for the location in such cases.
 * We also take care to discard empty statements entirely.
 */
stmtmulti:	stmtmulti ';' toplevel_stmt
				{
					if $1 != nil {
						// update length of previous stmt
						updateRawStmtEnd(as[*RawStmt]($1[len($1)-1]), @2)
					}
					if $3 != nil {
						$$ = append($1, makeRawStmt($3, @2+1))
					} else {
						$$ = $1
					}
				}
			| toplevel_stmt
				{
					if $1 != nil {
						$$ = []Node{makeRawStmt($1, 0)}
					} else {
						$$ = nil
					}
				}
		;

/*
 * toplevel_stmt includes BEGIN and END.  stmt does not include them, because
 * those words have different meanings in function bodies.
 */
toplevel_stmt:
			stmt
			| TransactionStmtLegacy
		;

stmt:
			AlterEventTrigStmt
			| AlterCollationStmt
			| AlterDatabaseStmt
			| AlterDatabaseSetStmt
			| AlterDefaultPrivilegesStmt
			| AlterDomainStmt
			| AlterEnumStmt
			| AlterExtensionStmt
			| AlterExtensionContentsStmt
			| AlterFdwStmt
			| AlterForeignServerStmt
			| AlterFunctionStmt
			| AlterGroupStmt
			| AlterObjectDependsStmt
			| AlterObjectSchemaStmt
			| AlterOwnerStmt
			| AlterOperatorStmt
			| AlterTypeStmt
			| AlterPolicyStmt
			| AlterSeqStmt
			| AlterSystemStmt
			| AlterTableStmt
			| AlterTblSpcStmt
			| AlterCompositeTypeStmt
			| AlterPublicationStmt
			| AlterRoleSetStmt
			| AlterRoleStmt
			| AlterSubscriptionStmt
			| AlterStatsStmt
			| AlterTSConfigurationStmt
			| AlterTSDictionaryStmt
			| AlterUserMappingStmt
			| AnalyzeStmt
			| CallStmt
			| CheckPointStmt
			| ClosePortalStmt
			| ClusterStmt
			| CommentStmt
			| ConstraintsSetStmt
			| CopyStmt
			| CreateAmStmt
			| CreateAsStmt
			| CreateAssertionStmt
			| CreateCastStmt
			| CreateConversionStmt
			| CreateDomainStmt
			| CreateExtensionStmt
			| CreateFdwStmt
			| CreateForeignServerStmt
			| CreateForeignTableStmt
			| CreateFunctionStmt
			| CreateGroupStmt
			| CreateMatViewStmt
			| CreateOpClassStmt
			| CreateOpFamilyStmt
			| CreatePublicationStmt
			| AlterOpFamilyStmt
			| CreatePolicyStmt
			| CreatePLangStmt
			| CreateSchemaStmt
			| CreateSeqStmt
			| CreateStmt
			| CreateSubscriptionStmt
			| CreateStatsStmt
			| CreateTableSpaceStmt
			| CreateTransformStmt
			| CreateTrigStmt
			| CreateEventTrigStmt
			| CreateRoleStmt
			| CreateUserStmt
			| CreateUserMappingStmt
			| CreatedbStmt
			| DeallocateStmt
			| DeclareCursorStmt
			| DefineStmt
			| DeleteStmt
			| DiscardStmt
			| DoStmt
			| DropCastStmt
			| DropOpClassStmt
			| DropOpFamilyStmt
			| DropOwnedStmt
			| DropStmt
			| DropSubscriptionStmt
			| DropTableSpaceStmt
			| DropTransformStmt
			| DropRoleStmt
			| DropUserMappingStmt
			| DropdbStmt
			| ExecuteStmt
			| ExplainStmt
			| FetchStmt
			| GrantStmt
			| GrantRoleStmt
			| ImportForeignSchemaStmt
			| IndexStmt
			| InsertStmt
			| ListenStmt
			| RefreshMatViewStmt
			| LoadStmt
			| LockStmt
			| MergeStmt
			| NotifyStmt
			| PrepareStmt
			| ReassignOwnedStmt
			| ReindexStmt
			| RemoveAggrStmt
			| RemoveFuncStmt
			| RemoveOperStmt
			| RenameStmt
			| RevokeStmt
			| RevokeRoleStmt
			| RuleStmt
			| SecLabelStmt
			| SelectStmt
			| TransactionStmt
			| TruncateStmt
			| UnlistenStmt
			| UpdateStmt
			| VacuumStmt
			| VariableResetStmt
			| VariableSetStmt
			| VariableShowStmt
			| ViewStmt
			| /*EMPTY*/
				{ $$ = nil }
		;

/*
 * Generic supporting productions for DDL
 */
opt_single_name:
			ColId							{ $$ = $1 }
			| /* EMPTY */					{ $$ = "" }
		;

opt_qualified_name:
			any_name						{ $$ = $1 }
			| /*EMPTY*/						{ $$ = nil }
		;

opt_concurrently:
			CONCURRENTLY					{ $$ = true }
			| /*EMPTY*/						{ $$ = false }
		;

opt_drop_behavior:
			CASCADE							{ $$ = int32(DROP_CASCADE) }
			| RESTRICT						{ $$ = int32(DROP_RESTRICT) }
			| /* EMPTY */					{ $$ = int32(DROP_RESTRICT) /* default */ }
		;

/*****************************************************************************
 *
 * CALL statement
 *
 *****************************************************************************/

CallStmt:	CALL func_application
				{
					n := &CallStmt{}

					n.Funccall = as[*FuncCall]($2)
					$$ = n
				}
		;

/*****************************************************************************
 *
 * Create a new Postgres DBMS role
 *
 *****************************************************************************/

CreateRoleStmt:
			CREATE ROLE RoleId opt_with OptRoleList
				{
					n := &CreateRoleStmt{}

					n.StmtType = ROLESTMT_ROLE
					n.Role = $3
					n.Options = $5
					$$ = n
				}
		;


opt_with:	WITH
			| WITH_LA
			| /*EMPTY*/
		;

/*
 * Options for CREATE ROLE and ALTER ROLE (also used by CREATE/ALTER USER
 * for backwards compatibility).  Note: the only option required by SQL99
 * is "WITH ADMIN name".
 */
OptRoleList:
			OptRoleList CreateOptRoleElem			{ $$ = append($1, $2) }
			| /* EMPTY */							{ $$ = nil }
		;

AlterOptRoleList:
			AlterOptRoleList AlterOptRoleElem		{ $$ = append($1, $2) }
			| /* EMPTY */							{ $$ = nil }
		;

AlterOptRoleElem:
			PASSWORD Sconst
				{ $$ = makeDefElem("password", makeString($2, @2), @1) }
			| PASSWORD NULL_P
				{ $$ = makeDefElem("password", nil, @1) }
			| ENCRYPTED PASSWORD Sconst
				{
					/*
					 * These days, passwords are always stored in encrypted
					 * form, so there is no difference between PASSWORD and
					 * ENCRYPTED PASSWORD.
					 */
					$$ = makeDefElem("password", makeString($3, @3), @1)
				}
			| UNENCRYPTED PASSWORD Sconst
				{ p.fail(@1, "UNENCRYPTED PASSWORD is no longer supported") }
			| INHERIT
				{ $$ = makeDefElem("inherit", makeBoolean(true), @1) }
			| CONNECTION LIMIT SignedIconst
				{ $$ = makeDefElem("connectionlimit", makeInteger($3), @1) }
			| VALID UNTIL Sconst
				{ $$ = makeDefElem("validUntil", makeString($3, @3), @1) }
		/*	Supported but not documented for roles, for use by ALTER GROUP. */
			| USER role_list
				{ $$ = makeDefElem("rolemembers", listNode($2), @1) }
			| IDENT
				{
					/*
					 * We handle identifiers that aren't parser keywords with
					 * the following special-case codes, to avoid bloating the
					 * size of the main parser.
					 */
					switch $1 {
					case "superuser":
						$$ = makeDefElem("superuser", makeBoolean(true), @1)
					case "nosuperuser":
						$$ = makeDefElem("superuser", makeBoolean(false), @1)
					case "createrole":
						$$ = makeDefElem("createrole", makeBoolean(true), @1)
					case "nocreaterole":
						$$ = makeDefElem("createrole", makeBoolean(false), @1)
					case "replication":
						$$ = makeDefElem("isreplication", makeBoolean(true), @1)
					case "noreplication":
						$$ = makeDefElem("isreplication", makeBoolean(false), @1)
					case "createdb":
						$$ = makeDefElem("createdb", makeBoolean(true), @1)
					case "nocreatedb":
						$$ = makeDefElem("createdb", makeBoolean(false), @1)
					case "login":
						$$ = makeDefElem("canlogin", makeBoolean(true), @1)
					case "nologin":
						$$ = makeDefElem("canlogin", makeBoolean(false), @1)
					case "bypassrls":
						$$ = makeDefElem("bypassrls", makeBoolean(true), @1)
					case "nobypassrls":
						$$ = makeDefElem("bypassrls", makeBoolean(false), @1)
					case "noinherit":
						/*
						 * Note that INHERIT is a keyword, so it's handled by main parser, but
						 * NOINHERIT is handled here.
						 */
						$$ = makeDefElem("inherit", makeBoolean(false), @1)
					default:
						p.fail(@1, fmt.Sprintf("unrecognized role option \"%s\"", $1))
					}
				}
		;

CreateOptRoleElem:
			AlterOptRoleElem			{ $$ = $1 }
			/* The following are not supported by ALTER ROLE/USER/GROUP */
			| SYSID Iconst
				{ $$ = makeDefElem("sysid", makeInteger($2), @1) }
			| ADMIN role_list
				{ $$ = makeDefElem("adminmembers", listNode($2), @1) }
			| ROLE role_list
				{ $$ = makeDefElem("rolemembers", listNode($2), @1) }
			| IN_P ROLE role_list
				{ $$ = makeDefElem("addroleto", listNode($3), @1) }
			| IN_P GROUP_P role_list
				{ $$ = makeDefElem("addroleto", listNode($3), @1) }
		;


/*****************************************************************************
 *
 * Create a new Postgres DBMS user (role with implied login ability)
 *
 *****************************************************************************/

CreateUserStmt:
			CREATE USER RoleId opt_with OptRoleList
				{
					n := &CreateRoleStmt{}

					n.StmtType = ROLESTMT_USER
					n.Role = $3
					n.Options = $5
					$$ = n
				}
		;


/*****************************************************************************
 *
 * Alter a postgresql DBMS role
 *
 *****************************************************************************/

AlterRoleStmt:
			ALTER ROLE RoleSpec opt_with AlterOptRoleList
				 {
				 	n := &AlterRoleStmt{}

				 	n.Role = as[*RoleSpec]($3)
				 	n.Action = +1 /* add, if there are members */
				 	n.Options = $5
				 	$$ = n
				 }
			| ALTER USER RoleSpec opt_with AlterOptRoleList
				 {
				 	n := &AlterRoleStmt{}

				 	n.Role = as[*RoleSpec]($3)
				 	n.Action = +1 /* add, if there are members */
				 	n.Options = $5
				 	$$ = n
				 }
		;

opt_in_database:
			   /* EMPTY */					{ $$ = "" }
			| IN_P DATABASE name	{ $$ = $3 }
		;

AlterRoleSetStmt:
			ALTER ROLE RoleSpec opt_in_database SetResetClause
				{
					n := &AlterRoleSetStmt{}

					n.Role = as[*RoleSpec]($3)
					n.Database = $4
					n.Setstmt = as[*VariableSetStmt]($5)
					$$ = n
				}
			| ALTER ROLE ALL opt_in_database SetResetClause
				{
					n := &AlterRoleSetStmt{}

					n.Role = nil
					n.Database = $4
					n.Setstmt = as[*VariableSetStmt]($5)
					$$ = n
				}
			| ALTER USER RoleSpec opt_in_database SetResetClause
				{
					n := &AlterRoleSetStmt{}

					n.Role = as[*RoleSpec]($3)
					n.Database = $4
					n.Setstmt = as[*VariableSetStmt]($5)
					$$ = n
				}
			| ALTER USER ALL opt_in_database SetResetClause
				{
					n := &AlterRoleSetStmt{}

					n.Role = nil
					n.Database = $4
					n.Setstmt = as[*VariableSetStmt]($5)
					$$ = n
				}
		;


/*****************************************************************************
 *
 * Drop a postgresql DBMS role
 *
 * XXX Ideally this would have CASCADE/RESTRICT options, but a role
 * might own objects in multiple databases, and there is presently no way to
 * implement cascading to other databases.  So we always behave as RESTRICT.
 *****************************************************************************/

DropRoleStmt:
			DROP ROLE role_list
				{
					n := &DropRoleStmt{}

					n.MissingOk = false
					n.Roles = $3
					$$ = n
				}
			| DROP ROLE IF_P EXISTS role_list
				{
					n := &DropRoleStmt{}

					n.MissingOk = true
					n.Roles = $5
					$$ = n
				}
			| DROP USER role_list
				{
					n := &DropRoleStmt{}

					n.MissingOk = false
					n.Roles = $3
					$$ = n
				}
			| DROP USER IF_P EXISTS role_list
				{
					n := &DropRoleStmt{}

					n.Roles = $5
					n.MissingOk = true
					$$ = n
				}
			| DROP GROUP_P role_list
				{
					n := &DropRoleStmt{}

					n.MissingOk = false
					n.Roles = $3
					$$ = n
				}
			| DROP GROUP_P IF_P EXISTS role_list
				{
					n := &DropRoleStmt{}

					n.MissingOk = true
					n.Roles = $5
					$$ = n
				}
			;


/*****************************************************************************
 *
 * Create a postgresql group (role without login ability)
 *
 *****************************************************************************/

CreateGroupStmt:
			CREATE GROUP_P RoleId opt_with OptRoleList
				{
					n := &CreateRoleStmt{}

					n.StmtType = ROLESTMT_GROUP
					n.Role = $3
					n.Options = $5
					$$ = n
				}
		;


/*****************************************************************************
 *
 * Alter a postgresql group
 *
 *****************************************************************************/

AlterGroupStmt:
			ALTER GROUP_P RoleSpec add_drop USER role_list
				{
					n := &AlterRoleStmt{}

					n.Role = as[*RoleSpec]($3)
					n.Action = $4
					n.Options = []Node{makeDefElem("rolemembers", listNode($6), @6)}
					$$ = n
				}
		;

add_drop:	ADD_P									{ $$ = 1 }
			| DROP									{ $$ = -1 }
		;


/*****************************************************************************
 *
 * Manipulate a schema
 *
 *****************************************************************************/

CreateSchemaStmt:
			CREATE SCHEMA opt_single_name AUTHORIZATION RoleSpec OptSchemaEltList
				{
					n := &CreateSchemaStmt{}

					/* One can omit the schema name or the authorization id. */
					n.Schemaname = $3
					n.Authrole = as[*RoleSpec]($5)
					n.SchemaElts = $6
					n.IfNotExists = false
					$$ = n
				}
			| CREATE SCHEMA ColId OptSchemaEltList
				{
					n := &CreateSchemaStmt{}

					/* ...but not both */
					n.Schemaname = $3
					n.Authrole = nil
					n.SchemaElts = $4
					n.IfNotExists = false
					$$ = n
				}
			| CREATE SCHEMA IF_P NOT EXISTS opt_single_name AUTHORIZATION RoleSpec OptSchemaEltList
				{
					n := &CreateSchemaStmt{}

					/* schema name can be omitted here, too */
					n.Schemaname = $6
					n.Authrole = as[*RoleSpec]($8)
					if $9 != nil {
						p.fail(@9, "CREATE SCHEMA IF NOT EXISTS cannot include schema elements")
					}
					n.SchemaElts = $9
					n.IfNotExists = true
					$$ = n
				}
			| CREATE SCHEMA IF_P NOT EXISTS ColId OptSchemaEltList
				{
					n := &CreateSchemaStmt{}

					/* ...but not here */
					n.Schemaname = $6
					n.Authrole = nil
					if $7 != nil {
						p.fail(@7, "CREATE SCHEMA IF NOT EXISTS cannot include schema elements")
					}
					n.SchemaElts = $7
					n.IfNotExists = true
					$$ = n
				}
		;

OptSchemaEltList:
			OptSchemaEltList schema_stmt
				{
					if @$ < 0 { /* see comments for YYLLOC_DEFAULT */
						@$ = @2
					}
					$$ = append($1, $2)
				}
			| /* EMPTY */
				{ $$ = nil }
		;

/*
 *	schema_stmt are the ones that can show up inside a CREATE SCHEMA
 *	statement (in addition to by themselves).
 */
schema_stmt:
			CreateStmt
			| IndexStmt
			| CreateSeqStmt
			| CreateTrigStmt
			| GrantStmt
			| ViewStmt
		;


/*****************************************************************************
 *
 * Set PG internal variable
 *	  SET name TO 'var_value'
 * Include SQL syntax (thomas 1997-10-22):
 *	  SET TIME ZONE 'var_value'
 *
 *****************************************************************************/

VariableSetStmt:
			SET set_rest
				{
					n := as[*VariableSetStmt]($2)

					n.IsLocal = false
					$$ = n
				}
			| SET LOCAL set_rest
				{
					n := as[*VariableSetStmt]($3)

					n.IsLocal = true
					$$ = n
				}
			| SET SESSION set_rest
				{
					n := as[*VariableSetStmt]($3)

					n.IsLocal = false
					$$ = n
				}
		;

set_rest:
			TRANSACTION transaction_mode_list
				{
					n := &VariableSetStmt{}

					n.Kind = VAR_SET_MULTI
					n.Name = "TRANSACTION"
					n.Args = $2
					$$ = n
				}
			| SESSION CHARACTERISTICS AS TRANSACTION transaction_mode_list
				{
					n := &VariableSetStmt{}

					n.Kind = VAR_SET_MULTI
					n.Name = "SESSION CHARACTERISTICS"
					n.Args = $5
					$$ = n
				}
			| set_rest_more
			;

generic_set:
			var_name TO var_list
				{
					n := &VariableSetStmt{}

					n.Kind = VAR_SET_VALUE
					n.Name = $1
					n.Args = $3
					$$ = n
				}
			| var_name '=' var_list
				{
					n := &VariableSetStmt{}

					n.Kind = VAR_SET_VALUE
					n.Name = $1
					n.Args = $3
					$$ = n
				}
			| var_name TO DEFAULT
				{
					n := &VariableSetStmt{}

					n.Kind = VAR_SET_DEFAULT
					n.Name = $1
					$$ = n
				}
			| var_name '=' DEFAULT
				{
					n := &VariableSetStmt{}

					n.Kind = VAR_SET_DEFAULT
					n.Name = $1
					$$ = n
				}
		;

set_rest_more:	/* Generic SET syntaxes: */
			generic_set							{ $$ = $1 }
			| var_name FROM CURRENT_P
				{
					n := &VariableSetStmt{}

					n.Kind = VAR_SET_CURRENT
					n.Name = $1
					$$ = n
				}
			/* Special syntaxes mandated by SQL standard: */
			| TIME ZONE zone_value
				{
					n := &VariableSetStmt{}

					n.Kind = VAR_SET_VALUE
					n.Name = "timezone"
					if $3 != nil {
						n.Args = []Node{$3}
					} else {
						n.Kind = VAR_SET_DEFAULT
					}
					$$ = n
				}
			| CATALOG_P Sconst
				{
					p.fail(@2, "current database cannot be changed")
					$$ = nil /*not reached*/
				}
			| SCHEMA Sconst
				{
					n := &VariableSetStmt{}

					n.Kind = VAR_SET_VALUE
					n.Name = "search_path"
					n.Args = []Node{makeStringConst($2, @2)}
					$$ = n
				}
			| NAMES opt_encoding
				{
					n := &VariableSetStmt{}

					n.Kind = VAR_SET_VALUE
					n.Name = "client_encoding"
					if $2 != "" {
						n.Args = []Node{makeStringConst($2, @2)}
					} else {
						n.Kind = VAR_SET_DEFAULT
					}
					$$ = n
				}
			| ROLE NonReservedWord_or_Sconst
				{
					n := &VariableSetStmt{}

					n.Kind = VAR_SET_VALUE
					n.Name = "role"
					n.Args = []Node{makeStringConst($2, @2)}
					$$ = n
				}
			| SESSION AUTHORIZATION NonReservedWord_or_Sconst
				{
					n := &VariableSetStmt{}

					n.Kind = VAR_SET_VALUE
					n.Name = "session_authorization"
					n.Args = []Node{makeStringConst($3, @3)}
					$$ = n
				}
			| SESSION AUTHORIZATION DEFAULT
				{
					n := &VariableSetStmt{}

					n.Kind = VAR_SET_DEFAULT
					n.Name = "session_authorization"
					$$ = n
				}
			| XML_P OPTION document_or_content
				{
					n := &VariableSetStmt{}

					n.Kind = VAR_SET_VALUE
					n.Name = "xmloption"
					if XmlOptionType($3) == XMLOPTION_DOCUMENT {
						n.Args = []Node{makeStringConst("DOCUMENT", @3)}
					} else {
						n.Args = []Node{makeStringConst("CONTENT", @3)}
					}
					$$ = n
				}
			/* Special syntaxes invented by PostgreSQL: */
			| TRANSACTION SNAPSHOT Sconst
				{
					n := &VariableSetStmt{}

					n.Kind = VAR_SET_MULTI
					n.Name = "TRANSACTION SNAPSHOT"
					n.Args = []Node{makeStringConst($3, @3)}
					$$ = n
				}
		;

var_name:	ColId								{ $$ = $1 }
			| var_name '.' ColId
				{ $$ = $1 + "." + $3 }
		;

var_list:	var_value								{ $$ = []Node{$1} }
			| var_list ',' var_value				{ $$ = append($1, $3) }
		;

var_value:	opt_boolean_or_string
				{ $$ = makeStringConst($1, @1) }
			| NumericOnly
				{ $$ = makeAConst($1, @1) }
		;

iso_level:	READ UNCOMMITTED						{ $$ = "read uncommitted" }
			| READ COMMITTED						{ $$ = "read committed" }
			| REPEATABLE READ						{ $$ = "repeatable read" }
			| SERIALIZABLE							{ $$ = "serializable" }
		;

opt_boolean_or_string:
			TRUE_P									{ $$ = "true" }
			| FALSE_P								{ $$ = "false" }
			| ON									{ $$ = "on" }
			/*
			 * OFF is also accepted as a boolean value, but is handled by
			 * the NonReservedWord rule.  The action for booleans and strings
			 * is the same, so we don't need to distinguish them here.
			 */
			| NonReservedWord_or_Sconst				{ $$ = $1 }
		;

/* Timezone values can be:
 * - a string such as 'pst8pdt'
 * - an identifier such as "pst8pdt"
 * - an integer or floating point number
 * - a time interval per SQL99
 * ColId gives reduce/reduce errors against ConstInterval and LOCAL,
 * so use IDENT (meaning we reject anything that is a key word).
 */
zone_value:
			Sconst
				{ $$ = makeStringConst($1, @1) }
			| IDENT
				{ $$ = makeStringConst($1, @1) }
			| ConstInterval Sconst opt_interval
				{
					t := as[*TypeName]($1)

					if $3 != nil {
						n := as[*A_Const]($3[0])

						if (as[*Integer](n.Val).Ival &^ (intervalMask(dtHour) | intervalMask(dtMinute))) != 0 {
							p.fail(@3, "time zone interval must be HOUR or HOUR TO MINUTE")
						}
					}
					t.Typmods = $3
					$$ = makeStringConstCast($2, @2, t)
				}
			| ConstInterval '(' Iconst ')' Sconst
				{
					t := as[*TypeName]($1)

					t.Typmods = []Node{makeIntConst(intervalFullRange, -1),
						makeIntConst($3, @3)}
					$$ = makeStringConstCast($5, @5, t)
				}
			| NumericOnly							{ $$ = makeAConst($1, @1) }
			| DEFAULT								{ $$ = nil }
			| LOCAL									{ $$ = nil }
		;

opt_encoding:
			Sconst									{ $$ = $1 }
			| DEFAULT								{ $$ = "" }
			| /*EMPTY*/								{ $$ = "" }
		;

NonReservedWord_or_Sconst:
			NonReservedWord							{ $$ = $1 }
			| Sconst								{ $$ = $1 }
		;

VariableResetStmt:
			RESET reset_rest						{ $$ = $2 }
		;

reset_rest:
			generic_reset							{ $$ = $1 }
			| TIME ZONE
				{
					n := &VariableSetStmt{}

					n.Kind = VAR_RESET
					n.Name = "timezone"
					$$ = n
				}
			| TRANSACTION ISOLATION LEVEL
				{
					n := &VariableSetStmt{}

					n.Kind = VAR_RESET
					n.Name = "transaction_isolation"
					$$ = n
				}
			| SESSION AUTHORIZATION
				{
					n := &VariableSetStmt{}

					n.Kind = VAR_RESET
					n.Name = "session_authorization"
					$$ = n
				}
		;

generic_reset:
			var_name
				{
					n := &VariableSetStmt{}

					n.Kind = VAR_RESET
					n.Name = $1
					$$ = n
				}
			| ALL
				{
					n := &VariableSetStmt{}

					n.Kind = VAR_RESET_ALL
					$$ = n
				}
		;

/* SetResetClause allows SET or RESET without LOCAL */
SetResetClause:
			SET set_rest					{ $$ = $2 }
			| VariableResetStmt				{ $$ = $1 }
		;

/* SetResetClause allows SET or RESET without LOCAL */
FunctionSetResetClause:
			SET set_rest_more				{ $$ = $2 }
			| VariableResetStmt				{ $$ = $1 }
		;


VariableShowStmt:
			SHOW var_name
				{
					n := &VariableShowStmt{}

					n.Name = $2
					$$ = n
				}
			| SHOW TIME ZONE
				{
					n := &VariableShowStmt{}

					n.Name = "timezone"
					$$ = n
				}
			| SHOW TRANSACTION ISOLATION LEVEL
				{
					n := &VariableShowStmt{}

					n.Name = "transaction_isolation"
					$$ = n
				}
			| SHOW SESSION AUTHORIZATION
				{
					n := &VariableShowStmt{}

					n.Name = "session_authorization"
					$$ = n
				}
			| SHOW ALL
				{
					n := &VariableShowStmt{}

					n.Name = "all"
					$$ = n
				}
		;


ConstraintsSetStmt:
			SET CONSTRAINTS constraints_set_list constraints_set_mode
				{
					n := &ConstraintsSetStmt{}

					n.Constraints = $3
					n.Deferred = $4
					$$ = n
				}
		;

constraints_set_list:
			ALL										{ $$ = nil }
			| qualified_name_list					{ $$ = $1 }
		;

constraints_set_mode:
			DEFERRED								{ $$ = true }
			| IMMEDIATE								{ $$ = false }
		;


/*
 * Checkpoint statement
 */
CheckPointStmt:
			CHECKPOINT
				{
					n := &CheckPointStmt{}

					$$ = n
				}
		;


/*****************************************************************************
 *
 * DISCARD { ALL | TEMP | PLANS | SEQUENCES }
 *
 *****************************************************************************/

DiscardStmt:
			DISCARD ALL
				{
					n := &DiscardStmt{}

					n.Target = DISCARD_ALL
					$$ = n
				}
			| DISCARD TEMP
				{
					n := &DiscardStmt{}

					n.Target = DISCARD_TEMP
					$$ = n
				}
			| DISCARD TEMPORARY
				{
					n := &DiscardStmt{}

					n.Target = DISCARD_TEMP
					$$ = n
				}
			| DISCARD PLANS
				{
					n := &DiscardStmt{}

					n.Target = DISCARD_PLANS
					$$ = n
				}
			| DISCARD SEQUENCES
				{
					n := &DiscardStmt{}

					n.Target = DISCARD_SEQUENCES
					$$ = n
				}

		;

