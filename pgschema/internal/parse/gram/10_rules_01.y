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
			| /* EMPTY */					{ /*C $$ = DROP_RESTRICT; /* default * / */ }
		;

/*****************************************************************************
 *
 * CALL statement
 *
 *****************************************************************************/

CallStmt:	CALL func_application
				{ /*C
					CallStmt   *n = makeNode(CallStmt);

					n->funccall = castNode(FuncCall, $2);
					$$ = (Node *) n;
				*/ }
		;

/*****************************************************************************
 *
 * Create a new Postgres DBMS role
 *
 *****************************************************************************/

CreateRoleStmt:
			CREATE ROLE RoleId opt_with OptRoleList
				{ /*C
					CreateRoleStmt *n = makeNode(CreateRoleStmt);

					n->stmt_type = ROLESTMT_ROLE;
					n->role = $3;
					n->options = $5;
					$$ = (Node *) n;
				*/ }
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
				{ /*C
					$$ = makeDefElem("password",
									 (Node *) makeString($2), @1);
				*/ }
			| PASSWORD NULL_P
				{ /*C
					$$ = makeDefElem("password", NULL, @1);
				*/ }
			| ENCRYPTED PASSWORD Sconst
				{ /*C
					/*
					 * These days, passwords are always stored in encrypted
					 * form, so there is no difference between PASSWORD and
					 * ENCRYPTED PASSWORD.
					 * /
					$$ = makeDefElem("password",
									 (Node *) makeString($3), @1);
				*/ }
			| UNENCRYPTED PASSWORD Sconst
				{ /*C
					ereport(ERROR,
							(errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
							 errmsg("UNENCRYPTED PASSWORD is no longer supported"),
							 errhint("Remove UNENCRYPTED to store the password in encrypted form instead."),
							 parser_errposition(@1)));
				*/ }
			| INHERIT
				{ /*C
					$$ = makeDefElem("inherit", (Node *) makeBoolean(true), @1);
				*/ }
			| CONNECTION LIMIT SignedIconst
				{ /*C
					$$ = makeDefElem("connectionlimit", (Node *) makeInteger($3), @1);
				*/ }
			| VALID UNTIL Sconst
				{ /*C
					$$ = makeDefElem("validUntil", (Node *) makeString($3), @1);
				*/ }
		/*	Supported but not documented for roles, for use by ALTER GROUP. */
			| USER role_list
				{ /*C
					$$ = makeDefElem("rolemembers", (Node *) $2, @1);
				*/ }
			| IDENT
				{ /*C
					/*
					 * We handle identifiers that aren't parser keywords with
					 * the following special-case codes, to avoid bloating the
					 * size of the main parser.
					 * /
					if (strcmp($1, "superuser") == 0)
						$$ = makeDefElem("superuser", (Node *) makeBoolean(true), @1);
					else if (strcmp($1, "nosuperuser") == 0)
						$$ = makeDefElem("superuser", (Node *) makeBoolean(false), @1);
					else if (strcmp($1, "createrole") == 0)
						$$ = makeDefElem("createrole", (Node *) makeBoolean(true), @1);
					else if (strcmp($1, "nocreaterole") == 0)
						$$ = makeDefElem("createrole", (Node *) makeBoolean(false), @1);
					else if (strcmp($1, "replication") == 0)
						$$ = makeDefElem("isreplication", (Node *) makeBoolean(true), @1);
					else if (strcmp($1, "noreplication") == 0)
						$$ = makeDefElem("isreplication", (Node *) makeBoolean(false), @1);
					else if (strcmp($1, "createdb") == 0)
						$$ = makeDefElem("createdb", (Node *) makeBoolean(true), @1);
					else if (strcmp($1, "nocreatedb") == 0)
						$$ = makeDefElem("createdb", (Node *) makeBoolean(false), @1);
					else if (strcmp($1, "login") == 0)
						$$ = makeDefElem("canlogin", (Node *) makeBoolean(true), @1);
					else if (strcmp($1, "nologin") == 0)
						$$ = makeDefElem("canlogin", (Node *) makeBoolean(false), @1);
					else if (strcmp($1, "bypassrls") == 0)
						$$ = makeDefElem("bypassrls", (Node *) makeBoolean(true), @1);
					else if (strcmp($1, "nobypassrls") == 0)
						$$ = makeDefElem("bypassrls", (Node *) makeBoolean(false), @1);
					else if (strcmp($1, "noinherit") == 0)
					{
						/*
						 * Note that INHERIT is a keyword, so it's handled by main parser, but
						 * NOINHERIT is handled here.
						 * /
						$$ = makeDefElem("inherit", (Node *) makeBoolean(false), @1);
					}
					else
						ereport(ERROR,
								(errcode(ERRCODE_SYNTAX_ERROR),
								 errmsg("unrecognized role option \"%s\"", $1),
									 parser_errposition(@1)));
				*/ }
		;

CreateOptRoleElem:
			AlterOptRoleElem			{ $$ = $1 }
			/* The following are not supported by ALTER ROLE/USER/GROUP */
			| SYSID Iconst
				{ /*C
					$$ = makeDefElem("sysid", (Node *) makeInteger($2), @1);
				*/ }
			| ADMIN role_list
				{ /*C
					$$ = makeDefElem("adminmembers", (Node *) $2, @1);
				*/ }
			| ROLE role_list
				{ /*C
					$$ = makeDefElem("rolemembers", (Node *) $2, @1);
				*/ }
			| IN_P ROLE role_list
				{ /*C
					$$ = makeDefElem("addroleto", (Node *) $3, @1);
				*/ }
			| IN_P GROUP_P role_list
				{ /*C
					$$ = makeDefElem("addroleto", (Node *) $3, @1);
				*/ }
		;


/*****************************************************************************
 *
 * Create a new Postgres DBMS user (role with implied login ability)
 *
 *****************************************************************************/

CreateUserStmt:
			CREATE USER RoleId opt_with OptRoleList
				{ /*C
					CreateRoleStmt *n = makeNode(CreateRoleStmt);

					n->stmt_type = ROLESTMT_USER;
					n->role = $3;
					n->options = $5;
					$$ = (Node *) n;
				*/ }
		;


/*****************************************************************************
 *
 * Alter a postgresql DBMS role
 *
 *****************************************************************************/

AlterRoleStmt:
			ALTER ROLE RoleSpec opt_with AlterOptRoleList
				 { /*C
					AlterRoleStmt *n = makeNode(AlterRoleStmt);

					n->role = $3;
					n->action = +1;	/* add, if there are members * /
					n->options = $5;
					$$ = (Node *) n;
				 */ }
			| ALTER USER RoleSpec opt_with AlterOptRoleList
				 { /*C
					AlterRoleStmt *n = makeNode(AlterRoleStmt);

					n->role = $3;
					n->action = +1;	/* add, if there are members * /
					n->options = $5;
					$$ = (Node *) n;
				 */ }
		;

opt_in_database:
			   /* EMPTY */					{ $$ = "" }
			| IN_P DATABASE name	{ $$ = $3 }
		;

AlterRoleSetStmt:
			ALTER ROLE RoleSpec opt_in_database SetResetClause
				{ /*C
					AlterRoleSetStmt *n = makeNode(AlterRoleSetStmt);

					n->role = $3;
					n->database = $4;
					n->setstmt = $5;
					$$ = (Node *) n;
				*/ }
			| ALTER ROLE ALL opt_in_database SetResetClause
				{ /*C
					AlterRoleSetStmt *n = makeNode(AlterRoleSetStmt);

					n->role = NULL;
					n->database = $4;
					n->setstmt = $5;
					$$ = (Node *) n;
				*/ }
			| ALTER USER RoleSpec opt_in_database SetResetClause
				{ /*C
					AlterRoleSetStmt *n = makeNode(AlterRoleSetStmt);

					n->role = $3;
					n->database = $4;
					n->setstmt = $5;
					$$ = (Node *) n;
				*/ }
			| ALTER USER ALL opt_in_database SetResetClause
				{ /*C
					AlterRoleSetStmt *n = makeNode(AlterRoleSetStmt);

					n->role = NULL;
					n->database = $4;
					n->setstmt = $5;
					$$ = (Node *) n;
				*/ }
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
				{ /*C
					DropRoleStmt *n = makeNode(DropRoleStmt);

					n->missing_ok = false;
					n->roles = $3;
					$$ = (Node *) n;
				*/ }
			| DROP ROLE IF_P EXISTS role_list
				{ /*C
					DropRoleStmt *n = makeNode(DropRoleStmt);

					n->missing_ok = true;
					n->roles = $5;
					$$ = (Node *) n;
				*/ }
			| DROP USER role_list
				{ /*C
					DropRoleStmt *n = makeNode(DropRoleStmt);

					n->missing_ok = false;
					n->roles = $3;
					$$ = (Node *) n;
				*/ }
			| DROP USER IF_P EXISTS role_list
				{ /*C
					DropRoleStmt *n = makeNode(DropRoleStmt);

					n->roles = $5;
					n->missing_ok = true;
					$$ = (Node *) n;
				*/ }
			| DROP GROUP_P role_list
				{ /*C
					DropRoleStmt *n = makeNode(DropRoleStmt);

					n->missing_ok = false;
					n->roles = $3;
					$$ = (Node *) n;
				*/ }
			| DROP GROUP_P IF_P EXISTS role_list
				{ /*C
					DropRoleStmt *n = makeNode(DropRoleStmt);

					n->missing_ok = true;
					n->roles = $5;
					$$ = (Node *) n;
				*/ }
			;


/*****************************************************************************
 *
 * Create a postgresql group (role without login ability)
 *
 *****************************************************************************/

CreateGroupStmt:
			CREATE GROUP_P RoleId opt_with OptRoleList
				{ /*C
					CreateRoleStmt *n = makeNode(CreateRoleStmt);

					n->stmt_type = ROLESTMT_GROUP;
					n->role = $3;
					n->options = $5;
					$$ = (Node *) n;
				*/ }
		;


/*****************************************************************************
 *
 * Alter a postgresql group
 *
 *****************************************************************************/

AlterGroupStmt:
			ALTER GROUP_P RoleSpec add_drop USER role_list
				{ /*C
					AlterRoleStmt *n = makeNode(AlterRoleStmt);

					n->role = $3;
					n->action = $4;
					n->options = list_make1(makeDefElem("rolemembers",
														(Node *) $6, @6));
					$$ = (Node *) n;
				*/ }
		;

add_drop:	ADD_P									{ /*C $$ = +1; */ }
			| DROP									{ /*C $$ = -1; */ }
		;


/*****************************************************************************
 *
 * Manipulate a schema
 *
 *****************************************************************************/

CreateSchemaStmt:
			CREATE SCHEMA opt_single_name AUTHORIZATION RoleSpec OptSchemaEltList
				{ /*C
					CreateSchemaStmt *n = makeNode(CreateSchemaStmt);

					/* One can omit the schema name or the authorization id. * /
					n->schemaname = $3;
					n->authrole = $5;
					n->schemaElts = $6;
					n->if_not_exists = false;
					$$ = (Node *) n;
				*/ }
			| CREATE SCHEMA ColId OptSchemaEltList
				{ /*C
					CreateSchemaStmt *n = makeNode(CreateSchemaStmt);

					/* ...but not both * /
					n->schemaname = $3;
					n->authrole = NULL;
					n->schemaElts = $4;
					n->if_not_exists = false;
					$$ = (Node *) n;
				*/ }
			| CREATE SCHEMA IF_P NOT EXISTS opt_single_name AUTHORIZATION RoleSpec OptSchemaEltList
				{ /*C
					CreateSchemaStmt *n = makeNode(CreateSchemaStmt);

					/* schema name can be omitted here, too * /
					n->schemaname = $6;
					n->authrole = $8;
					if ($9 != NIL)
						ereport(ERROR,
								(errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
								 errmsg("CREATE SCHEMA IF NOT EXISTS cannot include schema elements"),
								 parser_errposition(@9)));
					n->schemaElts = $9;
					n->if_not_exists = true;
					$$ = (Node *) n;
				*/ }
			| CREATE SCHEMA IF_P NOT EXISTS ColId OptSchemaEltList
				{ /*C
					CreateSchemaStmt *n = makeNode(CreateSchemaStmt);

					/* ...but not here * /
					n->schemaname = $6;
					n->authrole = NULL;
					if ($7 != NIL)
						ereport(ERROR,
								(errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
								 errmsg("CREATE SCHEMA IF NOT EXISTS cannot include schema elements"),
								 parser_errposition(@7)));
					n->schemaElts = $7;
					n->if_not_exists = true;
					$$ = (Node *) n;
				*/ }
		;

OptSchemaEltList:
			OptSchemaEltList schema_stmt
				{ /*C
					if (@$ < 0)			/* see comments for YYLLOC_DEFAULT * /
						@$ = @2;
					$$ = lappend($1, $2);
				*/ }
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
				{ /*C
					VariableSetStmt *n = $2;

					n->is_local = false;
					$$ = (Node *) n;
				*/ }
			| SET LOCAL set_rest
				{ /*C
					VariableSetStmt *n = $3;

					n->is_local = true;
					$$ = (Node *) n;
				*/ }
			| SET SESSION set_rest
				{ /*C
					VariableSetStmt *n = $3;

					n->is_local = false;
					$$ = (Node *) n;
				*/ }
		;

set_rest:
			TRANSACTION transaction_mode_list
				{ /*C
					VariableSetStmt *n = makeNode(VariableSetStmt);

					n->kind = VAR_SET_MULTI;
					n->name = "TRANSACTION";
					n->args = $2;
					$$ = n;
				*/ }
			| SESSION CHARACTERISTICS AS TRANSACTION transaction_mode_list
				{ /*C
					VariableSetStmt *n = makeNode(VariableSetStmt);

					n->kind = VAR_SET_MULTI;
					n->name = "SESSION CHARACTERISTICS";
					n->args = $5;
					$$ = n;
				*/ }
			| set_rest_more
			;

generic_set:
			var_name TO var_list
				{ /*C
					VariableSetStmt *n = makeNode(VariableSetStmt);

					n->kind = VAR_SET_VALUE;
					n->name = $1;
					n->args = $3;
					$$ = n;
				*/ }
			| var_name '=' var_list
				{ /*C
					VariableSetStmt *n = makeNode(VariableSetStmt);

					n->kind = VAR_SET_VALUE;
					n->name = $1;
					n->args = $3;
					$$ = n;
				*/ }
			| var_name TO DEFAULT
				{ /*C
					VariableSetStmt *n = makeNode(VariableSetStmt);

					n->kind = VAR_SET_DEFAULT;
					n->name = $1;
					$$ = n;
				*/ }
			| var_name '=' DEFAULT
				{ /*C
					VariableSetStmt *n = makeNode(VariableSetStmt);

					n->kind = VAR_SET_DEFAULT;
					n->name = $1;
					$$ = n;
				*/ }
		;

set_rest_more:	/* Generic SET syntaxes: */
			generic_set							{ $$ = $1 }
			| var_name FROM CURRENT_P
				{ /*C
					VariableSetStmt *n = makeNode(VariableSetStmt);

					n->kind = VAR_SET_CURRENT;
					n->name = $1;
					$$ = n;
				*/ }
			/* Special syntaxes mandated by SQL standard: */
			| TIME ZONE zone_value
				{ /*C
					VariableSetStmt *n = makeNode(VariableSetStmt);

					n->kind = VAR_SET_VALUE;
					n->name = "timezone";
					if ($3 != NULL)
						n->args = list_make1($3);
					else
						n->kind = VAR_SET_DEFAULT;
					$$ = n;
				*/ }
			| CATALOG_P Sconst
				{ /*C
					ereport(ERROR,
							(errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
							 errmsg("current database cannot be changed"),
							 parser_errposition(@2)));
					$$ = NULL; /*not reached* /
				*/ }
			| SCHEMA Sconst
				{ /*C
					VariableSetStmt *n = makeNode(VariableSetStmt);

					n->kind = VAR_SET_VALUE;
					n->name = "search_path";
					n->args = list_make1(makeStringConst($2, @2));
					$$ = n;
				*/ }
			| NAMES opt_encoding
				{ /*C
					VariableSetStmt *n = makeNode(VariableSetStmt);

					n->kind = VAR_SET_VALUE;
					n->name = "client_encoding";
					if ($2 != NULL)
						n->args = list_make1(makeStringConst($2, @2));
					else
						n->kind = VAR_SET_DEFAULT;
					$$ = n;
				*/ }
			| ROLE NonReservedWord_or_Sconst
				{ /*C
					VariableSetStmt *n = makeNode(VariableSetStmt);

					n->kind = VAR_SET_VALUE;
					n->name = "role";
					n->args = list_make1(makeStringConst($2, @2));
					$$ = n;
				*/ }
			| SESSION AUTHORIZATION NonReservedWord_or_Sconst
				{ /*C
					VariableSetStmt *n = makeNode(VariableSetStmt);

					n->kind = VAR_SET_VALUE;
					n->name = "session_authorization";
					n->args = list_make1(makeStringConst($3, @3));
					$$ = n;
				*/ }
			| SESSION AUTHORIZATION DEFAULT
				{ /*C
					VariableSetStmt *n = makeNode(VariableSetStmt);

					n->kind = VAR_SET_DEFAULT;
					n->name = "session_authorization";
					$$ = n;
				*/ }
			| XML_P OPTION document_or_content
				{ /*C
					VariableSetStmt *n = makeNode(VariableSetStmt);

					n->kind = VAR_SET_VALUE;
					n->name = "xmloption";
					n->args = list_make1(makeStringConst($3 == XMLOPTION_DOCUMENT ? "DOCUMENT" : "CONTENT", @3));
					$$ = n;
				*/ }
			/* Special syntaxes invented by PostgreSQL: */
			| TRANSACTION SNAPSHOT Sconst
				{ /*C
					VariableSetStmt *n = makeNode(VariableSetStmt);

					n->kind = VAR_SET_MULTI;
					n->name = "TRANSACTION SNAPSHOT";
					n->args = list_make1(makeStringConst($3, @3));
					$$ = n;
				*/ }
		;

var_name:	ColId								{ $$ = $1 }
			| var_name '.' ColId
				{ /*C $$ = psprintf("%s.%s", $1, $3); */ }
		;

var_list:	var_value								{ $$ = []Node{$1} }
			| var_list ',' var_value				{ $$ = append($1, $3) }
		;

var_value:	opt_boolean_or_string
				{ /*C $$ = makeStringConst($1, @1); */ }
			| NumericOnly
				{ /*C $$ = makeAConst($1, @1); */ }
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
				{ /*C
					$$ = makeStringConst($1, @1);
				*/ }
			| IDENT
				{ /*C
					$$ = makeStringConst($1, @1);
				*/ }
			| ConstInterval Sconst opt_interval
				{ /*C
					TypeName   *t = $1;

					if ($3 != NIL)
					{
						A_Const	   *n = (A_Const *) linitial($3);

						if ((n->val.ival.ival & ~(INTERVAL_MASK(HOUR) | INTERVAL_MASK(MINUTE))) != 0)
							ereport(ERROR,
									(errcode(ERRCODE_SYNTAX_ERROR),
									 errmsg("time zone interval must be HOUR or HOUR TO MINUTE"),
									 parser_errposition(@3)));
					}
					t->typmods = $3;
					$$ = makeStringConstCast($2, @2, t);
				*/ }
			| ConstInterval '(' Iconst ')' Sconst
				{ /*C
					TypeName   *t = $1;

					t->typmods = list_make2(makeIntConst(INTERVAL_FULL_RANGE, -1),
											makeIntConst($3, @3));
					$$ = makeStringConstCast($5, @5, t);
				*/ }
			| NumericOnly							{ /*C $$ = makeAConst($1, @1); */ }
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
				{ /*C
					VariableSetStmt *n = makeNode(VariableSetStmt);

					n->kind = VAR_RESET;
					n->name = "timezone";
					$$ = n;
				*/ }
			| TRANSACTION ISOLATION LEVEL
				{ /*C
					VariableSetStmt *n = makeNode(VariableSetStmt);

					n->kind = VAR_RESET;
					n->name = "transaction_isolation";
					$$ = n;
				*/ }
			| SESSION AUTHORIZATION
				{ /*C
					VariableSetStmt *n = makeNode(VariableSetStmt);

					n->kind = VAR_RESET;
					n->name = "session_authorization";
					$$ = n;
				*/ }
		;

generic_reset:
			var_name
				{ /*C
					VariableSetStmt *n = makeNode(VariableSetStmt);

					n->kind = VAR_RESET;
					n->name = $1;
					$$ = n;
				*/ }
			| ALL
				{ /*C
					VariableSetStmt *n = makeNode(VariableSetStmt);

					n->kind = VAR_RESET_ALL;
					$$ = n;
				*/ }
		;

/* SetResetClause allows SET or RESET without LOCAL */
SetResetClause:
			SET set_rest					{ $$ = $2 }
			| VariableResetStmt				{ /*C $$ = (VariableSetStmt *) $1; */ }
		;

/* SetResetClause allows SET or RESET without LOCAL */
FunctionSetResetClause:
			SET set_rest_more				{ $$ = $2 }
			| VariableResetStmt				{ /*C $$ = (VariableSetStmt *) $1; */ }
		;


VariableShowStmt:
			SHOW var_name
				{ /*C
					VariableShowStmt *n = makeNode(VariableShowStmt);

					n->name = $2;
					$$ = (Node *) n;
				*/ }
			| SHOW TIME ZONE
				{ /*C
					VariableShowStmt *n = makeNode(VariableShowStmt);

					n->name = "timezone";
					$$ = (Node *) n;
				*/ }
			| SHOW TRANSACTION ISOLATION LEVEL
				{ /*C
					VariableShowStmt *n = makeNode(VariableShowStmt);

					n->name = "transaction_isolation";
					$$ = (Node *) n;
				*/ }
			| SHOW SESSION AUTHORIZATION
				{ /*C
					VariableShowStmt *n = makeNode(VariableShowStmt);

					n->name = "session_authorization";
					$$ = (Node *) n;
				*/ }
			| SHOW ALL
				{ /*C
					VariableShowStmt *n = makeNode(VariableShowStmt);

					n->name = "all";
					$$ = (Node *) n;
				*/ }
		;


ConstraintsSetStmt:
			SET CONSTRAINTS constraints_set_list constraints_set_mode
				{ /*C
					ConstraintsSetStmt *n = makeNode(ConstraintsSetStmt);

					n->constraints = $3;
					n->deferred = $4;
					$$ = (Node *) n;
				*/ }
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
				{ /*C
					CheckPointStmt *n = makeNode(CheckPointStmt);

					$$ = (Node *) n;
				*/ }
		;


/*****************************************************************************
 *
 * DISCARD { ALL | TEMP | PLANS | SEQUENCES }
 *
 *****************************************************************************/

DiscardStmt:
			DISCARD ALL
				{ /*C
					DiscardStmt *n = makeNode(DiscardStmt);

					n->target = DISCARD_ALL;
					$$ = (Node *) n;
				*/ }
			| DISCARD TEMP
				{ /*C
					DiscardStmt *n = makeNode(DiscardStmt);

					n->target = DISCARD_TEMP;
					$$ = (Node *) n;
				*/ }
			| DISCARD TEMPORARY
				{ /*C
					DiscardStmt *n = makeNode(DiscardStmt);

					n->target = DISCARD_TEMP;
					$$ = (Node *) n;
				*/ }
			| DISCARD PLANS
				{ /*C
					DiscardStmt *n = makeNode(DiscardStmt);

					n->target = DISCARD_PLANS;
					$$ = (Node *) n;
				*/ }
			| DISCARD SEQUENCES
				{ /*C
					DiscardStmt *n = makeNode(DiscardStmt);

					n->target = DISCARD_SEQUENCES;
					$$ = (Node *) n;
				*/ }

		;

