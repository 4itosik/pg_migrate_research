/* gram.y lines 10509-12078 */
/*****************************************************************************
 *
 * CREATE PUBLICATION name [WITH options]
 *
 * CREATE PUBLICATION FOR ALL TABLES [WITH options]
 *
 * CREATE PUBLICATION FOR pub_obj [, ...] [WITH options]
 *
 * pub_obj is one of:
 *
 *		TABLE table [, ...]
 *		TABLES IN SCHEMA schema [, ...]
 *
 *****************************************************************************/

CreatePublicationStmt:
			CREATE PUBLICATION name opt_definition
				{ /*C
					CreatePublicationStmt *n = makeNode(CreatePublicationStmt);

					n->pubname = $3;
					n->options = $4;
					$$ = (Node *) n;
				*/ }
			| CREATE PUBLICATION name FOR ALL TABLES opt_definition
				{ /*C
					CreatePublicationStmt *n = makeNode(CreatePublicationStmt);

					n->pubname = $3;
					n->options = $7;
					n->for_all_tables = true;
					$$ = (Node *) n;
				*/ }
			| CREATE PUBLICATION name FOR pub_obj_list opt_definition
				{ /*C
					CreatePublicationStmt *n = makeNode(CreatePublicationStmt);

					n->pubname = $3;
					n->options = $6;
					n->pubobjects = (List *) $5;
					preprocess_pubobj_list(n->pubobjects, yyscanner);
					$$ = (Node *) n;
				*/ }
		;

/*
 * FOR TABLE and FOR TABLES IN SCHEMA specifications
 *
 * This rule parses publication objects with and without keyword prefixes.
 *
 * The actual type of the object without keyword prefix depends on the previous
 * one with keyword prefix. It will be preprocessed in preprocess_pubobj_list().
 *
 * For the object without keyword prefix, we cannot just use relation_expr here,
 * because some extended expressions in relation_expr cannot be used as a
 * schemaname and we cannot differentiate it. So, we extract the rules from
 * relation_expr here.
 */
PublicationObjSpec:
			TABLE relation_expr opt_column_list OptWhereClause
				{ /*C
					$$ = makeNode(PublicationObjSpec);
					$$->pubobjtype = PUBLICATIONOBJ_TABLE;
					$$->pubtable = makeNode(PublicationTable);
					$$->pubtable->relation = $2;
					$$->pubtable->columns = $3;
					$$->pubtable->whereClause = $4;
				*/ }
			| TABLES IN_P SCHEMA ColId
				{ /*C
					$$ = makeNode(PublicationObjSpec);
					$$->pubobjtype = PUBLICATIONOBJ_TABLES_IN_SCHEMA;
					$$->name = $4;
					$$->location = @4;
				*/ }
			| TABLES IN_P SCHEMA CURRENT_SCHEMA
				{ /*C
					$$ = makeNode(PublicationObjSpec);
					$$->pubobjtype = PUBLICATIONOBJ_TABLES_IN_CUR_SCHEMA;
					$$->location = @4;
				*/ }
			| ColId opt_column_list OptWhereClause
				{ /*C
					$$ = makeNode(PublicationObjSpec);
					$$->pubobjtype = PUBLICATIONOBJ_CONTINUATION;
					/*
					 * If either a row filter or column list is specified, create
					 * a PublicationTable object.
					 * /
					if ($2 || $3)
					{
						/*
						 * The OptWhereClause must be stored here but it is
						 * valid only for tables. For non-table objects, an
						 * error will be thrown later via
						 * preprocess_pubobj_list().
						 * /
						$$->pubtable = makeNode(PublicationTable);
						$$->pubtable->relation = makeRangeVar(NULL, $1, @1);
						$$->pubtable->columns = $2;
						$$->pubtable->whereClause = $3;
					}
					else
					{
						$$->name = $1;
					}
					$$->location = @1;
				*/ }
			| ColId indirection opt_column_list OptWhereClause
				{ /*C
					$$ = makeNode(PublicationObjSpec);
					$$->pubobjtype = PUBLICATIONOBJ_CONTINUATION;
					$$->pubtable = makeNode(PublicationTable);
					$$->pubtable->relation = makeRangeVarFromQualifiedName($1, $2, @1, yyscanner);
					$$->pubtable->columns = $3;
					$$->pubtable->whereClause = $4;
					$$->location = @1;
				*/ }
			/* grammar like tablename * , ONLY tablename, ONLY ( tablename ) */
			| extended_relation_expr opt_column_list OptWhereClause
				{ /*C
					$$ = makeNode(PublicationObjSpec);
					$$->pubobjtype = PUBLICATIONOBJ_CONTINUATION;
					$$->pubtable = makeNode(PublicationTable);
					$$->pubtable->relation = $1;
					$$->pubtable->columns = $2;
					$$->pubtable->whereClause = $3;
				*/ }
			| CURRENT_SCHEMA
				{ /*C
					$$ = makeNode(PublicationObjSpec);
					$$->pubobjtype = PUBLICATIONOBJ_CONTINUATION;
					$$->location = @1;
				*/ }
				;

pub_obj_list:	PublicationObjSpec
					{ $$ = []Node{$1} }
			| pub_obj_list ',' PublicationObjSpec
					{ $$ = append($1, $3) }
	;

/*****************************************************************************
 *
 * ALTER PUBLICATION name SET ( options )
 *
 * ALTER PUBLICATION name ADD pub_obj [, ...]
 *
 * ALTER PUBLICATION name DROP pub_obj [, ...]
 *
 * ALTER PUBLICATION name SET pub_obj [, ...]
 *
 * pub_obj is one of:
 *
 *		TABLE table_name [, ...]
 *		TABLES IN SCHEMA schema_name [, ...]
 *
 *****************************************************************************/

AlterPublicationStmt:
			ALTER PUBLICATION name SET definition
				{ /*C
					AlterPublicationStmt *n = makeNode(AlterPublicationStmt);

					n->pubname = $3;
					n->options = $5;
					$$ = (Node *) n;
				*/ }
			| ALTER PUBLICATION name ADD_P pub_obj_list
				{ /*C
					AlterPublicationStmt *n = makeNode(AlterPublicationStmt);

					n->pubname = $3;
					n->pubobjects = $5;
					preprocess_pubobj_list(n->pubobjects, yyscanner);
					n->action = AP_AddObjects;
					$$ = (Node *) n;
				*/ }
			| ALTER PUBLICATION name SET pub_obj_list
				{ /*C
					AlterPublicationStmt *n = makeNode(AlterPublicationStmt);

					n->pubname = $3;
					n->pubobjects = $5;
					preprocess_pubobj_list(n->pubobjects, yyscanner);
					n->action = AP_SetObjects;
					$$ = (Node *) n;
				*/ }
			| ALTER PUBLICATION name DROP pub_obj_list
				{ /*C
					AlterPublicationStmt *n = makeNode(AlterPublicationStmt);

					n->pubname = $3;
					n->pubobjects = $5;
					preprocess_pubobj_list(n->pubobjects, yyscanner);
					n->action = AP_DropObjects;
					$$ = (Node *) n;
				*/ }
		;

/*****************************************************************************
 *
 * CREATE SUBSCRIPTION name ...
 *
 *****************************************************************************/

CreateSubscriptionStmt:
			CREATE SUBSCRIPTION name CONNECTION Sconst PUBLICATION name_list opt_definition
				{ /*C
					CreateSubscriptionStmt *n =
						makeNode(CreateSubscriptionStmt);
					n->subname = $3;
					n->conninfo = $5;
					n->publication = $7;
					n->options = $8;
					$$ = (Node *) n;
				*/ }
		;

/*****************************************************************************
 *
 * ALTER SUBSCRIPTION name ...
 *
 *****************************************************************************/

AlterSubscriptionStmt:
			ALTER SUBSCRIPTION name SET definition
				{ /*C
					AlterSubscriptionStmt *n =
						makeNode(AlterSubscriptionStmt);

					n->kind = ALTER_SUBSCRIPTION_OPTIONS;
					n->subname = $3;
					n->options = $5;
					$$ = (Node *) n;
				*/ }
			| ALTER SUBSCRIPTION name CONNECTION Sconst
				{ /*C
					AlterSubscriptionStmt *n =
						makeNode(AlterSubscriptionStmt);

					n->kind = ALTER_SUBSCRIPTION_CONNECTION;
					n->subname = $3;
					n->conninfo = $5;
					$$ = (Node *) n;
				*/ }
			| ALTER SUBSCRIPTION name REFRESH PUBLICATION opt_definition
				{ /*C
					AlterSubscriptionStmt *n =
						makeNode(AlterSubscriptionStmt);

					n->kind = ALTER_SUBSCRIPTION_REFRESH;
					n->subname = $3;
					n->options = $6;
					$$ = (Node *) n;
				*/ }
			| ALTER SUBSCRIPTION name ADD_P PUBLICATION name_list opt_definition
				{ /*C
					AlterSubscriptionStmt *n =
						makeNode(AlterSubscriptionStmt);

					n->kind = ALTER_SUBSCRIPTION_ADD_PUBLICATION;
					n->subname = $3;
					n->publication = $6;
					n->options = $7;
					$$ = (Node *) n;
				*/ }
			| ALTER SUBSCRIPTION name DROP PUBLICATION name_list opt_definition
				{ /*C
					AlterSubscriptionStmt *n =
						makeNode(AlterSubscriptionStmt);

					n->kind = ALTER_SUBSCRIPTION_DROP_PUBLICATION;
					n->subname = $3;
					n->publication = $6;
					n->options = $7;
					$$ = (Node *) n;
				*/ }
			| ALTER SUBSCRIPTION name SET PUBLICATION name_list opt_definition
				{ /*C
					AlterSubscriptionStmt *n =
						makeNode(AlterSubscriptionStmt);

					n->kind = ALTER_SUBSCRIPTION_SET_PUBLICATION;
					n->subname = $3;
					n->publication = $6;
					n->options = $7;
					$$ = (Node *) n;
				*/ }
			| ALTER SUBSCRIPTION name ENABLE_P
				{ /*C
					AlterSubscriptionStmt *n =
						makeNode(AlterSubscriptionStmt);

					n->kind = ALTER_SUBSCRIPTION_ENABLED;
					n->subname = $3;
					n->options = list_make1(makeDefElem("enabled",
											(Node *) makeBoolean(true), @1));
					$$ = (Node *) n;
				*/ }
			| ALTER SUBSCRIPTION name DISABLE_P
				{ /*C
					AlterSubscriptionStmt *n =
						makeNode(AlterSubscriptionStmt);

					n->kind = ALTER_SUBSCRIPTION_ENABLED;
					n->subname = $3;
					n->options = list_make1(makeDefElem("enabled",
											(Node *) makeBoolean(false), @1));
					$$ = (Node *) n;
				*/ }
			| ALTER SUBSCRIPTION name SKIP definition
				{ /*C
					AlterSubscriptionStmt *n =
						makeNode(AlterSubscriptionStmt);

					n->kind = ALTER_SUBSCRIPTION_SKIP;
					n->subname = $3;
					n->options = $5;
					$$ = (Node *) n;
				*/ }
		;

/*****************************************************************************
 *
 * DROP SUBSCRIPTION [ IF EXISTS ] name
 *
 *****************************************************************************/

DropSubscriptionStmt: DROP SUBSCRIPTION name opt_drop_behavior
				{ /*C
					DropSubscriptionStmt *n = makeNode(DropSubscriptionStmt);

					n->subname = $3;
					n->missing_ok = false;
					n->behavior = $4;
					$$ = (Node *) n;
				*/ }
				|  DROP SUBSCRIPTION IF_P EXISTS name opt_drop_behavior
				{ /*C
					DropSubscriptionStmt *n = makeNode(DropSubscriptionStmt);

					n->subname = $5;
					n->missing_ok = true;
					n->behavior = $6;
					$$ = (Node *) n;
				*/ }
		;

/*****************************************************************************
 *
 *		QUERY:	Define Rewrite Rule
 *
 *****************************************************************************/

RuleStmt:	CREATE opt_or_replace RULE name AS
			ON event TO qualified_name where_clause
			DO opt_instead RuleActionList
				{ /*C
					RuleStmt   *n = makeNode(RuleStmt);

					n->replace = $2;
					n->relation = $9;
					n->rulename = $4;
					n->whereClause = $10;
					n->event = $7;
					n->instead = $12;
					n->actions = $13;
					$$ = (Node *) n;
				*/ }
		;

RuleActionList:
			NOTHING									{ $$ = nil }
			| RuleActionStmt						{ $$ = []Node{$1} }
			| '(' RuleActionMulti ')'				{ $$ = $2 }
		;

/* the thrashing around here is to discard "empty" statements... */
RuleActionMulti:
			RuleActionMulti ';' RuleActionStmtOrEmpty
				{ /*C if ($3 != NULL)
					$$ = lappend($1, $3);
				  else
					$$ = $1;
				*/ }
			| RuleActionStmtOrEmpty
				{ /*C if ($1 != NULL)
					$$ = list_make1($1);
				  else
					$$ = NIL;
				*/ }
		;

RuleActionStmt:
			SelectStmt
			| InsertStmt
			| UpdateStmt
			| DeleteStmt
			| NotifyStmt
		;

RuleActionStmtOrEmpty:
			RuleActionStmt							{ $$ = $1 }
			|	/*EMPTY*/							{ $$ = nil }
		;

event:		SELECT									{ /*C $$ = CMD_SELECT; */ }
			| UPDATE								{ /*C $$ = CMD_UPDATE; */ }
			| DELETE_P								{ /*C $$ = CMD_DELETE; */ }
			| INSERT								{ /*C $$ = CMD_INSERT; */ }
		 ;

opt_instead:
			INSTEAD									{ $$ = true }
			| ALSO									{ $$ = false }
			| /*EMPTY*/								{ $$ = false }
		;


/*****************************************************************************
 *
 *		QUERY:
 *				NOTIFY <identifier> can appear both in rule bodies and
 *				as a query-level command
 *
 *****************************************************************************/

NotifyStmt: NOTIFY ColId notify_payload
				{ /*C
					NotifyStmt *n = makeNode(NotifyStmt);

					n->conditionname = $2;
					n->payload = $3;
					$$ = (Node *) n;
				*/ }
		;

notify_payload:
			',' Sconst							{ $$ = $2 }
			| /*EMPTY*/							{ $$ = "" }
		;

ListenStmt: LISTEN ColId
				{ /*C
					ListenStmt *n = makeNode(ListenStmt);

					n->conditionname = $2;
					$$ = (Node *) n;
				*/ }
		;

UnlistenStmt:
			UNLISTEN ColId
				{ /*C
					UnlistenStmt *n = makeNode(UnlistenStmt);

					n->conditionname = $2;
					$$ = (Node *) n;
				*/ }
			| UNLISTEN '*'
				{ /*C
					UnlistenStmt *n = makeNode(UnlistenStmt);

					n->conditionname = NULL;
					$$ = (Node *) n;
				*/ }
		;


/*****************************************************************************
 *
 *		Transactions:
 *
 *		BEGIN / COMMIT / ROLLBACK
 *		(also older versions END / ABORT)
 *
 *****************************************************************************/

TransactionStmt:
			ABORT_P opt_transaction opt_transaction_chain
				{ /*C
					TransactionStmt *n = makeNode(TransactionStmt);

					n->kind = TRANS_STMT_ROLLBACK;
					n->options = NIL;
					n->chain = $3;
					n->location = -1;
					$$ = (Node *) n;
				*/ }
			| START TRANSACTION transaction_mode_list_or_empty
				{ /*C
					TransactionStmt *n = makeNode(TransactionStmt);

					n->kind = TRANS_STMT_START;
					n->options = $3;
					n->location = -1;
					$$ = (Node *) n;
				*/ }
			| COMMIT opt_transaction opt_transaction_chain
				{ /*C
					TransactionStmt *n = makeNode(TransactionStmt);

					n->kind = TRANS_STMT_COMMIT;
					n->options = NIL;
					n->chain = $3;
					n->location = -1;
					$$ = (Node *) n;
				*/ }
			| ROLLBACK opt_transaction opt_transaction_chain
				{ /*C
					TransactionStmt *n = makeNode(TransactionStmt);

					n->kind = TRANS_STMT_ROLLBACK;
					n->options = NIL;
					n->chain = $3;
					n->location = -1;
					$$ = (Node *) n;
				*/ }
			| SAVEPOINT ColId
				{ /*C
					TransactionStmt *n = makeNode(TransactionStmt);

					n->kind = TRANS_STMT_SAVEPOINT;
					n->savepoint_name = $2;
					n->location = @2;
					$$ = (Node *) n;
				*/ }
			| RELEASE SAVEPOINT ColId
				{ /*C
					TransactionStmt *n = makeNode(TransactionStmt);

					n->kind = TRANS_STMT_RELEASE;
					n->savepoint_name = $3;
					n->location = @3;
					$$ = (Node *) n;
				*/ }
			| RELEASE ColId
				{ /*C
					TransactionStmt *n = makeNode(TransactionStmt);

					n->kind = TRANS_STMT_RELEASE;
					n->savepoint_name = $2;
					n->location = @2;
					$$ = (Node *) n;
				*/ }
			| ROLLBACK opt_transaction TO SAVEPOINT ColId
				{ /*C
					TransactionStmt *n = makeNode(TransactionStmt);

					n->kind = TRANS_STMT_ROLLBACK_TO;
					n->savepoint_name = $5;
					n->location = @5;
					$$ = (Node *) n;
				*/ }
			| ROLLBACK opt_transaction TO ColId
				{ /*C
					TransactionStmt *n = makeNode(TransactionStmt);

					n->kind = TRANS_STMT_ROLLBACK_TO;
					n->savepoint_name = $4;
					n->location = @4;
					$$ = (Node *) n;
				*/ }
			| PREPARE TRANSACTION Sconst
				{ /*C
					TransactionStmt *n = makeNode(TransactionStmt);

					n->kind = TRANS_STMT_PREPARE;
					n->gid = $3;
					n->location = @3;
					$$ = (Node *) n;
				*/ }
			| COMMIT PREPARED Sconst
				{ /*C
					TransactionStmt *n = makeNode(TransactionStmt);

					n->kind = TRANS_STMT_COMMIT_PREPARED;
					n->gid = $3;
					n->location = @3;
					$$ = (Node *) n;
				*/ }
			| ROLLBACK PREPARED Sconst
				{ /*C
					TransactionStmt *n = makeNode(TransactionStmt);

					n->kind = TRANS_STMT_ROLLBACK_PREPARED;
					n->gid = $3;
					n->location = @3;
					$$ = (Node *) n;
				*/ }
		;

TransactionStmtLegacy:
			BEGIN_P opt_transaction transaction_mode_list_or_empty
				{ /*C
					TransactionStmt *n = makeNode(TransactionStmt);

					n->kind = TRANS_STMT_BEGIN;
					n->options = $3;
					n->location = -1;
					$$ = (Node *) n;
				*/ }
			| END_P opt_transaction opt_transaction_chain
				{ /*C
					TransactionStmt *n = makeNode(TransactionStmt);

					n->kind = TRANS_STMT_COMMIT;
					n->options = NIL;
					n->chain = $3;
					n->location = -1;
					$$ = (Node *) n;
				*/ }
		;

opt_transaction:	WORK
			| TRANSACTION
			| /*EMPTY*/
		;

transaction_mode_item:
			ISOLATION LEVEL iso_level
					{ /*C $$ = makeDefElem("transaction_isolation",
									   makeStringConst($3, @3), @1); */ }
			| READ ONLY
					{ /*C $$ = makeDefElem("transaction_read_only",
									   makeIntConst(true, @1), @1); */ }
			| READ WRITE
					{ /*C $$ = makeDefElem("transaction_read_only",
									   makeIntConst(false, @1), @1); */ }
			| DEFERRABLE
					{ /*C $$ = makeDefElem("transaction_deferrable",
									   makeIntConst(true, @1), @1); */ }
			| NOT DEFERRABLE
					{ /*C $$ = makeDefElem("transaction_deferrable",
									   makeIntConst(false, @1), @1); */ }
		;

/* Syntax with commas is SQL-spec, without commas is Postgres historical */
transaction_mode_list:
			transaction_mode_item
					{ $$ = []Node{$1} }
			| transaction_mode_list ',' transaction_mode_item
					{ $$ = append($1, $3) }
			| transaction_mode_list transaction_mode_item
					{ $$ = append($1, $2) }
		;

transaction_mode_list_or_empty:
			transaction_mode_list
			| /* EMPTY */
					{ $$ = nil }
		;

opt_transaction_chain:
			AND CHAIN		{ $$ = true }
			| AND NO CHAIN	{ $$ = false }
			| /* EMPTY */	{ $$ = false }
		;


/*****************************************************************************
 *
 *	QUERY:
 *		CREATE [ OR REPLACE ] [ TEMP ] VIEW <viewname> '('target-list ')'
 *			AS <query> [ WITH [ CASCADED | LOCAL ] CHECK OPTION ]
 *
 *****************************************************************************/

ViewStmt: CREATE OptTemp VIEW qualified_name opt_column_list opt_reloptions
				AS SelectStmt opt_check_option
				{ /*C
					ViewStmt   *n = makeNode(ViewStmt);

					n->view = $4;
					n->view->relpersistence = $2;
					n->aliases = $5;
					n->query = $8;
					n->replace = false;
					n->options = $6;
					n->withCheckOption = $9;
					$$ = (Node *) n;
				*/ }
		| CREATE OR REPLACE OptTemp VIEW qualified_name opt_column_list opt_reloptions
				AS SelectStmt opt_check_option
				{ /*C
					ViewStmt   *n = makeNode(ViewStmt);

					n->view = $6;
					n->view->relpersistence = $4;
					n->aliases = $7;
					n->query = $10;
					n->replace = true;
					n->options = $8;
					n->withCheckOption = $11;
					$$ = (Node *) n;
				*/ }
		| CREATE OptTemp RECURSIVE VIEW qualified_name '(' columnList ')' opt_reloptions
				AS SelectStmt opt_check_option
				{ /*C
					ViewStmt   *n = makeNode(ViewStmt);

					n->view = $5;
					n->view->relpersistence = $2;
					n->aliases = $7;
					n->query = makeRecursiveViewSelect(n->view->relname, n->aliases, $11);
					n->replace = false;
					n->options = $9;
					n->withCheckOption = $12;
					if (n->withCheckOption != NO_CHECK_OPTION)
						ereport(ERROR,
								(errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
								 errmsg("WITH CHECK OPTION not supported on recursive views"),
								 parser_errposition(@12)));
					$$ = (Node *) n;
				*/ }
		| CREATE OR REPLACE OptTemp RECURSIVE VIEW qualified_name '(' columnList ')' opt_reloptions
				AS SelectStmt opt_check_option
				{ /*C
					ViewStmt   *n = makeNode(ViewStmt);

					n->view = $7;
					n->view->relpersistence = $4;
					n->aliases = $9;
					n->query = makeRecursiveViewSelect(n->view->relname, n->aliases, $13);
					n->replace = true;
					n->options = $11;
					n->withCheckOption = $14;
					if (n->withCheckOption != NO_CHECK_OPTION)
						ereport(ERROR,
								(errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
								 errmsg("WITH CHECK OPTION not supported on recursive views"),
								 parser_errposition(@14)));
					$$ = (Node *) n;
				*/ }
		;

opt_check_option:
		WITH CHECK OPTION				{ /*C $$ = CASCADED_CHECK_OPTION; */ }
		| WITH CASCADED CHECK OPTION	{ /*C $$ = CASCADED_CHECK_OPTION; */ }
		| WITH LOCAL CHECK OPTION		{ /*C $$ = LOCAL_CHECK_OPTION; */ }
		| /* EMPTY */					{ /*C $$ = NO_CHECK_OPTION; */ }
		;

/*****************************************************************************
 *
 *		QUERY:
 *				LOAD "filename"
 *
 *****************************************************************************/

LoadStmt:	LOAD file_name
				{ /*C
					LoadStmt   *n = makeNode(LoadStmt);

					n->filename = $2;
					$$ = (Node *) n;
				*/ }
		;


/*****************************************************************************
 *
 *		CREATE DATABASE
 *
 *****************************************************************************/

CreatedbStmt:
			CREATE DATABASE name opt_with createdb_opt_list
				{ /*C
					CreatedbStmt *n = makeNode(CreatedbStmt);

					n->dbname = $3;
					n->options = $5;
					$$ = (Node *) n;
				*/ }
		;

createdb_opt_list:
			createdb_opt_items						{ $$ = $1 }
			| /* EMPTY */							{ $$ = nil }
		;

createdb_opt_items:
			createdb_opt_item						{ $$ = []Node{$1} }
			| createdb_opt_items createdb_opt_item	{ $$ = append($1, $2) }
		;

createdb_opt_item:
			createdb_opt_name opt_equal NumericOnly
				{ /*C
					$$ = makeDefElem($1, $3, @1);
				*/ }
			| createdb_opt_name opt_equal opt_boolean_or_string
				{ /*C
					$$ = makeDefElem($1, (Node *) makeString($3), @1);
				*/ }
			| createdb_opt_name opt_equal DEFAULT
				{ /*C
					$$ = makeDefElem($1, NULL, @1);
				*/ }
		;

/*
 * Ideally we'd use ColId here, but that causes shift/reduce conflicts against
 * the ALTER DATABASE SET/RESET syntaxes.  Instead call out specific keywords
 * we need, and allow IDENT so that database option names don't have to be
 * parser keywords unless they are already keywords for other reasons.
 *
 * XXX this coding technique is fragile since if someone makes a formerly
 * non-keyword option name into a keyword and forgets to add it here, the
 * option will silently break.  Best defense is to provide a regression test
 * exercising every such option, at least at the syntax level.
 */
createdb_opt_name:
			IDENT							{ $$ = $1 }
			| CONNECTION LIMIT				{ /*C $$ = pstrdup("connection_limit"); */ }
			| ENCODING						{ $$ = $1 }
			| LOCATION						{ $$ = $1 }
			| OWNER							{ $$ = $1 }
			| TABLESPACE					{ $$ = $1 }
			| TEMPLATE						{ $$ = $1 }
		;

/*
 *	Though the equals sign doesn't match other WITH options, pg_dump uses
 *	equals for backward compatibility, and it doesn't seem worth removing it.
 */
opt_equal:	'='
			| /*EMPTY*/
		;


/*****************************************************************************
 *
 *		ALTER DATABASE
 *
 *****************************************************************************/

AlterDatabaseStmt:
			ALTER DATABASE name WITH createdb_opt_list
				 { /*C
					AlterDatabaseStmt *n = makeNode(AlterDatabaseStmt);

					n->dbname = $3;
					n->options = $5;
					$$ = (Node *) n;
				 */ }
			| ALTER DATABASE name createdb_opt_list
				 { /*C
					AlterDatabaseStmt *n = makeNode(AlterDatabaseStmt);

					n->dbname = $3;
					n->options = $4;
					$$ = (Node *) n;
				 */ }
			| ALTER DATABASE name SET TABLESPACE name
				 { /*C
					AlterDatabaseStmt *n = makeNode(AlterDatabaseStmt);

					n->dbname = $3;
					n->options = list_make1(makeDefElem("tablespace",
														(Node *) makeString($6), @6));
					$$ = (Node *) n;
				 */ }
			| ALTER DATABASE name REFRESH COLLATION VERSION_P
				 { /*C
					AlterDatabaseRefreshCollStmt *n = makeNode(AlterDatabaseRefreshCollStmt);

					n->dbname = $3;
					$$ = (Node *) n;
				 */ }
		;

AlterDatabaseSetStmt:
			ALTER DATABASE name SetResetClause
				{ /*C
					AlterDatabaseSetStmt *n = makeNode(AlterDatabaseSetStmt);

					n->dbname = $3;
					n->setstmt = $4;
					$$ = (Node *) n;
				*/ }
		;


/*****************************************************************************
 *
 *		DROP DATABASE [ IF EXISTS ] dbname [ [ WITH ] ( options ) ]
 *
 * This is implicitly CASCADE, no need for drop behavior
 *****************************************************************************/

DropdbStmt: DROP DATABASE name
				{ /*C
					DropdbStmt *n = makeNode(DropdbStmt);

					n->dbname = $3;
					n->missing_ok = false;
					n->options = NULL;
					$$ = (Node *) n;
				*/ }
			| DROP DATABASE IF_P EXISTS name
				{ /*C
					DropdbStmt *n = makeNode(DropdbStmt);

					n->dbname = $5;
					n->missing_ok = true;
					n->options = NULL;
					$$ = (Node *) n;
				*/ }
			| DROP DATABASE name opt_with '(' drop_option_list ')'
				{ /*C
					DropdbStmt *n = makeNode(DropdbStmt);

					n->dbname = $3;
					n->missing_ok = false;
					n->options = $6;
					$$ = (Node *) n;
				*/ }
			| DROP DATABASE IF_P EXISTS name opt_with '(' drop_option_list ')'
				{ /*C
					DropdbStmt *n = makeNode(DropdbStmt);

					n->dbname = $5;
					n->missing_ok = true;
					n->options = $8;
					$$ = (Node *) n;
				*/ }
		;

drop_option_list:
			drop_option
				{ /*C
					$$ = list_make1((Node *) $1);
				*/ }
			| drop_option_list ',' drop_option
				{ /*C
					$$ = lappend($1, (Node *) $3);
				*/ }
		;

/*
 * Currently only the FORCE option is supported, but the syntax is designed
 * to be extensible so that we can add more options in the future if required.
 */
drop_option:
			FORCE
				{ /*C
					$$ = makeDefElem("force", NULL, @1);
				*/ }
		;

/*****************************************************************************
 *
 *		ALTER COLLATION
 *
 *****************************************************************************/

AlterCollationStmt: ALTER COLLATION any_name REFRESH VERSION_P
				{ /*C
					AlterCollationStmt *n = makeNode(AlterCollationStmt);

					n->collname = $3;
					$$ = (Node *) n;
				*/ }
		;


/*****************************************************************************
 *
 *		ALTER SYSTEM
 *
 * This is used to change configuration parameters persistently.
 *****************************************************************************/

AlterSystemStmt:
			ALTER SYSTEM_P SET generic_set
				{ /*C
					AlterSystemStmt *n = makeNode(AlterSystemStmt);

					n->setstmt = $4;
					$$ = (Node *) n;
				*/ }
			| ALTER SYSTEM_P RESET generic_reset
				{ /*C
					AlterSystemStmt *n = makeNode(AlterSystemStmt);

					n->setstmt = $4;
					$$ = (Node *) n;
				*/ }
		;


/*****************************************************************************
 *
 * Manipulate a domain
 *
 *****************************************************************************/

CreateDomainStmt:
			CREATE DOMAIN_P any_name opt_as Typename ColQualList
				{ /*C
					CreateDomainStmt *n = makeNode(CreateDomainStmt);

					n->domainname = $3;
					n->typeName = $5;
					SplitColQualList($6, &n->constraints, &n->collClause,
									 yyscanner);
					$$ = (Node *) n;
				*/ }
		;

AlterDomainStmt:
			/* ALTER DOMAIN <domain> {SET DEFAULT <expr>|DROP DEFAULT} */
			ALTER DOMAIN_P any_name alter_column_default
				{ /*C
					AlterDomainStmt *n = makeNode(AlterDomainStmt);

					n->subtype = 'T';
					n->typeName = $3;
					n->def = $4;
					$$ = (Node *) n;
				*/ }
			/* ALTER DOMAIN <domain> DROP NOT NULL */
			| ALTER DOMAIN_P any_name DROP NOT NULL_P
				{ /*C
					AlterDomainStmt *n = makeNode(AlterDomainStmt);

					n->subtype = 'N';
					n->typeName = $3;
					$$ = (Node *) n;
				*/ }
			/* ALTER DOMAIN <domain> SET NOT NULL */
			| ALTER DOMAIN_P any_name SET NOT NULL_P
				{ /*C
					AlterDomainStmt *n = makeNode(AlterDomainStmt);

					n->subtype = 'O';
					n->typeName = $3;
					$$ = (Node *) n;
				*/ }
			/* ALTER DOMAIN <domain> ADD CONSTRAINT ... */
			| ALTER DOMAIN_P any_name ADD_P DomainConstraint
				{ /*C
					AlterDomainStmt *n = makeNode(AlterDomainStmt);

					n->subtype = 'C';
					n->typeName = $3;
					n->def = $5;
					$$ = (Node *) n;
				*/ }
			/* ALTER DOMAIN <domain> DROP CONSTRAINT <name> [RESTRICT|CASCADE] */
			| ALTER DOMAIN_P any_name DROP CONSTRAINT name opt_drop_behavior
				{ /*C
					AlterDomainStmt *n = makeNode(AlterDomainStmt);

					n->subtype = 'X';
					n->typeName = $3;
					n->name = $6;
					n->behavior = $7;
					n->missing_ok = false;
					$$ = (Node *) n;
				*/ }
			/* ALTER DOMAIN <domain> DROP CONSTRAINT IF EXISTS <name> [RESTRICT|CASCADE] */
			| ALTER DOMAIN_P any_name DROP CONSTRAINT IF_P EXISTS name opt_drop_behavior
				{ /*C
					AlterDomainStmt *n = makeNode(AlterDomainStmt);

					n->subtype = 'X';
					n->typeName = $3;
					n->name = $8;
					n->behavior = $9;
					n->missing_ok = true;
					$$ = (Node *) n;
				*/ }
			/* ALTER DOMAIN <domain> VALIDATE CONSTRAINT <name> */
			| ALTER DOMAIN_P any_name VALIDATE CONSTRAINT name
				{ /*C
					AlterDomainStmt *n = makeNode(AlterDomainStmt);

					n->subtype = 'V';
					n->typeName = $3;
					n->name = $6;
					$$ = (Node *) n;
				*/ }
			;

opt_as:		AS
			| /* EMPTY */
		;


/*****************************************************************************
 *
 * Manipulate a text search dictionary or configuration
 *
 *****************************************************************************/

AlterTSDictionaryStmt:
			ALTER TEXT_P SEARCH DICTIONARY any_name definition
				{ /*C
					AlterTSDictionaryStmt *n = makeNode(AlterTSDictionaryStmt);

					n->dictname = $5;
					n->options = $6;
					$$ = (Node *) n;
				*/ }
		;

AlterTSConfigurationStmt:
			ALTER TEXT_P SEARCH CONFIGURATION any_name ADD_P MAPPING FOR name_list any_with any_name_list
				{ /*C
					AlterTSConfigurationStmt *n = makeNode(AlterTSConfigurationStmt);

					n->kind = ALTER_TSCONFIG_ADD_MAPPING;
					n->cfgname = $5;
					n->tokentype = $9;
					n->dicts = $11;
					n->override = false;
					n->replace = false;
					$$ = (Node *) n;
				*/ }
			| ALTER TEXT_P SEARCH CONFIGURATION any_name ALTER MAPPING FOR name_list any_with any_name_list
				{ /*C
					AlterTSConfigurationStmt *n = makeNode(AlterTSConfigurationStmt);

					n->kind = ALTER_TSCONFIG_ALTER_MAPPING_FOR_TOKEN;
					n->cfgname = $5;
					n->tokentype = $9;
					n->dicts = $11;
					n->override = true;
					n->replace = false;
					$$ = (Node *) n;
				*/ }
			| ALTER TEXT_P SEARCH CONFIGURATION any_name ALTER MAPPING REPLACE any_name any_with any_name
				{ /*C
					AlterTSConfigurationStmt *n = makeNode(AlterTSConfigurationStmt);

					n->kind = ALTER_TSCONFIG_REPLACE_DICT;
					n->cfgname = $5;
					n->tokentype = NIL;
					n->dicts = list_make2($9,$11);
					n->override = false;
					n->replace = true;
					$$ = (Node *) n;
				*/ }
			| ALTER TEXT_P SEARCH CONFIGURATION any_name ALTER MAPPING FOR name_list REPLACE any_name any_with any_name
				{ /*C
					AlterTSConfigurationStmt *n = makeNode(AlterTSConfigurationStmt);

					n->kind = ALTER_TSCONFIG_REPLACE_DICT_FOR_TOKEN;
					n->cfgname = $5;
					n->tokentype = $9;
					n->dicts = list_make2($11,$13);
					n->override = false;
					n->replace = true;
					$$ = (Node *) n;
				*/ }
			| ALTER TEXT_P SEARCH CONFIGURATION any_name DROP MAPPING FOR name_list
				{ /*C
					AlterTSConfigurationStmt *n = makeNode(AlterTSConfigurationStmt);

					n->kind = ALTER_TSCONFIG_DROP_MAPPING;
					n->cfgname = $5;
					n->tokentype = $9;
					n->missing_ok = false;
					$$ = (Node *) n;
				*/ }
			| ALTER TEXT_P SEARCH CONFIGURATION any_name DROP MAPPING IF_P EXISTS FOR name_list
				{ /*C
					AlterTSConfigurationStmt *n = makeNode(AlterTSConfigurationStmt);

					n->kind = ALTER_TSCONFIG_DROP_MAPPING;
					n->cfgname = $5;
					n->tokentype = $11;
					n->missing_ok = true;
					$$ = (Node *) n;
				*/ }
		;

/* Use this if TIME or ORDINALITY after WITH should be taken as an identifier */
any_with:	WITH
			| WITH_LA
		;


/*****************************************************************************
 *
 * Manipulate a conversion
 *
 *		CREATE [DEFAULT] CONVERSION <conversion_name>
 *		FOR <encoding_name> TO <encoding_name> FROM <func_name>
 *
 *****************************************************************************/

CreateConversionStmt:
			CREATE opt_default CONVERSION_P any_name FOR Sconst
			TO Sconst FROM any_name
			{ /*C
				CreateConversionStmt *n = makeNode(CreateConversionStmt);

				n->conversion_name = $4;
				n->for_encoding_name = $6;
				n->to_encoding_name = $8;
				n->func_name = $10;
				n->def = $2;
				$$ = (Node *) n;
			*/ }
		;

/*****************************************************************************
 *
 *		QUERY:
 *				CLUSTER (options) [ <qualified_name> [ USING <index_name> ] ]
 *				CLUSTER [VERBOSE] [ <qualified_name> [ USING <index_name> ] ]
 *				CLUSTER [VERBOSE] <index_name> ON <qualified_name> (for pre-8.3)
 *
 *****************************************************************************/

ClusterStmt:
			CLUSTER '(' utility_option_list ')' qualified_name cluster_index_specification
				{ /*C
					ClusterStmt *n = makeNode(ClusterStmt);

					n->relation = $5;
					n->indexname = $6;
					n->params = $3;
					$$ = (Node *) n;
				*/ }
			| CLUSTER '(' utility_option_list ')'
				{ /*C
					ClusterStmt *n = makeNode(ClusterStmt);

					n->relation = NULL;
					n->indexname = NULL;
					n->params = $3;
					$$ = (Node *) n;
				*/ }
			/* unparenthesized VERBOSE kept for pre-14 compatibility */
			| CLUSTER opt_verbose qualified_name cluster_index_specification
				{ /*C
					ClusterStmt *n = makeNode(ClusterStmt);

					n->relation = $3;
					n->indexname = $4;
					n->params = NIL;
					if ($2)
						n->params = lappend(n->params, makeDefElem("verbose", NULL, @2));
					$$ = (Node *) n;
				*/ }
			/* unparenthesized VERBOSE kept for pre-17 compatibility */
			| CLUSTER opt_verbose
				{ /*C
					ClusterStmt *n = makeNode(ClusterStmt);

					n->relation = NULL;
					n->indexname = NULL;
					n->params = NIL;
					if ($2)
						n->params = lappend(n->params, makeDefElem("verbose", NULL, @2));
					$$ = (Node *) n;
				*/ }
			/* kept for pre-8.3 compatibility */
			| CLUSTER opt_verbose name ON qualified_name
				{ /*C
					ClusterStmt *n = makeNode(ClusterStmt);

					n->relation = $5;
					n->indexname = $3;
					n->params = NIL;
					if ($2)
						n->params = lappend(n->params, makeDefElem("verbose", NULL, @2));
					$$ = (Node *) n;
				*/ }
		;

cluster_index_specification:
			USING name				{ $$ = $2 }
			| /*EMPTY*/				{ $$ = "" }
		;


/*****************************************************************************
 *
 *		QUERY:
 *				VACUUM
 *				ANALYZE
 *
 *****************************************************************************/

VacuumStmt: VACUUM opt_full opt_freeze opt_verbose opt_analyze opt_vacuum_relation_list
				{ /*C
					VacuumStmt *n = makeNode(VacuumStmt);

					n->options = NIL;
					if ($2)
						n->options = lappend(n->options,
											 makeDefElem("full", NULL, @2));
					if ($3)
						n->options = lappend(n->options,
											 makeDefElem("freeze", NULL, @3));
					if ($4)
						n->options = lappend(n->options,
											 makeDefElem("verbose", NULL, @4));
					if ($5)
						n->options = lappend(n->options,
											 makeDefElem("analyze", NULL, @5));
					n->rels = $6;
					n->is_vacuumcmd = true;
					$$ = (Node *) n;
				*/ }
			| VACUUM '(' utility_option_list ')' opt_vacuum_relation_list
				{ /*C
					VacuumStmt *n = makeNode(VacuumStmt);

					n->options = $3;
					n->rels = $5;
					n->is_vacuumcmd = true;
					$$ = (Node *) n;
				*/ }
		;

AnalyzeStmt: analyze_keyword opt_verbose opt_vacuum_relation_list
				{ /*C
					VacuumStmt *n = makeNode(VacuumStmt);

					n->options = NIL;
					if ($2)
						n->options = lappend(n->options,
											 makeDefElem("verbose", NULL, @2));
					n->rels = $3;
					n->is_vacuumcmd = false;
					$$ = (Node *) n;
				*/ }
			| analyze_keyword '(' utility_option_list ')' opt_vacuum_relation_list
				{ /*C
					VacuumStmt *n = makeNode(VacuumStmt);

					n->options = $3;
					n->rels = $5;
					n->is_vacuumcmd = false;
					$$ = (Node *) n;
				*/ }
		;

utility_option_list:
			utility_option_elem
				{ $$ = []Node{$1} }
			| utility_option_list ',' utility_option_elem
				{ $$ = append($1, $3) }
		;

analyze_keyword:
			ANALYZE
			| ANALYSE /* British */
		;

utility_option_elem:
			utility_option_name utility_option_arg
				{ /*C
					$$ = makeDefElem($1, $2, @1);
				*/ }
		;

utility_option_name:
			NonReservedWord							{ $$ = $1 }
			| analyze_keyword						{ $$ = "analyze" }
			| FORMAT_LA								{ $$ = "format" }
		;

utility_option_arg:
			opt_boolean_or_string					{ /*C $$ = (Node *) makeString($1); */ }
			| NumericOnly							{ $$ = $1 }
			| /* EMPTY */							{ $$ = nil }
		;

opt_analyze:
			analyze_keyword							{ $$ = true }
			| /*EMPTY*/								{ $$ = false }
		;

opt_verbose:
			VERBOSE									{ $$ = true }
			| /*EMPTY*/								{ $$ = false }
		;

opt_full:	FULL									{ $$ = true }
			| /*EMPTY*/								{ $$ = false }
		;

opt_freeze: FREEZE									{ $$ = true }
			| /*EMPTY*/								{ $$ = false }
		;

opt_name_list:
			'(' name_list ')'						{ $$ = $2 }
			| /*EMPTY*/								{ $$ = nil }
		;

vacuum_relation:
			qualified_name opt_name_list
				{ /*C
					$$ = (Node *) makeVacuumRelation($1, InvalidOid, $2);
				*/ }
		;

vacuum_relation_list:
			vacuum_relation
					{ $$ = []Node{$1} }
			| vacuum_relation_list ',' vacuum_relation
					{ $$ = append($1, $3) }
		;

opt_vacuum_relation_list:
			vacuum_relation_list					{ $$ = $1 }
			| /*EMPTY*/								{ $$ = nil }
		;


/*****************************************************************************
 *
 *		QUERY:
 *				EXPLAIN [ANALYZE] [VERBOSE] query
 *				EXPLAIN ( options ) query
 *
 *****************************************************************************/

ExplainStmt:
		EXPLAIN ExplainableStmt
				{ /*C
					ExplainStmt *n = makeNode(ExplainStmt);

					n->query = $2;
					n->options = NIL;
					$$ = (Node *) n;
				*/ }
		| EXPLAIN analyze_keyword opt_verbose ExplainableStmt
				{ /*C
					ExplainStmt *n = makeNode(ExplainStmt);

					n->query = $4;
					n->options = list_make1(makeDefElem("analyze", NULL, @2));
					if ($3)
						n->options = lappend(n->options,
											 makeDefElem("verbose", NULL, @3));
					$$ = (Node *) n;
				*/ }
		| EXPLAIN VERBOSE ExplainableStmt
				{ /*C
					ExplainStmt *n = makeNode(ExplainStmt);

					n->query = $3;
					n->options = list_make1(makeDefElem("verbose", NULL, @2));
					$$ = (Node *) n;
				*/ }
		| EXPLAIN '(' utility_option_list ')' ExplainableStmt
				{ /*C
					ExplainStmt *n = makeNode(ExplainStmt);

					n->query = $5;
					n->options = $3;
					$$ = (Node *) n;
				*/ }
		;

ExplainableStmt:
			SelectStmt
			| InsertStmt
			| UpdateStmt
			| DeleteStmt
			| MergeStmt
			| DeclareCursorStmt
			| CreateAsStmt
			| CreateMatViewStmt
			| RefreshMatViewStmt
			| ExecuteStmt					/* by default all are $$=$1 */
		;

/*****************************************************************************
 *
 *		QUERY:
 *				PREPARE <plan_name> [(args, ...)] AS <query>
 *
 *****************************************************************************/

PrepareStmt: PREPARE name prep_type_clause AS PreparableStmt
				{ /*C
					PrepareStmt *n = makeNode(PrepareStmt);

					n->name = $2;
					n->argtypes = $3;
					n->query = $5;
					$$ = (Node *) n;
				*/ }
		;

prep_type_clause: '(' type_list ')'			{ $$ = $2 }
				| /* EMPTY */				{ $$ = nil }
		;

PreparableStmt:
			SelectStmt
			| InsertStmt
			| UpdateStmt
			| DeleteStmt
			| MergeStmt						/* by default all are $$=$1 */
		;

/*****************************************************************************
 *
 * EXECUTE <plan_name> [(params, ...)]
 * CREATE TABLE <name> AS EXECUTE <plan_name> [(params, ...)]
 *
 *****************************************************************************/

ExecuteStmt: EXECUTE name execute_param_clause
				{ /*C
					ExecuteStmt *n = makeNode(ExecuteStmt);

					n->name = $2;
					n->params = $3;
					$$ = (Node *) n;
				*/ }
			| CREATE OptTemp TABLE create_as_target AS
				EXECUTE name execute_param_clause opt_with_data
				{ /*C
					CreateTableAsStmt *ctas = makeNode(CreateTableAsStmt);
					ExecuteStmt *n = makeNode(ExecuteStmt);

					n->name = $7;
					n->params = $8;
					ctas->query = (Node *) n;
					ctas->into = $4;
					ctas->objtype = OBJECT_TABLE;
					ctas->is_select_into = false;
					ctas->if_not_exists = false;
					/* cram additional flags into the IntoClause * /
					$4->rel->relpersistence = $2;
					$4->skipData = !($9);
					$$ = (Node *) ctas;
				*/ }
			| CREATE OptTemp TABLE IF_P NOT EXISTS create_as_target AS
				EXECUTE name execute_param_clause opt_with_data
				{ /*C
					CreateTableAsStmt *ctas = makeNode(CreateTableAsStmt);
					ExecuteStmt *n = makeNode(ExecuteStmt);

					n->name = $10;
					n->params = $11;
					ctas->query = (Node *) n;
					ctas->into = $7;
					ctas->objtype = OBJECT_TABLE;
					ctas->is_select_into = false;
					ctas->if_not_exists = true;
					/* cram additional flags into the IntoClause * /
					$7->rel->relpersistence = $2;
					$7->skipData = !($12);
					$$ = (Node *) ctas;
				*/ }
		;

execute_param_clause: '(' expr_list ')'				{ $$ = $2 }
					| /* EMPTY */					{ $$ = nil }
					;

