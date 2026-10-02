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
				{
					r := as[*RangeVar]($1)

					r.Alias = as[*Alias]($2)
					$$ = r
				}
			| relation_expr opt_alias_clause tablesample_clause
				{
					n := as[*RangeTableSample]($3)
					r := as[*RangeVar]($1)

					r.Alias = as[*Alias]($2)
					/* relation_expr goes inside the RangeTableSample node */
					n.Relation = r
					$$ = n
				}
			| func_table func_alias_clause
				{
					n := as[*RangeFunction]($1)

					n.Alias = as[*Alias]($2[0])
					n.Coldeflist = asList($2[1])
					$$ = n
				}
			| LATERAL_P func_table func_alias_clause
				{
					n := as[*RangeFunction]($2)

					n.Lateral = true
					n.Alias = as[*Alias]($3[0])
					n.Coldeflist = asList($3[1])
					$$ = n
				}
			| xmltable opt_alias_clause
				{
					n := as[*RangeTableFunc]($1)

					n.Alias = as[*Alias]($2)
					$$ = n
				}
			| LATERAL_P xmltable opt_alias_clause
				{
					n := as[*RangeTableFunc]($2)

					n.Lateral = true
					n.Alias = as[*Alias]($3)
					$$ = n
				}
			| select_with_parens opt_alias_clause
				{
					n := &RangeSubselect{}

					n.Lateral = false
					n.Subquery = $1
					n.Alias = as[*Alias]($2)
					$$ = n
				}
			| LATERAL_P select_with_parens opt_alias_clause
				{
					n := &RangeSubselect{}

					n.Lateral = true
					n.Subquery = $2
					n.Alias = as[*Alias]($3)
					$$ = n
				}
			| joined_table
				{ $$ = $1 }
			| '(' joined_table ')' alias_clause
				{
					j := as[*JoinExpr]($2)

					j.Alias = as[*Alias]($4)
					$$ = j
				}
			| json_table opt_alias_clause
				{
					jt := as[*JsonTable]($1)

					jt.Alias = as[*Alias]($2)
					$$ = jt
				}
			| LATERAL_P json_table opt_alias_clause
				{
					jt := as[*JsonTable]($2)

					jt.Alias = as[*Alias]($3)
					jt.Lateral = true
					$$ = jt
				}
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
				{
					/* CROSS JOIN is same as unqualified inner join */
					n := &JoinExpr{}

					n.Jointype = JOIN_INNER
					n.IsNatural = false
					n.Larg = $1
					n.Rarg = $4
					n.UsingClause = nil
					n.JoinUsingAlias = nil
					n.Quals = nil
					$$ = n
				}
			| table_ref join_type JOIN table_ref join_qual
				{
					n := &JoinExpr{}

					n.Jointype = JoinType($2)
					n.IsNatural = false
					n.Larg = $1
					n.Rarg = $4
					if l, ok := $5.(*List); ok {
						/* USING clause */
						n.UsingClause = asList(l.Items[0])
						n.JoinUsingAlias = as[*Alias](l.Items[1])
					} else {
						/* ON clause */
						n.Quals = $5
					}
					$$ = n
				}
			| table_ref JOIN table_ref join_qual
				{
					/* letting join_type reduce to empty doesn't work */
					n := &JoinExpr{}

					n.Jointype = JOIN_INNER
					n.IsNatural = false
					n.Larg = $1
					n.Rarg = $3
					if l, ok := $4.(*List); ok {
						/* USING clause */
						n.UsingClause = asList(l.Items[0])
						n.JoinUsingAlias = as[*Alias](l.Items[1])
					} else {
						/* ON clause */
						n.Quals = $4
					}
					$$ = n
				}
			| table_ref NATURAL join_type JOIN table_ref
				{
					n := &JoinExpr{}

					n.Jointype = JoinType($3)
					n.IsNatural = true
					n.Larg = $1
					n.Rarg = $5
					n.UsingClause = nil /* figure out which columns later... */
					n.JoinUsingAlias = nil
					n.Quals = nil /* fill later */
					$$ = n
				}
			| table_ref NATURAL JOIN table_ref
				{
					/* letting join_type reduce to empty doesn't work */
					n := &JoinExpr{}

					n.Jointype = JOIN_INNER
					n.IsNatural = true
					n.Larg = $1
					n.Rarg = $4
					n.UsingClause = nil /* figure out which columns later... */
					n.JoinUsingAlias = nil
					n.Quals = nil /* fill later */
					$$ = n
				}
		;

alias_clause:
			AS ColId '(' name_list ')'
				{
					n := &Alias{}

					n.Aliasname = $2
					n.Colnames = $4
					$$ = n
				}
			| AS ColId
				{
					n := &Alias{}

					n.Aliasname = $2
					$$ = n
				}
			| ColId '(' name_list ')'
				{
					n := &Alias{}

					n.Aliasname = $1
					n.Colnames = $3
					$$ = n
				}
			| ColId
				{
					n := &Alias{}

					n.Aliasname = $1
					$$ = n
				}
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
				{
					n := &Alias{}

					n.Aliasname = $2
					/* the column name list will be inserted later */
					$$ = n
				}
			| /*EMPTY*/								{ $$ = nil }
		;

/*
 * func_alias_clause can include both an Alias and a coldeflist, so we make it
 * return a 2-element list that gets disassembled by calling production.
 */
func_alias_clause:
			alias_clause
				{ $$ = []Node{$1, nil} }
			| AS '(' TableFuncElementList ')'
				{ $$ = []Node{nil, listNode($3)} }
			| AS ColId '(' TableFuncElementList ')'
				{
					a := &Alias{}

					a.Aliasname = $2
					$$ = []Node{a, listNode($4)}
				}
			| ColId '(' TableFuncElementList ')'
				{
					a := &Alias{}

					a.Aliasname = $1
					$$ = []Node{a, listNode($3)}
				}
			| /*EMPTY*/
				{ $$ = []Node{nil, nil} }
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
				{ $$ = &List{Items: []Node{listNode($3), $5}} }
			| ON a_expr
				{ $$ = $2 }
		;


relation_expr:
			qualified_name
				{
					/* inheritance query, implicitly */
					r := as[*RangeVar]($1)
					r.Inh = true
					r.Alias = nil
					$$ = r
				}
			| extended_relation_expr
				{ $$ = $1 }
		;

extended_relation_expr:
			qualified_name '*'
				{
					/* inheritance query, explicitly */
					r := as[*RangeVar]($1)
					r.Inh = true
					r.Alias = nil
					$$ = r
				}
			| ONLY qualified_name
				{
					/* no inheritance */
					r := as[*RangeVar]($2)
					r.Inh = false
					r.Alias = nil
					$$ = r
				}
			| ONLY '(' qualified_name ')'
				{
					/* no inheritance, SQL99-style syntax */
					r := as[*RangeVar]($3)
					r.Inh = false
					r.Alias = nil
					$$ = r
				}
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
				{
					alias := &Alias{}

					alias.Aliasname = $2
					r := as[*RangeVar]($1)
					r.Alias = alias
					$$ = r
				}
			| relation_expr AS ColId
				{
					alias := &Alias{}

					alias.Aliasname = $3
					r := as[*RangeVar]($1)
					r.Alias = alias
					$$ = r
				}
		;

/*
 * TABLESAMPLE decoration in a FROM item
 */
tablesample_clause:
			TABLESAMPLE func_name '(' expr_list ')' opt_repeatable_clause
				{
					n := &RangeTableSample{}

					/* n->relation will be filled in later */
					n.Method = $2
					n.Args = $4
					n.Repeatable = $6
					n.Location = @2
					$$ = n
				}
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
				{
					n := &RangeFunction{}

					n.Lateral = false
					n.Ordinality = $2
					n.IsRowsfrom = false
					n.Functions = []Node{listNode([]Node{$1, nil})}
					/* alias and coldeflist are set by table_ref production */
					$$ = n
				}
			| ROWS FROM '(' rowsfrom_list ')' opt_ordinality
				{
					n := &RangeFunction{}

					n.Lateral = false
					n.Ordinality = $6
					n.IsRowsfrom = true
					n.Functions = $4
					/* alias and coldeflist are set by table_ref production */
					$$ = n
				}
		;

rowsfrom_item: func_expr_windowless opt_col_def_list
				{ $$ = []Node{$1, listNode($2)} }
		;

rowsfrom_list:
			rowsfrom_item						{ $$ = []Node{listNode($1)} }
			| rowsfrom_list ',' rowsfrom_item	{ $$ = append($1, listNode($3)) }
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
				{
					n := &CurrentOfExpr{}

					/* cvarno is filled in by parse analysis */
					n.CursorName = $4
					n.CursorParam = 0
					$$ = n
				}
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
				{
					n := &ColumnDef{}

					n.Colname = $1
					n.TypeName = as[*TypeName]($2)
					n.Inhcount = 0
					n.IsLocal = true
					n.IsNotNull = false
					n.IsFromType = false
					n.Storage = ""
					n.RawDefault = nil
					n.CookedDefault = nil
					n.CollClause = as[*CollateClause]($3)
					n.CollOid = 0
					n.Constraints = nil
					n.Location = @1
					$$ = n
				}
		;

/*
 * XMLTABLE
 */
xmltable:
			XMLTABLE '(' c_expr xmlexists_argument COLUMNS xmltable_column_list ')'
				{
					n := &RangeTableFunc{}

					n.Rowexpr = $3
					n.Docexpr = $4
					n.Columns = $6
					n.Namespaces = nil
					n.Location = @1
					$$ = n
				}
			| XMLTABLE '(' XMLNAMESPACES '(' xml_namespace_list ')' ','
				c_expr xmlexists_argument COLUMNS xmltable_column_list ')'
				{
					n := &RangeTableFunc{}

					n.Rowexpr = $8
					n.Docexpr = $9
					n.Columns = $11
					n.Namespaces = $5
					n.Location = @1
					$$ = n
				}
		;

xmltable_column_list: xmltable_column_el					{ $$ = []Node{$1} }
			| xmltable_column_list ',' xmltable_column_el	{ $$ = append($1, $3) }
		;

xmltable_column_el:
			ColId Typename
				{
					fc := &RangeTableFuncCol{}

					fc.Colname = $1
					fc.ForOrdinality = false
					fc.TypeName = as[*TypeName]($2)
					fc.IsNotNull = false
					fc.Colexpr = nil
					fc.Coldefexpr = nil
					fc.Location = @1

					$$ = fc
				}
			| ColId Typename xmltable_column_option_list
				{
					fc := &RangeTableFuncCol{}
					nullabilitySeen := false

					fc.Colname = $1
					fc.TypeName = as[*TypeName]($2)
					fc.ForOrdinality = false
					fc.IsNotNull = false
					fc.Colexpr = nil
					fc.Coldefexpr = nil
					fc.Location = @1

					for _, option := range $3 {
						defel := as[*DefElem](option)

						if defel.Defname == "default" {
							if fc.Coldefexpr != nil {
								p.fail(defel.Location, "only one DEFAULT value is allowed")
							}
							fc.Coldefexpr = defel.Arg
						} else if defel.Defname == "path" {
							if fc.Colexpr != nil {
								p.fail(defel.Location, "only one PATH value per column is allowed")
							}
							fc.Colexpr = defel.Arg
						} else if defel.Defname == "__pg__is_not_null" {
							if nullabilitySeen {
								p.fail(defel.Location, fmt.Sprintf("conflicting or redundant NULL / NOT NULL declarations for column \"%s\"", fc.Colname))
							}
							fc.IsNotNull = as[*Boolean](defel.Arg).Boolval
							nullabilitySeen = true
						} else {
							p.fail(defel.Location, fmt.Sprintf("unrecognized column option \"%s\"", defel.Defname))
						}
					}
					$$ = fc
				}
			| ColId FOR ORDINALITY
				{
					fc := &RangeTableFuncCol{}

					fc.Colname = $1
					fc.ForOrdinality = true
					/* other fields are ignored, initialized by makeNode */
					fc.Location = @1

					$$ = fc
				}
		;

xmltable_column_option_list:
			xmltable_column_option_el
				{ $$ = []Node{$1} }
			| xmltable_column_option_list xmltable_column_option_el
				{ $$ = append($1, $2) }
		;

xmltable_column_option_el:
			IDENT b_expr
				{
					if $1 == "__pg__is_not_null" {
						p.fail(@1, fmt.Sprintf("option name \"%s\" cannot be used in XMLTABLE", $1))
					}
					$$ = makeDefElem($1, $2, @1)
				}
			| DEFAULT b_expr
				{ $$ = makeDefElem("default", $2, @1) }
			| NOT NULL_P
				{ $$ = makeDefElem("__pg__is_not_null", makeBoolean(true), @1) }
			| NULL_P
				{ $$ = makeDefElem("__pg__is_not_null", makeBoolean(false), @1) }
			| PATH b_expr
				{ $$ = makeDefElem("path", $2, @1) }
		;

xml_namespace_list:
			xml_namespace_el
				{ $$ = []Node{$1} }
			| xml_namespace_list ',' xml_namespace_el
				{ $$ = append($1, $3) }
		;

xml_namespace_el:
			b_expr AS ColLabel
				{
					n := &ResTarget{}
					n.Name = $3
					n.Indirection = nil
					n.Val = $1
					n.Location = @1
					$$ = n
				}
			| DEFAULT b_expr
				{
					n := &ResTarget{}
					n.Name = ""
					n.Indirection = nil
					n.Val = $2
					n.Location = @1
					$$ = n
				}
		;

json_table:
			JSON_TABLE '('
				json_value_expr ',' a_expr json_table_path_name_opt
				json_passing_clause_opt
				COLUMNS '(' json_table_column_definition_list ')'
				json_on_error_clause_opt
			')'
				{
					n := &JsonTable{}

					n.ContextItem = as[*JsonValueExpr]($3)
					c, ok := $5.(*A_Const)
					if !ok {
						p.fail(@5, "only string constants are supported in JSON_TABLE path specification")
					}
					s, ok := c.Val.(*String)
					if !ok {
						p.fail(@5, "only string constants are supported in JSON_TABLE path specification")
					}
					pathstring := s.Sval
					n.Pathspec = makeJsonTablePathSpec(pathstring, $6, @5, @6)
					n.Passing = $7
					n.Columns = $10
					n.OnError = as[*JsonBehavior]($12)
					n.Location = @1
					$$ = n
				}
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
				{
					n := &JsonTableColumn{}

					n.Coltype = JTC_FOR_ORDINALITY
					n.Name = $1
					n.Location = @1
					$$ = n
				}
			| ColId Typename
				json_table_column_path_clause_opt
				json_wrapper_behavior
				json_quotes_clause_opt
				json_behavior_clause_opt
				{
					n := &JsonTableColumn{}

					n.Coltype = JTC_REGULAR
					n.Name = $1
					n.TypeName = as[*TypeName]($2)
					n.Format = makeJsonFormat(JS_FORMAT_DEFAULT, JS_ENC_DEFAULT, -1)
					n.Pathspec = as[*JsonTablePathSpec]($3)
					n.Wrapper = JsonWrapper($4)
					n.Quotes = JsonQuotes($5)
					n.OnEmpty = as[*JsonBehavior]($6[0])
					n.OnError = as[*JsonBehavior]($6[1])
					n.Location = @1
					$$ = n
				}
			| ColId Typename json_format_clause
				json_table_column_path_clause_opt
				json_wrapper_behavior
				json_quotes_clause_opt
				json_behavior_clause_opt
				{
					n := &JsonTableColumn{}

					n.Coltype = JTC_FORMATTED
					n.Name = $1
					n.TypeName = as[*TypeName]($2)
					n.Format = as[*JsonFormat]($3)
					n.Pathspec = as[*JsonTablePathSpec]($4)
					n.Wrapper = JsonWrapper($5)
					n.Quotes = JsonQuotes($6)
					n.OnEmpty = as[*JsonBehavior]($7[0])
					n.OnError = as[*JsonBehavior]($7[1])
					n.Location = @1
					$$ = n
				}
			| ColId Typename
				EXISTS json_table_column_path_clause_opt
				json_on_error_clause_opt
				{
					n := &JsonTableColumn{}

					n.Coltype = JTC_EXISTS
					n.Name = $1
					n.TypeName = as[*TypeName]($2)
					n.Format = makeJsonFormat(JS_FORMAT_DEFAULT, JS_ENC_DEFAULT, -1)
					n.Wrapper = JSW_NONE
					n.Quotes = JS_QUOTES_UNSPEC
					n.Pathspec = as[*JsonTablePathSpec]($4)
					n.OnEmpty = nil
					n.OnError = as[*JsonBehavior]($5)
					n.Location = @1
					$$ = n
				}
			| NESTED path_opt Sconst
				COLUMNS '(' json_table_column_definition_list ')'
				{
					n := &JsonTableColumn{}

					n.Coltype = JTC_NESTED
					n.Pathspec = makeJsonTablePathSpec($3, "", @3, -1)
					n.Columns = $6
					n.Location = @1
					$$ = n
				}
			| NESTED path_opt Sconst AS name
				COLUMNS '(' json_table_column_definition_list ')'
				{
					n := &JsonTableColumn{}

					n.Coltype = JTC_NESTED
					n.Pathspec = makeJsonTablePathSpec($3, $5, @3, @5)
					n.Columns = $8
					n.Location = @1
					$$ = n
				}
		;

path_opt:
			PATH
			| /* EMPTY */
		;

json_table_column_path_clause_opt:
			PATH Sconst
				{ $$ = makeJsonTablePathSpec($2, "", @2, -1) }
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
				{
					t := as[*TypeName]($1)
					t.ArrayBounds = $2
					$$ = t
				}
			| SETOF SimpleTypename opt_array_bounds
				{
					t := as[*TypeName]($2)
					t.ArrayBounds = $3
					t.Setof = true
					$$ = t
				}
			/* SQL standard syntax, currently only one-dimensional */
			| SimpleTypename ARRAY '[' Iconst ']'
				{
					t := as[*TypeName]($1)
					t.ArrayBounds = []Node{makeInteger($4)}
					$$ = t
				}
			| SETOF SimpleTypename ARRAY '[' Iconst ']'
				{
					t := as[*TypeName]($2)
					t.ArrayBounds = []Node{makeInteger($5)}
					t.Setof = true
					$$ = t
				}
			| SimpleTypename ARRAY
				{
					t := as[*TypeName]($1)
					t.ArrayBounds = []Node{makeInteger(-1)}
					$$ = t
				}
			| SETOF SimpleTypename ARRAY
				{
					t := as[*TypeName]($2)
					t.ArrayBounds = []Node{makeInteger(-1)}
					t.Setof = true
					$$ = t
				}
		;

opt_array_bounds:
			opt_array_bounds '[' ']'
					{ $$ = append($1, makeInteger(-1)) }
			| opt_array_bounds '[' Iconst ']'
					{ $$ = append($1, makeInteger($3)) }
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
				{
					t := as[*TypeName]($1)
					t.Typmods = $2
					$$ = t
				}
			| ConstInterval '(' Iconst ')'
				{
					t := as[*TypeName]($1)
					t.Typmods = []Node{makeIntConst(intervalFullRange, -1),
						makeIntConst($3, @3)}
					$$ = t
				}
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
				{
					t := makeTypeName($1)
					t.Typmods = $2
					t.Location = @1
					$$ = t
				}
			| type_function_name attrs opt_type_modifiers
				{
					t := makeTypeNameFromNameList(append([]Node{makeString($1, @1)}, $2...))
					t.Typmods = $3
					t.Location = @1
					$$ = t
				}
		;

opt_type_modifiers: '(' expr_list ')'				{ $$ = $2 }
					| /* EMPTY */					{ $$ = nil }
		;

/*
 * SQL numeric data types
 */
Numeric:	INT_P
				{
					t := systemTypeName("int4")
					t.Location = @1
					$$ = t
				}
			| INTEGER
				{
					t := systemTypeName("int4")
					t.Location = @1
					$$ = t
				}
			| SMALLINT
				{
					t := systemTypeName("int2")
					t.Location = @1
					$$ = t
				}
			| BIGINT
				{
					t := systemTypeName("int8")
					t.Location = @1
					$$ = t
				}
			| REAL
				{
					t := systemTypeName("float4")
					t.Location = @1
					$$ = t
				}
			| FLOAT_P opt_float
				{
					t := as[*TypeName]($2)
					t.Location = @1
					$$ = t
				}
			| DOUBLE_P PRECISION
				{
					t := systemTypeName("float8")
					t.Location = @1
					$$ = t
				}
			| DECIMAL_P opt_type_modifiers
				{
					t := systemTypeName("numeric")
					t.Typmods = $2
					t.Location = @1
					$$ = t
				}
			| DEC opt_type_modifiers
				{
					t := systemTypeName("numeric")
					t.Typmods = $2
					t.Location = @1
					$$ = t
				}
			| NUMERIC opt_type_modifiers
				{
					t := systemTypeName("numeric")
					t.Typmods = $2
					t.Location = @1
					$$ = t
				}
			| BOOLEAN_P
				{
					t := systemTypeName("bool")
					t.Location = @1
					$$ = t
				}
		;

opt_float:	'(' Iconst ')'
				{
					/*
					 * Check FLOAT() precision limits assuming IEEE floating
					 * types - thomas 1997-09-18
					 */
					if $2 < 1 {
						p.fail(@2, "precision for type float must be at least 1 bit")
					} else if $2 <= 24 {
						$$ = systemTypeName("float4")
					} else if $2 <= 53 {
						$$ = systemTypeName("float8")
					} else {
						p.fail(@2, "precision for type float must be less than 54 bits")
					}
				}
			| /*EMPTY*/
				{ $$ = systemTypeName("float8") }
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
				{
					t := as[*TypeName]($1)
					t.Typmods = nil
					$$ = t
				}
		;

BitWithLength:
			BIT opt_varying '(' expr_list ')'
				{
					typname := "bit"
					if $2 {
						typname = "varbit"
					}
					t := systemTypeName(typname)
					t.Typmods = $4
					t.Location = @1
					$$ = t
				}
		;

BitWithoutLength:
			BIT opt_varying
				{
					/* bit defaults to bit(1), varbit to no limit */
					var t *TypeName
					if $2 {
						t = systemTypeName("varbit")
					} else {
						t = systemTypeName("bit")
						t.Typmods = []Node{makeIntConst(1, -1)}
					}
					t.Location = @1
					$$ = t
				}
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
				{
					/* Length was not specified so allow to be unrestricted.
					 * This handles problems with fixed-length (bpchar) strings
					 * which in column definitions must default to a length
					 * of one, but should not be constrained if the length
					 * was not specified.
					 */
					t := as[*TypeName]($1)
					t.Typmods = nil
					$$ = t
				}
		;

CharacterWithLength:  character '(' Iconst ')'
				{
					t := systemTypeName($1)
					t.Typmods = []Node{makeIntConst($3, @3)}
					t.Location = @1
					$$ = t
				}
		;

CharacterWithoutLength:	 character
				{
					t := systemTypeName($1)
					/* char defaults to char(1), varchar to no limit */
					if $1 == "bpchar" {
						t.Typmods = []Node{makeIntConst(1, -1)}
					}
					t.Location = @1
					$$ = t
				}
		;

character:	CHARACTER opt_varying
										{
											if $2 {
												$$ = "varchar"
											} else {
												$$ = "bpchar"
											}
										}
			| CHAR_P opt_varying
										{
											if $2 {
												$$ = "varchar"
											} else {
												$$ = "bpchar"
											}
										}
			| VARCHAR
										{ $$ = "varchar" }
			| NATIONAL CHARACTER opt_varying
										{
											if $3 {
												$$ = "varchar"
											} else {
												$$ = "bpchar"
											}
										}
			| NATIONAL CHAR_P opt_varying
										{
											if $3 {
												$$ = "varchar"
											} else {
												$$ = "bpchar"
											}
										}
			| NCHAR opt_varying
										{
											if $2 {
												$$ = "varchar"
											} else {
												$$ = "bpchar"
											}
										}
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
				{
					var t *TypeName
					if $5 {
						t = systemTypeName("timestamptz")
					} else {
						t = systemTypeName("timestamp")
					}
					t.Typmods = []Node{makeIntConst($3, @3)}
					t.Location = @1
					$$ = t
				}
			| TIMESTAMP opt_timezone
				{
					var t *TypeName
					if $2 {
						t = systemTypeName("timestamptz")
					} else {
						t = systemTypeName("timestamp")
					}
					t.Location = @1
					$$ = t
				}
			| TIME '(' Iconst ')' opt_timezone
				{
					var t *TypeName
					if $5 {
						t = systemTypeName("timetz")
					} else {
						t = systemTypeName("time")
					}
					t.Typmods = []Node{makeIntConst($3, @3)}
					t.Location = @1
					$$ = t
				}
			| TIME opt_timezone
				{
					var t *TypeName
					if $2 {
						t = systemTypeName("timetz")
					} else {
						t = systemTypeName("time")
					}
					t.Location = @1
					$$ = t
				}
		;

ConstInterval:
			INTERVAL
				{
					t := systemTypeName("interval")
					t.Location = @1
					$$ = t
				}
		;

opt_timezone:
			WITH_LA TIME ZONE						{ $$ = true }
			| WITHOUT_LA TIME ZONE					{ $$ = false }
			| /*EMPTY*/								{ $$ = false }
		;

opt_interval:
			YEAR_P
				{ $$ = []Node{makeIntConst(intervalMask(dtYear), @1)} }
			| MONTH_P
				{ $$ = []Node{makeIntConst(intervalMask(dtMonth), @1)} }
			| DAY_P
				{ $$ = []Node{makeIntConst(intervalMask(dtDay), @1)} }
			| HOUR_P
				{ $$ = []Node{makeIntConst(intervalMask(dtHour), @1)} }
			| MINUTE_P
				{ $$ = []Node{makeIntConst(intervalMask(dtMinute), @1)} }
			| interval_second
				{ $$ = $1 }
			| YEAR_P TO MONTH_P
				{
					$$ = []Node{makeIntConst(intervalMask(dtYear)|
						intervalMask(dtMonth), @1)}
				}
			| DAY_P TO HOUR_P
				{
					$$ = []Node{makeIntConst(intervalMask(dtDay)|
						intervalMask(dtHour), @1)}
				}
			| DAY_P TO MINUTE_P
				{
					$$ = []Node{makeIntConst(intervalMask(dtDay)|
						intervalMask(dtHour)|
						intervalMask(dtMinute), @1)}
				}
			| DAY_P TO interval_second
				{
					$$ = $3
					$$[0] = makeIntConst(intervalMask(dtDay)|
						intervalMask(dtHour)|
						intervalMask(dtMinute)|
						intervalMask(dtSecond), @1)
				}
			| HOUR_P TO MINUTE_P
				{
					$$ = []Node{makeIntConst(intervalMask(dtHour)|
						intervalMask(dtMinute), @1)}
				}
			| HOUR_P TO interval_second
				{
					$$ = $3
					$$[0] = makeIntConst(intervalMask(dtHour)|
						intervalMask(dtMinute)|
						intervalMask(dtSecond), @1)
				}
			| MINUTE_P TO interval_second
				{
					$$ = $3
					$$[0] = makeIntConst(intervalMask(dtMinute)|
						intervalMask(dtSecond), @1)
				}
			| /*EMPTY*/
				{ $$ = nil }
		;

interval_second:
			SECOND_P
				{ $$ = []Node{makeIntConst(intervalMask(dtSecond), @1)} }
			| SECOND_P '(' Iconst ')'
				{
					$$ = []Node{makeIntConst(intervalMask(dtSecond), @1),
						makeIntConst($3, @3)}
				}
		;

JsonType:
			JSON
				{
					t := systemTypeName("json")
					t.Location = @1
					$$ = t
				}
		;

