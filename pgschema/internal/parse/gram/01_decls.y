%type <node>	stmt toplevel_stmt schema_stmt routine_body_stmt
		AlterEventTrigStmt AlterCollationStmt
		AlterDatabaseStmt AlterDatabaseSetStmt AlterDomainStmt AlterEnumStmt
		AlterFdwStmt AlterForeignServerStmt AlterGroupStmt
		AlterObjectDependsStmt AlterObjectSchemaStmt AlterOwnerStmt
		AlterOperatorStmt AlterTypeStmt AlterSeqStmt AlterSystemStmt AlterTableStmt
		AlterTblSpcStmt AlterExtensionStmt AlterExtensionContentsStmt
		AlterCompositeTypeStmt AlterUserMappingStmt
		AlterRoleStmt AlterRoleSetStmt AlterPolicyStmt AlterStatsStmt
		AlterDefaultPrivilegesStmt DefACLAction
		AnalyzeStmt CallStmt ClosePortalStmt ClusterStmt CommentStmt
		ConstraintsSetStmt CopyStmt CreateAsStmt CreateCastStmt
		CreateDomainStmt CreateExtensionStmt CreateGroupStmt CreateOpClassStmt
		CreateOpFamilyStmt AlterOpFamilyStmt CreatePLangStmt
		CreateSchemaStmt CreateSeqStmt CreateStmt CreateStatsStmt CreateTableSpaceStmt
		CreateFdwStmt CreateForeignServerStmt CreateForeignTableStmt
		CreateAssertionStmt CreateTransformStmt CreateTrigStmt CreateEventTrigStmt
		CreateUserStmt CreateUserMappingStmt CreateRoleStmt CreatePolicyStmt
		CreatedbStmt DeclareCursorStmt DefineStmt DeleteStmt DiscardStmt DoStmt
		DropOpClassStmt DropOpFamilyStmt DropStmt
		DropCastStmt DropRoleStmt
		DropdbStmt DropTableSpaceStmt
		DropTransformStmt
		DropUserMappingStmt ExplainStmt FetchStmt
		GrantStmt GrantRoleStmt ImportForeignSchemaStmt IndexStmt InsertStmt
		ListenStmt LoadStmt LockStmt MergeStmt NotifyStmt ExplainableStmt PreparableStmt
		CreateFunctionStmt AlterFunctionStmt ReindexStmt RemoveAggrStmt
		RemoveFuncStmt RemoveOperStmt RenameStmt ReturnStmt RevokeStmt RevokeRoleStmt
		RuleActionStmt RuleActionStmtOrEmpty RuleStmt
		SecLabelStmt SelectStmt TransactionStmt TransactionStmtLegacy TruncateStmt
		UnlistenStmt UpdateStmt VacuumStmt
		VariableResetStmt VariableSetStmt VariableShowStmt
		ViewStmt CheckPointStmt CreateConversionStmt
		DeallocateStmt PrepareStmt ExecuteStmt
		DropOwnedStmt ReassignOwnedStmt
		AlterTSConfigurationStmt AlterTSDictionaryStmt
		CreateMatViewStmt RefreshMatViewStmt CreateAmStmt
		CreatePublicationStmt AlterPublicationStmt
		CreateSubscriptionStmt AlterSubscriptionStmt DropSubscriptionStmt

%type <node>	select_no_parens select_with_parens select_clause
				simple_select values_clause
				PLpgSQL_Expr PLAssignStmt

%type <str>			opt_single_name
%type <list>		opt_qualified_name
%type <boolean>		opt_concurrently
%type <ival>	opt_drop_behavior

%type <node>	alter_column_default opclass_item opclass_drop alter_using
%type <ival>	add_drop opt_asc_desc opt_nulls_order

%type <node>	alter_table_cmd alter_type_cmd opt_collate_clause
	   replica_identity partition_cmd index_partition_cmd
%type <list>	alter_table_cmds alter_type_cmds
%type <list>    alter_identity_column_option_list
%type <node>  alter_identity_column_option
%type <node>	set_statistics_value
%type <str>		set_access_method_name

%type <list>	createdb_opt_list createdb_opt_items copy_opt_list
				transaction_mode_list
				create_extension_opt_list alter_extension_opt_list
%type <node>	createdb_opt_item copy_opt_item
				transaction_mode_item
				create_extension_opt_item alter_extension_opt_item

%type <ival>	opt_lock lock_type cast_context
%type <str>		utility_option_name
%type <node>	utility_option_elem
%type <list>	utility_option_list
%type <node>	utility_option_arg
%type <node>	drop_option
%type <boolean>	opt_or_replace opt_no
				opt_grant_grant_option
				opt_nowait opt_if_exists opt_with_data
				opt_transaction_chain
%type <list>	grant_role_opt_list
%type <node>	grant_role_opt
%type <node>	grant_role_opt_value
%type <ival>	opt_nowait_or_skip

%type <list>	OptRoleList AlterOptRoleList
%type <node>	CreateOptRoleElem AlterOptRoleElem

%type <str>		opt_type
%type <str>		foreign_server_version opt_foreign_server_version
%type <str>		opt_in_database

%type <str>		parameter_name
%type <list>	OptSchemaEltList parameter_name_list

%type <str>		am_type

%type <boolean> TriggerForSpec TriggerForType
%type <ival>	TriggerActionTime
%type <list>	TriggerEvents TriggerOneEvent
%type <node>	TriggerFuncArg
%type <node>	TriggerWhen
%type <str>		TransitionRelName
%type <boolean>	TransitionRowOrTable TransitionOldOrNew
%type <node>	TriggerTransition

%type <list>	event_trigger_when_list event_trigger_value_list
%type <node>	event_trigger_when_item
%type <str>		enable_trigger

%type <str>		copy_file_name
				access_method_clause attr_name
				table_access_method_clause name cursor_name file_name
				cluster_index_specification

%type <list>	func_name handler_name qual_Op qual_all_Op subquery_Op
				opt_inline_handler opt_validator validator_clause
				opt_collate

%type <node>	qualified_name insert_target OptConstrFromTable

%type <str>		all_Op MathOp

%type <str>		row_security_cmd RowSecurityDefaultForCmd
%type <boolean> RowSecurityDefaultPermissive
%type <node>	RowSecurityOptionalWithCheck RowSecurityOptionalExpr
%type <list>	RowSecurityDefaultToRole RowSecurityOptionalToRole

%type <str>		iso_level opt_encoding
%type <node> grantee
%type <list>	grantee_list
%type <node> privilege
%type <list>	privileges privilege_list
%type <node> privilege_target
%type <node> function_with_argtypes aggregate_with_argtypes operator_with_argtypes
%type <list>	function_with_argtypes_list aggregate_with_argtypes_list operator_with_argtypes_list
%type <ival>	defacl_privilege_target
%type <node>	DefACLOption
%type <list>	DefACLOptionList
%type <ival>	import_qualification_type
%type <node> import_qualification
%type <node>	vacuum_relation
%type <node> opt_select_limit select_limit limit_clause

%type <list>	parse_toplevel stmtmulti routine_body_stmt_list
				OptTableElementList TableElementList OptInherit definition
				OptTypedTableElementList TypedTableElementList
				reloptions opt_reloptions
				OptWith opt_definition func_args func_args_list
				func_args_with_defaults func_args_with_defaults_list
				aggr_args aggr_args_list
				func_as createfunc_opt_list opt_createfunc_opt_list alterfunc_opt_list
				old_aggr_definition old_aggr_list
				oper_argtypes RuleActionList RuleActionMulti
				opt_column_list columnList opt_name_list
				sort_clause opt_sort_clause sortby_list index_params
				stats_params
				opt_include opt_c_include index_including_params
				name_list role_list from_clause from_list opt_array_bounds
				qualified_name_list any_name any_name_list type_name_list
				any_operator expr_list attrs
				distinct_clause opt_distinct_clause
				target_list opt_target_list insert_column_list set_target_list
				merge_values_clause
				set_clause_list set_clause
				def_list operator_def_list indirection opt_indirection
				reloption_list TriggerFuncArgs opclass_item_list opclass_drop_list
				opclass_purpose opt_opfamily transaction_mode_list_or_empty
				OptTableFuncElementList TableFuncElementList opt_type_modifiers
				prep_type_clause
				execute_param_clause using_clause returning_clause
				opt_enum_val_list enum_val_list table_func_column_list
				create_generic_options alter_generic_options
				relation_expr_list dostmt_opt_list
				transform_element_list transform_type_list
				TriggerTransitions TriggerReferencing
				vacuum_relation_list opt_vacuum_relation_list
				drop_option_list pub_obj_list

%type <node>	opt_routine_body
%type <node> group_clause
%type <list>	group_by_list
%type <node>	group_by_item empty_grouping_set rollup_clause cube_clause
%type <node>	grouping_sets_clause

%type <list>	opt_fdw_options fdw_options
%type <node>	fdw_option

%type <node>	OptTempTableName
%type <node>	into_clause create_as_target create_mv_target

%type <node>	createfunc_opt_item common_func_opt_item dostmt_opt_item
%type <node> func_arg func_arg_with_default table_func_column aggr_arg
%type <ival> arg_class
%type <node>	func_return func_type

%type <boolean>  opt_trusted opt_restart_seqs
%type <ival>	 OptTemp
%type <ival>	 OptNoLog
%type <ival> OnCommitOption

%type <ival>	for_locking_strength
%type <node>	for_locking_item
%type <list>	for_locking_clause opt_for_locking_clause for_locking_items
%type <list>	locked_rels_list
%type <ival> set_quantifier

%type <node>	join_qual
%type <ival>	join_type

%type <list>	extract_list overlay_list position_list
%type <list>	substr_list trim_list
%type <list>	opt_interval interval_second
%type <str>		unicode_normal_form

%type <boolean> opt_instead
%type <boolean> opt_unique opt_verbose opt_full
%type <boolean> opt_freeze opt_analyze opt_default opt_recheck
%type <node>	opt_binary copy_delimiter

%type <boolean> copy_from opt_program

%type <ival>	event cursor_options opt_hold opt_set_data
%type <ival>	object_type_any_name object_type_name object_type_name_on_any_name
				drop_type_name

%type <node>	fetch_args select_limit_value
				offset_clause select_offset_value
				select_fetch_first_value I_or_F_const
%type <ival>	row_or_rows first_or_next

%type <list>	OptSeqOptList SeqOptList OptParenthesizedSeqOptList
%type <node>	SeqOptElem

%type <node>	insert_rest
%type <node>	opt_conf_expr
%type <node> opt_on_conflict
%type <node>	merge_insert merge_update merge_delete

%type <ival> merge_when_tgt_matched merge_when_tgt_not_matched
%type <node>	merge_when_clause opt_merge_when_condition
%type <list>	merge_when_list

%type <node> generic_set set_rest set_rest_more generic_reset reset_rest
				 SetResetClause FunctionSetResetClause

%type <node>	TableElement TypedTableElement ConstraintElem DomainConstraintElem TableFuncElement
%type <node>	columnDef columnOptions
%type <node>	def_elem reloption_elem old_aggr_elem operator_def_elem
%type <node>	def_arg columnElem where_clause where_or_current_clause
				a_expr b_expr c_expr AexprConst indirection_el opt_slice_bound
				columnref in_expr having_clause func_table xmltable array_expr
				OptWhereClause operator_def_arg
%type <list>	rowsfrom_item rowsfrom_list opt_col_def_list
%type <boolean> opt_ordinality
%type <list>	ExclusionConstraintList ExclusionConstraintElem
%type <list>	func_arg_list func_arg_list_opt
%type <node>	func_arg_expr
%type <list>	row explicit_row implicit_row type_list array_expr_list
%type <node>	case_expr case_arg when_clause case_default
%type <list>	when_clause_list
%type <node>	opt_search_clause opt_cycle_clause
%type <ival>	sub_type opt_materialized
%type <node>	NumericOnly
%type <list>	NumericOnly_list
%type <node>	alias_clause opt_alias_clause opt_alias_clause_for_join_using
%type <list>	func_alias_clause
%type <node>	sortby
%type <node>	index_elem index_elem_options
%type <node>	stats_param
%type <node>	table_ref
%type <node>	joined_table
%type <node>	relation_expr
%type <node>	extended_relation_expr
%type <node>	relation_expr_opt_alias
%type <node>	tablesample_clause opt_repeatable_clause
%type <node>	target_el set_target insert_column_item

%type <str>		generic_option_name
%type <node>	generic_option_arg
%type <node>	generic_option_elem alter_generic_option_elem
%type <list>	generic_option_list alter_generic_option_list

%type <ival>	reindex_target_relation reindex_target_all
%type <list>	opt_reindex_option_list

%type <node>	copy_generic_opt_arg copy_generic_opt_arg_list_item
%type <node>	copy_generic_opt_elem
%type <list>	copy_generic_opt_list copy_generic_opt_arg_list
%type <list>	copy_options

%type <node>	Typename SimpleTypename ConstTypename
				GenericType Numeric opt_float JsonType
				Character ConstCharacter
				CharacterWithLength CharacterWithoutLength
				ConstDatetime ConstInterval
				Bit ConstBit BitWithLength BitWithoutLength
%type <str>		character
%type <str>		extract_arg
%type <boolean> opt_varying opt_timezone opt_no_inherit

%type <ival>	Iconst SignedIconst
%type <str>		Sconst comment_text notify_payload
%type <str>		RoleId opt_boolean_or_string
%type <list>	var_list
%type <str>		ColId ColLabel BareColLabel
%type <str>		NonReservedWord NonReservedWord_or_Sconst
%type <str>		var_name type_function_name param_name
%type <str>		createdb_opt_name plassign_target
%type <node>	var_value zone_value
%type <node> auth_ident RoleSpec opt_granted_by
%type <node> PublicationObjSpec

%type <str> unreserved_keyword type_func_name_keyword
%type <str> col_name_keyword reserved_keyword
%type <str> bare_label_keyword

%type <node>	DomainConstraint TableConstraint TableLikeClause
%type <ival>	TableLikeOptionList TableLikeOption
%type <str>		column_compression opt_column_compression column_storage opt_column_storage
%type <list>	ColQualList
%type <node>	ColConstraint ColConstraintElem ConstraintAttr
%type <ival>	key_match
%type <node> key_delete key_update key_action
%type <node> key_actions
%type <ival>	ConstraintAttributeSpec ConstraintAttributeElem
%type <str>		ExistingIndex

%type <list>	constraints_set_list
%type <boolean> constraints_set_mode
%type <str>		OptTableSpace OptConsTableSpace
%type <node> OptTableSpaceOwner
%type <ival>	opt_check_option

%type <str>		opt_provider security_label

%type <node>	xml_attribute_el
%type <list>	xml_attribute_list xml_attributes
%type <node>	xml_root_version opt_xml_root_standalone
%type <node>	xmlexists_argument
%type <ival>	document_or_content
%type <boolean>	xml_indent_option xml_whitespace_option
%type <list>	xmltable_column_list xmltable_column_option_list
%type <node>	xmltable_column_el
%type <node>	xmltable_column_option_el
%type <list>	xml_namespace_list
%type <node>	xml_namespace_el

%type <node>	func_application func_expr_common_subexpr
%type <node>	func_expr func_expr_windowless
%type <node>	common_table_expr
%type <node>	with_clause opt_with_clause
%type <list>	cte_list

%type <list>	within_group_clause
%type <node>	filter_clause
%type <list>	window_clause window_definition_list opt_partition_clause
%type <node>	window_definition over_clause window_specification
				opt_frame_clause frame_extent frame_bound
%type <ival>	opt_window_exclusion_clause
%type <str>		opt_existing_window_name
%type <boolean> opt_if_not_exists
%type <boolean> opt_unique_null_treatment
%type <ival>	generated_when override_kind
%type <node>	PartitionSpec OptPartitionSpec
%type <node>	part_elem
%type <list>		part_params
%type <node> PartitionBoundSpec
%type <list>		hash_partbound
%type <node>		hash_partbound_elem

%type <node>	json_format_clause
				json_format_clause_opt
				json_value_expr
				json_returning_clause_opt
				json_name_and_value
				json_aggregate_func
				json_argument
				json_behavior
				json_on_error_clause_opt
				json_table
				json_table_column_definition
				json_table_column_path_clause_opt
%type <list>	json_name_and_value_list
				json_value_expr_list
				json_array_aggregate_order_by_clause_opt
				json_arguments
				json_behavior_clause_opt
				json_passing_clause_opt
				json_table_column_definition_list
%type <str>		json_table_path_name_opt
%type <ival>	json_behavior_type
				json_predicate_type_constraint
				json_quotes_clause_opt
				json_wrapper_behavior
%type <boolean>	json_key_uniqueness_constraint_opt
				json_object_constructor_null_clause_opt
				json_array_constructor_null_clause_opt


/*
 * Non-keyword token types.  These are hard-wired into the "flex" lexer.
 * They must be listed first so that their numeric codes do not depend on
 * the set of keywords.  PL/pgSQL depends on this so that it can share the
 * same lexer.  If you add/change tokens here, fix PL/pgSQL to match!
 *
 * UIDENT and USCONST are reduced to IDENT and SCONST in parser.c, so that
 * they need no productions here; but we must assign token codes to them.
 *
 * DOT_DOT is unused in the core SQL grammar, and so will always provoke
 * parse errors.  It is needed by PL/pgSQL.
 */
%token <str>	IDENT UIDENT FCONST SCONST USCONST BCONST XCONST Op
%token <ival>	ICONST PARAM
%token			TYPECAST DOT_DOT COLON_EQUALS EQUALS_GREATER
%token			LESS_EQUALS GREATER_EQUALS NOT_EQUALS

/*
 * If you want to make any keyword changes, update the keyword table in
 * src/include/parser/kwlist.h and add new keywords to the appropriate one
 * of the reserved-or-not-so-reserved keyword lists, below; search
 * this file for "Keyword category lists".
 */

/* ordinary key words in alphabetical order */
%token <str> ABORT_P ABSENT ABSOLUTE_P ACCESS ACTION ADD_P ADMIN AFTER
	AGGREGATE ALL ALSO ALTER ALWAYS ANALYSE ANALYZE AND ANY ARRAY AS ASC
	ASENSITIVE ASSERTION ASSIGNMENT ASYMMETRIC ATOMIC AT ATTACH ATTRIBUTE AUTHORIZATION

	BACKWARD BEFORE BEGIN_P BETWEEN BIGINT BINARY BIT
	BOOLEAN_P BOTH BREADTH BY

	CACHE CALL CALLED CASCADE CASCADED CASE CAST CATALOG_P CHAIN CHAR_P
	CHARACTER CHARACTERISTICS CHECK CHECKPOINT CLASS CLOSE
	CLUSTER COALESCE COLLATE COLLATION COLUMN COLUMNS COMMENT COMMENTS COMMIT
	COMMITTED COMPRESSION CONCURRENTLY CONDITIONAL CONFIGURATION CONFLICT
	CONNECTION CONSTRAINT CONSTRAINTS CONTENT_P CONTINUE_P CONVERSION_P COPY
	COST CREATE CROSS CSV CUBE CURRENT_P
	CURRENT_CATALOG CURRENT_DATE CURRENT_ROLE CURRENT_SCHEMA
	CURRENT_TIME CURRENT_TIMESTAMP CURRENT_USER CURSOR CYCLE

	DATA_P DATABASE DAY_P DEALLOCATE DEC DECIMAL_P DECLARE DEFAULT DEFAULTS
	DEFERRABLE DEFERRED DEFINER DELETE_P DELIMITER DELIMITERS DEPENDS DEPTH DESC
	DETACH DICTIONARY DISABLE_P DISCARD DISTINCT DO DOCUMENT_P DOMAIN_P
	DOUBLE_P DROP

	EACH ELSE EMPTY_P ENABLE_P ENCODING ENCRYPTED END_P ENUM_P ERROR_P ESCAPE
	EVENT EXCEPT EXCLUDE EXCLUDING EXCLUSIVE EXECUTE EXISTS EXPLAIN EXPRESSION
	EXTENSION EXTERNAL EXTRACT

	FALSE_P FAMILY FETCH FILTER FINALIZE FIRST_P FLOAT_P FOLLOWING FOR
	FORCE FOREIGN FORMAT FORWARD FREEZE FROM FULL FUNCTION FUNCTIONS

	GENERATED GLOBAL GRANT GRANTED GREATEST GROUP_P GROUPING GROUPS

	HANDLER HAVING HEADER_P HOLD HOUR_P

	IDENTITY_P IF_P ILIKE IMMEDIATE IMMUTABLE IMPLICIT_P IMPORT_P IN_P INCLUDE
	INCLUDING INCREMENT INDENT INDEX INDEXES INHERIT INHERITS INITIALLY INLINE_P
	INNER_P INOUT INPUT_P INSENSITIVE INSERT INSTEAD INT_P INTEGER
	INTERSECT INTERVAL INTO INVOKER IS ISNULL ISOLATION

	JOIN JSON JSON_ARRAY JSON_ARRAYAGG JSON_EXISTS JSON_OBJECT JSON_OBJECTAGG
	JSON_QUERY JSON_SCALAR JSON_SERIALIZE JSON_TABLE JSON_VALUE

	KEEP KEY KEYS

	LABEL LANGUAGE LARGE_P LAST_P LATERAL_P
	LEADING LEAKPROOF LEAST LEFT LEVEL LIKE LIMIT LISTEN LOAD LOCAL
	LOCALTIME LOCALTIMESTAMP LOCATION LOCK_P LOCKED LOGGED

	MAPPING MATCH MATCHED MATERIALIZED MAXVALUE MERGE MERGE_ACTION METHOD
	MINUTE_P MINVALUE MODE MONTH_P MOVE

	NAME_P NAMES NATIONAL NATURAL NCHAR NESTED NEW NEXT NFC NFD NFKC NFKD NO
	NONE NORMALIZE NORMALIZED
	NOT NOTHING NOTIFY NOTNULL NOWAIT NULL_P NULLIF
	NULLS_P NUMERIC

	OBJECT_P OF OFF OFFSET OIDS OLD OMIT ON ONLY OPERATOR OPTION OPTIONS OR
	ORDER ORDINALITY OTHERS OUT_P OUTER_P
	OVER OVERLAPS OVERLAY OVERRIDING OWNED OWNER

	PARALLEL PARAMETER PARSER PARTIAL PARTITION PASSING PASSWORD PATH
	PLACING PLAN PLANS POLICY
	POSITION PRECEDING PRECISION PRESERVE PREPARE PREPARED PRIMARY
	PRIOR PRIVILEGES PROCEDURAL PROCEDURE PROCEDURES PROGRAM PUBLICATION

	QUOTE QUOTES

	RANGE READ REAL REASSIGN RECHECK RECURSIVE REF_P REFERENCES REFERENCING
	REFRESH REINDEX RELATIVE_P RELEASE RENAME REPEATABLE REPLACE REPLICA
	RESET RESTART RESTRICT RETURN RETURNING RETURNS REVOKE RIGHT ROLE ROLLBACK ROLLUP
	ROUTINE ROUTINES ROW ROWS RULE

	SAVEPOINT SCALAR SCHEMA SCHEMAS SCROLL SEARCH SECOND_P SECURITY SELECT
	SEQUENCE SEQUENCES
	SERIALIZABLE SERVER SESSION SESSION_USER SET SETS SETOF SHARE SHOW
	SIMILAR SIMPLE SKIP SMALLINT SNAPSHOT SOME SOURCE SQL_P STABLE STANDALONE_P
	START STATEMENT STATISTICS STDIN STDOUT STORAGE STORED STRICT_P STRING_P STRIP_P
	SUBSCRIPTION SUBSTRING SUPPORT SYMMETRIC SYSID SYSTEM_P SYSTEM_USER

	TABLE TABLES TABLESAMPLE TABLESPACE TARGET TEMP TEMPLATE TEMPORARY TEXT_P THEN
	TIES TIME TIMESTAMP TO TRAILING TRANSACTION TRANSFORM
	TREAT TRIGGER TRIM TRUE_P
	TRUNCATE TRUSTED TYPE_P TYPES_P

	UESCAPE UNBOUNDED UNCONDITIONAL UNCOMMITTED UNENCRYPTED UNION UNIQUE UNKNOWN
	UNLISTEN UNLOGGED UNTIL UPDATE USER USING

	VACUUM VALID VALIDATE VALIDATOR VALUE_P VALUES VARCHAR VARIADIC VARYING
	VERBOSE VERSION_P VIEW VIEWS VOLATILE

	WHEN WHERE WHITESPACE_P WINDOW WITH WITHIN WITHOUT WORK WRAPPER WRITE

	XML_P XMLATTRIBUTES XMLCONCAT XMLELEMENT XMLEXISTS XMLFOREST XMLNAMESPACES
	XMLPARSE XMLPI XMLROOT XMLSERIALIZE XMLTABLE

	YEAR_P YES_P

	ZONE

/*
 * The grammar thinks these are keywords, but they are not in the kwlist.h
 * list and so can never be entered directly.  The filter in parser.c
 * creates these tokens when required (based on looking one token ahead).
 *
 * NOT_LA exists so that productions such as NOT LIKE can be given the same
 * precedence as LIKE; otherwise they'd effectively have the same precedence
 * as NOT, at least with respect to their left-hand subexpression.
 * FORMAT_LA, NULLS_LA, WITH_LA, and WITHOUT_LA are needed to make the grammar
 * LALR(1).
 */
%token		FORMAT_LA NOT_LA NULLS_LA WITH_LA WITHOUT_LA

/*
 * The grammar likewise thinks these tokens are keywords, but they are never
 * generated by the scanner.  Rather, they can be injected by parser.c as
 * the initial token of the string (using the lookahead-token mechanism
 * implemented there).  This provides a way to tell the grammar to parse
 * something other than the usual list of SQL commands.
 */
%token		MODE_TYPE_NAME
%token		MODE_PLPGSQL_EXPR
%token		MODE_PLPGSQL_ASSIGN1
%token		MODE_PLPGSQL_ASSIGN2
%token		MODE_PLPGSQL_ASSIGN3


/* Precedence: lowest to highest */
%left		UNION EXCEPT
%left		INTERSECT
%left		OR
%left		AND
%right		NOT
%nonassoc	IS ISNULL NOTNULL	/* IS sets precedence for IS NULL, etc */
%nonassoc	'<' '>' '=' LESS_EQUALS GREATER_EQUALS NOT_EQUALS
%nonassoc	BETWEEN IN_P LIKE ILIKE SIMILAR NOT_LA
%nonassoc	ESCAPE			/* ESCAPE must be just above LIKE/ILIKE/SIMILAR */

/*
 * Sometimes it is necessary to assign precedence to keywords that are not
 * really part of the operator hierarchy, in order to resolve grammar
 * ambiguities.  It's best to avoid doing so whenever possible, because such
 * assignments have global effect and may hide ambiguities besides the one
 * you intended to solve.  (Attaching a precedence to a single rule with
 * %prec is far safer and should be preferred.)  If you must give precedence
 * to a new keyword, try very hard to give it the same precedence as IDENT.
 * If the keyword has IDENT's precedence then it clearly acts the same as
 * non-keywords and other similar keywords, thus reducing the risk of
 * unexpected precedence effects.
 *
 * We used to need to assign IDENT an explicit precedence just less than Op,
 * to support target_el without AS.  While that's not really necessary since
 * we removed postfix operators, we continue to do so because it provides a
 * reference point for a precedence level that we can assign to other
 * keywords that lack a natural precedence level.
 *
 * We need to do this for PARTITION, RANGE, ROWS, and GROUPS to support
 * opt_existing_window_name (see comment there).
 *
 * The frame_bound productions UNBOUNDED PRECEDING and UNBOUNDED FOLLOWING
 * are even messier: since UNBOUNDED is an unreserved keyword (per spec!),
 * there is no principled way to distinguish these from the productions
 * a_expr PRECEDING/FOLLOWING.  We hack this up by giving UNBOUNDED slightly
 * lower precedence than PRECEDING and FOLLOWING.  At present this doesn't
 * appear to cause UNBOUNDED to be treated differently from other unreserved
 * keywords anywhere else in the grammar, but it's definitely risky.  We can
 * blame any funny behavior of UNBOUNDED on the SQL standard, though.
 *
 * To support CUBE and ROLLUP in GROUP BY without reserving them, we give them
 * an explicit priority lower than '(', so that a rule with CUBE '(' will shift
 * rather than reducing a conflicting rule that takes CUBE as a function name.
 * Using the same precedence as IDENT seems right for the reasons given above.
 *
 * SET is likewise assigned the same precedence as IDENT, to support the
 * relation_expr_opt_alias production (see comment there).
 *
 * KEYS, OBJECT_P, SCALAR, VALUE_P, WITH, and WITHOUT are similarly assigned
 * the same precedence as IDENT.  This allows resolving conflicts in the
 * json_predicate_type_constraint and json_key_uniqueness_constraint_opt
 * productions (see comments there).
 *
 * Like the UNBOUNDED PRECEDING/FOLLOWING case, NESTED is assigned a lower
 * precedence than PATH to fix ambiguity in the json_table production.
 */
%nonassoc	UNBOUNDED NESTED /* ideally would have same precedence as IDENT */
%nonassoc	IDENT PARTITION RANGE ROWS GROUPS PRECEDING FOLLOWING CUBE ROLLUP
			SET KEYS OBJECT_P SCALAR VALUE_P WITH WITHOUT PATH
%left		Op OPERATOR		/* multi-character ops and user-defined operators */
%left		'+' '-'
%left		'*' '/' '%'
%left		'^'
/* Unary Operators */
%left		AT				/* sets precedence for AT TIME ZONE, AT LOCAL */
%left		COLLATE
%right		UMINUS
%left		'[' ']'
%left		'(' ')'
%left		TYPECAST
%left		'.'
/*
 * These might seem to be low-precedence, but actually they are not part
 * of the arithmetic hierarchy at all in their use as JOIN operators.
 * We make them high-precedence to support their use as function names.
 * They wouldn't be given a precedence at all, were it not that we need
 * left-associativity among the JOIN rules themselves.
 */
%left		JOIN CROSS LEFT FULL RIGHT INNER_P NATURAL

%%
