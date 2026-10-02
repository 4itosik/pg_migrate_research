/* gram.y lines 13425-14751 */
/*****************************************************************************
 *
 *	clauses common to all Optimizable Stmts:
 *		from_clause		- allow list of both JOIN expressions and table names
 *		where_clause	- qualifications for joins or restrictions
 *
 *****************************************************************************/

from_clause:
			FROM from_list							{ $$ = $2 }
			| /*EMPTY*/								{ $$ = nil }
		;

from_list:
			table_ref								{ $$ = []Node{$1} }
			| from_list ',' table_ref				{ $$ = append($1, $3) }
		;

/*
 * table_ref is where an alias clause can be attached.
 */
table_ref:	relation_expr opt_alias_clause
				{ /*C
					$1->alias = $2;
					$$ = (Node *) $1;
				*/ }
			| relation_expr opt_alias_clause tablesample_clause
				{ /*C
					RangeTableSample *n = (RangeTableSample *) $3;

					$1->alias = $2;
					/* relation_expr goes inside the RangeTableSample node * /
					n->relation = (Node *) $1;
					$$ = (Node *) n;
				*/ }
			| func_table func_alias_clause
				{ /*C
					RangeFunction *n = (RangeFunction *) $1;

					n->alias = linitial($2);
					n->coldeflist = lsecond($2);
					$$ = (Node *) n;
				*/ }
			| LATERAL_P func_table func_alias_clause
				{ /*C
					RangeFunction *n = (RangeFunction *) $2;

					n->lateral = true;
					n->alias = linitial($3);
					n->coldeflist = lsecond($3);
					$$ = (Node *) n;
				*/ }
			| xmltable opt_alias_clause
				{ /*C
					RangeTableFunc *n = (RangeTableFunc *) $1;

					n->alias = $2;
					$$ = (Node *) n;
				*/ }
			| LATERAL_P xmltable opt_alias_clause
				{ /*C
					RangeTableFunc *n = (RangeTableFunc *) $2;

					n->lateral = true;
					n->alias = $3;
					$$ = (Node *) n;
				*/ }
			| select_with_parens opt_alias_clause
				{ /*C
					RangeSubselect *n = makeNode(RangeSubselect);

					n->lateral = false;
					n->subquery = $1;
					n->alias = $2;
					$$ = (Node *) n;
				*/ }
			| LATERAL_P select_with_parens opt_alias_clause
				{ /*C
					RangeSubselect *n = makeNode(RangeSubselect);

					n->lateral = true;
					n->subquery = $2;
					n->alias = $3;
					$$ = (Node *) n;
				*/ }
			| joined_table
				{ $$ = $1 }
			| '(' joined_table ')' alias_clause
				{ /*C
					$2->alias = $4;
					$$ = (Node *) $2;
				*/ }
			| json_table opt_alias_clause
				{ /*C
					JsonTable  *jt = castNode(JsonTable, $1);

					jt->alias = $2;
					$$ = (Node *) jt;
				*/ }
			| LATERAL_P json_table opt_alias_clause
				{ /*C
					JsonTable  *jt = castNode(JsonTable, $2);

					jt->alias = $3;
					jt->lateral = true;
					$$ = (Node *) jt;
				*/ }
		;


/*
 * It may seem silly to separate joined_table from table_ref, but there is
 * method in SQL's madness: if you don't do it this way you get reduce-
 * reduce conflicts, because it's not clear to the parser generator whether
 * to expect alias_clause after ')' or not.  For the same reason we must
 * treat 'JOIN' and 'join_type JOIN' separately, rather than allowing
 * join_type to expand to empty; if we try it, the parser generator can't
 * figure out when to reduce an empty join_type right after table_ref.
 *
 * Note that a CROSS JOIN is the same as an unqualified
 * INNER JOIN, and an INNER JOIN/ON has the same shape
 * but a qualification expression to limit membership.
 * A NATURAL JOIN implicitly matches column names between
 * tables and the shape is determined by which columns are
 * in common. We'll collect columns during the later transformations.
 */

joined_table:
			'(' joined_table ')'
				{ $$ = $2 }
			| table_ref CROSS JOIN table_ref
				{ /*C
					/* CROSS JOIN is same as unqualified inner join * /
					JoinExpr   *n = makeNode(JoinExpr);

					n->jointype = JOIN_INNER;
					n->isNatural = false;
					n->larg = $1;
					n->rarg = $4;
					n->usingClause = NIL;
					n->join_using_alias = NULL;
					n->quals = NULL;
					$$ = n;
				*/ }
			| table_ref join_type JOIN table_ref join_qual
				{ /*C
					JoinExpr   *n = makeNode(JoinExpr);

					n->jointype = $2;
					n->isNatural = false;
					n->larg = $1;
					n->rarg = $4;
					if ($5 != NULL && IsA($5, List))
					{
						 /* USING clause * /
						n->usingClause = linitial_node(List, castNode(List, $5));
						n->join_using_alias = lsecond_node(Alias, castNode(List, $5));
					}
					else
					{
						/* ON clause * /
						n->quals = $5;
					}
					$$ = n;
				*/ }
			| table_ref JOIN table_ref join_qual
				{ /*C
					/* letting join_type reduce to empty doesn't work * /
					JoinExpr   *n = makeNode(JoinExpr);

					n->jointype = JOIN_INNER;
					n->isNatural = false;
					n->larg = $1;
					n->rarg = $3;
					if ($4 != NULL && IsA($4, List))
					{
						/* USING clause * /
						n->usingClause = linitial_node(List, castNode(List, $4));
						n->join_using_alias = lsecond_node(Alias, castNode(List, $4));
					}
					else
					{
						/* ON clause * /
						n->quals = $4;
					}
					$$ = n;
				*/ }
			| table_ref NATURAL join_type JOIN table_ref
				{ /*C
					JoinExpr   *n = makeNode(JoinExpr);

					n->jointype = $3;
					n->isNatural = true;
					n->larg = $1;
					n->rarg = $5;
					n->usingClause = NIL; /* figure out which columns later... * /
					n->join_using_alias = NULL;
					n->quals = NULL; /* fill later * /
					$$ = n;
				*/ }
			| table_ref NATURAL JOIN table_ref
				{ /*C
					/* letting join_type reduce to empty doesn't work * /
					JoinExpr   *n = makeNode(JoinExpr);

					n->jointype = JOIN_INNER;
					n->isNatural = true;
					n->larg = $1;
					n->rarg = $4;
					n->usingClause = NIL; /* figure out which columns later... * /
					n->join_using_alias = NULL;
					n->quals = NULL; /* fill later * /
					$$ = n;
				*/ }
		;

alias_clause:
			AS ColId '(' name_list ')'
				{ /*C
					$$ = makeNode(Alias);
					$$->aliasname = $2;
					$$->colnames = $4;
				*/ }
			| AS ColId
				{ /*C
					$$ = makeNode(Alias);
					$$->aliasname = $2;
				*/ }
			| ColId '(' name_list ')'
				{ /*C
					$$ = makeNode(Alias);
					$$->aliasname = $1;
					$$->colnames = $3;
				*/ }
			| ColId
				{ /*C
					$$ = makeNode(Alias);
					$$->aliasname = $1;
				*/ }
		;

opt_alias_clause: alias_clause						{ $$ = $1 }
			| /*EMPTY*/								{ $$ = nil }
		;

/*
 * The alias clause after JOIN ... USING only accepts the AS ColId spelling,
 * per SQL standard.  (The grammar could parse the other variants, but they
 * don't seem to be useful, and it might lead to parser problems in the
 * future.)
 */
opt_alias_clause_for_join_using:
			AS ColId
				{ /*C
					$$ = makeNode(Alias);
					$$->aliasname = $2;
					/* the column name list will be inserted later * /
				*/ }
			| /*EMPTY*/								{ $$ = nil }
		;

/*
 * func_alias_clause can include both an Alias and a coldeflist, so we make it
 * return a 2-element list that gets disassembled by calling production.
 */
func_alias_clause:
			alias_clause
				{ /*C
					$$ = list_make2($1, NIL);
				*/ }
			| AS '(' TableFuncElementList ')'
				{ /*C
					$$ = list_make2(NULL, $3);
				*/ }
			| AS ColId '(' TableFuncElementList ')'
				{ /*C
					Alias	   *a = makeNode(Alias);

					a->aliasname = $2;
					$$ = list_make2(a, $4);
				*/ }
			| ColId '(' TableFuncElementList ')'
				{ /*C
					Alias	   *a = makeNode(Alias);

					a->aliasname = $1;
					$$ = list_make2(a, $3);
				*/ }
			| /*EMPTY*/
				{ /*C
					$$ = list_make2(NULL, NIL);
				*/ }
		;

join_type:	FULL opt_outer							{ $$ = int32(JOIN_FULL) }
			| LEFT opt_outer						{ $$ = int32(JOIN_LEFT) }
			| RIGHT opt_outer						{ $$ = int32(JOIN_RIGHT) }
			| INNER_P								{ $$ = int32(JOIN_INNER) }
		;

/* OUTER is just noise... */
opt_outer: OUTER_P
			| /*EMPTY*/
		;

/* JOIN qualification clauses
 * Possibilities are:
 *	USING ( column list ) [ AS alias ]
 *						  allows only unqualified column names,
 *						  which must match between tables.
 *	ON expr allows more general qualifications.
 *
 * We return USING as a two-element List (the first item being a sub-List
 * of the common column names, and the second either an Alias item or NULL).
 * An ON-expr will not be a List, so it can be told apart that way.
 */

join_qual: USING '(' name_list ')' opt_alias_clause_for_join_using
				{ /*C
					$$ = (Node *) list_make2($3, $5);
				*/ }
			| ON a_expr
				{ $$ = $2 }
		;


relation_expr:
			qualified_name
				{ /*C
					/* inheritance query, implicitly * /
					$$ = $1;
					$$->inh = true;
					$$->alias = NULL;
				*/ }
			| extended_relation_expr
				{ $$ = $1 }
		;

extended_relation_expr:
			qualified_name '*'
				{ /*C
					/* inheritance query, explicitly * /
					$$ = $1;
					$$->inh = true;
					$$->alias = NULL;
				*/ }
			| ONLY qualified_name
				{ /*C
					/* no inheritance * /
					$$ = $2;
					$$->inh = false;
					$$->alias = NULL;
				*/ }
			| ONLY '(' qualified_name ')'
				{ /*C
					/* no inheritance, SQL99-style syntax * /
					$$ = $3;
					$$->inh = false;
					$$->alias = NULL;
				*/ }
		;


relation_expr_list:
			relation_expr							{ $$ = []Node{$1} }
			| relation_expr_list ',' relation_expr	{ $$ = append($1, $3) }
		;


/*
 * Given "UPDATE foo set set ...", we have to decide without looking any
 * further ahead whether the first "set" is an alias or the UPDATE's SET
 * keyword.  Since "set" is allowed as a column name both interpretations
 * are feasible.  We resolve the shift/reduce conflict by giving the first
 * relation_expr_opt_alias production a higher precedence than the SET token
 * has, causing the parser to prefer to reduce, in effect assuming that the
 * SET is not an alias.
 */
relation_expr_opt_alias: relation_expr					%prec UMINUS
				{ $$ = $1 }
			| relation_expr ColId
				{ /*C
					Alias	   *alias = makeNode(Alias);

					alias->aliasname = $2;
					$1->alias = alias;
					$$ = $1;
				*/ }
			| relation_expr AS ColId
				{ /*C
					Alias	   *alias = makeNode(Alias);

					alias->aliasname = $3;
					$1->alias = alias;
					$$ = $1;
				*/ }
		;

/*
 * TABLESAMPLE decoration in a FROM item
 */
tablesample_clause:
			TABLESAMPLE func_name '(' expr_list ')' opt_repeatable_clause
				{ /*C
					RangeTableSample *n = makeNode(RangeTableSample);

					/* n->relation will be filled in later * /
					n->method = $2;
					n->args = $4;
					n->repeatable = $6;
					n->location = @2;
					$$ = (Node *) n;
				*/ }
		;

opt_repeatable_clause:
			REPEATABLE '(' a_expr ')'	{ $$ = $3 }
			| /*EMPTY*/					{ $$ = nil }
		;

/*
 * func_table represents a function invocation in a FROM list. It can be
 * a plain function call, like "foo(...)", or a ROWS FROM expression with
 * one or more function calls, "ROWS FROM (foo(...), bar(...))",
 * optionally with WITH ORDINALITY attached.
 * In the ROWS FROM syntax, a column definition list can be given for each
 * function, for example:
 *     ROWS FROM (foo() AS (foo_res_a text, foo_res_b text),
 *                bar() AS (bar_res_a text, bar_res_b text))
 * It's also possible to attach a column definition list to the RangeFunction
 * as a whole, but that's handled by the table_ref production.
 */
func_table: func_expr_windowless opt_ordinality
				{ /*C
					RangeFunction *n = makeNode(RangeFunction);

					n->lateral = false;
					n->ordinality = $2;
					n->is_rowsfrom = false;
					n->functions = list_make1(list_make2($1, NIL));
					/* alias and coldeflist are set by table_ref production * /
					$$ = (Node *) n;
				*/ }
			| ROWS FROM '(' rowsfrom_list ')' opt_ordinality
				{ /*C
					RangeFunction *n = makeNode(RangeFunction);

					n->lateral = false;
					n->ordinality = $6;
					n->is_rowsfrom = true;
					n->functions = $4;
					/* alias and coldeflist are set by table_ref production * /
					$$ = (Node *) n;
				*/ }
		;

rowsfrom_item: func_expr_windowless opt_col_def_list
				{ /*C $$ = list_make2($1, $2); */ }
		;

rowsfrom_list:
			rowsfrom_item						{ /*C $$ = list_make1($1); */ }
			| rowsfrom_list ',' rowsfrom_item	{ /*C $$ = lappend($1, $3); */ }
		;

opt_col_def_list: AS '(' TableFuncElementList ')'	{ $$ = $3 }
			| /*EMPTY*/								{ $$ = nil }
		;

opt_ordinality: WITH_LA ORDINALITY					{ $$ = true }
			| /*EMPTY*/								{ $$ = false }
		;


where_clause:
			WHERE a_expr							{ $$ = $2 }
			| /*EMPTY*/								{ $$ = nil }
		;

/* variant for UPDATE and DELETE */
where_or_current_clause:
			WHERE a_expr							{ $$ = $2 }
			| WHERE CURRENT_P OF cursor_name
				{ /*C
					CurrentOfExpr *n = makeNode(CurrentOfExpr);

					/* cvarno is filled in by parse analysis * /
					n->cursor_name = $4;
					n->cursor_param = 0;
					$$ = (Node *) n;
				*/ }
			| /*EMPTY*/								{ $$ = nil }
		;


OptTableFuncElementList:
			TableFuncElementList				{ $$ = $1 }
			| /*EMPTY*/							{ $$ = nil }
		;

TableFuncElementList:
			TableFuncElement
				{ $$ = []Node{$1} }
			| TableFuncElementList ',' TableFuncElement
				{ $$ = append($1, $3) }
		;

TableFuncElement:	ColId Typename opt_collate_clause
				{ /*C
					ColumnDef *n = makeNode(ColumnDef);

					n->colname = $1;
					n->typeName = $2;
					n->inhcount = 0;
					n->is_local = true;
					n->is_not_null = false;
					n->is_from_type = false;
					n->storage = 0;
					n->raw_default = NULL;
					n->cooked_default = NULL;
					n->collClause = (CollateClause *) $3;
					n->collOid = InvalidOid;
					n->constraints = NIL;
					n->location = @1;
					$$ = (Node *) n;
				*/ }
		;

/*
 * XMLTABLE
 */
xmltable:
			XMLTABLE '(' c_expr xmlexists_argument COLUMNS xmltable_column_list ')'
				{ /*C
					RangeTableFunc *n = makeNode(RangeTableFunc);

					n->rowexpr = $3;
					n->docexpr = $4;
					n->columns = $6;
					n->namespaces = NIL;
					n->location = @1;
					$$ = (Node *) n;
				*/ }
			| XMLTABLE '(' XMLNAMESPACES '(' xml_namespace_list ')' ','
				c_expr xmlexists_argument COLUMNS xmltable_column_list ')'
				{ /*C
					RangeTableFunc *n = makeNode(RangeTableFunc);

					n->rowexpr = $8;
					n->docexpr = $9;
					n->columns = $11;
					n->namespaces = $5;
					n->location = @1;
					$$ = (Node *) n;
				*/ }
		;

xmltable_column_list: xmltable_column_el					{ $$ = []Node{$1} }
			| xmltable_column_list ',' xmltable_column_el	{ $$ = append($1, $3) }
		;

xmltable_column_el:
			ColId Typename
				{ /*C
					RangeTableFuncCol *fc = makeNode(RangeTableFuncCol);

					fc->colname = $1;
					fc->for_ordinality = false;
					fc->typeName = $2;
					fc->is_not_null = false;
					fc->colexpr = NULL;
					fc->coldefexpr = NULL;
					fc->location = @1;

					$$ = (Node *) fc;
				*/ }
			| ColId Typename xmltable_column_option_list
				{ /*C
					RangeTableFuncCol *fc = makeNode(RangeTableFuncCol);
					ListCell   *option;
					bool		nullability_seen = false;

					fc->colname = $1;
					fc->typeName = $2;
					fc->for_ordinality = false;
					fc->is_not_null = false;
					fc->colexpr = NULL;
					fc->coldefexpr = NULL;
					fc->location = @1;

					foreach(option, $3)
					{
						DefElem   *defel = (DefElem *) lfirst(option);

						if (strcmp(defel->defname, "default") == 0)
						{
							if (fc->coldefexpr != NULL)
								ereport(ERROR,
										(errcode(ERRCODE_SYNTAX_ERROR),
										 errmsg("only one DEFAULT value is allowed"),
										 parser_errposition(defel->location)));
							fc->coldefexpr = defel->arg;
						}
						else if (strcmp(defel->defname, "path") == 0)
						{
							if (fc->colexpr != NULL)
								ereport(ERROR,
										(errcode(ERRCODE_SYNTAX_ERROR),
										 errmsg("only one PATH value per column is allowed"),
										 parser_errposition(defel->location)));
							fc->colexpr = defel->arg;
						}
						else if (strcmp(defel->defname, "__pg__is_not_null") == 0)
						{
							if (nullability_seen)
								ereport(ERROR,
										(errcode(ERRCODE_SYNTAX_ERROR),
										 errmsg("conflicting or redundant NULL / NOT NULL declarations for column \"%s\"", fc->colname),
										 parser_errposition(defel->location)));
							fc->is_not_null = boolVal(defel->arg);
							nullability_seen = true;
						}
						else
						{
							ereport(ERROR,
									(errcode(ERRCODE_SYNTAX_ERROR),
									 errmsg("unrecognized column option \"%s\"",
											defel->defname),
									 parser_errposition(defel->location)));
						}
					}
					$$ = (Node *) fc;
				*/ }
			| ColId FOR ORDINALITY
				{ /*C
					RangeTableFuncCol *fc = makeNode(RangeTableFuncCol);

					fc->colname = $1;
					fc->for_ordinality = true;
					/* other fields are ignored, initialized by makeNode * /
					fc->location = @1;

					$$ = (Node *) fc;
				*/ }
		;

xmltable_column_option_list:
			xmltable_column_option_el
				{ $$ = []Node{$1} }
			| xmltable_column_option_list xmltable_column_option_el
				{ $$ = append($1, $2) }
		;

xmltable_column_option_el:
			IDENT b_expr
				{ /*C
					if (strcmp($1, "__pg__is_not_null") == 0)
						ereport(ERROR,
								(errcode(ERRCODE_SYNTAX_ERROR),
								 errmsg("option name \"%s\" cannot be used in XMLTABLE", $1),
								 parser_errposition(@1)));
					$$ = makeDefElem($1, $2, @1);
				*/ }
			| DEFAULT b_expr
				{ /*C $$ = makeDefElem("default", $2, @1); */ }
			| NOT NULL_P
				{ /*C $$ = makeDefElem("__pg__is_not_null", (Node *) makeBoolean(true), @1); */ }
			| NULL_P
				{ /*C $$ = makeDefElem("__pg__is_not_null", (Node *) makeBoolean(false), @1); */ }
			| PATH b_expr
				{ /*C $$ = makeDefElem("path", $2, @1); */ }
		;

xml_namespace_list:
			xml_namespace_el
				{ $$ = []Node{$1} }
			| xml_namespace_list ',' xml_namespace_el
				{ $$ = append($1, $3) }
		;

xml_namespace_el:
			b_expr AS ColLabel
				{ /*C
					$$ = makeNode(ResTarget);
					$$->name = $3;
					$$->indirection = NIL;
					$$->val = $1;
					$$->location = @1;
				*/ }
			| DEFAULT b_expr
				{ /*C
					$$ = makeNode(ResTarget);
					$$->name = NULL;
					$$->indirection = NIL;
					$$->val = $2;
					$$->location = @1;
				*/ }
		;

json_table:
			JSON_TABLE '('
				json_value_expr ',' a_expr json_table_path_name_opt
				json_passing_clause_opt
				COLUMNS '(' json_table_column_definition_list ')'
				json_on_error_clause_opt
			')'
				{ /*C
					JsonTable *n = makeNode(JsonTable);
					char	  *pathstring;

					n->context_item = (JsonValueExpr *) $3;
					if (!IsA($5, A_Const) ||
						castNode(A_Const, $5)->val.node.type != T_String)
						ereport(ERROR,
								errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
								errmsg("only string constants are supported in JSON_TABLE path specification"),
								parser_errposition(@5));
					pathstring = castNode(A_Const, $5)->val.sval.sval;
					n->pathspec = makeJsonTablePathSpec(pathstring, $6, @5, @6);
					n->passing = $7;
					n->columns = $10;
					n->on_error = (JsonBehavior *) $12;
					n->location = @1;
					$$ = (Node *) n;
				*/ }
		;

json_table_path_name_opt:
			AS name			{ $$ = $2 }
			| /* empty */	{ $$ = "" }
		;

json_table_column_definition_list:
			json_table_column_definition
				{ $$ = []Node{$1} }
			| json_table_column_definition_list ',' json_table_column_definition
				{ $$ = append($1, $3) }
		;

json_table_column_definition:
			ColId FOR ORDINALITY
				{ /*C
					JsonTableColumn *n = makeNode(JsonTableColumn);

					n->coltype = JTC_FOR_ORDINALITY;
					n->name = $1;
					n->location = @1;
					$$ = (Node *) n;
				*/ }
			| ColId Typename
				json_table_column_path_clause_opt
				json_wrapper_behavior
				json_quotes_clause_opt
				json_behavior_clause_opt
				{ /*C
					JsonTableColumn *n = makeNode(JsonTableColumn);

					n->coltype = JTC_REGULAR;
					n->name = $1;
					n->typeName = $2;
					n->format = makeJsonFormat(JS_FORMAT_DEFAULT, JS_ENC_DEFAULT, -1);
					n->pathspec = (JsonTablePathSpec *) $3;
					n->wrapper = $4;
					n->quotes = $5;
					n->on_empty = (JsonBehavior *) linitial($6);
					n->on_error = (JsonBehavior *) lsecond($6);
					n->location = @1;
					$$ = (Node *) n;
				*/ }
			| ColId Typename json_format_clause
				json_table_column_path_clause_opt
				json_wrapper_behavior
				json_quotes_clause_opt
				json_behavior_clause_opt
				{ /*C
					JsonTableColumn *n = makeNode(JsonTableColumn);

					n->coltype = JTC_FORMATTED;
					n->name = $1;
					n->typeName = $2;
					n->format = (JsonFormat *) $3;
					n->pathspec = (JsonTablePathSpec *) $4;
					n->wrapper = $5;
					n->quotes = $6;
					n->on_empty = (JsonBehavior *) linitial($7);
					n->on_error = (JsonBehavior *) lsecond($7);
					n->location = @1;
					$$ = (Node *) n;
				*/ }
			| ColId Typename
				EXISTS json_table_column_path_clause_opt
				json_on_error_clause_opt
				{ /*C
					JsonTableColumn *n = makeNode(JsonTableColumn);

					n->coltype = JTC_EXISTS;
					n->name = $1;
					n->typeName = $2;
					n->format = makeJsonFormat(JS_FORMAT_DEFAULT, JS_ENC_DEFAULT, -1);
					n->wrapper = JSW_NONE;
					n->quotes = JS_QUOTES_UNSPEC;
					n->pathspec = (JsonTablePathSpec *) $4;
					n->on_empty = NULL;
					n->on_error = (JsonBehavior *) $5;
					n->location = @1;
					$$ = (Node *) n;
				*/ }
			| NESTED path_opt Sconst
				COLUMNS '(' json_table_column_definition_list ')'
				{ /*C
					JsonTableColumn *n = makeNode(JsonTableColumn);

					n->coltype = JTC_NESTED;
					n->pathspec = (JsonTablePathSpec *)
						makeJsonTablePathSpec($3, NULL, @3, -1);
					n->columns = $6;
					n->location = @1;
					$$ = (Node *) n;
				*/ }
			| NESTED path_opt Sconst AS name
				COLUMNS '(' json_table_column_definition_list ')'
				{ /*C
					JsonTableColumn *n = makeNode(JsonTableColumn);

					n->coltype = JTC_NESTED;
					n->pathspec = (JsonTablePathSpec *)
						makeJsonTablePathSpec($3, $5, @3, @5);
					n->columns = $8;
					n->location = @1;
					$$ = (Node *) n;
				*/ }
		;

path_opt:
			PATH
			| /* EMPTY */
		;

json_table_column_path_clause_opt:
			PATH Sconst
				{ /*C $$ = (Node *) makeJsonTablePathSpec($2, NULL, @2, -1); */ }
			| /* EMPTY */
				{ $$ = nil }
		;

/*****************************************************************************
 *
 *	Type syntax
 *		SQL introduces a large amount of type-specific syntax.
 *		Define individual clauses to handle these cases, and use
 *		 the generic case to handle regular type-extensible Postgres syntax.
 *		- thomas 1997-10-10
 *
 *****************************************************************************/

Typename:	SimpleTypename opt_array_bounds
				{ /*C
					$$ = $1;
					$$->arrayBounds = $2;
				*/ }
			| SETOF SimpleTypename opt_array_bounds
				{ /*C
					$$ = $2;
					$$->arrayBounds = $3;
					$$->setof = true;
				*/ }
			/* SQL standard syntax, currently only one-dimensional */
			| SimpleTypename ARRAY '[' Iconst ']'
				{ /*C
					$$ = $1;
					$$->arrayBounds = list_make1(makeInteger($4));
				*/ }
			| SETOF SimpleTypename ARRAY '[' Iconst ']'
				{ /*C
					$$ = $2;
					$$->arrayBounds = list_make1(makeInteger($5));
					$$->setof = true;
				*/ }
			| SimpleTypename ARRAY
				{ /*C
					$$ = $1;
					$$->arrayBounds = list_make1(makeInteger(-1));
				*/ }
			| SETOF SimpleTypename ARRAY
				{ /*C
					$$ = $2;
					$$->arrayBounds = list_make1(makeInteger(-1));
					$$->setof = true;
				*/ }
		;

opt_array_bounds:
			opt_array_bounds '[' ']'
					{ /*C  $$ = lappend($1, makeInteger(-1)); */ }
			| opt_array_bounds '[' Iconst ']'
					{ /*C  $$ = lappend($1, makeInteger($3)); */ }
			| /*EMPTY*/
					{ $$ = nil }
		;

SimpleTypename:
			GenericType								{ $$ = $1 }
			| Numeric								{ $$ = $1 }
			| Bit									{ $$ = $1 }
			| Character								{ $$ = $1 }
			| ConstDatetime							{ $$ = $1 }
			| ConstInterval opt_interval
				{ /*C
					$$ = $1;
					$$->typmods = $2;
				*/ }
			| ConstInterval '(' Iconst ')'
				{ /*C
					$$ = $1;
					$$->typmods = list_make2(makeIntConst(INTERVAL_FULL_RANGE, -1),
											 makeIntConst($3, @3));
				*/ }
			| JsonType								{ $$ = $1 }
		;

/* We have a separate ConstTypename to allow defaulting fixed-length
 * types such as CHAR() and BIT() to an unspecified length.
 * SQL9x requires that these default to a length of one, but this
 * makes no sense for constructs like CHAR 'hi' and BIT '0101',
 * where there is an obvious better choice to make.
 * Note that ConstInterval is not included here since it must
 * be pushed up higher in the rules to accommodate the postfix
 * options (e.g. INTERVAL '1' YEAR). Likewise, we have to handle
 * the generic-type-name case in AexprConst to avoid premature
 * reduce/reduce conflicts against function names.
 */
ConstTypename:
			Numeric									{ $$ = $1 }
			| ConstBit								{ $$ = $1 }
			| ConstCharacter						{ $$ = $1 }
			| ConstDatetime							{ $$ = $1 }
			| JsonType								{ $$ = $1 }
		;

/*
 * GenericType covers all type names that don't have special syntax mandated
 * by the standard, including qualified names.  We also allow type modifiers.
 * To avoid parsing conflicts against function invocations, the modifiers
 * have to be shown as expr_list here, but parse analysis will only accept
 * constants for them.
 */
GenericType:
			type_function_name opt_type_modifiers
				{ /*C
					$$ = makeTypeName($1);
					$$->typmods = $2;
					$$->location = @1;
				*/ }
			| type_function_name attrs opt_type_modifiers
				{ /*C
					$$ = makeTypeNameFromNameList(lcons(makeString($1), $2));
					$$->typmods = $3;
					$$->location = @1;
				*/ }
		;

opt_type_modifiers: '(' expr_list ')'				{ $$ = $2 }
					| /* EMPTY */					{ $$ = nil }
		;

/*
 * SQL numeric data types
 */
Numeric:	INT_P
				{ /*C
					$$ = SystemTypeName("int4");
					$$->location = @1;
				*/ }
			| INTEGER
				{ /*C
					$$ = SystemTypeName("int4");
					$$->location = @1;
				*/ }
			| SMALLINT
				{ /*C
					$$ = SystemTypeName("int2");
					$$->location = @1;
				*/ }
			| BIGINT
				{ /*C
					$$ = SystemTypeName("int8");
					$$->location = @1;
				*/ }
			| REAL
				{ /*C
					$$ = SystemTypeName("float4");
					$$->location = @1;
				*/ }
			| FLOAT_P opt_float
				{ /*C
					$$ = $2;
					$$->location = @1;
				*/ }
			| DOUBLE_P PRECISION
				{ /*C
					$$ = SystemTypeName("float8");
					$$->location = @1;
				*/ }
			| DECIMAL_P opt_type_modifiers
				{ /*C
					$$ = SystemTypeName("numeric");
					$$->typmods = $2;
					$$->location = @1;
				*/ }
			| DEC opt_type_modifiers
				{ /*C
					$$ = SystemTypeName("numeric");
					$$->typmods = $2;
					$$->location = @1;
				*/ }
			| NUMERIC opt_type_modifiers
				{ /*C
					$$ = SystemTypeName("numeric");
					$$->typmods = $2;
					$$->location = @1;
				*/ }
			| BOOLEAN_P
				{ /*C
					$$ = SystemTypeName("bool");
					$$->location = @1;
				*/ }
		;

opt_float:	'(' Iconst ')'
				{ /*C
					/*
					 * Check FLOAT() precision limits assuming IEEE floating
					 * types - thomas 1997-09-18
					 * /
					if ($2 < 1)
						ereport(ERROR,
								(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
								 errmsg("precision for type float must be at least 1 bit"),
								 parser_errposition(@2)));
					else if ($2 <= 24)
						$$ = SystemTypeName("float4");
					else if ($2 <= 53)
						$$ = SystemTypeName("float8");
					else
						ereport(ERROR,
								(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
								 errmsg("precision for type float must be less than 54 bits"),
								 parser_errposition(@2)));
				*/ }
			| /*EMPTY*/
				{ /*C
					$$ = SystemTypeName("float8");
				*/ }
		;

/*
 * SQL bit-field data types
 * The following implements BIT() and BIT VARYING().
 */
Bit:		BitWithLength
				{ $$ = $1 }
			| BitWithoutLength
				{ $$ = $1 }
		;

/* ConstBit is like Bit except "BIT" defaults to unspecified length */
/* See notes for ConstCharacter, which addresses same issue for "CHAR" */
ConstBit:	BitWithLength
				{ $$ = $1 }
			| BitWithoutLength
				{ /*C
					$$ = $1;
					$$->typmods = NIL;
				*/ }
		;

BitWithLength:
			BIT opt_varying '(' expr_list ')'
				{ /*C
					char *typname;

					typname = $2 ? "varbit" : "bit";
					$$ = SystemTypeName(typname);
					$$->typmods = $4;
					$$->location = @1;
				*/ }
		;

BitWithoutLength:
			BIT opt_varying
				{ /*C
					/* bit defaults to bit(1), varbit to no limit * /
					if ($2)
					{
						$$ = SystemTypeName("varbit");
					}
					else
					{
						$$ = SystemTypeName("bit");
						$$->typmods = list_make1(makeIntConst(1, -1));
					}
					$$->location = @1;
				*/ }
		;


/*
 * SQL character data types
 * The following implements CHAR() and VARCHAR().
 */
Character:  CharacterWithLength
				{ $$ = $1 }
			| CharacterWithoutLength
				{ $$ = $1 }
		;

ConstCharacter:  CharacterWithLength
				{ $$ = $1 }
			| CharacterWithoutLength
				{ /*C
					/* Length was not specified so allow to be unrestricted.
					 * This handles problems with fixed-length (bpchar) strings
					 * which in column definitions must default to a length
					 * of one, but should not be constrained if the length
					 * was not specified.
					 * /
					$$ = $1;
					$$->typmods = NIL;
				*/ }
		;

CharacterWithLength:  character '(' Iconst ')'
				{ /*C
					$$ = SystemTypeName($1);
					$$->typmods = list_make1(makeIntConst($3, @3));
					$$->location = @1;
				*/ }
		;

CharacterWithoutLength:	 character
				{ /*C
					$$ = SystemTypeName($1);
					/* char defaults to char(1), varchar to no limit * /
					if (strcmp($1, "bpchar") == 0)
						$$->typmods = list_make1(makeIntConst(1, -1));
					$$->location = @1;
				*/ }
		;

character:	CHARACTER opt_varying
										{ /*C $$ = $2 ? "varchar": "bpchar"; */ }
			| CHAR_P opt_varying
										{ /*C $$ = $2 ? "varchar": "bpchar"; */ }
			| VARCHAR
										{ $$ = "varchar" }
			| NATIONAL CHARACTER opt_varying
										{ /*C $$ = $3 ? "varchar": "bpchar"; */ }
			| NATIONAL CHAR_P opt_varying
										{ /*C $$ = $3 ? "varchar": "bpchar"; */ }
			| NCHAR opt_varying
										{ /*C $$ = $2 ? "varchar": "bpchar"; */ }
		;

opt_varying:
			VARYING									{ $$ = true }
			| /*EMPTY*/								{ $$ = false }
		;

/*
 * SQL date/time types
 */
ConstDatetime:
			TIMESTAMP '(' Iconst ')' opt_timezone
				{ /*C
					if ($5)
						$$ = SystemTypeName("timestamptz");
					else
						$$ = SystemTypeName("timestamp");
					$$->typmods = list_make1(makeIntConst($3, @3));
					$$->location = @1;
				*/ }
			| TIMESTAMP opt_timezone
				{ /*C
					if ($2)
						$$ = SystemTypeName("timestamptz");
					else
						$$ = SystemTypeName("timestamp");
					$$->location = @1;
				*/ }
			| TIME '(' Iconst ')' opt_timezone
				{ /*C
					if ($5)
						$$ = SystemTypeName("timetz");
					else
						$$ = SystemTypeName("time");
					$$->typmods = list_make1(makeIntConst($3, @3));
					$$->location = @1;
				*/ }
			| TIME opt_timezone
				{ /*C
					if ($2)
						$$ = SystemTypeName("timetz");
					else
						$$ = SystemTypeName("time");
					$$->location = @1;
				*/ }
		;

ConstInterval:
			INTERVAL
				{ /*C
					$$ = SystemTypeName("interval");
					$$->location = @1;
				*/ }
		;

opt_timezone:
			WITH_LA TIME ZONE						{ $$ = true }
			| WITHOUT_LA TIME ZONE					{ $$ = false }
			| /*EMPTY*/								{ $$ = false }
		;

opt_interval:
			YEAR_P
				{ /*C $$ = list_make1(makeIntConst(INTERVAL_MASK(YEAR), @1)); */ }
			| MONTH_P
				{ /*C $$ = list_make1(makeIntConst(INTERVAL_MASK(MONTH), @1)); */ }
			| DAY_P
				{ /*C $$ = list_make1(makeIntConst(INTERVAL_MASK(DAY), @1)); */ }
			| HOUR_P
				{ /*C $$ = list_make1(makeIntConst(INTERVAL_MASK(HOUR), @1)); */ }
			| MINUTE_P
				{ /*C $$ = list_make1(makeIntConst(INTERVAL_MASK(MINUTE), @1)); */ }
			| interval_second
				{ $$ = $1 }
			| YEAR_P TO MONTH_P
				{ /*C
					$$ = list_make1(makeIntConst(INTERVAL_MASK(YEAR) |
												 INTERVAL_MASK(MONTH), @1));
				*/ }
			| DAY_P TO HOUR_P
				{ /*C
					$$ = list_make1(makeIntConst(INTERVAL_MASK(DAY) |
												 INTERVAL_MASK(HOUR), @1));
				*/ }
			| DAY_P TO MINUTE_P
				{ /*C
					$$ = list_make1(makeIntConst(INTERVAL_MASK(DAY) |
												 INTERVAL_MASK(HOUR) |
												 INTERVAL_MASK(MINUTE), @1));
				*/ }
			| DAY_P TO interval_second
				{ /*C
					$$ = $3;
					linitial($$) = makeIntConst(INTERVAL_MASK(DAY) |
												INTERVAL_MASK(HOUR) |
												INTERVAL_MASK(MINUTE) |
												INTERVAL_MASK(SECOND), @1);
				*/ }
			| HOUR_P TO MINUTE_P
				{ /*C
					$$ = list_make1(makeIntConst(INTERVAL_MASK(HOUR) |
												 INTERVAL_MASK(MINUTE), @1));
				*/ }
			| HOUR_P TO interval_second
				{ /*C
					$$ = $3;
					linitial($$) = makeIntConst(INTERVAL_MASK(HOUR) |
												INTERVAL_MASK(MINUTE) |
												INTERVAL_MASK(SECOND), @1);
				*/ }
			| MINUTE_P TO interval_second
				{ /*C
					$$ = $3;
					linitial($$) = makeIntConst(INTERVAL_MASK(MINUTE) |
												INTERVAL_MASK(SECOND), @1);
				*/ }
			| /*EMPTY*/
				{ $$ = nil }
		;

interval_second:
			SECOND_P
				{ /*C
					$$ = list_make1(makeIntConst(INTERVAL_MASK(SECOND), @1));
				*/ }
			| SECOND_P '(' Iconst ')'
				{ /*C
					$$ = list_make2(makeIntConst(INTERVAL_MASK(SECOND), @1),
									makeIntConst($3, @3));
				*/ }
		;

JsonType:
			JSON
				{ /*C
					$$ = SystemTypeName("json");
					$$->location = @1;
				*/ }
		;

