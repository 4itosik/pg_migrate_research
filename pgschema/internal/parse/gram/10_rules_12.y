/* gram.y lines 17080-18520 */
/*****************************************************************************
 *
 *	target list for SELECT
 *
 *****************************************************************************/

opt_target_list: target_list						{ $$ = $1 }
			| /* EMPTY */							{ $$ = nil }
		;

target_list:
			target_el								{ $$ = []Node{$1} }
			| target_list ',' target_el				{ $$ = append($1, $3) }
		;

target_el:	a_expr AS ColLabel
				{ /*C
					$$ = makeNode(ResTarget);
					$$->name = $3;
					$$->indirection = NIL;
					$$->val = (Node *) $1;
					$$->location = @1;
				*/ }
			| a_expr BareColLabel
				{ /*C
					$$ = makeNode(ResTarget);
					$$->name = $2;
					$$->indirection = NIL;
					$$->val = (Node *) $1;
					$$->location = @1;
				*/ }
			| a_expr
				{ /*C
					$$ = makeNode(ResTarget);
					$$->name = NULL;
					$$->indirection = NIL;
					$$->val = (Node *) $1;
					$$->location = @1;
				*/ }
			| '*'
				{ /*C
					ColumnRef  *n = makeNode(ColumnRef);

					n->fields = list_make1(makeNode(A_Star));
					n->location = @1;

					$$ = makeNode(ResTarget);
					$$->name = NULL;
					$$->indirection = NIL;
					$$->val = (Node *) n;
					$$->location = @1;
				*/ }
		;


/*****************************************************************************
 *
 *	Names and constants
 *
 *****************************************************************************/

qualified_name_list:
			qualified_name							{ $$ = []Node{$1} }
			| qualified_name_list ',' qualified_name { $$ = append($1, $3) }
		;

/*
 * The production for a qualified relation name has to exactly match the
 * production for a qualified func_name, because in a FROM clause we cannot
 * tell which we are parsing until we see what comes after it ('(' for a
 * func_name, something else for a relation). Therefore we allow 'indirection'
 * which may contain subscripts, and reject that case in the C code.
 */
qualified_name:
			ColId
				{ /*C
					$$ = makeRangeVar(NULL, $1, @1);
				*/ }
			| ColId indirection
				{ /*C
					$$ = makeRangeVarFromQualifiedName($1, $2, @1, yyscanner);
				*/ }
		;

name_list:	name
					{ /*C $$ = list_make1(makeString($1)); */ }
			| name_list ',' name
					{ /*C $$ = lappend($1, makeString($3)); */ }
		;


name:		ColId									{ $$ = $1 };

attr_name:	ColLabel								{ $$ = $1 };

file_name:	Sconst									{ $$ = $1 };

/*
 * The production for a qualified func_name has to exactly match the
 * production for a qualified columnref, because we cannot tell which we
 * are parsing until we see what comes after it ('(' or Sconst for a func_name,
 * anything else for a columnref).  Therefore we allow 'indirection' which
 * may contain subscripts, and reject that case in the C code.  (If we
 * ever implement SQL99-like methods, such syntax may actually become legal!)
 */
func_name:	type_function_name
					{ /*C $$ = list_make1(makeString($1)); */ }
			| ColId indirection
					{ /*C
						$$ = check_func_name(lcons(makeString($1), $2),
											 yyscanner);
					*/ }
		;


/*
 * Constants
 */
AexprConst: Iconst
				{ /*C
					$$ = makeIntConst($1, @1);
				*/ }
			| FCONST
				{ /*C
					$$ = makeFloatConst($1, @1);
				*/ }
			| Sconst
				{ /*C
					$$ = makeStringConst($1, @1);
				*/ }
			| BCONST
				{ /*C
					$$ = makeBitStringConst($1, @1);
				*/ }
			| XCONST
				{ /*C
					/* This is a bit constant per SQL99:
					 * Without Feature F511, "BIT data type",
					 * a <general literal> shall not be a
					 * <bit string literal> or a <hex string literal>.
					 * /
					$$ = makeBitStringConst($1, @1);
				*/ }
			| func_name Sconst
				{ /*C
					/* generic type 'literal' syntax * /
					TypeName   *t = makeTypeNameFromNameList($1);

					t->location = @1;
					$$ = makeStringConstCast($2, @2, t);
				*/ }
			| func_name '(' func_arg_list opt_sort_clause ')' Sconst
				{ /*C
					/* generic syntax with a type modifier * /
					TypeName   *t = makeTypeNameFromNameList($1);
					ListCell   *lc;

					/*
					 * We must use func_arg_list and opt_sort_clause in the
					 * production to avoid reduce/reduce conflicts, but we
					 * don't actually wish to allow NamedArgExpr in this
					 * context, nor ORDER BY.
					 * /
					foreach(lc, $3)
					{
						NamedArgExpr *arg = (NamedArgExpr *) lfirst(lc);

						if (IsA(arg, NamedArgExpr))
							ereport(ERROR,
									(errcode(ERRCODE_SYNTAX_ERROR),
									 errmsg("type modifier cannot have parameter name"),
									 parser_errposition(arg->location)));
					}
					if ($4 != NIL)
							ereport(ERROR,
									(errcode(ERRCODE_SYNTAX_ERROR),
									 errmsg("type modifier cannot have ORDER BY"),
									 parser_errposition(@4)));

					t->typmods = $3;
					t->location = @1;
					$$ = makeStringConstCast($6, @6, t);
				*/ }
			| ConstTypename Sconst
				{ /*C
					$$ = makeStringConstCast($2, @2, $1);
				*/ }
			| ConstInterval Sconst opt_interval
				{ /*C
					TypeName   *t = $1;

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
			| TRUE_P
				{ /*C
					$$ = makeBoolAConst(true, @1);
				*/ }
			| FALSE_P
				{ /*C
					$$ = makeBoolAConst(false, @1);
				*/ }
			| NULL_P
				{ /*C
					$$ = makeNullAConst(@1);
				*/ }
		;

Iconst:		ICONST									{ $$ = $1 };
Sconst:		SCONST									{ $$ = $1 };

SignedIconst: Iconst								{ $$ = $1 }
			| '+' Iconst							{ /*C $$ = + $2; */ }
			| '-' Iconst							{ /*C $$ = - $2; */ }
		;

/* Role specifications */
RoleId:		RoleSpec
				{ /*C
					RoleSpec   *spc = (RoleSpec *) $1;

					switch (spc->roletype)
					{
						case ROLESPEC_CSTRING:
							$$ = spc->rolename;
							break;
						case ROLESPEC_PUBLIC:
							ereport(ERROR,
									(errcode(ERRCODE_RESERVED_NAME),
									 errmsg("role name \"%s\" is reserved",
											"public"),
									 parser_errposition(@1)));
							break;
						case ROLESPEC_SESSION_USER:
							ereport(ERROR,
									(errcode(ERRCODE_RESERVED_NAME),
									 errmsg("%s cannot be used as a role name here",
											"SESSION_USER"),
									 parser_errposition(@1)));
							break;
						case ROLESPEC_CURRENT_USER:
							ereport(ERROR,
									(errcode(ERRCODE_RESERVED_NAME),
									 errmsg("%s cannot be used as a role name here",
											"CURRENT_USER"),
									 parser_errposition(@1)));
							break;
						case ROLESPEC_CURRENT_ROLE:
							ereport(ERROR,
									(errcode(ERRCODE_RESERVED_NAME),
									 errmsg("%s cannot be used as a role name here",
											"CURRENT_ROLE"),
									 parser_errposition(@1)));
							break;
					}
				*/ }
			;

RoleSpec:	NonReservedWord
				{ /*C
					/*
					 * "public" and "none" are not keywords, but they must
					 * be treated specially here.
					 * /
					RoleSpec   *n;

					if (strcmp($1, "public") == 0)
					{
						n = (RoleSpec *) makeRoleSpec(ROLESPEC_PUBLIC, @1);
						n->roletype = ROLESPEC_PUBLIC;
					}
					else if (strcmp($1, "none") == 0)
					{
						ereport(ERROR,
								(errcode(ERRCODE_RESERVED_NAME),
								 errmsg("role name \"%s\" is reserved",
										"none"),
								 parser_errposition(@1)));
					}
					else
					{
						n = makeRoleSpec(ROLESPEC_CSTRING, @1);
						n->rolename = pstrdup($1);
					}
					$$ = n;
				*/ }
			| CURRENT_ROLE
				{ /*C
					$$ = makeRoleSpec(ROLESPEC_CURRENT_ROLE, @1);
				*/ }
			| CURRENT_USER
				{ /*C
					$$ = makeRoleSpec(ROLESPEC_CURRENT_USER, @1);
				*/ }
			| SESSION_USER
				{ /*C
					$$ = makeRoleSpec(ROLESPEC_SESSION_USER, @1);
				*/ }
		;

role_list:	RoleSpec
				{ $$ = []Node{$1} }
			| role_list ',' RoleSpec
				{ $$ = append($1, $3) }
		;


/*****************************************************************************
 *
 * PL/pgSQL extensions
 *
 * You'd think a PL/pgSQL "expression" should be just an a_expr, but
 * historically it can include just about anything that can follow SELECT.
 * Therefore the returned struct is a SelectStmt.
 *****************************************************************************/

PLpgSQL_Expr: opt_distinct_clause opt_target_list
			from_clause where_clause
			group_clause having_clause window_clause
			opt_sort_clause opt_select_limit opt_for_locking_clause
				{ /*C
					SelectStmt *n = makeNode(SelectStmt);

					n->distinctClause = $1;
					n->targetList = $2;
					n->fromClause = $3;
					n->whereClause = $4;
					n->groupClause = ($5)->list;
					n->groupDistinct = ($5)->distinct;
					n->havingClause = $6;
					n->windowClause = $7;
					n->sortClause = $8;
					if ($9)
					{
						n->limitOffset = $9->limitOffset;
						n->limitCount = $9->limitCount;
						if (!n->sortClause &&
							$9->limitOption == LIMIT_OPTION_WITH_TIES)
							ereport(ERROR,
									(errcode(ERRCODE_SYNTAX_ERROR),
									 errmsg("WITH TIES cannot be specified without ORDER BY clause")));
						n->limitOption = $9->limitOption;
					}
					n->lockingClause = $10;
					$$ = (Node *) n;
				*/ }
		;

/*
 * PL/pgSQL Assignment statement: name opt_indirection := PLpgSQL_Expr
 */

PLAssignStmt: plassign_target opt_indirection plassign_equals PLpgSQL_Expr
				{ /*C
					PLAssignStmt *n = makeNode(PLAssignStmt);

					n->name = $1;
					n->indirection = check_indirection($2, yyscanner);
					/* nnames will be filled by calling production * /
					n->val = (SelectStmt *) $4;
					n->location = @1;
					$$ = (Node *) n;
				*/ }
		;

plassign_target: ColId							{ $$ = $1 }
			| PARAM								{ /*C $$ = psprintf("$%d", $1); */ }
		;

plassign_equals: COLON_EQUALS
			| '='
		;


/*
 * Name classification hierarchy.
 *
 * IDENT is the lexeme returned by the lexer for identifiers that match
 * no known keyword.  In most cases, we can accept certain keywords as
 * names, not only IDENTs.	We prefer to accept as many such keywords
 * as possible to minimize the impact of "reserved words" on programmers.
 * So, we divide names into several possible classes.  The classification
 * is chosen in part to make keywords acceptable as names wherever possible.
 */

/* Column identifier --- names that can be column, table, etc names.
 */
ColId:		IDENT									{ $$ = $1 }
			| unreserved_keyword					{ $$ = $1 }
			| col_name_keyword						{ $$ = $1 }
		;

/* Type/function identifier --- names that can be type or function names.
 */
type_function_name:	IDENT							{ $$ = $1 }
			| unreserved_keyword					{ $$ = $1 }
			| type_func_name_keyword				{ $$ = $1 }
		;

/* Any not-fully-reserved word --- these names can be, eg, role names.
 */
NonReservedWord:	IDENT							{ $$ = $1 }
			| unreserved_keyword					{ $$ = $1 }
			| col_name_keyword						{ $$ = $1 }
			| type_func_name_keyword				{ $$ = $1 }
		;

/* Column label --- allowed labels in "AS" clauses.
 * This presently includes *all* Postgres keywords.
 */
ColLabel:	IDENT									{ $$ = $1 }
			| unreserved_keyword					{ $$ = $1 }
			| col_name_keyword						{ $$ = $1 }
			| type_func_name_keyword				{ $$ = $1 }
			| reserved_keyword						{ $$ = $1 }
		;

/* Bare column label --- names that can be column labels without writing "AS".
 * This classification is orthogonal to the other keyword categories.
 */
BareColLabel:	IDENT								{ $$ = $1 }
			| bare_label_keyword					{ $$ = $1 }
		;


/*
 * Keyword category lists.  Generally, every keyword present in
 * the Postgres grammar should appear in exactly one of these lists.
 *
 * Put a new keyword into the first list that it can go into without causing
 * shift or reduce conflicts.  The earlier lists define "less reserved"
 * categories of keywords.
 *
 * Make sure that each keyword's category in kwlist.h matches where
 * it is listed here.  (Someday we may be able to generate these lists and
 * kwlist.h's table from one source of truth.)
 */

/* "Unreserved" keywords --- available for use as any kind of name.
 */
unreserved_keyword:
			  ABORT_P
			| ABSENT
			| ABSOLUTE_P
			| ACCESS
			| ACTION
			| ADD_P
			| ADMIN
			| AFTER
			| AGGREGATE
			| ALSO
			| ALTER
			| ALWAYS
			| ASENSITIVE
			| ASSERTION
			| ASSIGNMENT
			| AT
			| ATOMIC
			| ATTACH
			| ATTRIBUTE
			| BACKWARD
			| BEFORE
			| BEGIN_P
			| BREADTH
			| BY
			| CACHE
			| CALL
			| CALLED
			| CASCADE
			| CASCADED
			| CATALOG_P
			| CHAIN
			| CHARACTERISTICS
			| CHECKPOINT
			| CLASS
			| CLOSE
			| CLUSTER
			| COLUMNS
			| COMMENT
			| COMMENTS
			| COMMIT
			| COMMITTED
			| COMPRESSION
			| CONDITIONAL
			| CONFIGURATION
			| CONFLICT
			| CONNECTION
			| CONSTRAINTS
			| CONTENT_P
			| CONTINUE_P
			| CONVERSION_P
			| COPY
			| COST
			| CSV
			| CUBE
			| CURRENT_P
			| CURSOR
			| CYCLE
			| DATA_P
			| DATABASE
			| DAY_P
			| DEALLOCATE
			| DECLARE
			| DEFAULTS
			| DEFERRED
			| DEFINER
			| DELETE_P
			| DELIMITER
			| DELIMITERS
			| DEPENDS
			| DEPTH
			| DETACH
			| DICTIONARY
			| DISABLE_P
			| DISCARD
			| DOCUMENT_P
			| DOMAIN_P
			| DOUBLE_P
			| DROP
			| EACH
			| EMPTY_P
			| ENABLE_P
			| ENCODING
			| ENCRYPTED
			| ENUM_P
			| ERROR_P
			| ESCAPE
			| EVENT
			| EXCLUDE
			| EXCLUDING
			| EXCLUSIVE
			| EXECUTE
			| EXPLAIN
			| EXPRESSION
			| EXTENSION
			| EXTERNAL
			| FAMILY
			| FILTER
			| FINALIZE
			| FIRST_P
			| FOLLOWING
			| FORCE
			| FORMAT
			| FORWARD
			| FUNCTION
			| FUNCTIONS
			| GENERATED
			| GLOBAL
			| GRANTED
			| GROUPS
			| HANDLER
			| HEADER_P
			| HOLD
			| HOUR_P
			| IDENTITY_P
			| IF_P
			| IMMEDIATE
			| IMMUTABLE
			| IMPLICIT_P
			| IMPORT_P
			| INCLUDE
			| INCLUDING
			| INCREMENT
			| INDENT
			| INDEX
			| INDEXES
			| INHERIT
			| INHERITS
			| INLINE_P
			| INPUT_P
			| INSENSITIVE
			| INSERT
			| INSTEAD
			| INVOKER
			| ISOLATION
			| KEEP
			| KEY
			| KEYS
			| LABEL
			| LANGUAGE
			| LARGE_P
			| LAST_P
			| LEAKPROOF
			| LEVEL
			| LISTEN
			| LOAD
			| LOCAL
			| LOCATION
			| LOCK_P
			| LOCKED
			| LOGGED
			| MAPPING
			| MATCH
			| MATCHED
			| MATERIALIZED
			| MAXVALUE
			| MERGE
			| METHOD
			| MINUTE_P
			| MINVALUE
			| MODE
			| MONTH_P
			| MOVE
			| NAME_P
			| NAMES
			| NESTED
			| NEW
			| NEXT
			| NFC
			| NFD
			| NFKC
			| NFKD
			| NO
			| NORMALIZED
			| NOTHING
			| NOTIFY
			| NOWAIT
			| NULLS_P
			| OBJECT_P
			| OF
			| OFF
			| OIDS
			| OLD
			| OMIT
			| OPERATOR
			| OPTION
			| OPTIONS
			| ORDINALITY
			| OTHERS
			| OVER
			| OVERRIDING
			| OWNED
			| OWNER
			| PARALLEL
			| PARAMETER
			| PARSER
			| PARTIAL
			| PARTITION
			| PASSING
			| PASSWORD
			| PATH
			| PLAN
			| PLANS
			| POLICY
			| PRECEDING
			| PREPARE
			| PREPARED
			| PRESERVE
			| PRIOR
			| PRIVILEGES
			| PROCEDURAL
			| PROCEDURE
			| PROCEDURES
			| PROGRAM
			| PUBLICATION
			| QUOTE
			| QUOTES
			| RANGE
			| READ
			| REASSIGN
			| RECHECK
			| RECURSIVE
			| REF_P
			| REFERENCING
			| REFRESH
			| REINDEX
			| RELATIVE_P
			| RELEASE
			| RENAME
			| REPEATABLE
			| REPLACE
			| REPLICA
			| RESET
			| RESTART
			| RESTRICT
			| RETURN
			| RETURNS
			| REVOKE
			| ROLE
			| ROLLBACK
			| ROLLUP
			| ROUTINE
			| ROUTINES
			| ROWS
			| RULE
			| SAVEPOINT
			| SCALAR
			| SCHEMA
			| SCHEMAS
			| SCROLL
			| SEARCH
			| SECOND_P
			| SECURITY
			| SEQUENCE
			| SEQUENCES
			| SERIALIZABLE
			| SERVER
			| SESSION
			| SET
			| SETS
			| SHARE
			| SHOW
			| SIMPLE
			| SKIP
			| SNAPSHOT
			| SOURCE
			| SQL_P
			| STABLE
			| STANDALONE_P
			| START
			| STATEMENT
			| STATISTICS
			| STDIN
			| STDOUT
			| STORAGE
			| STORED
			| STRICT_P
			| STRING_P
			| STRIP_P
			| SUBSCRIPTION
			| SUPPORT
			| SYSID
			| SYSTEM_P
			| TABLES
			| TABLESPACE
			| TARGET
			| TEMP
			| TEMPLATE
			| TEMPORARY
			| TEXT_P
			| TIES
			| TRANSACTION
			| TRANSFORM
			| TRIGGER
			| TRUNCATE
			| TRUSTED
			| TYPE_P
			| TYPES_P
			| UESCAPE
			| UNBOUNDED
			| UNCOMMITTED
			| UNCONDITIONAL
			| UNENCRYPTED
			| UNKNOWN
			| UNLISTEN
			| UNLOGGED
			| UNTIL
			| UPDATE
			| VACUUM
			| VALID
			| VALIDATE
			| VALIDATOR
			| VALUE_P
			| VARYING
			| VERSION_P
			| VIEW
			| VIEWS
			| VOLATILE
			| WHITESPACE_P
			| WITHIN
			| WITHOUT
			| WORK
			| WRAPPER
			| WRITE
			| XML_P
			| YEAR_P
			| YES_P
			| ZONE
		;

/* Column identifier --- keywords that can be column, table, etc names.
 *
 * Many of these keywords will in fact be recognized as type or function
 * names too; but they have special productions for the purpose, and so
 * can't be treated as "generic" type or function names.
 *
 * The type names appearing here are not usable as function names
 * because they can be followed by '(' in typename productions, which
 * looks too much like a function call for an LR(1) parser.
 */
col_name_keyword:
			  BETWEEN
			| BIGINT
			| BIT
			| BOOLEAN_P
			| CHAR_P
			| CHARACTER
			| COALESCE
			| DEC
			| DECIMAL_P
			| EXISTS
			| EXTRACT
			| FLOAT_P
			| GREATEST
			| GROUPING
			| INOUT
			| INT_P
			| INTEGER
			| INTERVAL
			| JSON
			| JSON_ARRAY
			| JSON_ARRAYAGG
			| JSON_EXISTS
			| JSON_OBJECT
			| JSON_OBJECTAGG
			| JSON_QUERY
			| JSON_SCALAR
			| JSON_SERIALIZE
			| JSON_TABLE
			| JSON_VALUE
			| LEAST
			| MERGE_ACTION
			| NATIONAL
			| NCHAR
			| NONE
			| NORMALIZE
			| NULLIF
			| NUMERIC
			| OUT_P
			| OVERLAY
			| POSITION
			| PRECISION
			| REAL
			| ROW
			| SETOF
			| SMALLINT
			| SUBSTRING
			| TIME
			| TIMESTAMP
			| TREAT
			| TRIM
			| VALUES
			| VARCHAR
			| XMLATTRIBUTES
			| XMLCONCAT
			| XMLELEMENT
			| XMLEXISTS
			| XMLFOREST
			| XMLNAMESPACES
			| XMLPARSE
			| XMLPI
			| XMLROOT
			| XMLSERIALIZE
			| XMLTABLE
		;

/* Type/function identifier --- keywords that can be type or function names.
 *
 * Most of these are keywords that are used as operators in expressions;
 * in general such keywords can't be column names because they would be
 * ambiguous with variables, but they are unambiguous as function identifiers.
 *
 * Do not include POSITION, SUBSTRING, etc here since they have explicit
 * productions in a_expr to support the goofy SQL9x argument syntax.
 * - thomas 2000-11-28
 */
type_func_name_keyword:
			  AUTHORIZATION
			| BINARY
			| COLLATION
			| CONCURRENTLY
			| CROSS
			| CURRENT_SCHEMA
			| FREEZE
			| FULL
			| ILIKE
			| INNER_P
			| IS
			| ISNULL
			| JOIN
			| LEFT
			| LIKE
			| NATURAL
			| NOTNULL
			| OUTER_P
			| OVERLAPS
			| RIGHT
			| SIMILAR
			| TABLESAMPLE
			| VERBOSE
		;

/* Reserved keyword --- these keywords are usable only as a ColLabel.
 *
 * Keywords appear here if they could not be distinguished from variable,
 * type, or function names in some contexts.  Don't put things here unless
 * forced to.
 */
reserved_keyword:
			  ALL
			| ANALYSE
			| ANALYZE
			| AND
			| ANY
			| ARRAY
			| AS
			| ASC
			| ASYMMETRIC
			| BOTH
			| CASE
			| CAST
			| CHECK
			| COLLATE
			| COLUMN
			| CONSTRAINT
			| CREATE
			| CURRENT_CATALOG
			| CURRENT_DATE
			| CURRENT_ROLE
			| CURRENT_TIME
			| CURRENT_TIMESTAMP
			| CURRENT_USER
			| DEFAULT
			| DEFERRABLE
			| DESC
			| DISTINCT
			| DO
			| ELSE
			| END_P
			| EXCEPT
			| FALSE_P
			| FETCH
			| FOR
			| FOREIGN
			| FROM
			| GRANT
			| GROUP_P
			| HAVING
			| IN_P
			| INITIALLY
			| INTERSECT
			| INTO
			| LATERAL_P
			| LEADING
			| LIMIT
			| LOCALTIME
			| LOCALTIMESTAMP
			| NOT
			| NULL_P
			| OFFSET
			| ON
			| ONLY
			| OR
			| ORDER
			| PLACING
			| PRIMARY
			| REFERENCES
			| RETURNING
			| SELECT
			| SESSION_USER
			| SOME
			| SYMMETRIC
			| SYSTEM_USER
			| TABLE
			| THEN
			| TO
			| TRAILING
			| TRUE_P
			| UNION
			| UNIQUE
			| USER
			| USING
			| VARIADIC
			| WHEN
			| WHERE
			| WINDOW
			| WITH
		;

/*
 * While all keywords can be used as column labels when preceded by AS,
 * not all of them can be used as a "bare" column label without AS.
 * Those that can be used as a bare label must be listed here,
 * in addition to appearing in one of the category lists above.
 *
 * Always add a new keyword to this list if possible.  Mark it BARE_LABEL
 * in kwlist.h if it is included here, or AS_LABEL if it is not.
 */
bare_label_keyword:
			  ABORT_P
			| ABSENT
			| ABSOLUTE_P
			| ACCESS
			| ACTION
			| ADD_P
			| ADMIN
			| AFTER
			| AGGREGATE
			| ALL
			| ALSO
			| ALTER
			| ALWAYS
			| ANALYSE
			| ANALYZE
			| AND
			| ANY
			| ASC
			| ASENSITIVE
			| ASSERTION
			| ASSIGNMENT
			| ASYMMETRIC
			| AT
			| ATOMIC
			| ATTACH
			| ATTRIBUTE
			| AUTHORIZATION
			| BACKWARD
			| BEFORE
			| BEGIN_P
			| BETWEEN
			| BIGINT
			| BINARY
			| BIT
			| BOOLEAN_P
			| BOTH
			| BREADTH
			| BY
			| CACHE
			| CALL
			| CALLED
			| CASCADE
			| CASCADED
			| CASE
			| CAST
			| CATALOG_P
			| CHAIN
			| CHARACTERISTICS
			| CHECK
			| CHECKPOINT
			| CLASS
			| CLOSE
			| CLUSTER
			| COALESCE
			| COLLATE
			| COLLATION
			| COLUMN
			| COLUMNS
			| COMMENT
			| COMMENTS
			| COMMIT
			| COMMITTED
			| COMPRESSION
			| CONCURRENTLY
			| CONDITIONAL
			| CONFIGURATION
			| CONFLICT
			| CONNECTION
			| CONSTRAINT
			| CONSTRAINTS
			| CONTENT_P
			| CONTINUE_P
			| CONVERSION_P
			| COPY
			| COST
			| CROSS
			| CSV
			| CUBE
			| CURRENT_P
			| CURRENT_CATALOG
			| CURRENT_DATE
			| CURRENT_ROLE
			| CURRENT_SCHEMA
			| CURRENT_TIME
			| CURRENT_TIMESTAMP
			| CURRENT_USER
			| CURSOR
			| CYCLE
			| DATA_P
			| DATABASE
			| DEALLOCATE
			| DEC
			| DECIMAL_P
			| DECLARE
			| DEFAULT
			| DEFAULTS
			| DEFERRABLE
			| DEFERRED
			| DEFINER
			| DELETE_P
			| DELIMITER
			| DELIMITERS
			| DEPENDS
			| DEPTH
			| DESC
			| DETACH
			| DICTIONARY
			| DISABLE_P
			| DISCARD
			| DISTINCT
			| DO
			| DOCUMENT_P
			| DOMAIN_P
			| DOUBLE_P
			| DROP
			| EACH
			| ELSE
			| EMPTY_P
			| ENABLE_P
			| ENCODING
			| ENCRYPTED
			| END_P
			| ENUM_P
			| ERROR_P
			| ESCAPE
			| EVENT
			| EXCLUDE
			| EXCLUDING
			| EXCLUSIVE
			| EXECUTE
			| EXISTS
			| EXPLAIN
			| EXPRESSION
			| EXTENSION
			| EXTERNAL
			| EXTRACT
			| FALSE_P
			| FAMILY
			| FINALIZE
			| FIRST_P
			| FLOAT_P
			| FOLLOWING
			| FORCE
			| FOREIGN
			| FORMAT
			| FORWARD
			| FREEZE
			| FULL
			| FUNCTION
			| FUNCTIONS
			| GENERATED
			| GLOBAL
			| GRANTED
			| GREATEST
			| GROUPING
			| GROUPS
			| HANDLER
			| HEADER_P
			| HOLD
			| IDENTITY_P
			| IF_P
			| ILIKE
			| IMMEDIATE
			| IMMUTABLE
			| IMPLICIT_P
			| IMPORT_P
			| IN_P
			| INCLUDE
			| INCLUDING
			| INCREMENT
			| INDENT
			| INDEX
			| INDEXES
			| INHERIT
			| INHERITS
			| INITIALLY
			| INLINE_P
			| INNER_P
			| INOUT
			| INPUT_P
			| INSENSITIVE
			| INSERT
			| INSTEAD
			| INT_P
			| INTEGER
			| INTERVAL
			| INVOKER
			| IS
			| ISOLATION
			| JOIN
			| JSON
			| JSON_ARRAY
			| JSON_ARRAYAGG
			| JSON_EXISTS
			| JSON_OBJECT
			| JSON_OBJECTAGG
			| JSON_QUERY
			| JSON_SCALAR
			| JSON_SERIALIZE
			| JSON_TABLE
			| JSON_VALUE
			| KEEP
			| KEY
			| KEYS
			| LABEL
			| LANGUAGE
			| LARGE_P
			| LAST_P
			| LATERAL_P
			| LEADING
			| LEAKPROOF
			| LEAST
			| LEFT
			| LEVEL
			| LIKE
			| LISTEN
			| LOAD
			| LOCAL
			| LOCALTIME
			| LOCALTIMESTAMP
			| LOCATION
			| LOCK_P
			| LOCKED
			| LOGGED
			| MAPPING
			| MATCH
			| MATCHED
			| MATERIALIZED
			| MAXVALUE
			| MERGE
			| MERGE_ACTION
			| METHOD
			| MINVALUE
			| MODE
			| MOVE
			| NAME_P
			| NAMES
			| NATIONAL
			| NATURAL
			| NCHAR
			| NESTED
			| NEW
			| NEXT
			| NFC
			| NFD
			| NFKC
			| NFKD
			| NO
			| NONE
			| NORMALIZE
			| NORMALIZED
			| NOT
			| NOTHING
			| NOTIFY
			| NOWAIT
			| NULL_P
			| NULLIF
			| NULLS_P
			| NUMERIC
			| OBJECT_P
			| OF
			| OFF
			| OIDS
			| OLD
			| OMIT
			| ONLY
			| OPERATOR
			| OPTION
			| OPTIONS
			| OR
			| ORDINALITY
			| OTHERS
			| OUT_P
			| OUTER_P
			| OVERLAY
			| OVERRIDING
			| OWNED
			| OWNER
			| PARALLEL
			| PARAMETER
			| PARSER
			| PARTIAL
			| PARTITION
			| PASSING
			| PASSWORD
			| PATH
			| PLACING
			| PLAN
			| PLANS
			| POLICY
			| POSITION
			| PRECEDING
			| PREPARE
			| PREPARED
			| PRESERVE
			| PRIMARY
			| PRIOR
			| PRIVILEGES
			| PROCEDURAL
			| PROCEDURE
			| PROCEDURES
			| PROGRAM
			| PUBLICATION
			| QUOTE
			| QUOTES
			| RANGE
			| READ
			| REAL
			| REASSIGN
			| RECHECK
			| RECURSIVE
			| REF_P
			| REFERENCES
			| REFERENCING
			| REFRESH
			| REINDEX
			| RELATIVE_P
			| RELEASE
			| RENAME
			| REPEATABLE
			| REPLACE
			| REPLICA
			| RESET
			| RESTART
			| RESTRICT
			| RETURN
			| RETURNS
			| REVOKE
			| RIGHT
			| ROLE
			| ROLLBACK
			| ROLLUP
			| ROUTINE
			| ROUTINES
			| ROW
			| ROWS
			| RULE
			| SAVEPOINT
			| SCALAR
			| SCHEMA
			| SCHEMAS
			| SCROLL
			| SEARCH
			| SECURITY
			| SELECT
			| SEQUENCE
			| SEQUENCES
			| SERIALIZABLE
			| SERVER
			| SESSION
			| SESSION_USER
			| SET
			| SETOF
			| SETS
			| SHARE
			| SHOW
			| SIMILAR
			| SIMPLE
			| SKIP
			| SMALLINT
			| SNAPSHOT
			| SOME
			| SOURCE
			| SQL_P
			| STABLE
			| STANDALONE_P
			| START
			| STATEMENT
			| STATISTICS
			| STDIN
			| STDOUT
			| STORAGE
			| STORED
			| STRICT_P
			| STRING_P
			| STRIP_P
			| SUBSCRIPTION
			| SUBSTRING
			| SUPPORT
			| SYMMETRIC
			| SYSID
			| SYSTEM_P
			| SYSTEM_USER
			| TABLE
			| TABLES
			| TABLESAMPLE
			| TABLESPACE
			| TARGET
			| TEMP
			| TEMPLATE
			| TEMPORARY
			| TEXT_P
			| THEN
			| TIES
			| TIME
			| TIMESTAMP
			| TRAILING
			| TRANSACTION
			| TRANSFORM
			| TREAT
			| TRIGGER
			| TRIM
			| TRUE_P
			| TRUNCATE
			| TRUSTED
			| TYPE_P
			| TYPES_P
			| UESCAPE
			| UNBOUNDED
			| UNCOMMITTED
			| UNCONDITIONAL
			| UNENCRYPTED
			| UNIQUE
			| UNKNOWN
			| UNLISTEN
			| UNLOGGED
			| UNTIL
			| UPDATE
			| USER
			| USING
			| VACUUM
			| VALID
			| VALIDATE
			| VALIDATOR
			| VALUE_P
			| VALUES
			| VARCHAR
			| VARIADIC
			| VERBOSE
			| VERSION_P
			| VIEW
			| VIEWS
			| VOLATILE
			| WHEN
			| WHITESPACE_P
			| WORK
			| WRAPPER
			| WRITE
			| XML_P
			| XMLATTRIBUTES
			| XMLCONCAT
			| XMLELEMENT
			| XMLEXISTS
			| XMLFOREST
			| XMLNAMESPACES
			| XMLPARSE
			| XMLPI
			| XMLROOT
			| XMLSERIALIZE
			| XMLTABLE
			| YES_P
			| ZONE
		;

