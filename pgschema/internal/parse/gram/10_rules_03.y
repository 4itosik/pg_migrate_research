/* gram.y lines 3292-5159 */
/*****************************************************************************
 *
 *		QUERY :
 *				close <portalname>
 *
 *****************************************************************************/

ClosePortalStmt:
			CLOSE cursor_name
				{
					n := &ClosePortalStmt{}

					n.Portalname = $2
					$$ = n
				}
			| CLOSE ALL
				{
					n := &ClosePortalStmt{}

					n.Portalname = ""
					$$ = n
				}
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
				{
					n := &CopyStmt{}

					n.Relation = as[*RangeVar]($3)
					n.Query = nil
					n.Attlist = $4
					n.IsFrom = $5
					n.IsProgram = $6
					n.Filename = $7
					n.WhereClause = $11

					if n.IsProgram && p.copyFileNameIsNull(n.Filename, @7) {
						p.fail(@8, "STDIN/STDOUT not allowed with PROGRAM")
					}

					if !n.IsFrom && n.WhereClause != nil {
						p.fail(@11, "WHERE clause not allowed with COPY TO")
					}

					n.Options = nil
					/* Concatenate user-supplied flags */
					if $2 != nil {
						n.Options = append(n.Options, $2)
					}
					if $8 != nil {
						n.Options = append(n.Options, $8)
					}
					if $10 != nil {
						n.Options = append(n.Options, $10...)
					}
					$$ = n
				}
			| COPY '(' PreparableStmt ')' TO opt_program copy_file_name opt_with copy_options
				{
					n := &CopyStmt{}

					n.Relation = nil
					n.Query = $3
					n.Attlist = nil
					n.IsFrom = false
					n.IsProgram = $6
					n.Filename = $7
					n.Options = $9

					if n.IsProgram && p.copyFileNameIsNull(n.Filename, @7) {
						p.fail(@5, "STDIN/STDOUT not allowed with PROGRAM")
					}

					$$ = n
				}
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
				{
					$$ = makeDefElem("format", makeString("binary", @1), @1)
				}
			| FREEZE
				{
					$$ = makeDefElem("freeze", makeBoolean(true), @1)
				}
			| DELIMITER opt_as Sconst
				{
					$$ = makeDefElem("delimiter", makeString($3, @3), @1)
				}
			| NULL_P opt_as Sconst
				{
					$$ = makeDefElem("null", makeString($3, @3), @1)
				}
			| CSV
				{
					$$ = makeDefElem("format", makeString("csv", @1), @1)
				}
			| HEADER_P
				{
					$$ = makeDefElem("header", makeBoolean(true), @1)
				}
			| QUOTE opt_as Sconst
				{
					$$ = makeDefElem("quote", makeString($3, @3), @1)
				}
			| ESCAPE opt_as Sconst
				{
					$$ = makeDefElem("escape", makeString($3, @3), @1)
				}
			| FORCE QUOTE columnList
				{
					$$ = makeDefElem("force_quote", listNode($3), @1)
				}
			| FORCE QUOTE '*'
				{
					$$ = makeDefElem("force_quote", &A_Star{}, @1)
				}
			| FORCE NOT NULL_P columnList
				{
					$$ = makeDefElem("force_not_null", listNode($4), @1)
				}
			| FORCE NOT NULL_P '*'
				{
					$$ = makeDefElem("force_not_null", &A_Star{}, @1)
				}
			| FORCE NULL_P columnList
				{
					$$ = makeDefElem("force_null", listNode($3), @1)
				}
			| FORCE NULL_P '*'
				{
					$$ = makeDefElem("force_null", &A_Star{}, @1)
				}
			| ENCODING Sconst
				{
					$$ = makeDefElem("encoding", makeString($2, @2), @1)
				}
		;

/* The following exist for backward compatibility with very old versions */

opt_binary:
			BINARY
				{
					$$ = makeDefElem("format", makeString("binary", @1), @1)
				}
			| /*EMPTY*/								{ $$ = nil }
		;

copy_delimiter:
			opt_using DELIMITERS Sconst
				{
					$$ = makeDefElem("delimiter", makeString($3, @3), @2)
				}
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
				{
					$$ = makeDefElem($1, $2, @1)
				}
		;

copy_generic_opt_arg:
			opt_boolean_or_string			{ $$ = makeString($1, @1) }
			| NumericOnly					{ $$ = $1 }
			| '*'							{ $$ = &A_Star{} }
			| DEFAULT                       { $$ = makeString("default", @1) }
			| '(' copy_generic_opt_arg_list ')'		{ $$ = listNode($2) }
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
			opt_boolean_or_string	{ $$ = makeString($1, @1) }
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
				{
					n := &CreateStmt{}

					setRelpersistence(as[*RangeVar]($4), $2)
					n.Relation = as[*RangeVar]($4)
					n.TableElts = $6
					n.InhRelations = $8
					n.Partspec = as[*PartitionSpec]($9)
					n.OfTypename = nil
					n.Constraints = nil
					n.AccessMethod = $10
					n.Options = $11
					n.Oncommit = OnCommitAction($12)
					n.Tablespacename = $13
					n.IfNotExists = false
					$$ = n
				}
		| CREATE OptTemp TABLE IF_P NOT EXISTS qualified_name '('
			OptTableElementList ')' OptInherit OptPartitionSpec table_access_method_clause
			OptWith OnCommitOption OptTableSpace
				{
					n := &CreateStmt{}

					setRelpersistence(as[*RangeVar]($7), $2)
					n.Relation = as[*RangeVar]($7)
					n.TableElts = $9
					n.InhRelations = $11
					n.Partspec = as[*PartitionSpec]($12)
					n.OfTypename = nil
					n.Constraints = nil
					n.AccessMethod = $13
					n.Options = $14
					n.Oncommit = OnCommitAction($15)
					n.Tablespacename = $16
					n.IfNotExists = true
					$$ = n
				}
		| CREATE OptTemp TABLE qualified_name OF any_name
			OptTypedTableElementList OptPartitionSpec table_access_method_clause
			OptWith OnCommitOption OptTableSpace
				{
					n := &CreateStmt{}

					setRelpersistence(as[*RangeVar]($4), $2)
					n.Relation = as[*RangeVar]($4)
					n.TableElts = $7
					n.InhRelations = nil
					n.Partspec = as[*PartitionSpec]($8)
					n.OfTypename = makeTypeNameFromNameList($6)
					n.OfTypename.Location = @6
					n.Constraints = nil
					n.AccessMethod = $9
					n.Options = $10
					n.Oncommit = OnCommitAction($11)
					n.Tablespacename = $12
					n.IfNotExists = false
					$$ = n
				}
		| CREATE OptTemp TABLE IF_P NOT EXISTS qualified_name OF any_name
			OptTypedTableElementList OptPartitionSpec table_access_method_clause
			OptWith OnCommitOption OptTableSpace
				{
					n := &CreateStmt{}

					setRelpersistence(as[*RangeVar]($7), $2)
					n.Relation = as[*RangeVar]($7)
					n.TableElts = $10
					n.InhRelations = nil
					n.Partspec = as[*PartitionSpec]($11)
					n.OfTypename = makeTypeNameFromNameList($9)
					n.OfTypename.Location = @9
					n.Constraints = nil
					n.AccessMethod = $12
					n.Options = $13
					n.Oncommit = OnCommitAction($14)
					n.Tablespacename = $15
					n.IfNotExists = true
					$$ = n
				}
		| CREATE OptTemp TABLE qualified_name PARTITION OF qualified_name
			OptTypedTableElementList PartitionBoundSpec OptPartitionSpec
			table_access_method_clause OptWith OnCommitOption OptTableSpace
				{
					n := &CreateStmt{}

					setRelpersistence(as[*RangeVar]($4), $2)
					n.Relation = as[*RangeVar]($4)
					n.TableElts = $8
					n.InhRelations = []Node{$7}
					n.Partbound = as[*PartitionBoundSpec]($9)
					n.Partspec = as[*PartitionSpec]($10)
					n.OfTypename = nil
					n.Constraints = nil
					n.AccessMethod = $11
					n.Options = $12
					n.Oncommit = OnCommitAction($13)
					n.Tablespacename = $14
					n.IfNotExists = false
					$$ = n
				}
		| CREATE OptTemp TABLE IF_P NOT EXISTS qualified_name PARTITION OF
			qualified_name OptTypedTableElementList PartitionBoundSpec OptPartitionSpec
			table_access_method_clause OptWith OnCommitOption OptTableSpace
				{
					n := &CreateStmt{}

					setRelpersistence(as[*RangeVar]($7), $2)
					n.Relation = as[*RangeVar]($7)
					n.TableElts = $11
					n.InhRelations = []Node{$10}
					n.Partbound = as[*PartitionBoundSpec]($12)
					n.Partspec = as[*PartitionSpec]($13)
					n.OfTypename = nil
					n.Constraints = nil
					n.AccessMethod = $14
					n.Options = $15
					n.Oncommit = OnCommitAction($16)
					n.Tablespacename = $17
					n.IfNotExists = true
					$$ = n
				}
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
OptTemp:	TEMPORARY					{ $$ = int32(relpersistenceTemp[0]) }
			| TEMP						{ $$ = int32(relpersistenceTemp[0]) }
			| LOCAL TEMPORARY			{ $$ = int32(relpersistenceTemp[0]) }
			| LOCAL TEMP				{ $$ = int32(relpersistenceTemp[0]) }
			| GLOBAL TEMPORARY
				{
					/* GLOBAL is deprecated in temporary table creation: only a warning, nothing to report */
					$$ = int32(relpersistenceTemp[0])
				}
			| GLOBAL TEMP
				{
					/* GLOBAL is deprecated in temporary table creation: only a warning, nothing to report */
					$$ = int32(relpersistenceTemp[0])
				}
			| UNLOGGED					{ $$ = int32(relpersistenceUnlogged[0]) }
			| /*EMPTY*/					{ $$ = int32(relpersistencePermanent[0]) }
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
				{
					n := &ColumnDef{}

					n.Colname = $1
					n.TypeName = as[*TypeName]($2)
					n.StorageName = $3
					n.Compression = $4
					n.Inhcount = 0
					n.IsLocal = true
					n.IsNotNull = false
					n.IsFromType = false
					n.Storage = ""
					n.RawDefault = nil
					n.CookedDefault = nil
					n.CollOid = 0
					n.Fdwoptions = $5
					n.Constraints, n.CollClause = p.splitColQualList($6)
					n.Location = @1
					$$ = n
				}
		;

columnOptions:	ColId ColQualList
				{
					n := &ColumnDef{}

					n.Colname = $1
					n.TypeName = nil
					n.Inhcount = 0
					n.IsLocal = true
					n.IsNotNull = false
					n.IsFromType = false
					n.Storage = ""
					n.RawDefault = nil
					n.CookedDefault = nil
					n.CollOid = 0
					n.Constraints, n.CollClause = p.splitColQualList($2)
					n.Location = @1
					$$ = n
				}
				| ColId WITH OPTIONS ColQualList
				{
					n := &ColumnDef{}

					n.Colname = $1
					n.TypeName = nil
					n.Inhcount = 0
					n.IsLocal = true
					n.IsNotNull = false
					n.IsFromType = false
					n.Storage = ""
					n.RawDefault = nil
					n.CookedDefault = nil
					n.CollOid = 0
					n.Constraints, n.CollClause = p.splitColQualList($4)
					n.Location = @1
					$$ = n
				}
		;

column_compression:
			COMPRESSION ColId						{ $$ = $2 }
			| COMPRESSION DEFAULT					{ $$ = "default" }
		;

opt_column_compression:
			column_compression						{ $$ = $1 }
			| /*EMPTY*/								{ $$ = "" }
		;

column_storage:
			STORAGE ColId							{ $$ = $2 }
			| STORAGE DEFAULT						{ $$ = "default" }
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
				{
					n := as[*Constraint]($3)

					n.Conname = $2
					n.Location = @1
					$$ = n
				}
			| ColConstraintElem						{ $$ = $1 }
			| ConstraintAttr						{ $$ = $1 }
			| COLLATE any_name
				{
					/*
					 * Note: the CollateClause is momentarily included in
					 * the list built by ColQualList, but we split it out
					 * again in SplitColQualList.
					 */
					n := &CollateClause{}

					n.Arg = nil
					n.Collname = $2
					n.Location = @1
					$$ = n
				}
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
				{
					n := &Constraint{}

					n.Contype = CONSTR_NOTNULL
					n.Location = @1
					$$ = n
				}
			| NULL_P
				{
					n := &Constraint{}

					n.Contype = CONSTR_NULL
					n.Location = @1
					$$ = n
				}
			| UNIQUE opt_unique_null_treatment opt_definition OptConsTableSpace
				{
					n := &Constraint{}

					n.Contype = CONSTR_UNIQUE
					n.Location = @1
					n.NullsNotDistinct = !$2
					n.Keys = nil
					n.Options = $3
					n.Indexname = ""
					n.Indexspace = $4
					$$ = n
				}
			| PRIMARY KEY opt_definition OptConsTableSpace
				{
					n := &Constraint{}

					n.Contype = CONSTR_PRIMARY
					n.Location = @1
					n.Keys = nil
					n.Options = $3
					n.Indexname = ""
					n.Indexspace = $4
					$$ = n
				}
			| CHECK '(' a_expr ')' opt_no_inherit
				{
					n := &Constraint{}

					n.Contype = CONSTR_CHECK
					n.Location = @1
					n.IsNoInherit = $5
					n.RawExpr = $3
					n.CookedExpr = ""
					n.SkipValidation = false
					n.InitiallyValid = true
					$$ = n
				}
			| DEFAULT b_expr
				{
					n := &Constraint{}

					n.Contype = CONSTR_DEFAULT
					n.Location = @1
					n.RawExpr = $2
					n.CookedExpr = ""
					$$ = n
				}
			| GENERATED generated_when AS IDENTITY_P OptParenthesizedSeqOptList
				{
					n := &Constraint{}

					n.Contype = CONSTR_IDENTITY
					n.GeneratedWhen = string(rune($2))
					n.Options = $5
					n.Location = @1
					$$ = n
				}
			| GENERATED generated_when AS '(' a_expr ')' STORED
				{
					n := &Constraint{}

					n.Contype = CONSTR_GENERATED
					n.GeneratedWhen = string(rune($2))
					n.RawExpr = $5
					n.CookedExpr = ""
					n.Location = @1

					/*
					 * Can't do this in the grammar because of shift/reduce
					 * conflicts.  (IDENTITY allows both ALWAYS and BY
					 * DEFAULT, but generated columns only allow ALWAYS.)  We
					 * can also give a more useful error message and location.
					 */
					if $2 != ATTRIBUTE_IDENTITY_ALWAYS {
						p.fail(@2, "for a generated column, GENERATED ALWAYS must be specified")
					}

					$$ = n
				}
			| REFERENCES qualified_name opt_column_list key_match key_actions
				{
					n := &Constraint{}

					n.Contype = CONSTR_FOREIGN
					n.Location = @1
					n.Pktable = as[*RangeVar]($2)
					n.FkAttrs = nil
					n.PkAttrs = $3
					n.FkMatchtype = string(rune($4))
					n.FkUpdAction = as[*keyActions]($5).updateAction.action
					n.FkDelAction = as[*keyActions]($5).deleteAction.action
					n.FkDelSetCols = as[*keyActions]($5).deleteAction.cols
					n.SkipValidation = false
					n.InitiallyValid = true
					$$ = n
				}
		;

opt_unique_null_treatment:
			NULLS_P DISTINCT		{ $$ = true }
			| NULLS_P NOT DISTINCT	{ $$ = false }
			| /*EMPTY*/				{ $$ = true }
		;

generated_when:
			ALWAYS			{ $$ = ATTRIBUTE_IDENTITY_ALWAYS }
			| BY DEFAULT	{ $$ = ATTRIBUTE_IDENTITY_BY_DEFAULT }
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
				{
					n := &Constraint{}

					n.Contype = CONSTR_ATTR_DEFERRABLE
					n.Location = @1
					$$ = n
				}
			| NOT DEFERRABLE
				{
					n := &Constraint{}

					n.Contype = CONSTR_ATTR_NOT_DEFERRABLE
					n.Location = @1
					$$ = n
				}
			| INITIALLY DEFERRED
				{
					n := &Constraint{}

					n.Contype = CONSTR_ATTR_DEFERRED
					n.Location = @1
					$$ = n
				}
			| INITIALLY IMMEDIATE
				{
					n := &Constraint{}

					n.Contype = CONSTR_ATTR_IMMEDIATE
					n.Location = @1
					$$ = n
				}
		;


TableLikeClause:
			LIKE qualified_name TableLikeOptionList
				{
					n := &TableLikeClause{}

					n.Relation = as[*RangeVar]($2)
					n.Options = uint32($3)
					n.RelationOid = 0
					$$ = n
				}
		;

TableLikeOptionList:
				TableLikeOptionList INCLUDING TableLikeOption	{ $$ = $1 | $3 }
				| TableLikeOptionList EXCLUDING TableLikeOption	{ $$ = $1 &^ $3 }
				| /* EMPTY */						{ $$ = 0 }
		;

TableLikeOption:
				COMMENTS			{ $$ = createTableLikeComments }
				| COMPRESSION		{ $$ = createTableLikeCompression }
				| CONSTRAINTS		{ $$ = createTableLikeConstraints }
				| DEFAULTS			{ $$ = createTableLikeDefaults }
				| IDENTITY_P		{ $$ = createTableLikeIdentity }
				| GENERATED			{ $$ = createTableLikeGenerated }
				| INDEXES			{ $$ = createTableLikeIndexes }
				| STATISTICS		{ $$ = createTableLikeStatistics }
				| STORAGE			{ $$ = createTableLikeStorage }
				| ALL				{ $$ = createTableLikeAll }
		;


/* ConstraintElem specifies constraint syntax which is not embedded into
 *	a column definition. ColConstraintElem specifies the embedded form.
 * - thomas 1997-12-03
 */
TableConstraint:
			CONSTRAINT name ConstraintElem
				{
					n := as[*Constraint]($3)

					n.Conname = $2
					n.Location = @1
					$$ = n
				}
			| ConstraintElem						{ $$ = $1 }
		;

ConstraintElem:
			CHECK '(' a_expr ')' ConstraintAttributeSpec
				{
					n := &Constraint{}

					n.Contype = CONSTR_CHECK
					n.Location = @1
					n.RawExpr = $3
					n.CookedExpr = ""
					p.processCASbits($5, @5, "CHECK",
						nil, nil, &n.SkipValidation,
						&n.IsNoInherit)
					n.InitiallyValid = !n.SkipValidation
					$$ = n
				}
			| UNIQUE opt_unique_null_treatment '(' columnList ')' opt_c_include opt_definition OptConsTableSpace
				ConstraintAttributeSpec
				{
					n := &Constraint{}

					n.Contype = CONSTR_UNIQUE
					n.Location = @1
					n.NullsNotDistinct = !$2
					n.Keys = $4
					n.Including = $6
					n.Options = $7
					n.Indexname = ""
					n.Indexspace = $8
					p.processCASbits($9, @9, "UNIQUE",
						&n.Deferrable, &n.Initdeferred, nil,
						nil)
					$$ = n
				}
			| UNIQUE ExistingIndex ConstraintAttributeSpec
				{
					n := &Constraint{}

					n.Contype = CONSTR_UNIQUE
					n.Location = @1
					n.Keys = nil
					n.Including = nil
					n.Options = nil
					n.Indexname = $2
					n.Indexspace = ""
					p.processCASbits($3, @3, "UNIQUE",
						&n.Deferrable, &n.Initdeferred, nil,
						nil)
					$$ = n
				}
			| PRIMARY KEY '(' columnList ')' opt_c_include opt_definition OptConsTableSpace
				ConstraintAttributeSpec
				{
					n := &Constraint{}

					n.Contype = CONSTR_PRIMARY
					n.Location = @1
					n.Keys = $4
					n.Including = $6
					n.Options = $7
					n.Indexname = ""
					n.Indexspace = $8
					p.processCASbits($9, @9, "PRIMARY KEY",
						&n.Deferrable, &n.Initdeferred, nil,
						nil)
					$$ = n
				}
			| PRIMARY KEY ExistingIndex ConstraintAttributeSpec
				{
					n := &Constraint{}

					n.Contype = CONSTR_PRIMARY
					n.Location = @1
					n.Keys = nil
					n.Including = nil
					n.Options = nil
					n.Indexname = $3
					n.Indexspace = ""
					p.processCASbits($4, @4, "PRIMARY KEY",
						&n.Deferrable, &n.Initdeferred, nil,
						nil)
					$$ = n
				}
			| EXCLUDE access_method_clause '(' ExclusionConstraintList ')'
				opt_c_include opt_definition OptConsTableSpace OptWhereClause
				ConstraintAttributeSpec
				{
					n := &Constraint{}

					n.Contype = CONSTR_EXCLUSION
					n.Location = @1
					n.AccessMethod = $2
					n.Exclusions = $4
					n.Including = $6
					n.Options = $7
					n.Indexname = ""
					n.Indexspace = $8
					n.WhereClause = $9
					p.processCASbits($10, @10, "EXCLUDE",
						&n.Deferrable, &n.Initdeferred, nil,
						nil)
					$$ = n
				}
			| FOREIGN KEY '(' columnList ')' REFERENCES qualified_name
				opt_column_list key_match key_actions ConstraintAttributeSpec
				{
					n := &Constraint{}

					n.Contype = CONSTR_FOREIGN
					n.Location = @1
					n.Pktable = as[*RangeVar]($7)
					n.FkAttrs = $4
					n.PkAttrs = $8
					n.FkMatchtype = string(rune($9))
					n.FkUpdAction = as[*keyActions]($10).updateAction.action
					n.FkDelAction = as[*keyActions]($10).deleteAction.action
					n.FkDelSetCols = as[*keyActions]($10).deleteAction.cols
					p.processCASbits($11, @11, "FOREIGN KEY",
						&n.Deferrable, &n.Initdeferred,
						&n.SkipValidation, nil)
					n.InitiallyValid = !n.SkipValidation
					$$ = n
				}
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
				{
					n := as[*Constraint]($3)

					n.Conname = $2
					n.Location = @1
					$$ = n
				}
			| DomainConstraintElem					{ $$ = $1 }
		;

DomainConstraintElem:
			CHECK '(' a_expr ')' ConstraintAttributeSpec
				{
					n := &Constraint{}

					n.Contype = CONSTR_CHECK
					n.Location = @1
					n.RawExpr = $3
					n.CookedExpr = ""
					p.processCASbits($5, @5, "CHECK",
						nil, nil, &n.SkipValidation,
						&n.IsNoInherit)
					n.InitiallyValid = !n.SkipValidation
					$$ = n
				}
			| NOT NULL_P ConstraintAttributeSpec
				{
					n := &Constraint{}

					n.Contype = CONSTR_NOTNULL
					n.Location = @1
					n.Keys = []Node{makeString("value", -1)}
					/* no NOT VALID support yet */
					p.processCASbits($3, @3, "NOT NULL",
						nil, nil, nil,
						&n.IsNoInherit)
					n.InitiallyValid = true
					$$ = n
				}
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
				{
					$$ = makeString($1, @1)
				}
		;

opt_c_include:	INCLUDE '(' columnList ')'			{ $$ = $3 }
			 |		/* EMPTY */						{ $$ = nil }
		;

key_match:  MATCH FULL
			{
				$$ = FKCONSTR_MATCH_FULL
			}
		| MATCH PARTIAL
			{
				p.fail(@1, "MATCH PARTIAL not yet implemented")
				$$ = FKCONSTR_MATCH_PARTIAL
			}
		| MATCH SIMPLE
			{
				$$ = FKCONSTR_MATCH_SIMPLE
			}
		| /*EMPTY*/
			{
				$$ = FKCONSTR_MATCH_SIMPLE
			}
		;

ExclusionConstraintList:
			ExclusionConstraintElem					{ $$ = []Node{listNode($1)} }
			| ExclusionConstraintList ',' ExclusionConstraintElem
													{ $$ = append($1, listNode($3)) }
		;

ExclusionConstraintElem: index_elem WITH any_operator
			{
				$$ = []Node{$1, listNode($3)}
			}
			/* allow OPERATOR() decoration for the benefit of ruleutils.c */
			| index_elem WITH OPERATOR '(' any_operator ')'
			{
				$$ = []Node{$1, listNode($5)}
			}
		;

OptWhereClause:
			WHERE '(' a_expr ')'					{ $$ = $3 }
			| /*EMPTY*/								{ $$ = nil }
		;

key_actions:
			key_update
				{
					n := &keyActions{}

					n.updateAction = as[*keyAction]($1)
					n.deleteAction = &keyAction{}
					n.deleteAction.action = FKCONSTR_ACTION_NOACTION
					n.deleteAction.cols = nil
					$$ = n
				}
			| key_delete
				{
					n := &keyActions{}

					n.updateAction = &keyAction{}
					n.updateAction.action = FKCONSTR_ACTION_NOACTION
					n.updateAction.cols = nil
					n.deleteAction = as[*keyAction]($1)
					$$ = n
				}
			| key_update key_delete
				{
					n := &keyActions{}

					n.updateAction = as[*keyAction]($1)
					n.deleteAction = as[*keyAction]($2)
					$$ = n
				}
			| key_delete key_update
				{
					n := &keyActions{}

					n.updateAction = as[*keyAction]($2)
					n.deleteAction = as[*keyAction]($1)
					$$ = n
				}
			| /*EMPTY*/
				{
					n := &keyActions{}

					n.updateAction = &keyAction{}
					n.updateAction.action = FKCONSTR_ACTION_NOACTION
					n.updateAction.cols = nil
					n.deleteAction = &keyAction{}
					n.deleteAction.action = FKCONSTR_ACTION_NOACTION
					n.deleteAction.cols = nil
					$$ = n
				}
		;

key_update: ON UPDATE key_action
				{
					if len(as[*keyAction]($3).cols) > 0 {
						setWhat := "SET DEFAULT"
						if as[*keyAction]($3).action == FKCONSTR_ACTION_SETNULL {
							setWhat = "SET NULL"
						}
						p.fail(@1, fmt.Sprintf("a column list with %s is only supported for ON DELETE actions", setWhat))
					}
					$$ = $3
				}
		;

key_delete: ON DELETE_P key_action
				{ $$ = $3 }
		;

key_action:
			NO ACTION
				{
					n := &keyAction{}

					n.action = FKCONSTR_ACTION_NOACTION
					n.cols = nil
					$$ = n
				}
			| RESTRICT
				{
					n := &keyAction{}

					n.action = FKCONSTR_ACTION_RESTRICT
					n.cols = nil
					$$ = n
				}
			| CASCADE
				{
					n := &keyAction{}

					n.action = FKCONSTR_ACTION_CASCADE
					n.cols = nil
					$$ = n
				}
			| SET NULL_P opt_column_list
				{
					n := &keyAction{}

					n.action = FKCONSTR_ACTION_SETNULL
					n.cols = $3
					$$ = n
				}
			| SET DEFAULT opt_column_list
				{
					n := &keyAction{}

					n.action = FKCONSTR_ACTION_SETDEFAULT
					n.cols = $3
					$$ = n
				}
		;

OptInherit: INHERITS '(' qualified_name_list ')'	{ $$ = $3 }
			| /*EMPTY*/								{ $$ = nil }
		;

/* Optional partition key specification */
OptPartitionSpec: PartitionSpec	{ $$ = $1 }
			| /*EMPTY*/			{ $$ = nil }
		;

PartitionSpec: PARTITION BY ColId '(' part_params ')'
				{
					n := &PartitionSpec{}

					n.Strategy = p.parsePartitionStrategy($3)
					n.PartParams = $5
					n.Location = @1

					$$ = n
				}
		;

part_params:	part_elem						{ $$ = []Node{$1} }
			| part_params ',' part_elem			{ $$ = append($1, $3) }
		;

part_elem: ColId opt_collate opt_qualified_name
				{
					n := &PartitionElem{}

					n.Name = $1
					n.Expr = nil
					n.Collation = $2
					n.Opclass = $3
					n.Location = @1
					$$ = n
				}
			| func_expr_windowless opt_collate opt_qualified_name
				{
					n := &PartitionElem{}

					n.Name = ""
					n.Expr = $1
					n.Collation = $2
					n.Opclass = $3
					n.Location = @1
					$$ = n
				}
			| '(' a_expr ')' opt_collate opt_qualified_name
				{
					n := &PartitionElem{}

					n.Name = ""
					n.Expr = $2
					n.Collation = $4
					n.Opclass = $5
					n.Location = @1
					$$ = n
				}
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
				{
					n := &CreateStatsStmt{}

					n.Defnames = $3
					n.StatTypes = $4
					n.Exprs = $6
					n.Relations = $8
					n.Stxcomment = ""
					n.IfNotExists = false
					$$ = n
				}
			| CREATE STATISTICS IF_P NOT EXISTS any_name
			opt_name_list ON stats_params FROM from_list
				{
					n := &CreateStatsStmt{}

					n.Defnames = $6
					n.StatTypes = $7
					n.Exprs = $9
					n.Relations = $11
					n.Stxcomment = ""
					n.IfNotExists = true
					$$ = n
				}
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
				{
					n := &StatsElem{}

					n.Name = $1
					n.Expr = nil
					$$ = n
				}
			| func_expr_windowless
				{
					n := &StatsElem{}

					n.Name = ""
					n.Expr = $1
					$$ = n
				}
			| '(' a_expr ')'
				{
					n := &StatsElem{}

					n.Name = ""
					n.Expr = $2
					$$ = n
				}
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
				{
					n := &AlterStatsStmt{}

					n.Defnames = $3
					n.MissingOk = false
					n.Stxstattarget = $6
					$$ = n
				}
			| ALTER STATISTICS IF_P EXISTS any_name SET STATISTICS set_statistics_value
				{
					n := &AlterStatsStmt{}

					n.Defnames = $5
					n.MissingOk = true
					n.Stxstattarget = $8
					$$ = n
				}
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
				{
					ctas := &CreateTableAsStmt{}

					ctas.Query = $6
					ctas.Into = as[*IntoClause]($4)
					ctas.Objtype = OBJECT_TABLE
					ctas.IsSelectInto = false
					ctas.IfNotExists = false
					/* cram additional flags into the IntoClause */
					setRelpersistence(as[*IntoClause]($4).Rel, $2)
					as[*IntoClause]($4).SkipData = !$7
					$$ = ctas
				}
		| CREATE OptTemp TABLE IF_P NOT EXISTS create_as_target AS SelectStmt opt_with_data
				{
					ctas := &CreateTableAsStmt{}

					ctas.Query = $9
					ctas.Into = as[*IntoClause]($7)
					ctas.Objtype = OBJECT_TABLE
					ctas.IsSelectInto = false
					ctas.IfNotExists = true
					/* cram additional flags into the IntoClause */
					setRelpersistence(as[*IntoClause]($7).Rel, $2)
					as[*IntoClause]($7).SkipData = !$10
					$$ = ctas
				}
		;

create_as_target:
			qualified_name opt_column_list table_access_method_clause
			OptWith OnCommitOption OptTableSpace
				{
					n := &IntoClause{}

					n.Rel = as[*RangeVar]($1)
					n.ColNames = $2
					n.AccessMethod = $3
					n.Options = $4
					n.OnCommit = OnCommitAction($5)
					n.TableSpaceName = $6
					n.ViewQuery = nil
					n.SkipData = false /* might get changed later */
					$$ = n
				}
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
				{
					ctas := &CreateTableAsStmt{}

					ctas.Query = $7
					ctas.Into = as[*IntoClause]($5)
					ctas.Objtype = OBJECT_MATVIEW
					ctas.IsSelectInto = false
					ctas.IfNotExists = false
					/* cram additional flags into the IntoClause */
					setRelpersistence(as[*IntoClause]($5).Rel, $2)
					as[*IntoClause]($5).SkipData = !$8
					$$ = ctas
				}
		| CREATE OptNoLog MATERIALIZED VIEW IF_P NOT EXISTS create_mv_target AS SelectStmt opt_with_data
				{
					ctas := &CreateTableAsStmt{}

					ctas.Query = $10
					ctas.Into = as[*IntoClause]($8)
					ctas.Objtype = OBJECT_MATVIEW
					ctas.IsSelectInto = false
					ctas.IfNotExists = true
					/* cram additional flags into the IntoClause */
					setRelpersistence(as[*IntoClause]($8).Rel, $2)
					as[*IntoClause]($8).SkipData = !$11
					$$ = ctas
				}
		;

create_mv_target:
			qualified_name opt_column_list table_access_method_clause opt_reloptions OptTableSpace
				{
					n := &IntoClause{}

					n.Rel = as[*RangeVar]($1)
					n.ColNames = $2
					n.AccessMethod = $3
					n.Options = $4
					n.OnCommit = ONCOMMIT_NOOP
					n.TableSpaceName = $5
					n.ViewQuery = nil /* filled at analysis time */
					n.SkipData = false /* might get changed later */
					$$ = n
				}
		;

OptNoLog:	UNLOGGED					{ $$ = int32(relpersistenceUnlogged[0]) }
			| /*EMPTY*/					{ $$ = int32(relpersistencePermanent[0]) }
		;


/*****************************************************************************
 *
 *		QUERY :
 *				REFRESH MATERIALIZED VIEW qualified_name
 *
 *****************************************************************************/

RefreshMatViewStmt:
			REFRESH MATERIALIZED VIEW opt_concurrently qualified_name opt_with_data
				{
					n := &RefreshMatViewStmt{}

					n.Concurrent = $4
					n.Relation = as[*RangeVar]($5)
					n.SkipData = !$6
					$$ = n
				}
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
				{
					n := &CreateSeqStmt{}

					setRelpersistence(as[*RangeVar]($4), $2)
					n.Sequence = as[*RangeVar]($4)
					n.Options = $5
					n.OwnerId = 0
					n.IfNotExists = false
					$$ = n
				}
			| CREATE OptTemp SEQUENCE IF_P NOT EXISTS qualified_name OptSeqOptList
				{
					n := &CreateSeqStmt{}

					setRelpersistence(as[*RangeVar]($7), $2)
					n.Sequence = as[*RangeVar]($7)
					n.Options = $8
					n.OwnerId = 0
					n.IfNotExists = true
					$$ = n
				}
		;

AlterSeqStmt:
			ALTER SEQUENCE qualified_name SeqOptList
				{
					n := &AlterSeqStmt{}

					n.Sequence = as[*RangeVar]($3)
					n.Options = $4
					n.MissingOk = false
					$$ = n
				}
			| ALTER SEQUENCE IF_P EXISTS qualified_name SeqOptList
				{
					n := &AlterSeqStmt{}

					n.Sequence = as[*RangeVar]($5)
					n.Options = $6
					n.MissingOk = true
					$$ = n
				}

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
				{
					$$ = makeDefElem("as", $2, @1)
				}
			| CACHE NumericOnly
				{
					$$ = makeDefElem("cache", $2, @1)
				}
			| CYCLE
				{
					$$ = makeDefElem("cycle", makeBoolean(true), @1)
				}
			| NO CYCLE
				{
					$$ = makeDefElem("cycle", makeBoolean(false), @1)
				}
			| INCREMENT opt_by NumericOnly
				{
					$$ = makeDefElem("increment", $3, @1)
				}
			| LOGGED
				{
					$$ = makeDefElem("logged", nil, @1)
				}
			| MAXVALUE NumericOnly
				{
					$$ = makeDefElem("maxvalue", $2, @1)
				}
			| MINVALUE NumericOnly
				{
					$$ = makeDefElem("minvalue", $2, @1)
				}
			| NO MAXVALUE
				{
					$$ = makeDefElem("maxvalue", nil, @1)
				}
			| NO MINVALUE
				{
					$$ = makeDefElem("minvalue", nil, @1)
				}
			| OWNED BY any_name
				{
					$$ = makeDefElem("owned_by", listNode($3), @1)
				}
			| SEQUENCE NAME_P any_name
				{
					$$ = makeDefElem("sequence_name", listNode($3), @1)
				}
			| START opt_with NumericOnly
				{
					$$ = makeDefElem("start", $3, @1)
				}
			| RESTART
				{
					$$ = makeDefElem("restart", nil, @1)
				}
			| RESTART opt_with NumericOnly
				{
					$$ = makeDefElem("restart", $3, @1)
				}
			| UNLOGGED
				{
					$$ = makeDefElem("unlogged", nil, @1)
				}
		;

opt_by:		BY
			| /* EMPTY */
	  ;

NumericOnly:
			FCONST								{ $$ = makeFloat($1) }
			| '+' FCONST						{ $$ = makeFloat($2) }
			| '-' FCONST
				{
					f := makeFloat($2)

					doNegateFloat(f)
					$$ = f
				}
			| SignedIconst						{ $$ = makeInteger($1) }
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
			{
				/*
				 * We now interpret parameterless CREATE LANGUAGE as
				 * CREATE EXTENSION.  "OR REPLACE" is silently translated
				 * to "IF NOT EXISTS", which isn't quite the same, but
				 * seems more useful than throwing an error.  We just
				 * ignore TRUSTED, as the previous code would have too.
				 */
				n := &CreateExtensionStmt{}

				n.IfNotExists = $2
				n.Extname = $6
				n.Options = nil
				$$ = n
			}
			| CREATE opt_or_replace opt_trusted opt_procedural LANGUAGE name
			  HANDLER handler_name opt_inline_handler opt_validator
			{
				n := &CreatePLangStmt{}

				n.Replace = $2
				n.Plname = $6
				n.Plhandler = $8
				n.Plinline = $9
				n.Plvalidator = $10
				n.Pltrusted = $3
				$$ = n
			}
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
			name						{ $$ = []Node{makeString($1, @1)} }
			| name attrs				{ $$ = append([]Node{makeString($1, @1)}, $2...) }
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
				{
					n := &CreateTableSpaceStmt{}

					n.Tablespacename = $3
					n.Owner = as[*RoleSpec]($4)
					n.Location = $6
					n.Options = $7
					$$ = n
				}
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
				{
					n := &DropTableSpaceStmt{}

					n.Tablespacename = $3
					n.MissingOk = false
					$$ = n
				}
				|  DROP TABLESPACE IF_P EXISTS name
				{
					n := &DropTableSpaceStmt{}

					n.Tablespacename = $5
					n.MissingOk = true
					$$ = n
				}
		;

/*****************************************************************************
 *
 *		QUERY:
 *             CREATE EXTENSION extension
 *             [ WITH ] [ SCHEMA schema ] [ VERSION version ]
 *
 *****************************************************************************/

CreateExtensionStmt: CREATE EXTENSION name opt_with create_extension_opt_list
				{
					n := &CreateExtensionStmt{}

					n.Extname = $3
					n.IfNotExists = false
					n.Options = $5
					$$ = n
				}
				| CREATE EXTENSION IF_P NOT EXISTS name opt_with create_extension_opt_list
				{
					n := &CreateExtensionStmt{}

					n.Extname = $6
					n.IfNotExists = true
					n.Options = $8
					$$ = n
				}
		;

create_extension_opt_list:
			create_extension_opt_list create_extension_opt_item
				{ $$ = append($1, $2) }
			| /* EMPTY */
				{ $$ = nil }
		;

create_extension_opt_item:
			SCHEMA name
				{
					$$ = makeDefElem("schema", makeString($2, @2), @1)
				}
			| VERSION_P NonReservedWord_or_Sconst
				{
					$$ = makeDefElem("new_version", makeString($2, @2), @1)
				}
			| FROM NonReservedWord_or_Sconst
				{
					p.fail(@1, "CREATE EXTENSION ... FROM is no longer supported")
				}
			| CASCADE
				{
					$$ = makeDefElem("cascade", makeBoolean(true), @1)
				}
		;

