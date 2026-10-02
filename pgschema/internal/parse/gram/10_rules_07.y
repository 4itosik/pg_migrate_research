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
				{
					n := &CreatePublicationStmt{}

					n.Pubname = $3
					n.Options = $4
					$$ = n
				}
			| CREATE PUBLICATION name FOR ALL TABLES opt_definition
				{
					n := &CreatePublicationStmt{}

					n.Pubname = $3
					n.Options = $7
					n.ForAllTables = true
					$$ = n
				}
			| CREATE PUBLICATION name FOR pub_obj_list opt_definition
				{
					n := &CreatePublicationStmt{}

					n.Pubname = $3
					n.Options = $6
					n.Pubobjects = $5
					p.preprocessPubobjList(n.Pubobjects)
					$$ = n
				}
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
				{
					n := &PublicationObjSpec{}

					n.Pubobjtype = PUBLICATIONOBJ_TABLE
					n.Pubtable = &PublicationTable{}
					n.Pubtable.Relation = as[*RangeVar]($2)
					n.Pubtable.Columns = $3
					n.Pubtable.WhereClause = $4
					$$ = n
				}
			| TABLES IN_P SCHEMA ColId
				{
					n := &PublicationObjSpec{}

					n.Pubobjtype = PUBLICATIONOBJ_TABLES_IN_SCHEMA
					n.Name = $4
					n.Location = @4
					$$ = n
				}
			| TABLES IN_P SCHEMA CURRENT_SCHEMA
				{
					n := &PublicationObjSpec{}

					n.Pubobjtype = PUBLICATIONOBJ_TABLES_IN_CUR_SCHEMA
					n.Location = @4
					$$ = n
				}
			| ColId opt_column_list OptWhereClause
				{
					n := &PublicationObjSpec{}

					n.Pubobjtype = PUBLICATIONOBJ_CONTINUATION
					/*
					 * If either a row filter or column list is specified, create
					 * a PublicationTable object.
					 */
					if $2 != nil || $3 != nil {
						/*
						 * The OptWhereClause must be stored here but it is
						 * valid only for tables. For non-table objects, an
						 * error will be thrown later via
						 * preprocess_pubobj_list().
						 */
						n.Pubtable = &PublicationTable{}
						n.Pubtable.Relation = makeRangeVar("", $1, @1)
						n.Pubtable.Columns = $2
						n.Pubtable.WhereClause = $3
					} else {
						n.Name = $1
					}
					n.Location = @1
					$$ = n
				}
			| ColId indirection opt_column_list OptWhereClause
				{
					n := &PublicationObjSpec{}

					n.Pubobjtype = PUBLICATIONOBJ_CONTINUATION
					n.Pubtable = &PublicationTable{}
					n.Pubtable.Relation = p.makeRangeVarFromQualifiedName($1, $2, @1)
					n.Pubtable.Columns = $3
					n.Pubtable.WhereClause = $4
					n.Location = @1
					$$ = n
				}
			/* grammar like tablename * , ONLY tablename, ONLY ( tablename ) */
			| extended_relation_expr opt_column_list OptWhereClause
				{
					n := &PublicationObjSpec{}

					n.Pubobjtype = PUBLICATIONOBJ_CONTINUATION
					n.Pubtable = &PublicationTable{}
					n.Pubtable.Relation = as[*RangeVar]($1)
					n.Pubtable.Columns = $2
					n.Pubtable.WhereClause = $3
					$$ = n
				}
			| CURRENT_SCHEMA
				{
					n := &PublicationObjSpec{}

					n.Pubobjtype = PUBLICATIONOBJ_CONTINUATION
					n.Location = @1
					$$ = n
				}
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
				{
					n := &AlterPublicationStmt{}

					n.Pubname = $3
					n.Options = $5
					$$ = n
				}
			| ALTER PUBLICATION name ADD_P pub_obj_list
				{
					n := &AlterPublicationStmt{}

					n.Pubname = $3
					n.Pubobjects = $5
					p.preprocessPubobjList(n.Pubobjects)
					n.Action = AP_AddObjects
					$$ = n
				}
			| ALTER PUBLICATION name SET pub_obj_list
				{
					n := &AlterPublicationStmt{}

					n.Pubname = $3
					n.Pubobjects = $5
					p.preprocessPubobjList(n.Pubobjects)
					n.Action = AP_SetObjects
					$$ = n
				}
			| ALTER PUBLICATION name DROP pub_obj_list
				{
					n := &AlterPublicationStmt{}

					n.Pubname = $3
					n.Pubobjects = $5
					p.preprocessPubobjList(n.Pubobjects)
					n.Action = AP_DropObjects
					$$ = n
				}
		;

/*****************************************************************************
 *
 * CREATE SUBSCRIPTION name ...
 *
 *****************************************************************************/

CreateSubscriptionStmt:
			CREATE SUBSCRIPTION name CONNECTION Sconst PUBLICATION name_list opt_definition
				{
					n := &CreateSubscriptionStmt{}

					n.Subname = $3
					n.Conninfo = $5
					n.Publication = $7
					n.Options = $8
					$$ = n
				}
		;

/*****************************************************************************
 *
 * ALTER SUBSCRIPTION name ...
 *
 *****************************************************************************/

AlterSubscriptionStmt:
			ALTER SUBSCRIPTION name SET definition
				{
					n := &AlterSubscriptionStmt{}

					n.Kind = ALTER_SUBSCRIPTION_OPTIONS
					n.Subname = $3
					n.Options = $5
					$$ = n
				}
			| ALTER SUBSCRIPTION name CONNECTION Sconst
				{
					n := &AlterSubscriptionStmt{}

					n.Kind = ALTER_SUBSCRIPTION_CONNECTION
					n.Subname = $3
					n.Conninfo = $5
					$$ = n
				}
			| ALTER SUBSCRIPTION name REFRESH PUBLICATION opt_definition
				{
					n := &AlterSubscriptionStmt{}

					n.Kind = ALTER_SUBSCRIPTION_REFRESH
					n.Subname = $3
					n.Options = $6
					$$ = n
				}
			| ALTER SUBSCRIPTION name ADD_P PUBLICATION name_list opt_definition
				{
					n := &AlterSubscriptionStmt{}

					n.Kind = ALTER_SUBSCRIPTION_ADD_PUBLICATION
					n.Subname = $3
					n.Publication = $6
					n.Options = $7
					$$ = n
				}
			| ALTER SUBSCRIPTION name DROP PUBLICATION name_list opt_definition
				{
					n := &AlterSubscriptionStmt{}

					n.Kind = ALTER_SUBSCRIPTION_DROP_PUBLICATION
					n.Subname = $3
					n.Publication = $6
					n.Options = $7
					$$ = n
				}
			| ALTER SUBSCRIPTION name SET PUBLICATION name_list opt_definition
				{
					n := &AlterSubscriptionStmt{}

					n.Kind = ALTER_SUBSCRIPTION_SET_PUBLICATION
					n.Subname = $3
					n.Publication = $6
					n.Options = $7
					$$ = n
				}
			| ALTER SUBSCRIPTION name ENABLE_P
				{
					n := &AlterSubscriptionStmt{}

					n.Kind = ALTER_SUBSCRIPTION_ENABLED
					n.Subname = $3
					n.Options = []Node{makeDefElem("enabled",
						makeBoolean(true), @1)}
					$$ = n
				}
			| ALTER SUBSCRIPTION name DISABLE_P
				{
					n := &AlterSubscriptionStmt{}

					n.Kind = ALTER_SUBSCRIPTION_ENABLED
					n.Subname = $3
					n.Options = []Node{makeDefElem("enabled",
						makeBoolean(false), @1)}
					$$ = n
				}
			| ALTER SUBSCRIPTION name SKIP definition
				{
					n := &AlterSubscriptionStmt{}

					n.Kind = ALTER_SUBSCRIPTION_SKIP
					n.Subname = $3
					n.Options = $5
					$$ = n
				}
		;

/*****************************************************************************
 *
 * DROP SUBSCRIPTION [ IF EXISTS ] name
 *
 *****************************************************************************/

DropSubscriptionStmt: DROP SUBSCRIPTION name opt_drop_behavior
				{
					n := &DropSubscriptionStmt{}

					n.Subname = $3
					n.MissingOk = false
					n.Behavior = DropBehavior($4)
					$$ = n
				}
				|  DROP SUBSCRIPTION IF_P EXISTS name opt_drop_behavior
				{
					n := &DropSubscriptionStmt{}

					n.Subname = $5
					n.MissingOk = true
					n.Behavior = DropBehavior($6)
					$$ = n
				}
		;

/*****************************************************************************
 *
 *		QUERY:	Define Rewrite Rule
 *
 *****************************************************************************/

RuleStmt:	CREATE opt_or_replace RULE name AS
			ON event TO qualified_name where_clause
			DO opt_instead RuleActionList
				{
					n := &RuleStmt{}

					n.Replace = $2
					n.Relation = as[*RangeVar]($9)
					n.Rulename = $4
					n.WhereClause = $10
					n.Event = CmdType($7)
					n.Instead = $12
					n.Actions = $13
					$$ = n
				}
		;

RuleActionList:
			NOTHING									{ $$ = nil }
			| RuleActionStmt						{ $$ = []Node{$1} }
			| '(' RuleActionMulti ')'				{ $$ = $2 }
		;

/* the thrashing around here is to discard "empty" statements... */
RuleActionMulti:
			RuleActionMulti ';' RuleActionStmtOrEmpty
				{
					if $3 != nil {
						$$ = append($1, $3)
					} else {
						$$ = $1
					}
				}
			| RuleActionStmtOrEmpty
				{
					if $1 != nil {
						$$ = []Node{$1}
					} else {
						$$ = nil
					}
				}
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

event:		SELECT									{ $$ = int32(CMD_SELECT) }
			| UPDATE								{ $$ = int32(CMD_UPDATE) }
			| DELETE_P								{ $$ = int32(CMD_DELETE) }
			| INSERT								{ $$ = int32(CMD_INSERT) }
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
				{
					n := &NotifyStmt{}

					n.Conditionname = $2
					n.Payload = $3
					$$ = n
				}
		;

notify_payload:
			',' Sconst							{ $$ = $2 }
			| /*EMPTY*/							{ $$ = "" }
		;

ListenStmt: LISTEN ColId
				{
					n := &ListenStmt{}

					n.Conditionname = $2
					$$ = n
				}
		;

UnlistenStmt:
			UNLISTEN ColId
				{
					n := &UnlistenStmt{}

					n.Conditionname = $2
					$$ = n
				}
			| UNLISTEN '*'
				{
					n := &UnlistenStmt{}

					n.Conditionname = ""
					$$ = n
				}
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
				{
					n := &TransactionStmt{}

					n.Kind = TRANS_STMT_ROLLBACK
					n.Options = nil
					n.Chain = $3
					n.Location = -1
					$$ = n
				}
			| START TRANSACTION transaction_mode_list_or_empty
				{
					n := &TransactionStmt{}

					n.Kind = TRANS_STMT_START
					n.Options = $3
					n.Location = -1
					$$ = n
				}
			| COMMIT opt_transaction opt_transaction_chain
				{
					n := &TransactionStmt{}

					n.Kind = TRANS_STMT_COMMIT
					n.Options = nil
					n.Chain = $3
					n.Location = -1
					$$ = n
				}
			| ROLLBACK opt_transaction opt_transaction_chain
				{
					n := &TransactionStmt{}

					n.Kind = TRANS_STMT_ROLLBACK
					n.Options = nil
					n.Chain = $3
					n.Location = -1
					$$ = n
				}
			| SAVEPOINT ColId
				{
					n := &TransactionStmt{}

					n.Kind = TRANS_STMT_SAVEPOINT
					n.SavepointName = $2
					n.Location = @2
					$$ = n
				}
			| RELEASE SAVEPOINT ColId
				{
					n := &TransactionStmt{}

					n.Kind = TRANS_STMT_RELEASE
					n.SavepointName = $3
					n.Location = @3
					$$ = n
				}
			| RELEASE ColId
				{
					n := &TransactionStmt{}

					n.Kind = TRANS_STMT_RELEASE
					n.SavepointName = $2
					n.Location = @2
					$$ = n
				}
			| ROLLBACK opt_transaction TO SAVEPOINT ColId
				{
					n := &TransactionStmt{}

					n.Kind = TRANS_STMT_ROLLBACK_TO
					n.SavepointName = $5
					n.Location = @5
					$$ = n
				}
			| ROLLBACK opt_transaction TO ColId
				{
					n := &TransactionStmt{}

					n.Kind = TRANS_STMT_ROLLBACK_TO
					n.SavepointName = $4
					n.Location = @4
					$$ = n
				}
			| PREPARE TRANSACTION Sconst
				{
					n := &TransactionStmt{}

					n.Kind = TRANS_STMT_PREPARE
					n.Gid = $3
					n.Location = @3
					$$ = n
				}
			| COMMIT PREPARED Sconst
				{
					n := &TransactionStmt{}

					n.Kind = TRANS_STMT_COMMIT_PREPARED
					n.Gid = $3
					n.Location = @3
					$$ = n
				}
			| ROLLBACK PREPARED Sconst
				{
					n := &TransactionStmt{}

					n.Kind = TRANS_STMT_ROLLBACK_PREPARED
					n.Gid = $3
					n.Location = @3
					$$ = n
				}
		;

TransactionStmtLegacy:
			BEGIN_P opt_transaction transaction_mode_list_or_empty
				{
					n := &TransactionStmt{}

					n.Kind = TRANS_STMT_BEGIN
					n.Options = $3
					n.Location = -1
					$$ = n
				}
			| END_P opt_transaction opt_transaction_chain
				{
					n := &TransactionStmt{}

					n.Kind = TRANS_STMT_COMMIT
					n.Options = nil
					n.Chain = $3
					n.Location = -1
					$$ = n
				}
		;

opt_transaction:	WORK
			| TRANSACTION
			| /*EMPTY*/
		;

transaction_mode_item:
			ISOLATION LEVEL iso_level
					{
						$$ = makeDefElem("transaction_isolation",
							makeStringConst($3, @3), @1)
					}
			| READ ONLY
					{
						$$ = makeDefElem("transaction_read_only",
							makeIntConst(1, @1), @1)
					}
			| READ WRITE
					{
						$$ = makeDefElem("transaction_read_only",
							makeIntConst(0, @1), @1)
					}
			| DEFERRABLE
					{
						$$ = makeDefElem("transaction_deferrable",
							makeIntConst(1, @1), @1)
					}
			| NOT DEFERRABLE
					{
						$$ = makeDefElem("transaction_deferrable",
							makeIntConst(0, @1), @1)
					}
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
				{
					n := &ViewStmt{}

					n.View = as[*RangeVar]($4)
					n.View.Relpersistence = string(rune($2))
					n.Aliases = $5
					n.Query = $8
					n.Replace = false
					n.Options = $6
					n.WithCheckOption = ViewCheckOption($9)
					$$ = n
				}
		| CREATE OR REPLACE OptTemp VIEW qualified_name opt_column_list opt_reloptions
				AS SelectStmt opt_check_option
				{
					n := &ViewStmt{}

					n.View = as[*RangeVar]($6)
					n.View.Relpersistence = string(rune($4))
					n.Aliases = $7
					n.Query = $10
					n.Replace = true
					n.Options = $8
					n.WithCheckOption = ViewCheckOption($11)
					$$ = n
				}
		| CREATE OptTemp RECURSIVE VIEW qualified_name '(' columnList ')' opt_reloptions
				AS SelectStmt opt_check_option
				{
					n := &ViewStmt{}

					n.View = as[*RangeVar]($5)
					n.View.Relpersistence = string(rune($2))
					n.Aliases = $7
					n.Query = p.makeRecursiveViewSelect(n.View.Relname, n.Aliases, $11)
					n.Replace = false
					n.Options = $9
					n.WithCheckOption = ViewCheckOption($12)
					if n.WithCheckOption != NO_CHECK_OPTION {
						p.fail(@12, "WITH CHECK OPTION not supported on recursive views")
					}
					$$ = n
				}
		| CREATE OR REPLACE OptTemp RECURSIVE VIEW qualified_name '(' columnList ')' opt_reloptions
				AS SelectStmt opt_check_option
				{
					n := &ViewStmt{}

					n.View = as[*RangeVar]($7)
					n.View.Relpersistence = string(rune($4))
					n.Aliases = $9
					n.Query = p.makeRecursiveViewSelect(n.View.Relname, n.Aliases, $13)
					n.Replace = true
					n.Options = $11
					n.WithCheckOption = ViewCheckOption($14)
					if n.WithCheckOption != NO_CHECK_OPTION {
						p.fail(@14, "WITH CHECK OPTION not supported on recursive views")
					}
					$$ = n
				}
		;

opt_check_option:
		WITH CHECK OPTION				{ $$ = int32(CASCADED_CHECK_OPTION) }
		| WITH CASCADED CHECK OPTION	{ $$ = int32(CASCADED_CHECK_OPTION) }
		| WITH LOCAL CHECK OPTION		{ $$ = int32(LOCAL_CHECK_OPTION) }
		| /* EMPTY */					{ $$ = int32(NO_CHECK_OPTION) }
		;

/*****************************************************************************
 *
 *		QUERY:
 *				LOAD "filename"
 *
 *****************************************************************************/

LoadStmt:	LOAD file_name
				{
					n := &LoadStmt{}

					n.Filename = $2
					$$ = n
				}
		;


/*****************************************************************************
 *
 *		CREATE DATABASE
 *
 *****************************************************************************/

CreatedbStmt:
			CREATE DATABASE name opt_with createdb_opt_list
				{
					n := &CreatedbStmt{}

					n.Dbname = $3
					n.Options = $5
					$$ = n
				}
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
				{ $$ = makeDefElem($1, $3, @1) }
			| createdb_opt_name opt_equal opt_boolean_or_string
				{ $$ = makeDefElem($1, makeString($3, @3), @1) }
			| createdb_opt_name opt_equal DEFAULT
				{ $$ = makeDefElem($1, nil, @1) }
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
			| CONNECTION LIMIT				{ $$ = "connection_limit" }
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
				 {
				 	n := &AlterDatabaseStmt{}

				 	n.Dbname = $3
				 	n.Options = $5
				 	$$ = n
				 }
			| ALTER DATABASE name createdb_opt_list
				 {
				 	n := &AlterDatabaseStmt{}

				 	n.Dbname = $3
				 	n.Options = $4
				 	$$ = n
				 }
			| ALTER DATABASE name SET TABLESPACE name
				 {
				 	n := &AlterDatabaseStmt{}

				 	n.Dbname = $3
				 	n.Options = []Node{makeDefElem("tablespace",
				 		makeString($6, @6), @6)}
				 	$$ = n
				 }
			| ALTER DATABASE name REFRESH COLLATION VERSION_P
				 {
				 	n := &AlterDatabaseRefreshCollStmt{}

				 	n.Dbname = $3
				 	$$ = n
				 }
		;

AlterDatabaseSetStmt:
			ALTER DATABASE name SetResetClause
				{
					n := &AlterDatabaseSetStmt{}

					n.Dbname = $3
					n.Setstmt = as[*VariableSetStmt]($4)
					$$ = n
				}
		;


/*****************************************************************************
 *
 *		DROP DATABASE [ IF EXISTS ] dbname [ [ WITH ] ( options ) ]
 *
 * This is implicitly CASCADE, no need for drop behavior
 *****************************************************************************/

DropdbStmt: DROP DATABASE name
				{
					n := &DropdbStmt{}

					n.Dbname = $3
					n.MissingOk = false
					n.Options = nil
					$$ = n
				}
			| DROP DATABASE IF_P EXISTS name
				{
					n := &DropdbStmt{}

					n.Dbname = $5
					n.MissingOk = true
					n.Options = nil
					$$ = n
				}
			| DROP DATABASE name opt_with '(' drop_option_list ')'
				{
					n := &DropdbStmt{}

					n.Dbname = $3
					n.MissingOk = false
					n.Options = $6
					$$ = n
				}
			| DROP DATABASE IF_P EXISTS name opt_with '(' drop_option_list ')'
				{
					n := &DropdbStmt{}

					n.Dbname = $5
					n.MissingOk = true
					n.Options = $8
					$$ = n
				}
		;

drop_option_list:
			drop_option
				{ $$ = []Node{$1} }
			| drop_option_list ',' drop_option
				{ $$ = append($1, $3) }
		;

/*
 * Currently only the FORCE option is supported, but the syntax is designed
 * to be extensible so that we can add more options in the future if required.
 */
drop_option:
			FORCE
				{ $$ = makeDefElem("force", nil, @1) }
		;

/*****************************************************************************
 *
 *		ALTER COLLATION
 *
 *****************************************************************************/

AlterCollationStmt: ALTER COLLATION any_name REFRESH VERSION_P
				{
					n := &AlterCollationStmt{}

					n.Collname = $3
					$$ = n
				}
		;


/*****************************************************************************
 *
 *		ALTER SYSTEM
 *
 * This is used to change configuration parameters persistently.
 *****************************************************************************/

AlterSystemStmt:
			ALTER SYSTEM_P SET generic_set
				{
					n := &AlterSystemStmt{}

					n.Setstmt = as[*VariableSetStmt]($4)
					$$ = n
				}
			| ALTER SYSTEM_P RESET generic_reset
				{
					n := &AlterSystemStmt{}

					n.Setstmt = as[*VariableSetStmt]($4)
					$$ = n
				}
		;


/*****************************************************************************
 *
 * Manipulate a domain
 *
 *****************************************************************************/

CreateDomainStmt:
			CREATE DOMAIN_P any_name opt_as Typename ColQualList
				{
					n := &CreateDomainStmt{}

					n.Domainname = $3
					n.TypeName = as[*TypeName]($5)
					n.Constraints, n.CollClause = p.splitColQualList($6)
					$$ = n
				}
		;

AlterDomainStmt:
			/* ALTER DOMAIN <domain> {SET DEFAULT <expr>|DROP DEFAULT} */
			ALTER DOMAIN_P any_name alter_column_default
				{
					n := &AlterDomainStmt{}

					n.Subtype = "T"
					n.TypeName = $3
					n.Def = $4
					$$ = n
				}
			/* ALTER DOMAIN <domain> DROP NOT NULL */
			| ALTER DOMAIN_P any_name DROP NOT NULL_P
				{
					n := &AlterDomainStmt{}

					n.Subtype = "N"
					n.TypeName = $3
					$$ = n
				}
			/* ALTER DOMAIN <domain> SET NOT NULL */
			| ALTER DOMAIN_P any_name SET NOT NULL_P
				{
					n := &AlterDomainStmt{}

					n.Subtype = "O"
					n.TypeName = $3
					$$ = n
				}
			/* ALTER DOMAIN <domain> ADD CONSTRAINT ... */
			| ALTER DOMAIN_P any_name ADD_P DomainConstraint
				{
					n := &AlterDomainStmt{}

					n.Subtype = "C"
					n.TypeName = $3
					n.Def = $5
					$$ = n
				}
			/* ALTER DOMAIN <domain> DROP CONSTRAINT <name> [RESTRICT|CASCADE] */
			| ALTER DOMAIN_P any_name DROP CONSTRAINT name opt_drop_behavior
				{
					n := &AlterDomainStmt{}

					n.Subtype = "X"
					n.TypeName = $3
					n.Name = $6
					n.Behavior = DropBehavior($7)
					n.MissingOk = false
					$$ = n
				}
			/* ALTER DOMAIN <domain> DROP CONSTRAINT IF EXISTS <name> [RESTRICT|CASCADE] */
			| ALTER DOMAIN_P any_name DROP CONSTRAINT IF_P EXISTS name opt_drop_behavior
				{
					n := &AlterDomainStmt{}

					n.Subtype = "X"
					n.TypeName = $3
					n.Name = $8
					n.Behavior = DropBehavior($9)
					n.MissingOk = true
					$$ = n
				}
			/* ALTER DOMAIN <domain> VALIDATE CONSTRAINT <name> */
			| ALTER DOMAIN_P any_name VALIDATE CONSTRAINT name
				{
					n := &AlterDomainStmt{}

					n.Subtype = "V"
					n.TypeName = $3
					n.Name = $6
					$$ = n
				}
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
				{
					n := &AlterTSDictionaryStmt{}

					n.Dictname = $5
					n.Options = $6
					$$ = n
				}
		;

AlterTSConfigurationStmt:
			ALTER TEXT_P SEARCH CONFIGURATION any_name ADD_P MAPPING FOR name_list any_with any_name_list
				{
					n := &AlterTSConfigurationStmt{}

					n.Kind = ALTER_TSCONFIG_ADD_MAPPING
					n.Cfgname = $5
					n.Tokentype = $9
					n.Dicts = $11
					n.Override = false
					n.Replace = false
					$$ = n
				}
			| ALTER TEXT_P SEARCH CONFIGURATION any_name ALTER MAPPING FOR name_list any_with any_name_list
				{
					n := &AlterTSConfigurationStmt{}

					n.Kind = ALTER_TSCONFIG_ALTER_MAPPING_FOR_TOKEN
					n.Cfgname = $5
					n.Tokentype = $9
					n.Dicts = $11
					n.Override = true
					n.Replace = false
					$$ = n
				}
			| ALTER TEXT_P SEARCH CONFIGURATION any_name ALTER MAPPING REPLACE any_name any_with any_name
				{
					n := &AlterTSConfigurationStmt{}

					n.Kind = ALTER_TSCONFIG_REPLACE_DICT
					n.Cfgname = $5
					n.Tokentype = nil
					n.Dicts = []Node{listNode($9), listNode($11)}
					n.Override = false
					n.Replace = true
					$$ = n
				}
			| ALTER TEXT_P SEARCH CONFIGURATION any_name ALTER MAPPING FOR name_list REPLACE any_name any_with any_name
				{
					n := &AlterTSConfigurationStmt{}

					n.Kind = ALTER_TSCONFIG_REPLACE_DICT_FOR_TOKEN
					n.Cfgname = $5
					n.Tokentype = $9
					n.Dicts = []Node{listNode($11), listNode($13)}
					n.Override = false
					n.Replace = true
					$$ = n
				}
			| ALTER TEXT_P SEARCH CONFIGURATION any_name DROP MAPPING FOR name_list
				{
					n := &AlterTSConfigurationStmt{}

					n.Kind = ALTER_TSCONFIG_DROP_MAPPING
					n.Cfgname = $5
					n.Tokentype = $9
					n.MissingOk = false
					$$ = n
				}
			| ALTER TEXT_P SEARCH CONFIGURATION any_name DROP MAPPING IF_P EXISTS FOR name_list
				{
					n := &AlterTSConfigurationStmt{}

					n.Kind = ALTER_TSCONFIG_DROP_MAPPING
					n.Cfgname = $5
					n.Tokentype = $11
					n.MissingOk = true
					$$ = n
				}
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
			{
				n := &CreateConversionStmt{}

				n.ConversionName = $4
				n.ForEncodingName = $6
				n.ToEncodingName = $8
				n.FuncName = $10
				n.Def = $2
				$$ = n
			}
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
				{
					n := &ClusterStmt{}

					n.Relation = as[*RangeVar]($5)
					n.Indexname = $6
					n.Params = $3
					$$ = n
				}
			| CLUSTER '(' utility_option_list ')'
				{
					n := &ClusterStmt{}

					n.Relation = nil
					n.Indexname = ""
					n.Params = $3
					$$ = n
				}
			/* unparenthesized VERBOSE kept for pre-14 compatibility */
			| CLUSTER opt_verbose qualified_name cluster_index_specification
				{
					n := &ClusterStmt{}

					n.Relation = as[*RangeVar]($3)
					n.Indexname = $4
					n.Params = nil
					if $2 {
						n.Params = append(n.Params, makeDefElem("verbose", nil, @2))
					}
					$$ = n
				}
			/* unparenthesized VERBOSE kept for pre-17 compatibility */
			| CLUSTER opt_verbose
				{
					n := &ClusterStmt{}

					n.Relation = nil
					n.Indexname = ""
					n.Params = nil
					if $2 {
						n.Params = append(n.Params, makeDefElem("verbose", nil, @2))
					}
					$$ = n
				}
			/* kept for pre-8.3 compatibility */
			| CLUSTER opt_verbose name ON qualified_name
				{
					n := &ClusterStmt{}

					n.Relation = as[*RangeVar]($5)
					n.Indexname = $3
					n.Params = nil
					if $2 {
						n.Params = append(n.Params, makeDefElem("verbose", nil, @2))
					}
					$$ = n
				}
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
				{
					n := &VacuumStmt{}

					n.Options = nil
					if $2 {
						n.Options = append(n.Options,
							makeDefElem("full", nil, @2))
					}
					if $3 {
						n.Options = append(n.Options,
							makeDefElem("freeze", nil, @3))
					}
					if $4 {
						n.Options = append(n.Options,
							makeDefElem("verbose", nil, @4))
					}
					if $5 {
						n.Options = append(n.Options,
							makeDefElem("analyze", nil, @5))
					}
					n.Rels = $6
					n.IsVacuumcmd = true
					$$ = n
				}
			| VACUUM '(' utility_option_list ')' opt_vacuum_relation_list
				{
					n := &VacuumStmt{}

					n.Options = $3
					n.Rels = $5
					n.IsVacuumcmd = true
					$$ = n
				}
		;

AnalyzeStmt: analyze_keyword opt_verbose opt_vacuum_relation_list
				{
					n := &VacuumStmt{}

					n.Options = nil
					if $2 {
						n.Options = append(n.Options,
							makeDefElem("verbose", nil, @2))
					}
					n.Rels = $3
					n.IsVacuumcmd = false
					$$ = n
				}
			| analyze_keyword '(' utility_option_list ')' opt_vacuum_relation_list
				{
					n := &VacuumStmt{}

					n.Options = $3
					n.Rels = $5
					n.IsVacuumcmd = false
					$$ = n
				}
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
				{ $$ = makeDefElem($1, $2, @1) }
		;

utility_option_name:
			NonReservedWord							{ $$ = $1 }
			| analyze_keyword						{ $$ = "analyze" }
			| FORMAT_LA								{ $$ = "format" }
		;

utility_option_arg:
			opt_boolean_or_string					{ $$ = makeString($1, @1) }
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
				{ $$ = makeVacuumRelation(as[*RangeVar]($1), 0, $2) }
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
				{
					n := &ExplainStmt{}

					n.Query = $2
					n.Options = nil
					$$ = n
				}
		| EXPLAIN analyze_keyword opt_verbose ExplainableStmt
				{
					n := &ExplainStmt{}

					n.Query = $4
					n.Options = []Node{makeDefElem("analyze", nil, @2)}
					if $3 {
						n.Options = append(n.Options,
							makeDefElem("verbose", nil, @3))
					}
					$$ = n
				}
		| EXPLAIN VERBOSE ExplainableStmt
				{
					n := &ExplainStmt{}

					n.Query = $3
					n.Options = []Node{makeDefElem("verbose", nil, @2)}
					$$ = n
				}
		| EXPLAIN '(' utility_option_list ')' ExplainableStmt
				{
					n := &ExplainStmt{}

					n.Query = $5
					n.Options = $3
					$$ = n
				}
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
				{
					n := &PrepareStmt{}

					n.Name = $2
					n.Argtypes = $3
					n.Query = $5
					$$ = n
				}
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
				{
					n := &ExecuteStmt{}

					n.Name = $2
					n.Params = $3
					$$ = n
				}
			| CREATE OptTemp TABLE create_as_target AS
				EXECUTE name execute_param_clause opt_with_data
				{
					ctas := &CreateTableAsStmt{}
					n := &ExecuteStmt{}

					n.Name = $7
					n.Params = $8
					ctas.Query = n
					ctas.Into = as[*IntoClause]($4)
					ctas.Objtype = OBJECT_TABLE
					ctas.IsSelectInto = false
					ctas.IfNotExists = false
					/* cram additional flags into the IntoClause */
					if ctas.Into != nil { // always true once create_as_target is ported
						ctas.Into.Rel.Relpersistence = string(rune($2))
						ctas.Into.SkipData = !($9)
					}
					$$ = ctas
				}
			| CREATE OptTemp TABLE IF_P NOT EXISTS create_as_target AS
				EXECUTE name execute_param_clause opt_with_data
				{
					ctas := &CreateTableAsStmt{}
					n := &ExecuteStmt{}

					n.Name = $10
					n.Params = $11
					ctas.Query = n
					ctas.Into = as[*IntoClause]($7)
					ctas.Objtype = OBJECT_TABLE
					ctas.IsSelectInto = false
					ctas.IfNotExists = true
					/* cram additional flags into the IntoClause */
					if ctas.Into != nil { // always true once create_as_target is ported
						ctas.Into.Rel.Relpersistence = string(rune($2))
						ctas.Into.SkipData = !($12)
					}
					$$ = ctas
				}
		;

execute_param_clause: '(' expr_list ')'				{ $$ = $2 }
					| /* EMPTY */					{ $$ = nil }
					;

