/* gram.y lines 3292-5159 */
/*****************************************************************************
 *
 *		QUERY :
 *				close <portalname>
 *
 *****************************************************************************/

ClosePortalStmt:
			CLOSE cursor_name
				{ /*C
					ClosePortalStmt *n = makeNode(ClosePortalStmt);

					n->portalname = $2;
					$$ = (Node *) n;
				*/ }
			| CLOSE ALL
				{ /*C
					ClosePortalStmt *n = makeNode(ClosePortalStmt);

					n->portalname = NULL;
					$$ = (Node *) n;
				*/ }
		;


/*****************************************************************************
 *
 *		QUERY :
 *				COPY relname [(columnList)] FROM/TO file [WITH] [(options)]
 *				COPY ( query ) TO file	[WITH] [(options)]
 *
 *				where 'query' can be one of:
 *				{ SELECT | UPDATE | INSERT | DELETE }
 *
 *				and 'file' can be one of:
 *				{ PROGRAM 'command' | STDIN | STDOUT | 'filename' }
 *
 *				In the preferred syntax the options are comma-separated
 *				and use generic identifiers instead of keywords.  The pre-9.0
 *				syntax had a hard-wired, space-separated set of options.
 *
 *				Really old syntax, from versions 7.2 and prior:
 *				COPY [ BINARY ] table FROM/TO file
 *					[ [ USING ] DELIMITERS 'delimiter' ] ]
 *					[ WITH NULL AS 'null string' ]
 *				This option placement is not supported with COPY (query...).
 *
 *****************************************************************************/

CopyStmt:	COPY opt_binary qualified_name opt_column_list
			copy_from opt_program copy_file_name copy_delimiter opt_with
			copy_options where_clause
				{ /*C
					CopyStmt *n = makeNode(CopyStmt);

					n->relation = $3;
					n->query = NULL;
					n->attlist = $4;
					n->is_from = $5;
					n->is_program = $6;
					n->filename = $7;
					n->whereClause = $11;

					if (n->is_program && n->filename == NULL)
						ereport(ERROR,
								(errcode(ERRCODE_SYNTAX_ERROR),
								 errmsg("STDIN/STDOUT not allowed with PROGRAM"),
								 parser_errposition(@8)));

					if (!n->is_from && n->whereClause != NULL)
						ereport(ERROR,
								(errcode(ERRCODE_SYNTAX_ERROR),
								 errmsg("WHERE clause not allowed with COPY TO"),
								 parser_errposition(@11)));

					n->options = NIL;
					/* Concatenate user-supplied flags * /
					if ($2)
						n->options = lappend(n->options, $2);
					if ($8)
						n->options = lappend(n->options, $8);
					if ($10)
						n->options = list_concat(n->options, $10);
					$$ = (Node *) n;
				*/ }
			| COPY '(' PreparableStmt ')' TO opt_program copy_file_name opt_with copy_options
				{ /*C
					CopyStmt *n = makeNode(CopyStmt);

					n->relation = NULL;
					n->query = $3;
					n->attlist = NIL;
					n->is_from = false;
					n->is_program = $6;
					n->filename = $7;
					n->options = $9;

					if (n->is_program && n->filename == NULL)
						ereport(ERROR,
								(errcode(ERRCODE_SYNTAX_ERROR),
								 errmsg("STDIN/STDOUT not allowed with PROGRAM"),
								 parser_errposition(@5)));

					$$ = (Node *) n;
				*/ }
		;

copy_from:
			FROM									{ $$ = true }
			| TO									{ $$ = false }
		;

opt_program:
			PROGRAM									{ $$ = true }
			| /* EMPTY */							{ $$ = false }
		;

/*
 * copy_file_name NULL indicates stdio is used. Whether stdin or stdout is
 * used depends on the direction. (It really doesn't make sense to copy from
 * stdout. We silently correct the "typo".)		 - AY 9/94
 */
copy_file_name:
			Sconst									{ $$ = $1 }
			| STDIN									{ $$ = "" }
			| STDOUT								{ $$ = "" }
		;

copy_options: copy_opt_list							{ $$ = $1 }
			| '(' copy_generic_opt_list ')'			{ $$ = $2 }
		;

/* old COPY option syntax */
copy_opt_list:
			copy_opt_list copy_opt_item				{ $$ = append($1, $2) }
			| /* EMPTY */							{ $$ = nil }
		;

copy_opt_item:
			BINARY
				{ /*C
					$$ = makeDefElem("format", (Node *) makeString("binary"), @1);
				*/ }
			| FREEZE
				{ /*C
					$$ = makeDefElem("freeze", (Node *) makeBoolean(true), @1);
				*/ }
			| DELIMITER opt_as Sconst
				{ /*C
					$$ = makeDefElem("delimiter", (Node *) makeString($3), @1);
				*/ }
			| NULL_P opt_as Sconst
				{ /*C
					$$ = makeDefElem("null", (Node *) makeString($3), @1);
				*/ }
			| CSV
				{ /*C
					$$ = makeDefElem("format", (Node *) makeString("csv"), @1);
				*/ }
			| HEADER_P
				{ /*C
					$$ = makeDefElem("header", (Node *) makeBoolean(true), @1);
				*/ }
			| QUOTE opt_as Sconst
				{ /*C
					$$ = makeDefElem("quote", (Node *) makeString($3), @1);
				*/ }
			| ESCAPE opt_as Sconst
				{ /*C
					$$ = makeDefElem("escape", (Node *) makeString($3), @1);
				*/ }
			| FORCE QUOTE columnList
				{ /*C
					$$ = makeDefElem("force_quote", (Node *) $3, @1);
				*/ }
			| FORCE QUOTE '*'
				{ /*C
					$$ = makeDefElem("force_quote", (Node *) makeNode(A_Star), @1);
				*/ }
			| FORCE NOT NULL_P columnList
				{ /*C
					$$ = makeDefElem("force_not_null", (Node *) $4, @1);
				*/ }
			| FORCE NOT NULL_P '*'
				{ /*C
					$$ = makeDefElem("force_not_null", (Node *) makeNode(A_Star), @1);
				*/ }
			| FORCE NULL_P columnList
				{ /*C
					$$ = makeDefElem("force_null", (Node *) $3, @1);
				*/ }
			| FORCE NULL_P '*'
				{ /*C
					$$ = makeDefElem("force_null", (Node *) makeNode(A_Star), @1);
				*/ }
			| ENCODING Sconst
				{ /*C
					$$ = makeDefElem("encoding", (Node *) makeString($2), @1);
				*/ }
		;

/* The following exist for backward compatibility with very old versions */

opt_binary:
			BINARY
				{ /*C
					$$ = makeDefElem("format", (Node *) makeString("binary"), @1);
				*/ }
			| /*EMPTY*/								{ $$ = nil }
		;

copy_delimiter:
			opt_using DELIMITERS Sconst
				{ /*C
					$$ = makeDefElem("delimiter", (Node *) makeString($3), @2);
				*/ }
			| /*EMPTY*/								{ $$ = nil }
		;

opt_using:
			USING
			| /*EMPTY*/
		;

/* new COPY option syntax */
copy_generic_opt_list:
			copy_generic_opt_elem
				{ $$ = []Node{$1} }
			| copy_generic_opt_list ',' copy_generic_opt_elem
				{ $$ = append($1, $3) }
		;

copy_generic_opt_elem:
			ColLabel copy_generic_opt_arg
				{ /*C
					$$ = makeDefElem($1, $2, @1);
				*/ }
		;

copy_generic_opt_arg:
			opt_boolean_or_string			{ /*C $$ = (Node *) makeString($1); */ }
			| NumericOnly					{ $$ = $1 }
			| '*'							{ /*C $$ = (Node *) makeNode(A_Star); */ }
			| DEFAULT                       { /*C $$ = (Node *) makeString("default"); */ }
			| '(' copy_generic_opt_arg_list ')'		{ /*C $$ = (Node *) $2; */ }
			| /* EMPTY */					{ $$ = nil }
		;

copy_generic_opt_arg_list:
			  copy_generic_opt_arg_list_item
				{ $$ = []Node{$1} }
			| copy_generic_opt_arg_list ',' copy_generic_opt_arg_list_item
				{ $$ = append($1, $3) }
		;

/* beware of emitting non-string list elements here; see commands/define.c */
copy_generic_opt_arg_list_item:
			opt_boolean_or_string	{ /*C $$ = (Node *) makeString($1); */ }
		;


/*****************************************************************************
 *
 *		QUERY :
 *				CREATE TABLE relname
 *
 *****************************************************************************/

CreateStmt:	CREATE OptTemp TABLE qualified_name '(' OptTableElementList ')'
			OptInherit OptPartitionSpec table_access_method_clause OptWith
			OnCommitOption OptTableSpace
				{ /*C
					CreateStmt *n = makeNode(CreateStmt);

					$4->relpersistence = $2;
					n->relation = $4;
					n->tableElts = $6;
					n->inhRelations = $8;
					n->partspec = $9;
					n->ofTypename = NULL;
					n->constraints = NIL;
					n->accessMethod = $10;
					n->options = $11;
					n->oncommit = $12;
					n->tablespacename = $13;
					n->if_not_exists = false;
					$$ = (Node *) n;
				*/ }
		| CREATE OptTemp TABLE IF_P NOT EXISTS qualified_name '('
			OptTableElementList ')' OptInherit OptPartitionSpec table_access_method_clause
			OptWith OnCommitOption OptTableSpace
				{ /*C
					CreateStmt *n = makeNode(CreateStmt);

					$7->relpersistence = $2;
					n->relation = $7;
					n->tableElts = $9;
					n->inhRelations = $11;
					n->partspec = $12;
					n->ofTypename = NULL;
					n->constraints = NIL;
					n->accessMethod = $13;
					n->options = $14;
					n->oncommit = $15;
					n->tablespacename = $16;
					n->if_not_exists = true;
					$$ = (Node *) n;
				*/ }
		| CREATE OptTemp TABLE qualified_name OF any_name
			OptTypedTableElementList OptPartitionSpec table_access_method_clause
			OptWith OnCommitOption OptTableSpace
				{ /*C
					CreateStmt *n = makeNode(CreateStmt);

					$4->relpersistence = $2;
					n->relation = $4;
					n->tableElts = $7;
					n->inhRelations = NIL;
					n->partspec = $8;
					n->ofTypename = makeTypeNameFromNameList($6);
					n->ofTypename->location = @6;
					n->constraints = NIL;
					n->accessMethod = $9;
					n->options = $10;
					n->oncommit = $11;
					n->tablespacename = $12;
					n->if_not_exists = false;
					$$ = (Node *) n;
				*/ }
		| CREATE OptTemp TABLE IF_P NOT EXISTS qualified_name OF any_name
			OptTypedTableElementList OptPartitionSpec table_access_method_clause
			OptWith OnCommitOption OptTableSpace
				{ /*C
					CreateStmt *n = makeNode(CreateStmt);

					$7->relpersistence = $2;
					n->relation = $7;
					n->tableElts = $10;
					n->inhRelations = NIL;
					n->partspec = $11;
					n->ofTypename = makeTypeNameFromNameList($9);
					n->ofTypename->location = @9;
					n->constraints = NIL;
					n->accessMethod = $12;
					n->options = $13;
					n->oncommit = $14;
					n->tablespacename = $15;
					n->if_not_exists = true;
					$$ = (Node *) n;
				*/ }
		| CREATE OptTemp TABLE qualified_name PARTITION OF qualified_name
			OptTypedTableElementList PartitionBoundSpec OptPartitionSpec
			table_access_method_clause OptWith OnCommitOption OptTableSpace
				{ /*C
					CreateStmt *n = makeNode(CreateStmt);

					$4->relpersistence = $2;
					n->relation = $4;
					n->tableElts = $8;
					n->inhRelations = list_make1($7);
					n->partbound = $9;
					n->partspec = $10;
					n->ofTypename = NULL;
					n->constraints = NIL;
					n->accessMethod = $11;
					n->options = $12;
					n->oncommit = $13;
					n->tablespacename = $14;
					n->if_not_exists = false;
					$$ = (Node *) n;
				*/ }
		| CREATE OptTemp TABLE IF_P NOT EXISTS qualified_name PARTITION OF
			qualified_name OptTypedTableElementList PartitionBoundSpec OptPartitionSpec
			table_access_method_clause OptWith OnCommitOption OptTableSpace
				{ /*C
					CreateStmt *n = makeNode(CreateStmt);

					$7->relpersistence = $2;
					n->relation = $7;
					n->tableElts = $11;
					n->inhRelations = list_make1($10);
					n->partbound = $12;
					n->partspec = $13;
					n->ofTypename = NULL;
					n->constraints = NIL;
					n->accessMethod = $14;
					n->options = $15;
					n->oncommit = $16;
					n->tablespacename = $17;
					n->if_not_exists = true;
					$$ = (Node *) n;
				*/ }
		;

/*
 * Redundancy here is needed to avoid shift/reduce conflicts,
 * since TEMP is not a reserved word.  See also OptTempTableName.
 *
 * NOTE: we accept both GLOBAL and LOCAL options.  They currently do nothing,
 * but future versions might consider GLOBAL to request SQL-spec-compliant
 * temp table behavior, so warn about that.  Since we have no modules the
 * LOCAL keyword is really meaningless; furthermore, some other products
 * implement LOCAL as meaning the same as our default temp table behavior,
 * so we'll probably continue to treat LOCAL as a noise word.
 */
OptTemp:	TEMPORARY					{ /*C $$ = RELPERSISTENCE_TEMP; */ }
			| TEMP						{ /*C $$ = RELPERSISTENCE_TEMP; */ }
			| LOCAL TEMPORARY			{ /*C $$ = RELPERSISTENCE_TEMP; */ }
			| LOCAL TEMP				{ /*C $$ = RELPERSISTENCE_TEMP; */ }
			| GLOBAL TEMPORARY
				{ /*C
					ereport(WARNING,
							(errmsg("GLOBAL is deprecated in temporary table creation"),
							 parser_errposition(@1)));
					$$ = RELPERSISTENCE_TEMP;
				*/ }
			| GLOBAL TEMP
				{ /*C
					ereport(WARNING,
							(errmsg("GLOBAL is deprecated in temporary table creation"),
							 parser_errposition(@1)));
					$$ = RELPERSISTENCE_TEMP;
				*/ }
			| UNLOGGED					{ /*C $$ = RELPERSISTENCE_UNLOGGED; */ }
			| /*EMPTY*/					{ /*C $$ = RELPERSISTENCE_PERMANENT; */ }
		;

OptTableElementList:
			TableElementList					{ $$ = $1 }
			| /*EMPTY*/							{ $$ = nil }
		;

OptTypedTableElementList:
			'(' TypedTableElementList ')'		{ $$ = $2 }
			| /*EMPTY*/							{ $$ = nil }
		;

TableElementList:
			TableElement
				{ $$ = []Node{$1} }
			| TableElementList ',' TableElement
				{ $$ = append($1, $3) }
		;

TypedTableElementList:
			TypedTableElement
				{ $$ = []Node{$1} }
			| TypedTableElementList ',' TypedTableElement
				{ $$ = append($1, $3) }
		;

TableElement:
			columnDef							{ $$ = $1 }
			| TableLikeClause					{ $$ = $1 }
			| TableConstraint					{ $$ = $1 }
		;

TypedTableElement:
			columnOptions						{ $$ = $1 }
			| TableConstraint					{ $$ = $1 }
		;

columnDef:	ColId Typename opt_column_storage opt_column_compression create_generic_options ColQualList
				{ /*C
					ColumnDef *n = makeNode(ColumnDef);

					n->colname = $1;
					n->typeName = $2;
					n->storage_name = $3;
					n->compression = $4;
					n->inhcount = 0;
					n->is_local = true;
					n->is_not_null = false;
					n->is_from_type = false;
					n->storage = 0;
					n->raw_default = NULL;
					n->cooked_default = NULL;
					n->collOid = InvalidOid;
					n->fdwoptions = $5;
					SplitColQualList($6, &n->constraints, &n->collClause,
									 yyscanner);
					n->location = @1;
					$$ = (Node *) n;
				*/ }
		;

columnOptions:	ColId ColQualList
				{ /*C
					ColumnDef *n = makeNode(ColumnDef);

					n->colname = $1;
					n->typeName = NULL;
					n->inhcount = 0;
					n->is_local = true;
					n->is_not_null = false;
					n->is_from_type = false;
					n->storage = 0;
					n->raw_default = NULL;
					n->cooked_default = NULL;
					n->collOid = InvalidOid;
					SplitColQualList($2, &n->constraints, &n->collClause,
									 yyscanner);
					n->location = @1;
					$$ = (Node *) n;
				*/ }
				| ColId WITH OPTIONS ColQualList
				{ /*C
					ColumnDef *n = makeNode(ColumnDef);

					n->colname = $1;
					n->typeName = NULL;
					n->inhcount = 0;
					n->is_local = true;
					n->is_not_null = false;
					n->is_from_type = false;
					n->storage = 0;
					n->raw_default = NULL;
					n->cooked_default = NULL;
					n->collOid = InvalidOid;
					SplitColQualList($4, &n->constraints, &n->collClause,
									 yyscanner);
					n->location = @1;
					$$ = (Node *) n;
				*/ }
		;

column_compression:
			COMPRESSION ColId						{ $$ = $2 }
			| COMPRESSION DEFAULT					{ /*C $$ = pstrdup("default"); */ }
		;

opt_column_compression:
			column_compression						{ $$ = $1 }
			| /*EMPTY*/								{ $$ = "" }
		;

column_storage:
			STORAGE ColId							{ $$ = $2 }
			| STORAGE DEFAULT						{ /*C $$ = pstrdup("default"); */ }
		;

opt_column_storage:
			column_storage							{ $$ = $1 }
			| /*EMPTY*/								{ $$ = "" }
		;

ColQualList:
			ColQualList ColConstraint				{ $$ = append($1, $2) }
			| /*EMPTY*/								{ $$ = nil }
		;

ColConstraint:
			CONSTRAINT name ColConstraintElem
				{ /*C
					Constraint *n = castNode(Constraint, $3);

					n->conname = $2;
					n->location = @1;
					$$ = (Node *) n;
				*/ }
			| ColConstraintElem						{ $$ = $1 }
			| ConstraintAttr						{ $$ = $1 }
			| COLLATE any_name
				{ /*C
					/*
					 * Note: the CollateClause is momentarily included in
					 * the list built by ColQualList, but we split it out
					 * again in SplitColQualList.
					 * /
					CollateClause *n = makeNode(CollateClause);

					n->arg = NULL;
					n->collname = $2;
					n->location = @1;
					$$ = (Node *) n;
				*/ }
		;

/* DEFAULT NULL is already the default for Postgres.
 * But define it here and carry it forward into the system
 * to make it explicit.
 * - thomas 1998-09-13
 *
 * WITH NULL and NULL are not SQL-standard syntax elements,
 * so leave them out. Use DEFAULT NULL to explicitly indicate
 * that a column may have that value. WITH NULL leads to
 * shift/reduce conflicts with WITH TIME ZONE anyway.
 * - thomas 1999-01-08
 *
 * DEFAULT expression must be b_expr not a_expr to prevent shift/reduce
 * conflict on NOT (since NOT might start a subsequent NOT NULL constraint,
 * or be part of a_expr NOT LIKE or similar constructs).
 */
ColConstraintElem:
			NOT NULL_P
				{ /*C
					Constraint *n = makeNode(Constraint);

					n->contype = CONSTR_NOTNULL;
					n->location = @1;
					$$ = (Node *) n;
				*/ }
			| NULL_P
				{ /*C
					Constraint *n = makeNode(Constraint);

					n->contype = CONSTR_NULL;
					n->location = @1;
					$$ = (Node *) n;
				*/ }
			| UNIQUE opt_unique_null_treatment opt_definition OptConsTableSpace
				{ /*C
					Constraint *n = makeNode(Constraint);

					n->contype = CONSTR_UNIQUE;
					n->location = @1;
					n->nulls_not_distinct = !$2;
					n->keys = NULL;
					n->options = $3;
					n->indexname = NULL;
					n->indexspace = $4;
					$$ = (Node *) n;
				*/ }
			| PRIMARY KEY opt_definition OptConsTableSpace
				{ /*C
					Constraint *n = makeNode(Constraint);

					n->contype = CONSTR_PRIMARY;
					n->location = @1;
					n->keys = NULL;
					n->options = $3;
					n->indexname = NULL;
					n->indexspace = $4;
					$$ = (Node *) n;
				*/ }
			| CHECK '(' a_expr ')' opt_no_inherit
				{ /*C
					Constraint *n = makeNode(Constraint);

					n->contype = CONSTR_CHECK;
					n->location = @1;
					n->is_no_inherit = $5;
					n->raw_expr = $3;
					n->cooked_expr = NULL;
					n->skip_validation = false;
					n->initially_valid = true;
					$$ = (Node *) n;
				*/ }
			| DEFAULT b_expr
				{ /*C
					Constraint *n = makeNode(Constraint);

					n->contype = CONSTR_DEFAULT;
					n->location = @1;
					n->raw_expr = $2;
					n->cooked_expr = NULL;
					$$ = (Node *) n;
				*/ }
			| GENERATED generated_when AS IDENTITY_P OptParenthesizedSeqOptList
				{ /*C
					Constraint *n = makeNode(Constraint);

					n->contype = CONSTR_IDENTITY;
					n->generated_when = $2;
					n->options = $5;
					n->location = @1;
					$$ = (Node *) n;
				*/ }
			| GENERATED generated_when AS '(' a_expr ')' STORED
				{ /*C
					Constraint *n = makeNode(Constraint);

					n->contype = CONSTR_GENERATED;
					n->generated_when = $2;
					n->raw_expr = $5;
					n->cooked_expr = NULL;
					n->location = @1;

					/*
					 * Can't do this in the grammar because of shift/reduce
					 * conflicts.  (IDENTITY allows both ALWAYS and BY
					 * DEFAULT, but generated columns only allow ALWAYS.)  We
					 * can also give a more useful error message and location.
					 * /
					if ($2 != ATTRIBUTE_IDENTITY_ALWAYS)
						ereport(ERROR,
								(errcode(ERRCODE_SYNTAX_ERROR),
								 errmsg("for a generated column, GENERATED ALWAYS must be specified"),
								 parser_errposition(@2)));

					$$ = (Node *) n;
				*/ }
			| REFERENCES qualified_name opt_column_list key_match key_actions
				{ /*C
					Constraint *n = makeNode(Constraint);

					n->contype = CONSTR_FOREIGN;
					n->location = @1;
					n->pktable = $2;
					n->fk_attrs = NIL;
					n->pk_attrs = $3;
					n->fk_matchtype = $4;
					n->fk_upd_action = ($5)->updateAction->action;
					n->fk_del_action = ($5)->deleteAction->action;
					n->fk_del_set_cols = ($5)->deleteAction->cols;
					n->skip_validation = false;
					n->initially_valid = true;
					$$ = (Node *) n;
				*/ }
		;

opt_unique_null_treatment:
			NULLS_P DISTINCT		{ $$ = true }
			| NULLS_P NOT DISTINCT	{ $$ = false }
			| /*EMPTY*/				{ $$ = true }
		;

generated_when:
			ALWAYS			{ /*C $$ = ATTRIBUTE_IDENTITY_ALWAYS; */ }
			| BY DEFAULT	{ /*C $$ = ATTRIBUTE_IDENTITY_BY_DEFAULT; */ }
		;

/*
 * ConstraintAttr represents constraint attributes, which we parse as if
 * they were independent constraint clauses, in order to avoid shift/reduce
 * conflicts (since NOT might start either an independent NOT NULL clause
 * or an attribute).  parse_utilcmd.c is responsible for attaching the
 * attribute information to the preceding "real" constraint node, and for
 * complaining if attribute clauses appear in the wrong place or wrong
 * combinations.
 *
 * See also ConstraintAttributeSpec, which can be used in places where
 * there is no parsing conflict.  (Note: currently, NOT VALID and NO INHERIT
 * are allowed clauses in ConstraintAttributeSpec, but not here.  Someday we
 * might need to allow them here too, but for the moment it doesn't seem
 * useful in the statements that use ConstraintAttr.)
 */
ConstraintAttr:
			DEFERRABLE
				{ /*C
					Constraint *n = makeNode(Constraint);

					n->contype = CONSTR_ATTR_DEFERRABLE;
					n->location = @1;
					$$ = (Node *) n;
				*/ }
			| NOT DEFERRABLE
				{ /*C
					Constraint *n = makeNode(Constraint);

					n->contype = CONSTR_ATTR_NOT_DEFERRABLE;
					n->location = @1;
					$$ = (Node *) n;
				*/ }
			| INITIALLY DEFERRED
				{ /*C
					Constraint *n = makeNode(Constraint);

					n->contype = CONSTR_ATTR_DEFERRED;
					n->location = @1;
					$$ = (Node *) n;
				*/ }
			| INITIALLY IMMEDIATE
				{ /*C
					Constraint *n = makeNode(Constraint);

					n->contype = CONSTR_ATTR_IMMEDIATE;
					n->location = @1;
					$$ = (Node *) n;
				*/ }
		;


TableLikeClause:
			LIKE qualified_name TableLikeOptionList
				{ /*C
					TableLikeClause *n = makeNode(TableLikeClause);

					n->relation = $2;
					n->options = $3;
					n->relationOid = InvalidOid;
					$$ = (Node *) n;
				*/ }
		;

TableLikeOptionList:
				TableLikeOptionList INCLUDING TableLikeOption	{ /*C $$ = $1 | $3; */ }
				| TableLikeOptionList EXCLUDING TableLikeOption	{ /*C $$ = $1 & ~$3; */ }
				| /* EMPTY */						{ $$ = 0 }
		;

TableLikeOption:
				COMMENTS			{ /*C $$ = CREATE_TABLE_LIKE_COMMENTS; */ }
				| COMPRESSION		{ /*C $$ = CREATE_TABLE_LIKE_COMPRESSION; */ }
				| CONSTRAINTS		{ /*C $$ = CREATE_TABLE_LIKE_CONSTRAINTS; */ }
				| DEFAULTS			{ /*C $$ = CREATE_TABLE_LIKE_DEFAULTS; */ }
				| IDENTITY_P		{ /*C $$ = CREATE_TABLE_LIKE_IDENTITY; */ }
				| GENERATED			{ /*C $$ = CREATE_TABLE_LIKE_GENERATED; */ }
				| INDEXES			{ /*C $$ = CREATE_TABLE_LIKE_INDEXES; */ }
				| STATISTICS		{ /*C $$ = CREATE_TABLE_LIKE_STATISTICS; */ }
				| STORAGE			{ /*C $$ = CREATE_TABLE_LIKE_STORAGE; */ }
				| ALL				{ /*C $$ = CREATE_TABLE_LIKE_ALL; */ }
		;


/* ConstraintElem specifies constraint syntax which is not embedded into
 *	a column definition. ColConstraintElem specifies the embedded form.
 * - thomas 1997-12-03
 */
TableConstraint:
			CONSTRAINT name ConstraintElem
				{ /*C
					Constraint *n = castNode(Constraint, $3);

					n->conname = $2;
					n->location = @1;
					$$ = (Node *) n;
				*/ }
			| ConstraintElem						{ $$ = $1 }
		;

ConstraintElem:
			CHECK '(' a_expr ')' ConstraintAttributeSpec
				{ /*C
					Constraint *n = makeNode(Constraint);

					n->contype = CONSTR_CHECK;
					n->location = @1;
					n->raw_expr = $3;
					n->cooked_expr = NULL;
					processCASbits($5, @5, "CHECK",
								   NULL, NULL, &n->skip_validation,
								   &n->is_no_inherit, yyscanner);
					n->initially_valid = !n->skip_validation;
					$$ = (Node *) n;
				*/ }
			| UNIQUE opt_unique_null_treatment '(' columnList ')' opt_c_include opt_definition OptConsTableSpace
				ConstraintAttributeSpec
				{ /*C
					Constraint *n = makeNode(Constraint);

					n->contype = CONSTR_UNIQUE;
					n->location = @1;
					n->nulls_not_distinct = !$2;
					n->keys = $4;
					n->including = $6;
					n->options = $7;
					n->indexname = NULL;
					n->indexspace = $8;
					processCASbits($9, @9, "UNIQUE",
								   &n->deferrable, &n->initdeferred, NULL,
								   NULL, yyscanner);
					$$ = (Node *) n;
				*/ }
			| UNIQUE ExistingIndex ConstraintAttributeSpec
				{ /*C
					Constraint *n = makeNode(Constraint);

					n->contype = CONSTR_UNIQUE;
					n->location = @1;
					n->keys = NIL;
					n->including = NIL;
					n->options = NIL;
					n->indexname = $2;
					n->indexspace = NULL;
					processCASbits($3, @3, "UNIQUE",
								   &n->deferrable, &n->initdeferred, NULL,
								   NULL, yyscanner);
					$$ = (Node *) n;
				*/ }
			| PRIMARY KEY '(' columnList ')' opt_c_include opt_definition OptConsTableSpace
				ConstraintAttributeSpec
				{ /*C
					Constraint *n = makeNode(Constraint);

					n->contype = CONSTR_PRIMARY;
					n->location = @1;
					n->keys = $4;
					n->including = $6;
					n->options = $7;
					n->indexname = NULL;
					n->indexspace = $8;
					processCASbits($9, @9, "PRIMARY KEY",
								   &n->deferrable, &n->initdeferred, NULL,
								   NULL, yyscanner);
					$$ = (Node *) n;
				*/ }
			| PRIMARY KEY ExistingIndex ConstraintAttributeSpec
				{ /*C
					Constraint *n = makeNode(Constraint);

					n->contype = CONSTR_PRIMARY;
					n->location = @1;
					n->keys = NIL;
					n->including = NIL;
					n->options = NIL;
					n->indexname = $3;
					n->indexspace = NULL;
					processCASbits($4, @4, "PRIMARY KEY",
								   &n->deferrable, &n->initdeferred, NULL,
								   NULL, yyscanner);
					$$ = (Node *) n;
				*/ }
			| EXCLUDE access_method_clause '(' ExclusionConstraintList ')'
				opt_c_include opt_definition OptConsTableSpace OptWhereClause
				ConstraintAttributeSpec
				{ /*C
					Constraint *n = makeNode(Constraint);

					n->contype = CONSTR_EXCLUSION;
					n->location = @1;
					n->access_method = $2;
					n->exclusions = $4;
					n->including = $6;
					n->options = $7;
					n->indexname = NULL;
					n->indexspace = $8;
					n->where_clause = $9;
					processCASbits($10, @10, "EXCLUDE",
								   &n->deferrable, &n->initdeferred, NULL,
								   NULL, yyscanner);
					$$ = (Node *) n;
				*/ }
			| FOREIGN KEY '(' columnList ')' REFERENCES qualified_name
				opt_column_list key_match key_actions ConstraintAttributeSpec
				{ /*C
					Constraint *n = makeNode(Constraint);

					n->contype = CONSTR_FOREIGN;
					n->location = @1;
					n->pktable = $7;
					n->fk_attrs = $4;
					n->pk_attrs = $8;
					n->fk_matchtype = $9;
					n->fk_upd_action = ($10)->updateAction->action;
					n->fk_del_action = ($10)->deleteAction->action;
					n->fk_del_set_cols = ($10)->deleteAction->cols;
					processCASbits($11, @11, "FOREIGN KEY",
								   &n->deferrable, &n->initdeferred,
								   &n->skip_validation, NULL,
								   yyscanner);
					n->initially_valid = !n->skip_validation;
					$$ = (Node *) n;
				*/ }
		;

/*
 * DomainConstraint is separate from TableConstraint because the syntax for
 * NOT NULL constraints is different.  For table constraints, we need to
 * accept a column name, but for domain constraints, we don't.  (We could
 * accept something like NOT NULL VALUE, but that seems weird.)  CREATE DOMAIN
 * (which uses ColQualList) has for a long time accepted NOT NULL without a
 * column name, so it makes sense that ALTER DOMAIN (which uses
 * DomainConstraint) does as well.  None of these syntaxes are per SQL
 * standard; we are just living with the bits of inconsistency that have built
 * up over time.
 */
DomainConstraint:
			CONSTRAINT name DomainConstraintElem
				{ /*C
					Constraint *n = castNode(Constraint, $3);

					n->conname = $2;
					n->location = @1;
					$$ = (Node *) n;
				*/ }
			| DomainConstraintElem					{ $$ = $1 }
		;

DomainConstraintElem:
			CHECK '(' a_expr ')' ConstraintAttributeSpec
				{ /*C
					Constraint *n = makeNode(Constraint);

					n->contype = CONSTR_CHECK;
					n->location = @1;
					n->raw_expr = $3;
					n->cooked_expr = NULL;
					processCASbits($5, @5, "CHECK",
								   NULL, NULL, &n->skip_validation,
								   &n->is_no_inherit, yyscanner);
					n->initially_valid = !n->skip_validation;
					$$ = (Node *) n;
				*/ }
			| NOT NULL_P ConstraintAttributeSpec
				{ /*C
					Constraint *n = makeNode(Constraint);

					n->contype = CONSTR_NOTNULL;
					n->location = @1;
					n->keys = list_make1(makeString("value"));
					/* no NOT VALID support yet * /
					processCASbits($3, @3, "NOT NULL",
								   NULL, NULL, NULL,
								   &n->is_no_inherit, yyscanner);
					n->initially_valid = true;
					$$ = (Node *) n;
				*/ }
		;

opt_no_inherit:	NO INHERIT							{ $$ = true }
			| /* EMPTY */							{ $$ = false }
		;

opt_column_list:
			'(' columnList ')'						{ $$ = $2 }
			| /*EMPTY*/								{ $$ = nil }
		;

columnList:
			columnElem								{ $$ = []Node{$1} }
			| columnList ',' columnElem				{ $$ = append($1, $3) }
		;

columnElem: ColId
				{ /*C
					$$ = (Node *) makeString($1);
				*/ }
		;

opt_c_include:	INCLUDE '(' columnList ')'			{ $$ = $3 }
			 |		/* EMPTY */						{ $$ = nil }
		;

key_match:  MATCH FULL
			{ /*C
				$$ = FKCONSTR_MATCH_FULL;
			*/ }
		| MATCH PARTIAL
			{ /*C
				ereport(ERROR,
						(errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
						 errmsg("MATCH PARTIAL not yet implemented"),
						 parser_errposition(@1)));
				$$ = FKCONSTR_MATCH_PARTIAL;
			*/ }
		| MATCH SIMPLE
			{ /*C
				$$ = FKCONSTR_MATCH_SIMPLE;
			*/ }
		| /*EMPTY*/
			{ /*C
				$$ = FKCONSTR_MATCH_SIMPLE;
			*/ }
		;

ExclusionConstraintList:
			ExclusionConstraintElem					{ /*C $$ = list_make1($1); */ }
			| ExclusionConstraintList ',' ExclusionConstraintElem
													{ /*C $$ = lappend($1, $3); */ }
		;

ExclusionConstraintElem: index_elem WITH any_operator
			{ /*C
				$$ = list_make2($1, $3);
			*/ }
			/* allow OPERATOR() decoration for the benefit of ruleutils.c */
			| index_elem WITH OPERATOR '(' any_operator ')'
			{ /*C
				$$ = list_make2($1, $5);
			*/ }
		;

OptWhereClause:
			WHERE '(' a_expr ')'					{ $$ = $3 }
			| /*EMPTY*/								{ $$ = nil }
		;

key_actions:
			key_update
				{ /*C
					KeyActions *n = palloc(sizeof(KeyActions));

					n->updateAction = $1;
					n->deleteAction = palloc(sizeof(KeyAction));
					n->deleteAction->action = FKCONSTR_ACTION_NOACTION;
					n->deleteAction->cols = NIL;
					$$ = n;
				*/ }
			| key_delete
				{ /*C
					KeyActions *n = palloc(sizeof(KeyActions));

					n->updateAction = palloc(sizeof(KeyAction));
					n->updateAction->action = FKCONSTR_ACTION_NOACTION;
					n->updateAction->cols = NIL;
					n->deleteAction = $1;
					$$ = n;
				*/ }
			| key_update key_delete
				{ /*C
					KeyActions *n = palloc(sizeof(KeyActions));

					n->updateAction = $1;
					n->deleteAction = $2;
					$$ = n;
				*/ }
			| key_delete key_update
				{ /*C
					KeyActions *n = palloc(sizeof(KeyActions));

					n->updateAction = $2;
					n->deleteAction = $1;
					$$ = n;
				*/ }
			| /*EMPTY*/
				{ /*C
					KeyActions *n = palloc(sizeof(KeyActions));

					n->updateAction = palloc(sizeof(KeyAction));
					n->updateAction->action = FKCONSTR_ACTION_NOACTION;
					n->updateAction->cols = NIL;
					n->deleteAction = palloc(sizeof(KeyAction));
					n->deleteAction->action = FKCONSTR_ACTION_NOACTION;
					n->deleteAction->cols = NIL;
					$$ = n;
				*/ }
		;

key_update: ON UPDATE key_action
				{ /*C
					if (($3)->cols)
						ereport(ERROR,
								(errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
								 errmsg("a column list with %s is only supported for ON DELETE actions",
										($3)->action == FKCONSTR_ACTION_SETNULL ? "SET NULL" : "SET DEFAULT"),
								 parser_errposition(@1)));
					$$ = $3;
				*/ }
		;

key_delete: ON DELETE_P key_action
				{ $$ = $3 }
		;

key_action:
			NO ACTION
				{ /*C
					KeyAction *n = palloc(sizeof(KeyAction));

					n->action = FKCONSTR_ACTION_NOACTION;
					n->cols = NIL;
					$$ = n;
				*/ }
			| RESTRICT
				{ /*C
					KeyAction *n = palloc(sizeof(KeyAction));

					n->action = FKCONSTR_ACTION_RESTRICT;
					n->cols = NIL;
					$$ = n;
				*/ }
			| CASCADE
				{ /*C
					KeyAction *n = palloc(sizeof(KeyAction));

					n->action = FKCONSTR_ACTION_CASCADE;
					n->cols = NIL;
					$$ = n;
				*/ }
			| SET NULL_P opt_column_list
				{ /*C
					KeyAction *n = palloc(sizeof(KeyAction));

					n->action = FKCONSTR_ACTION_SETNULL;
					n->cols = $3;
					$$ = n;
				*/ }
			| SET DEFAULT opt_column_list
				{ /*C
					KeyAction *n = palloc(sizeof(KeyAction));

					n->action = FKCONSTR_ACTION_SETDEFAULT;
					n->cols = $3;
					$$ = n;
				*/ }
		;

OptInherit: INHERITS '(' qualified_name_list ')'	{ $$ = $3 }
			| /*EMPTY*/								{ $$ = nil }
		;

/* Optional partition key specification */
OptPartitionSpec: PartitionSpec	{ $$ = $1 }
			| /*EMPTY*/			{ $$ = nil }
		;

PartitionSpec: PARTITION BY ColId '(' part_params ')'
				{ /*C
					PartitionSpec *n = makeNode(PartitionSpec);

					n->strategy = parsePartitionStrategy($3);
					n->partParams = $5;
					n->location = @1;

					$$ = n;
				*/ }
		;

part_params:	part_elem						{ $$ = []Node{$1} }
			| part_params ',' part_elem			{ $$ = append($1, $3) }
		;

part_elem: ColId opt_collate opt_qualified_name
				{ /*C
					PartitionElem *n = makeNode(PartitionElem);

					n->name = $1;
					n->expr = NULL;
					n->collation = $2;
					n->opclass = $3;
					n->location = @1;
					$$ = n;
				*/ }
			| func_expr_windowless opt_collate opt_qualified_name
				{ /*C
					PartitionElem *n = makeNode(PartitionElem);

					n->name = NULL;
					n->expr = $1;
					n->collation = $2;
					n->opclass = $3;
					n->location = @1;
					$$ = n;
				*/ }
			| '(' a_expr ')' opt_collate opt_qualified_name
				{ /*C
					PartitionElem *n = makeNode(PartitionElem);

					n->name = NULL;
					n->expr = $2;
					n->collation = $4;
					n->opclass = $5;
					n->location = @1;
					$$ = n;
				*/ }
		;

table_access_method_clause:
			USING name							{ $$ = $2 }
			| /*EMPTY*/							{ $$ = "" }
		;

/* WITHOUT OIDS is legacy only */
OptWith:
			WITH reloptions				{ $$ = $2 }
			| WITHOUT OIDS				{ $$ = nil }
			| /*EMPTY*/					{ $$ = nil }
		;

OnCommitOption:  ON COMMIT DROP				{ $$ = int32(ONCOMMIT_DROP) }
			| ON COMMIT DELETE_P ROWS		{ $$ = int32(ONCOMMIT_DELETE_ROWS) }
			| ON COMMIT PRESERVE ROWS		{ $$ = int32(ONCOMMIT_PRESERVE_ROWS) }
			| /*EMPTY*/						{ $$ = int32(ONCOMMIT_NOOP) }
		;

OptTableSpace:   TABLESPACE name					{ $$ = $2 }
			| /*EMPTY*/								{ $$ = "" }
		;

OptConsTableSpace:   USING INDEX TABLESPACE name	{ $$ = $4 }
			| /*EMPTY*/								{ $$ = "" }
		;

ExistingIndex:   USING INDEX name					{ $$ = $3 }
		;

/*****************************************************************************
 *
 *		QUERY :
 *				CREATE STATISTICS [[IF NOT EXISTS] stats_name] [(stat types)]
 *					ON expression-list FROM from_list
 *
 * Note: the expectation here is that the clauses after ON are a subset of
 * SELECT syntax, allowing for expressions and joined tables, and probably
 * someday a WHERE clause.  Much less than that is currently implemented,
 * but the grammar accepts it and then we'll throw FEATURE_NOT_SUPPORTED
 * errors as necessary at execution.
 *
 * Statistics name is optional unless IF NOT EXISTS is specified.
 *
 *****************************************************************************/

CreateStatsStmt:
			CREATE STATISTICS opt_qualified_name
			opt_name_list ON stats_params FROM from_list
				{ /*C
					CreateStatsStmt *n = makeNode(CreateStatsStmt);

					n->defnames = $3;
					n->stat_types = $4;
					n->exprs = $6;
					n->relations = $8;
					n->stxcomment = NULL;
					n->if_not_exists = false;
					$$ = (Node *) n;
				*/ }
			| CREATE STATISTICS IF_P NOT EXISTS any_name
			opt_name_list ON stats_params FROM from_list
				{ /*C
					CreateStatsStmt *n = makeNode(CreateStatsStmt);

					n->defnames = $6;
					n->stat_types = $7;
					n->exprs = $9;
					n->relations = $11;
					n->stxcomment = NULL;
					n->if_not_exists = true;
					$$ = (Node *) n;
				*/ }
			;

/*
 * Statistics attributes can be either simple column references, or arbitrary
 * expressions in parens.  For compatibility with index attributes permitted
 * in CREATE INDEX, we allow an expression that's just a function call to be
 * written without parens.
 */

stats_params:	stats_param							{ $$ = []Node{$1} }
			| stats_params ',' stats_param			{ $$ = append($1, $3) }
		;

stats_param:	ColId
				{ /*C
					$$ = makeNode(StatsElem);
					$$->name = $1;
					$$->expr = NULL;
				*/ }
			| func_expr_windowless
				{ /*C
					$$ = makeNode(StatsElem);
					$$->name = NULL;
					$$->expr = $1;
				*/ }
			| '(' a_expr ')'
				{ /*C
					$$ = makeNode(StatsElem);
					$$->name = NULL;
					$$->expr = $2;
				*/ }
		;

/*****************************************************************************
 *
 *		QUERY :
 *				ALTER STATISTICS [IF EXISTS] stats_name
 *					SET STATISTICS  <SignedIconst>
 *
 *****************************************************************************/

AlterStatsStmt:
			ALTER STATISTICS any_name SET STATISTICS set_statistics_value
				{ /*C
					AlterStatsStmt *n = makeNode(AlterStatsStmt);

					n->defnames = $3;
					n->missing_ok = false;
					n->stxstattarget = $6;
					$$ = (Node *) n;
				*/ }
			| ALTER STATISTICS IF_P EXISTS any_name SET STATISTICS set_statistics_value
				{ /*C
					AlterStatsStmt *n = makeNode(AlterStatsStmt);

					n->defnames = $5;
					n->missing_ok = true;
					n->stxstattarget = $8;
					$$ = (Node *) n;
				*/ }
			;

/*****************************************************************************
 *
 *		QUERY :
 *				CREATE TABLE relname AS SelectStmt [ WITH [NO] DATA ]
 *
 *
 * Note: SELECT ... INTO is a now-deprecated alternative for this.
 *
 *****************************************************************************/

CreateAsStmt:
		CREATE OptTemp TABLE create_as_target AS SelectStmt opt_with_data
				{ /*C
					CreateTableAsStmt *ctas = makeNode(CreateTableAsStmt);

					ctas->query = $6;
					ctas->into = $4;
					ctas->objtype = OBJECT_TABLE;
					ctas->is_select_into = false;
					ctas->if_not_exists = false;
					/* cram additional flags into the IntoClause * /
					$4->rel->relpersistence = $2;
					$4->skipData = !($7);
					$$ = (Node *) ctas;
				*/ }
		| CREATE OptTemp TABLE IF_P NOT EXISTS create_as_target AS SelectStmt opt_with_data
				{ /*C
					CreateTableAsStmt *ctas = makeNode(CreateTableAsStmt);

					ctas->query = $9;
					ctas->into = $7;
					ctas->objtype = OBJECT_TABLE;
					ctas->is_select_into = false;
					ctas->if_not_exists = true;
					/* cram additional flags into the IntoClause * /
					$7->rel->relpersistence = $2;
					$7->skipData = !($10);
					$$ = (Node *) ctas;
				*/ }
		;

create_as_target:
			qualified_name opt_column_list table_access_method_clause
			OptWith OnCommitOption OptTableSpace
				{ /*C
					$$ = makeNode(IntoClause);
					$$->rel = $1;
					$$->colNames = $2;
					$$->accessMethod = $3;
					$$->options = $4;
					$$->onCommit = $5;
					$$->tableSpaceName = $6;
					$$->viewQuery = NULL;
					$$->skipData = false;		/* might get changed later * /
				*/ }
		;

opt_with_data:
			WITH DATA_P								{ $$ = true }
			| WITH NO DATA_P						{ $$ = false }
			| /*EMPTY*/								{ $$ = true }
		;


/*****************************************************************************
 *
 *		QUERY :
 *				CREATE MATERIALIZED VIEW relname AS SelectStmt
 *
 *****************************************************************************/

CreateMatViewStmt:
		CREATE OptNoLog MATERIALIZED VIEW create_mv_target AS SelectStmt opt_with_data
				{ /*C
					CreateTableAsStmt *ctas = makeNode(CreateTableAsStmt);

					ctas->query = $7;
					ctas->into = $5;
					ctas->objtype = OBJECT_MATVIEW;
					ctas->is_select_into = false;
					ctas->if_not_exists = false;
					/* cram additional flags into the IntoClause * /
					$5->rel->relpersistence = $2;
					$5->skipData = !($8);
					$$ = (Node *) ctas;
				*/ }
		| CREATE OptNoLog MATERIALIZED VIEW IF_P NOT EXISTS create_mv_target AS SelectStmt opt_with_data
				{ /*C
					CreateTableAsStmt *ctas = makeNode(CreateTableAsStmt);

					ctas->query = $10;
					ctas->into = $8;
					ctas->objtype = OBJECT_MATVIEW;
					ctas->is_select_into = false;
					ctas->if_not_exists = true;
					/* cram additional flags into the IntoClause * /
					$8->rel->relpersistence = $2;
					$8->skipData = !($11);
					$$ = (Node *) ctas;
				*/ }
		;

create_mv_target:
			qualified_name opt_column_list table_access_method_clause opt_reloptions OptTableSpace
				{ /*C
					$$ = makeNode(IntoClause);
					$$->rel = $1;
					$$->colNames = $2;
					$$->accessMethod = $3;
					$$->options = $4;
					$$->onCommit = ONCOMMIT_NOOP;
					$$->tableSpaceName = $5;
					$$->viewQuery = NULL;		/* filled at analysis time * /
					$$->skipData = false;		/* might get changed later * /
				*/ }
		;

OptNoLog:	UNLOGGED					{ /*C $$ = RELPERSISTENCE_UNLOGGED; */ }
			| /*EMPTY*/					{ /*C $$ = RELPERSISTENCE_PERMANENT; */ }
		;


/*****************************************************************************
 *
 *		QUERY :
 *				REFRESH MATERIALIZED VIEW qualified_name
 *
 *****************************************************************************/

RefreshMatViewStmt:
			REFRESH MATERIALIZED VIEW opt_concurrently qualified_name opt_with_data
				{ /*C
					RefreshMatViewStmt *n = makeNode(RefreshMatViewStmt);

					n->concurrent = $4;
					n->relation = $5;
					n->skipData = !($6);
					$$ = (Node *) n;
				*/ }
		;


/*****************************************************************************
 *
 *		QUERY :
 *				CREATE SEQUENCE seqname
 *				ALTER SEQUENCE seqname
 *
 *****************************************************************************/

CreateSeqStmt:
			CREATE OptTemp SEQUENCE qualified_name OptSeqOptList
				{ /*C
					CreateSeqStmt *n = makeNode(CreateSeqStmt);

					$4->relpersistence = $2;
					n->sequence = $4;
					n->options = $5;
					n->ownerId = InvalidOid;
					n->if_not_exists = false;
					$$ = (Node *) n;
				*/ }
			| CREATE OptTemp SEQUENCE IF_P NOT EXISTS qualified_name OptSeqOptList
				{ /*C
					CreateSeqStmt *n = makeNode(CreateSeqStmt);

					$7->relpersistence = $2;
					n->sequence = $7;
					n->options = $8;
					n->ownerId = InvalidOid;
					n->if_not_exists = true;
					$$ = (Node *) n;
				*/ }
		;

AlterSeqStmt:
			ALTER SEQUENCE qualified_name SeqOptList
				{ /*C
					AlterSeqStmt *n = makeNode(AlterSeqStmt);

					n->sequence = $3;
					n->options = $4;
					n->missing_ok = false;
					$$ = (Node *) n;
				*/ }
			| ALTER SEQUENCE IF_P EXISTS qualified_name SeqOptList
				{ /*C
					AlterSeqStmt *n = makeNode(AlterSeqStmt);

					n->sequence = $5;
					n->options = $6;
					n->missing_ok = true;
					$$ = (Node *) n;
				*/ }

		;

OptSeqOptList: SeqOptList							{ $$ = $1 }
			| /*EMPTY*/								{ $$ = nil }
		;

OptParenthesizedSeqOptList: '(' SeqOptList ')'		{ $$ = $2 }
			| /*EMPTY*/								{ $$ = nil }
		;

SeqOptList: SeqOptElem								{ $$ = []Node{$1} }
			| SeqOptList SeqOptElem					{ $$ = append($1, $2) }
		;

SeqOptElem: AS SimpleTypename
				{ /*C
					$$ = makeDefElem("as", (Node *) $2, @1);
				*/ }
			| CACHE NumericOnly
				{ /*C
					$$ = makeDefElem("cache", (Node *) $2, @1);
				*/ }
			| CYCLE
				{ /*C
					$$ = makeDefElem("cycle", (Node *) makeBoolean(true), @1);
				*/ }
			| NO CYCLE
				{ /*C
					$$ = makeDefElem("cycle", (Node *) makeBoolean(false), @1);
				*/ }
			| INCREMENT opt_by NumericOnly
				{ /*C
					$$ = makeDefElem("increment", (Node *) $3, @1);
				*/ }
			| LOGGED
				{ /*C
					$$ = makeDefElem("logged", NULL, @1);
				*/ }
			| MAXVALUE NumericOnly
				{ /*C
					$$ = makeDefElem("maxvalue", (Node *) $2, @1);
				*/ }
			| MINVALUE NumericOnly
				{ /*C
					$$ = makeDefElem("minvalue", (Node *) $2, @1);
				*/ }
			| NO MAXVALUE
				{ /*C
					$$ = makeDefElem("maxvalue", NULL, @1);
				*/ }
			| NO MINVALUE
				{ /*C
					$$ = makeDefElem("minvalue", NULL, @1);
				*/ }
			| OWNED BY any_name
				{ /*C
					$$ = makeDefElem("owned_by", (Node *) $3, @1);
				*/ }
			| SEQUENCE NAME_P any_name
				{ /*C
					$$ = makeDefElem("sequence_name", (Node *) $3, @1);
				*/ }
			| START opt_with NumericOnly
				{ /*C
					$$ = makeDefElem("start", (Node *) $3, @1);
				*/ }
			| RESTART
				{ /*C
					$$ = makeDefElem("restart", NULL, @1);
				*/ }
			| RESTART opt_with NumericOnly
				{ /*C
					$$ = makeDefElem("restart", (Node *) $3, @1);
				*/ }
			| UNLOGGED
				{ /*C
					$$ = makeDefElem("unlogged", NULL, @1);
				*/ }
		;

opt_by:		BY
			| /* EMPTY */
	  ;

NumericOnly:
			FCONST								{ /*C $$ = (Node *) makeFloat($1); */ }
			| '+' FCONST						{ /*C $$ = (Node *) makeFloat($2); */ }
			| '-' FCONST
				{ /*C
					Float	   *f = makeFloat($2);

					doNegateFloat(f);
					$$ = (Node *) f;
				*/ }
			| SignedIconst						{ /*C $$ = (Node *) makeInteger($1); */ }
		;

NumericOnly_list:	NumericOnly						{ $$ = []Node{$1} }
				| NumericOnly_list ',' NumericOnly	{ $$ = append($1, $3) }
		;

/*****************************************************************************
 *
 *		QUERIES :
 *				CREATE [OR REPLACE] [TRUSTED] [PROCEDURAL] LANGUAGE ...
 *				DROP [PROCEDURAL] LANGUAGE ...
 *
 *****************************************************************************/

CreatePLangStmt:
			CREATE opt_or_replace opt_trusted opt_procedural LANGUAGE name
			{ /*C
				/*
				 * We now interpret parameterless CREATE LANGUAGE as
				 * CREATE EXTENSION.  "OR REPLACE" is silently translated
				 * to "IF NOT EXISTS", which isn't quite the same, but
				 * seems more useful than throwing an error.  We just
				 * ignore TRUSTED, as the previous code would have too.
				 * /
				CreateExtensionStmt *n = makeNode(CreateExtensionStmt);

				n->if_not_exists = $2;
				n->extname = $6;
				n->options = NIL;
				$$ = (Node *) n;
			*/ }
			| CREATE opt_or_replace opt_trusted opt_procedural LANGUAGE name
			  HANDLER handler_name opt_inline_handler opt_validator
			{ /*C
				CreatePLangStmt *n = makeNode(CreatePLangStmt);

				n->replace = $2;
				n->plname = $6;
				n->plhandler = $8;
				n->plinline = $9;
				n->plvalidator = $10;
				n->pltrusted = $3;
				$$ = (Node *) n;
			*/ }
		;

opt_trusted:
			TRUSTED									{ $$ = true }
			| /*EMPTY*/								{ $$ = false }
		;

/* This ought to be just func_name, but that causes reduce/reduce conflicts
 * (CREATE LANGUAGE is the only place where func_name isn't followed by '(').
 * Work around by using simple names, instead.
 */
handler_name:
			name						{ /*C $$ = list_make1(makeString($1)); */ }
			| name attrs				{ /*C $$ = lcons(makeString($1), $2); */ }
		;

opt_inline_handler:
			INLINE_P handler_name					{ $$ = $2 }
			| /*EMPTY*/								{ $$ = nil }
		;

validator_clause:
			VALIDATOR handler_name					{ $$ = $2 }
			| NO VALIDATOR							{ $$ = nil }
		;

opt_validator:
			validator_clause						{ $$ = $1 }
			| /*EMPTY*/								{ $$ = nil }
		;

opt_procedural:
			PROCEDURAL
			| /*EMPTY*/
		;

/*****************************************************************************
 *
 *		QUERY:
 *             CREATE TABLESPACE tablespace LOCATION '/path/to/tablespace/'
 *
 *****************************************************************************/

CreateTableSpaceStmt: CREATE TABLESPACE name OptTableSpaceOwner LOCATION Sconst opt_reloptions
				{ /*C
					CreateTableSpaceStmt *n = makeNode(CreateTableSpaceStmt);

					n->tablespacename = $3;
					n->owner = $4;
					n->location = $6;
					n->options = $7;
					$$ = (Node *) n;
				*/ }
		;

OptTableSpaceOwner: OWNER RoleSpec		{ $$ = $2 }
			| /*EMPTY */				{ $$ = nil }
		;

/*****************************************************************************
 *
 *		QUERY :
 *				DROP TABLESPACE <tablespace>
 *
 *		No need for drop behaviour as we cannot implement dependencies for
 *		objects in other databases; we can only support RESTRICT.
 *
 ****************************************************************************/

DropTableSpaceStmt: DROP TABLESPACE name
				{ /*C
					DropTableSpaceStmt *n = makeNode(DropTableSpaceStmt);

					n->tablespacename = $3;
					n->missing_ok = false;
					$$ = (Node *) n;
				*/ }
				|  DROP TABLESPACE IF_P EXISTS name
				{ /*C
					DropTableSpaceStmt *n = makeNode(DropTableSpaceStmt);

					n->tablespacename = $5;
					n->missing_ok = true;
					$$ = (Node *) n;
				*/ }
		;

/*****************************************************************************
 *
 *		QUERY:
 *             CREATE EXTENSION extension
 *             [ WITH ] [ SCHEMA schema ] [ VERSION version ]
 *
 *****************************************************************************/

CreateExtensionStmt: CREATE EXTENSION name opt_with create_extension_opt_list
				{ /*C
					CreateExtensionStmt *n = makeNode(CreateExtensionStmt);

					n->extname = $3;
					n->if_not_exists = false;
					n->options = $5;
					$$ = (Node *) n;
				*/ }
				| CREATE EXTENSION IF_P NOT EXISTS name opt_with create_extension_opt_list
				{ /*C
					CreateExtensionStmt *n = makeNode(CreateExtensionStmt);

					n->extname = $6;
					n->if_not_exists = true;
					n->options = $8;
					$$ = (Node *) n;
				*/ }
		;

create_extension_opt_list:
			create_extension_opt_list create_extension_opt_item
				{ $$ = append($1, $2) }
			| /* EMPTY */
				{ $$ = nil }
		;

create_extension_opt_item:
			SCHEMA name
				{ /*C
					$$ = makeDefElem("schema", (Node *) makeString($2), @1);
				*/ }
			| VERSION_P NonReservedWord_or_Sconst
				{ /*C
					$$ = makeDefElem("new_version", (Node *) makeString($2), @1);
				*/ }
			| FROM NonReservedWord_or_Sconst
				{ /*C
					ereport(ERROR,
							(errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
							 errmsg("CREATE EXTENSION ... FROM is no longer supported"),
							 parser_errposition(@1)));
				*/ }
			| CASCADE
				{ /*C
					$$ = makeDefElem("cascade", (Node *) makeBoolean(true), @1);
				*/ }
		;

