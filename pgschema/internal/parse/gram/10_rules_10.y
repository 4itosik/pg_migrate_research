/* gram.y lines 14752-16111 */
/*****************************************************************************
 *
 *	expression grammar
 *
 *****************************************************************************/

/*
 * General expressions
 * This is the heart of the expression syntax.
 *
 * We have two expression types: a_expr is the unrestricted kind, and
 * b_expr is a subset that must be used in some places to avoid shift/reduce
 * conflicts.  For example, we can't do BETWEEN as "BETWEEN a_expr AND a_expr"
 * because that use of AND conflicts with AND as a boolean operator.  So,
 * b_expr is used in BETWEEN and we remove boolean keywords from b_expr.
 *
 * Note that '(' a_expr ')' is a b_expr, so an unrestricted expression can
 * always be used by surrounding it with parens.
 *
 * c_expr is all the productions that are common to a_expr and b_expr;
 * it's factored out just to eliminate redundant coding.
 *
 * Be careful of productions involving more than one terminal token.
 * By default, bison will assign such productions the precedence of their
 * last terminal, but in nearly all cases you want it to be the precedence
 * of the first terminal instead; otherwise you will not get the behavior
 * you expect!  So we use %prec annotations freely to set precedences.
 */
a_expr:		c_expr									{ $$ = $1 }
			| a_expr TYPECAST Typename
					{ $$ = makeTypeCast($1, as[*TypeName]($3), @2) }
			| a_expr COLLATE any_name
				{
					n := &CollateClause{}

					n.Arg = $1
					n.Collname = $3
					n.Location = @2
					$$ = n
				}
			| a_expr AT TIME ZONE a_expr			%prec AT
				{
					$$ = makeFuncCall(systemFuncName("timezone"),
						[]Node{$5, $1},
						COERCE_SQL_SYNTAX,
						@2)
				}
			| a_expr AT LOCAL						%prec AT
				{
					$$ = makeFuncCall(systemFuncName("timezone"),
						[]Node{$1},
						COERCE_SQL_SYNTAX,
						-1)
				}
		/*
		 * These operators must be called out explicitly in order to make use
		 * of bison's automatic operator-precedence handling.  All other
		 * operator names are handled by the generic productions using "Op",
		 * below; and all those operators will have the same precedence.
		 *
		 * If you add more explicitly-known operators, be sure to add them
		 * also to b_expr and to the MathOp list below.
		 */
			| '+' a_expr					%prec UMINUS
				{ $$ = makeSimpleA_Expr(AEXPR_OP, "+", nil, $2, @1) }
			| '-' a_expr					%prec UMINUS
				{ $$ = doNegate($2, @1) }
			| a_expr '+' a_expr
				{ $$ = makeSimpleA_Expr(AEXPR_OP, "+", $1, $3, @2) }
			| a_expr '-' a_expr
				{ $$ = makeSimpleA_Expr(AEXPR_OP, "-", $1, $3, @2) }
			| a_expr '*' a_expr
				{ $$ = makeSimpleA_Expr(AEXPR_OP, "*", $1, $3, @2) }
			| a_expr '/' a_expr
				{ $$ = makeSimpleA_Expr(AEXPR_OP, "/", $1, $3, @2) }
			| a_expr '%' a_expr
				{ $$ = makeSimpleA_Expr(AEXPR_OP, "%", $1, $3, @2) }
			| a_expr '^' a_expr
				{ $$ = makeSimpleA_Expr(AEXPR_OP, "^", $1, $3, @2) }
			| a_expr '<' a_expr
				{ $$ = makeSimpleA_Expr(AEXPR_OP, "<", $1, $3, @2) }
			| a_expr '>' a_expr
				{ $$ = makeSimpleA_Expr(AEXPR_OP, ">", $1, $3, @2) }
			| a_expr '=' a_expr
				{ $$ = makeSimpleA_Expr(AEXPR_OP, "=", $1, $3, @2) }
			| a_expr LESS_EQUALS a_expr
				{ $$ = makeSimpleA_Expr(AEXPR_OP, "<=", $1, $3, @2) }
			| a_expr GREATER_EQUALS a_expr
				{ $$ = makeSimpleA_Expr(AEXPR_OP, ">=", $1, $3, @2) }
			| a_expr NOT_EQUALS a_expr
				{ $$ = makeSimpleA_Expr(AEXPR_OP, "<>", $1, $3, @2) }

			| a_expr qual_Op a_expr				%prec Op
				{ $$ = makeA_Expr(AEXPR_OP, $2, $1, $3, @2) }
			| qual_Op a_expr					%prec Op
				{ $$ = makeA_Expr(AEXPR_OP, $1, nil, $2, @1) }

			| a_expr AND a_expr
				{ $$ = makeAndExpr($1, $3, @2) }
			| a_expr OR a_expr
				{ $$ = makeOrExpr($1, $3, @2) }
			| NOT a_expr
				{ $$ = makeNotExpr($2, @1) }
			| NOT_LA a_expr						%prec NOT
				{ $$ = makeNotExpr($2, @1) }

			| a_expr LIKE a_expr
				{ $$ = makeSimpleA_Expr(AEXPR_LIKE, "~~", $1, $3, @2) }
			| a_expr LIKE a_expr ESCAPE a_expr					%prec LIKE
				{
					n := makeFuncCall(systemFuncName("like_escape"),
						[]Node{$3, $5},
						COERCE_EXPLICIT_CALL,
						@2)
					$$ = makeSimpleA_Expr(AEXPR_LIKE, "~~", $1, n, @2)
				}
			| a_expr NOT_LA LIKE a_expr							%prec NOT_LA
				{ $$ = makeSimpleA_Expr(AEXPR_LIKE, "!~~", $1, $4, @2) }
			| a_expr NOT_LA LIKE a_expr ESCAPE a_expr			%prec NOT_LA
				{
					n := makeFuncCall(systemFuncName("like_escape"),
						[]Node{$4, $6},
						COERCE_EXPLICIT_CALL,
						@2)
					$$ = makeSimpleA_Expr(AEXPR_LIKE, "!~~", $1, n, @2)
				}
			| a_expr ILIKE a_expr
				{ $$ = makeSimpleA_Expr(AEXPR_ILIKE, "~~*", $1, $3, @2) }
			| a_expr ILIKE a_expr ESCAPE a_expr					%prec ILIKE
				{
					n := makeFuncCall(systemFuncName("like_escape"),
						[]Node{$3, $5},
						COERCE_EXPLICIT_CALL,
						@2)
					$$ = makeSimpleA_Expr(AEXPR_ILIKE, "~~*", $1, n, @2)
				}
			| a_expr NOT_LA ILIKE a_expr						%prec NOT_LA
				{ $$ = makeSimpleA_Expr(AEXPR_ILIKE, "!~~*", $1, $4, @2) }
			| a_expr NOT_LA ILIKE a_expr ESCAPE a_expr			%prec NOT_LA
				{
					n := makeFuncCall(systemFuncName("like_escape"),
						[]Node{$4, $6},
						COERCE_EXPLICIT_CALL,
						@2)
					$$ = makeSimpleA_Expr(AEXPR_ILIKE, "!~~*", $1, n, @2)
				}

			| a_expr SIMILAR TO a_expr							%prec SIMILAR
				{
					n := makeFuncCall(systemFuncName("similar_to_escape"),
						[]Node{$4},
						COERCE_EXPLICIT_CALL,
						@2)
					$$ = makeSimpleA_Expr(AEXPR_SIMILAR, "~", $1, n, @2)
				}
			| a_expr SIMILAR TO a_expr ESCAPE a_expr			%prec SIMILAR
				{
					n := makeFuncCall(systemFuncName("similar_to_escape"),
						[]Node{$4, $6},
						COERCE_EXPLICIT_CALL,
						@2)
					$$ = makeSimpleA_Expr(AEXPR_SIMILAR, "~", $1, n, @2)
				}
			| a_expr NOT_LA SIMILAR TO a_expr					%prec NOT_LA
				{
					n := makeFuncCall(systemFuncName("similar_to_escape"),
						[]Node{$5},
						COERCE_EXPLICIT_CALL,
						@2)
					$$ = makeSimpleA_Expr(AEXPR_SIMILAR, "!~", $1, n, @2)
				}
			| a_expr NOT_LA SIMILAR TO a_expr ESCAPE a_expr		%prec NOT_LA
				{
					n := makeFuncCall(systemFuncName("similar_to_escape"),
						[]Node{$5, $7},
						COERCE_EXPLICIT_CALL,
						@2)
					$$ = makeSimpleA_Expr(AEXPR_SIMILAR, "!~", $1, n, @2)
				}

			/* NullTest clause
			 * Define SQL-style Null test clause.
			 * Allow two forms described in the standard:
			 *	a IS NULL
			 *	a IS NOT NULL
			 * Allow two SQL extensions
			 *	a ISNULL
			 *	a NOTNULL
			 */
			| a_expr IS NULL_P							%prec IS
				{
					n := &NullTest{}

					n.Arg = $1
					n.Nulltesttype = IS_NULL
					n.Location = @2
					$$ = n
				}
			| a_expr ISNULL
				{
					n := &NullTest{}

					n.Arg = $1
					n.Nulltesttype = IS_NULL
					n.Location = @2
					$$ = n
				}
			| a_expr IS NOT NULL_P						%prec IS
				{
					n := &NullTest{}

					n.Arg = $1
					n.Nulltesttype = IS_NOT_NULL
					n.Location = @2
					$$ = n
				}
			| a_expr NOTNULL
				{
					n := &NullTest{}

					n.Arg = $1
					n.Nulltesttype = IS_NOT_NULL
					n.Location = @2
					$$ = n
				}
			| row OVERLAPS row
				{
					if len($1) != 2 {
						p.fail(@1, "wrong number of parameters on left side of OVERLAPS expression")
					}
					if len($3) != 2 {
						p.fail(@3, "wrong number of parameters on right side of OVERLAPS expression")
					}
					$$ = makeFuncCall(systemFuncName("overlaps"),
						append($1, $3...),
						COERCE_SQL_SYNTAX,
						@2)
				}
			| a_expr IS TRUE_P							%prec IS
				{
					b := &BooleanTest{}

					b.Arg = $1
					b.Booltesttype = IS_TRUE
					b.Location = @2
					$$ = b
				}
			| a_expr IS NOT TRUE_P						%prec IS
				{
					b := &BooleanTest{}

					b.Arg = $1
					b.Booltesttype = IS_NOT_TRUE
					b.Location = @2
					$$ = b
				}
			| a_expr IS FALSE_P							%prec IS
				{
					b := &BooleanTest{}

					b.Arg = $1
					b.Booltesttype = IS_FALSE
					b.Location = @2
					$$ = b
				}
			| a_expr IS NOT FALSE_P						%prec IS
				{
					b := &BooleanTest{}

					b.Arg = $1
					b.Booltesttype = IS_NOT_FALSE
					b.Location = @2
					$$ = b
				}
			| a_expr IS UNKNOWN							%prec IS
				{
					b := &BooleanTest{}

					b.Arg = $1
					b.Booltesttype = IS_UNKNOWN
					b.Location = @2
					$$ = b
				}
			| a_expr IS NOT UNKNOWN						%prec IS
				{
					b := &BooleanTest{}

					b.Arg = $1
					b.Booltesttype = IS_NOT_UNKNOWN
					b.Location = @2
					$$ = b
				}
			| a_expr IS DISTINCT FROM a_expr			%prec IS
				{ $$ = makeSimpleA_Expr(AEXPR_DISTINCT, "=", $1, $5, @2) }
			| a_expr IS NOT DISTINCT FROM a_expr		%prec IS
				{ $$ = makeSimpleA_Expr(AEXPR_NOT_DISTINCT, "=", $1, $6, @2) }
			| a_expr BETWEEN opt_asymmetric b_expr AND a_expr		%prec BETWEEN
				{
					$$ = makeSimpleA_Expr(AEXPR_BETWEEN,
						"BETWEEN",
						$1,
						listNode([]Node{$4, $6}),
						@2)
				}
			| a_expr NOT_LA BETWEEN opt_asymmetric b_expr AND a_expr %prec NOT_LA
				{
					$$ = makeSimpleA_Expr(AEXPR_NOT_BETWEEN,
						"NOT BETWEEN",
						$1,
						listNode([]Node{$5, $7}),
						@2)
				}
			| a_expr BETWEEN SYMMETRIC b_expr AND a_expr			%prec BETWEEN
				{
					$$ = makeSimpleA_Expr(AEXPR_BETWEEN_SYM,
						"BETWEEN SYMMETRIC",
						$1,
						listNode([]Node{$4, $6}),
						@2)
				}
			| a_expr NOT_LA BETWEEN SYMMETRIC b_expr AND a_expr		%prec NOT_LA
				{
					$$ = makeSimpleA_Expr(AEXPR_NOT_BETWEEN_SYM,
						"NOT BETWEEN SYMMETRIC",
						$1,
						listNode([]Node{$5, $7}),
						@2)
				}
			| a_expr IN_P in_expr
				{
					/* in_expr returns a SubLink or a list of a_exprs */
					if n, ok := $3.(*SubLink); ok {
						/* generate foo = ANY (subquery) */
						n.SubLinkType = ANY_SUBLINK
						n.SubLinkId = 0
						n.Testexpr = $1
						n.OperName = nil /* show it's IN not = ANY */
						n.Location = @2
						$$ = n
					} else {
						/* generate scalar IN expression */
						$$ = makeSimpleA_Expr(AEXPR_IN, "=", $1, $3, @2)
					}
				}
			| a_expr NOT_LA IN_P in_expr						%prec NOT_LA
				{
					/* in_expr returns a SubLink or a list of a_exprs */
					if n, ok := $4.(*SubLink); ok {
						/* generate NOT (foo = ANY (subquery)) */
						/* Make an = ANY node */
						n.SubLinkType = ANY_SUBLINK
						n.SubLinkId = 0
						n.Testexpr = $1
						n.OperName = nil /* show it's IN not = ANY */
						n.Location = @2
						/* Stick a NOT on top; must have same parse location */
						$$ = makeNotExpr(n, @2)
					} else {
						/* generate scalar NOT IN expression */
						$$ = makeSimpleA_Expr(AEXPR_IN, "<>", $1, $4, @2)
					}
				}
			| a_expr subquery_Op sub_type select_with_parens	%prec Op
				{
					n := &SubLink{}

					n.SubLinkType = SubLinkType($3)
					n.SubLinkId = 0
					n.Testexpr = $1
					n.OperName = $2
					n.Subselect = $4
					n.Location = @2
					$$ = n
				}
			| a_expr subquery_Op sub_type '(' a_expr ')'		%prec Op
				{
					if SubLinkType($3) == ANY_SUBLINK {
						$$ = makeA_Expr(AEXPR_OP_ANY, $2, $1, $5, @2)
					} else {
						$$ = makeA_Expr(AEXPR_OP_ALL, $2, $1, $5, @2)
					}
				}
			| UNIQUE opt_unique_null_treatment select_with_parens
				{
					/* Not sure how to get rid of the parentheses
					 * but there are lots of shift/reduce errors without them.
					 *
					 * Should be able to implement this by plopping the entire
					 * select into a node, then transforming the target expressions
					 * from whatever they are into count(*), and testing the
					 * entire result equal to one.
					 * But, will probably implement a separate node in the executor.
					 */
					p.fail(@1, "UNIQUE predicate is not yet implemented")
				}
			| a_expr IS DOCUMENT_P					%prec IS
				{ $$ = makeXmlExpr(IS_DOCUMENT, "", nil, []Node{$1}, @2) }
			| a_expr IS NOT DOCUMENT_P				%prec IS
				{ $$ = makeNotExpr(makeXmlExpr(IS_DOCUMENT, "", nil, []Node{$1}, @2), @2) }
			| a_expr IS NORMALIZED								%prec IS
				{
					$$ = makeFuncCall(systemFuncName("is_normalized"),
						[]Node{$1},
						COERCE_SQL_SYNTAX,
						@2)
				}
			| a_expr IS unicode_normal_form NORMALIZED			%prec IS
				{
					$$ = makeFuncCall(systemFuncName("is_normalized"),
						[]Node{$1, makeStringConst($3, @3)},
						COERCE_SQL_SYNTAX,
						@2)
				}
			| a_expr IS NOT NORMALIZED							%prec IS
				{
					$$ = makeNotExpr(makeFuncCall(systemFuncName("is_normalized"),
						[]Node{$1},
						COERCE_SQL_SYNTAX,
						@2),
						@2)
				}
			| a_expr IS NOT unicode_normal_form NORMALIZED		%prec IS
				{
					$$ = makeNotExpr(makeFuncCall(systemFuncName("is_normalized"),
						[]Node{$1, makeStringConst($4, @4)},
						COERCE_SQL_SYNTAX,
						@2),
						@2)
				}
			| a_expr IS json_predicate_type_constraint
					json_key_uniqueness_constraint_opt		%prec IS
				{
					format := makeJsonFormat(JS_FORMAT_DEFAULT, JS_ENC_DEFAULT, -1)

					$$ = makeJsonIsPredicate($1, format, JsonValueType($3), $4, @1)
				}
			/*
			 * Required by SQL/JSON, but there are conflicts
			| a_expr
				json_format_clause
				IS  json_predicate_type_constraint
					json_key_uniqueness_constraint_opt		%prec IS
				{
					$$ = makeJsonIsPredicate($1, $2, $4, $5, @1);
				}
			*/
			| a_expr IS NOT
					json_predicate_type_constraint
					json_key_uniqueness_constraint_opt		%prec IS
				{
					format := makeJsonFormat(JS_FORMAT_DEFAULT, JS_ENC_DEFAULT, -1)

					$$ = makeNotExpr(makeJsonIsPredicate($1, format, JsonValueType($4), $5, @1), @1)
				}
			/*
			 * Required by SQL/JSON, but there are conflicts
			| a_expr
				json_format_clause
				IS NOT
					json_predicate_type_constraint
					json_key_uniqueness_constraint_opt		%prec IS
				{
					$$ = makeNotExpr(makeJsonIsPredicate($1, $2, $5, $6, @1), @1);
				}
			*/
			| DEFAULT
				{
					/*
					 * The SQL spec only allows DEFAULT in "contextually typed
					 * expressions", but for us, it's easier to allow it in
					 * any a_expr and then throw error during parse analysis
					 * if it's in an inappropriate context.  This way also
					 * lets us say something smarter than "syntax error".
					 */
					n := &SetToDefault{}

					/* parse analysis will fill in the rest */
					n.Location = @1
					$$ = n
				}
		;

/*
 * Restricted expressions
 *
 * b_expr is a subset of the complete expression syntax defined by a_expr.
 *
 * Presently, AND, NOT, IS, and IN are the a_expr keywords that would
 * cause trouble in the places where b_expr is used.  For simplicity, we
 * just eliminate all the boolean-keyword-operator productions from b_expr.
 */
b_expr:		c_expr
				{ $$ = $1 }
			| b_expr TYPECAST Typename
				{ $$ = makeTypeCast($1, as[*TypeName]($3), @2) }
			| '+' b_expr					%prec UMINUS
				{ $$ = makeSimpleA_Expr(AEXPR_OP, "+", nil, $2, @1) }
			| '-' b_expr					%prec UMINUS
				{ $$ = doNegate($2, @1) }
			| b_expr '+' b_expr
				{ $$ = makeSimpleA_Expr(AEXPR_OP, "+", $1, $3, @2) }
			| b_expr '-' b_expr
				{ $$ = makeSimpleA_Expr(AEXPR_OP, "-", $1, $3, @2) }
			| b_expr '*' b_expr
				{ $$ = makeSimpleA_Expr(AEXPR_OP, "*", $1, $3, @2) }
			| b_expr '/' b_expr
				{ $$ = makeSimpleA_Expr(AEXPR_OP, "/", $1, $3, @2) }
			| b_expr '%' b_expr
				{ $$ = makeSimpleA_Expr(AEXPR_OP, "%", $1, $3, @2) }
			| b_expr '^' b_expr
				{ $$ = makeSimpleA_Expr(AEXPR_OP, "^", $1, $3, @2) }
			| b_expr '<' b_expr
				{ $$ = makeSimpleA_Expr(AEXPR_OP, "<", $1, $3, @2) }
			| b_expr '>' b_expr
				{ $$ = makeSimpleA_Expr(AEXPR_OP, ">", $1, $3, @2) }
			| b_expr '=' b_expr
				{ $$ = makeSimpleA_Expr(AEXPR_OP, "=", $1, $3, @2) }
			| b_expr LESS_EQUALS b_expr
				{ $$ = makeSimpleA_Expr(AEXPR_OP, "<=", $1, $3, @2) }
			| b_expr GREATER_EQUALS b_expr
				{ $$ = makeSimpleA_Expr(AEXPR_OP, ">=", $1, $3, @2) }
			| b_expr NOT_EQUALS b_expr
				{ $$ = makeSimpleA_Expr(AEXPR_OP, "<>", $1, $3, @2) }
			| b_expr qual_Op b_expr				%prec Op
				{ $$ = makeA_Expr(AEXPR_OP, $2, $1, $3, @2) }
			| qual_Op b_expr					%prec Op
				{ $$ = makeA_Expr(AEXPR_OP, $1, nil, $2, @1) }
			| b_expr IS DISTINCT FROM b_expr		%prec IS
				{ $$ = makeSimpleA_Expr(AEXPR_DISTINCT, "=", $1, $5, @2) }
			| b_expr IS NOT DISTINCT FROM b_expr	%prec IS
				{ $$ = makeSimpleA_Expr(AEXPR_NOT_DISTINCT, "=", $1, $6, @2) }
			| b_expr IS DOCUMENT_P					%prec IS
				{ $$ = makeXmlExpr(IS_DOCUMENT, "", nil, []Node{$1}, @2) }
			| b_expr IS NOT DOCUMENT_P				%prec IS
				{ $$ = makeNotExpr(makeXmlExpr(IS_DOCUMENT, "", nil, []Node{$1}, @2), @2) }
		;

/*
 * Productions that can be used in both a_expr and b_expr.
 *
 * Note: productions that refer recursively to a_expr or b_expr mostly
 * cannot appear here.	However, it's OK to refer to a_exprs that occur
 * inside parentheses, such as function arguments; that cannot introduce
 * ambiguity to the b_expr syntax.
 */
c_expr:		columnref								{ $$ = $1 }
			| AexprConst							{ $$ = $1 }
			| PARAM opt_indirection
				{
					pr := &ParamRef{}

					pr.Number = $1
					pr.Location = @1
					if len($2) > 0 {
						n := &A_Indirection{}

						n.Arg = pr
						n.Indirection = p.checkIndirection($2)
						$$ = n
					} else {
						$$ = pr
					}
				}
			| '(' a_expr ')' opt_indirection
				{
					if len($4) > 0 {
						n := &A_Indirection{}

						n.Arg = $2
						n.Indirection = p.checkIndirection($4)
						$$ = n
					} else {
						$$ = $2
					}
				}
			| case_expr
				{ $$ = $1 }
			| func_expr
				{ $$ = $1 }
			| select_with_parens			%prec UMINUS
				{
					n := &SubLink{}

					n.SubLinkType = EXPR_SUBLINK
					n.SubLinkId = 0
					n.Testexpr = nil
					n.OperName = nil
					n.Subselect = $1
					n.Location = @1
					$$ = n
				}
			| select_with_parens indirection
				{
					/*
					 * Because the select_with_parens nonterminal is designed
					 * to "eat" as many levels of parens as possible, the
					 * '(' a_expr ')' opt_indirection production above will
					 * fail to match a sub-SELECT with indirection decoration;
					 * the sub-SELECT won't be regarded as an a_expr as long
					 * as there are parens around it.  To support applying
					 * subscripting or field selection to a sub-SELECT result,
					 * we need this redundant-looking production.
					 */
					n := &SubLink{}
					a := &A_Indirection{}

					n.SubLinkType = EXPR_SUBLINK
					n.SubLinkId = 0
					n.Testexpr = nil
					n.OperName = nil
					n.Subselect = $1
					n.Location = @1
					a.Arg = n
					a.Indirection = p.checkIndirection($2)
					$$ = a
				}
			| EXISTS select_with_parens
				{
					n := &SubLink{}

					n.SubLinkType = EXISTS_SUBLINK
					n.SubLinkId = 0
					n.Testexpr = nil
					n.OperName = nil
					n.Subselect = $2
					n.Location = @1
					$$ = n
				}
			| ARRAY select_with_parens
				{
					n := &SubLink{}

					n.SubLinkType = ARRAY_SUBLINK
					n.SubLinkId = 0
					n.Testexpr = nil
					n.OperName = nil
					n.Subselect = $2
					n.Location = @1
					$$ = n
				}
			| ARRAY array_expr
				{
					/* castNode(A_ArrayExpr, $2), array_expr always makes one */
					n := as[*A_ArrayExpr]($2)

					/* point outermost A_ArrayExpr to the ARRAY keyword */
					if n != nil {
						n.Location = @1
					}
					$$ = $2
				}
			| explicit_row
				{
					r := &RowExpr{}

					r.Args = $1
					r.RowTypeid = 0 /* not analyzed yet */
					r.Colnames = nil /* to be filled in during analysis */
					r.RowFormat = COERCE_EXPLICIT_CALL /* abuse */
					r.Location = @1
					$$ = r
				}
			| implicit_row
				{
					r := &RowExpr{}

					r.Args = $1
					r.RowTypeid = 0 /* not analyzed yet */
					r.Colnames = nil /* to be filled in during analysis */
					r.RowFormat = COERCE_IMPLICIT_CAST /* abuse */
					r.Location = @1
					$$ = r
				}
			| GROUPING '(' expr_list ')'
			  {
			  	g := &GroupingFunc{}

			  	g.Args = $3
			  	g.Location = @1
			  	$$ = g
			  }
		;

func_application: func_name '(' ')'
				{ $$ = makeFuncCall($1, nil, COERCE_EXPLICIT_CALL, @1) }
			| func_name '(' func_arg_list opt_sort_clause ')'
				{
					n := makeFuncCall($1, $3,
						COERCE_EXPLICIT_CALL,
						@1)

					n.AggOrder = $4
					$$ = n
				}
			| func_name '(' VARIADIC func_arg_expr opt_sort_clause ')'
				{
					n := makeFuncCall($1, []Node{$4},
						COERCE_EXPLICIT_CALL,
						@1)

					n.FuncVariadic = true
					n.AggOrder = $5
					$$ = n
				}
			| func_name '(' func_arg_list ',' VARIADIC func_arg_expr opt_sort_clause ')'
				{
					n := makeFuncCall($1, append($3, $6),
						COERCE_EXPLICIT_CALL,
						@1)

					n.FuncVariadic = true
					n.AggOrder = $7
					$$ = n
				}
			| func_name '(' ALL func_arg_list opt_sort_clause ')'
				{
					n := makeFuncCall($1, $4,
						COERCE_EXPLICIT_CALL,
						@1)

					n.AggOrder = $5
					/* Ideally we'd mark the FuncCall node to indicate
					 * "must be an aggregate", but there's no provision
					 * for that in FuncCall at the moment.
					 */
					$$ = n
				}
			| func_name '(' DISTINCT func_arg_list opt_sort_clause ')'
				{
					n := makeFuncCall($1, $4,
						COERCE_EXPLICIT_CALL,
						@1)

					n.AggOrder = $5
					n.AggDistinct = true
					$$ = n
				}
			| func_name '(' '*' ')'
				{
					/*
					 * We consider AGGREGATE(*) to invoke a parameterless
					 * aggregate.  This does the right thing for COUNT(*),
					 * and there are no other aggregates in SQL that accept
					 * '*' as parameter.
					 *
					 * The FuncCall node is also marked agg_star = true,
					 * so that later processing can detect what the argument
					 * really was.
					 */
					n := makeFuncCall($1, nil,
						COERCE_EXPLICIT_CALL,
						@1)

					n.AggStar = true
					$$ = n
				}
		;


/*
 * func_expr and its cousin func_expr_windowless are split out from c_expr just
 * so that we have classifications for "everything that is a function call or
 * looks like one".  This isn't very important, but it saves us having to
 * document which variants are legal in places like "FROM function()" or the
 * backwards-compatible functional-index syntax for CREATE INDEX.
 * (Note that many of the special SQL functions wouldn't actually make any
 * sense as functional index entries, but we ignore that consideration here.)
 */
func_expr: func_application within_group_clause filter_clause over_clause
				{
					n := as[*FuncCall]($1)

					/*
					 * The order clause for WITHIN GROUP and the one for
					 * plain-aggregate ORDER BY share a field, so we have to
					 * check here that at most one is present.  We also check
					 * for DISTINCT and VARIADIC here to give a better error
					 * location.  Other consistency checks are deferred to
					 * parse analysis.
					 */
					if $2 != nil {
						if n.AggOrder != nil {
							p.fail(@2, "cannot use multiple ORDER BY clauses with WITHIN GROUP")
						}
						if n.AggDistinct {
							p.fail(@2, "cannot use DISTINCT with WITHIN GROUP")
						}
						if n.FuncVariadic {
							p.fail(@2, "cannot use VARIADIC with WITHIN GROUP")
						}
						n.AggOrder = $2
						n.AggWithinGroup = true
					}
					n.AggFilter = $3
					n.Over = as[*WindowDef]($4)
					$$ = n
				}
			| json_aggregate_func filter_clause over_clause
				{
					var n *JsonAggConstructor

					switch a := $1.(type) {
					case *JsonObjectAgg:
						n = a.Constructor
					case *JsonArrayAgg:
						n = a.Constructor
					}

					if n != nil {
						n.AggFilter = $2
						n.Over = as[*WindowDef]($3)
					}
					$$ = $1
				}
			| func_expr_common_subexpr
				{ $$ = $1 }
		;

/*
 * Like func_expr but does not accept WINDOW functions directly
 * (but they can still be contained in arguments for functions etc).
 * Use this when window expressions are not allowed, where needed to
 * disambiguate the grammar (e.g. in CREATE INDEX).
 */
func_expr_windowless:
			func_application						{ $$ = $1 }
			| func_expr_common_subexpr				{ $$ = $1 }
			| json_aggregate_func					{ $$ = $1 }
		;

/*
 * Special expressions that are considered to be functions.
 */
func_expr_common_subexpr:
			COLLATION FOR '(' a_expr ')'
				{
					$$ = makeFuncCall(systemFuncName("pg_collation_for"),
						[]Node{$4},
						COERCE_SQL_SYNTAX,
						@1)
				}
			| CURRENT_DATE
				{ $$ = makeSQLValueFunction(SVFOP_CURRENT_DATE, -1, @1) }
			| CURRENT_TIME
				{ $$ = makeSQLValueFunction(SVFOP_CURRENT_TIME, -1, @1) }
			| CURRENT_TIME '(' Iconst ')'
				{ $$ = makeSQLValueFunction(SVFOP_CURRENT_TIME_N, $3, @1) }
			| CURRENT_TIMESTAMP
				{ $$ = makeSQLValueFunction(SVFOP_CURRENT_TIMESTAMP, -1, @1) }
			| CURRENT_TIMESTAMP '(' Iconst ')'
				{ $$ = makeSQLValueFunction(SVFOP_CURRENT_TIMESTAMP_N, $3, @1) }
			| LOCALTIME
				{ $$ = makeSQLValueFunction(SVFOP_LOCALTIME, -1, @1) }
			| LOCALTIME '(' Iconst ')'
				{ $$ = makeSQLValueFunction(SVFOP_LOCALTIME_N, $3, @1) }
			| LOCALTIMESTAMP
				{ $$ = makeSQLValueFunction(SVFOP_LOCALTIMESTAMP, -1, @1) }
			| LOCALTIMESTAMP '(' Iconst ')'
				{ $$ = makeSQLValueFunction(SVFOP_LOCALTIMESTAMP_N, $3, @1) }
			| CURRENT_ROLE
				{ $$ = makeSQLValueFunction(SVFOP_CURRENT_ROLE, -1, @1) }
			| CURRENT_USER
				{ $$ = makeSQLValueFunction(SVFOP_CURRENT_USER, -1, @1) }
			| SESSION_USER
				{ $$ = makeSQLValueFunction(SVFOP_SESSION_USER, -1, @1) }
			| SYSTEM_USER
				{
					$$ = makeFuncCall(systemFuncName("system_user"),
						nil,
						COERCE_SQL_SYNTAX,
						@1)
				}
			| USER
				{ $$ = makeSQLValueFunction(SVFOP_USER, -1, @1) }
			| CURRENT_CATALOG
				{ $$ = makeSQLValueFunction(SVFOP_CURRENT_CATALOG, -1, @1) }
			| CURRENT_SCHEMA
				{ $$ = makeSQLValueFunction(SVFOP_CURRENT_SCHEMA, -1, @1) }
			| CAST '(' a_expr AS Typename ')'
				{ $$ = makeTypeCast($3, as[*TypeName]($5), @1) }
			| EXTRACT '(' extract_list ')'
				{
					$$ = makeFuncCall(systemFuncName("extract"),
						$3,
						COERCE_SQL_SYNTAX,
						@1)
				}
			| NORMALIZE '(' a_expr ')'
				{
					$$ = makeFuncCall(systemFuncName("normalize"),
						[]Node{$3},
						COERCE_SQL_SYNTAX,
						@1)
				}
			| NORMALIZE '(' a_expr ',' unicode_normal_form ')'
				{
					$$ = makeFuncCall(systemFuncName("normalize"),
						[]Node{$3, makeStringConst($5, @5)},
						COERCE_SQL_SYNTAX,
						@1)
				}
			| OVERLAY '(' overlay_list ')'
				{
					$$ = makeFuncCall(systemFuncName("overlay"),
						$3,
						COERCE_SQL_SYNTAX,
						@1)
				}
			| OVERLAY '(' func_arg_list_opt ')'
				{
					/*
					 * allow functions named overlay() to be called without
					 * special syntax
					 */
					$$ = makeFuncCall([]Node{makeString("overlay", -1)},
						$3,
						COERCE_EXPLICIT_CALL,
						@1)
				}
			| POSITION '(' position_list ')'
				{
					/*
					 * position(A in B) is converted to position(B, A)
					 *
					 * We deliberately don't offer a "plain syntax" option
					 * for position(), because the reversal of the arguments
					 * creates too much risk of confusion.
					 */
					$$ = makeFuncCall(systemFuncName("position"),
						$3,
						COERCE_SQL_SYNTAX,
						@1)
				}
			| SUBSTRING '(' substr_list ')'
				{
					/* substring(A from B for C) is converted to
					 * substring(A, B, C) - thomas 2000-11-28
					 */
					$$ = makeFuncCall(systemFuncName("substring"),
						$3,
						COERCE_SQL_SYNTAX,
						@1)
				}
			| SUBSTRING '(' func_arg_list_opt ')'
				{
					/*
					 * allow functions named substring() to be called without
					 * special syntax
					 */
					$$ = makeFuncCall([]Node{makeString("substring", -1)},
						$3,
						COERCE_EXPLICIT_CALL,
						@1)
				}
			| TREAT '(' a_expr AS Typename ')'
				{
					/* TREAT(expr AS target) converts expr of a particular type to target,
					 * which is defined to be a subtype of the original expression.
					 * In SQL99, this is intended for use with structured UDTs,
					 * but let's make this a generally useful form allowing stronger
					 * coercions than are handled by implicit casting.
					 *
					 * Convert SystemTypeName() to SystemFuncName() even though
					 * at the moment they result in the same thing.
					 */
					names := as[*TypeName]($5).Names

					$$ = makeFuncCall(systemFuncName(strVal(names[len(names)-1])),
						[]Node{$3},
						COERCE_EXPLICIT_CALL,
						@1)
				}
			| TRIM '(' BOTH trim_list ')'
				{
					/* various trim expressions are defined in SQL
					 * - thomas 1997-07-19
					 */
					$$ = makeFuncCall(systemFuncName("btrim"),
						$4,
						COERCE_SQL_SYNTAX,
						@1)
				}
			| TRIM '(' LEADING trim_list ')'
				{
					$$ = makeFuncCall(systemFuncName("ltrim"),
						$4,
						COERCE_SQL_SYNTAX,
						@1)
				}
			| TRIM '(' TRAILING trim_list ')'
				{
					$$ = makeFuncCall(systemFuncName("rtrim"),
						$4,
						COERCE_SQL_SYNTAX,
						@1)
				}
			| TRIM '(' trim_list ')'
				{
					$$ = makeFuncCall(systemFuncName("btrim"),
						$3,
						COERCE_SQL_SYNTAX,
						@1)
				}
			| NULLIF '(' a_expr ',' a_expr ')'
				{ $$ = makeSimpleA_Expr(AEXPR_NULLIF, "=", $3, $5, @1) }
			| COALESCE '(' expr_list ')'
				{
					c := &CoalesceExpr{}

					c.Args = $3
					c.Location = @1
					$$ = c
				}
			| GREATEST '(' expr_list ')'
				{
					v := &MinMaxExpr{}

					v.Args = $3
					v.Op = IS_GREATEST
					v.Location = @1
					$$ = v
				}
			| LEAST '(' expr_list ')'
				{
					v := &MinMaxExpr{}

					v.Args = $3
					v.Op = IS_LEAST
					v.Location = @1
					$$ = v
				}
			| XMLCONCAT '(' expr_list ')'
				{ $$ = makeXmlExpr(IS_XMLCONCAT, "", nil, $3, @1) }
			| XMLELEMENT '(' NAME_P ColLabel ')'
				{ $$ = makeXmlExpr(IS_XMLELEMENT, $4, nil, nil, @1) }
			| XMLELEMENT '(' NAME_P ColLabel ',' xml_attributes ')'
				{ $$ = makeXmlExpr(IS_XMLELEMENT, $4, $6, nil, @1) }
			| XMLELEMENT '(' NAME_P ColLabel ',' expr_list ')'
				{ $$ = makeXmlExpr(IS_XMLELEMENT, $4, nil, $6, @1) }
			| XMLELEMENT '(' NAME_P ColLabel ',' xml_attributes ',' expr_list ')'
				{ $$ = makeXmlExpr(IS_XMLELEMENT, $4, $6, $8, @1) }
			| XMLEXISTS '(' c_expr xmlexists_argument ')'
				{
					/* xmlexists(A PASSING [BY REF] B [BY REF]) is
					 * converted to xmlexists(A, B)*/
					$$ = makeFuncCall(systemFuncName("xmlexists"),
						[]Node{$3, $4},
						COERCE_SQL_SYNTAX,
						@1)
				}
			| XMLFOREST '(' xml_attribute_list ')'
				{ $$ = makeXmlExpr(IS_XMLFOREST, "", $3, nil, @1) }
			| XMLPARSE '(' document_or_content a_expr xml_whitespace_option ')'
				{
					x := as[*XmlExpr](makeXmlExpr(IS_XMLPARSE, "", nil,
						[]Node{$4, makeBoolAConst($5, -1)},
						@1))

					x.Xmloption = XmlOptionType($3)
					$$ = x
				}
			| XMLPI '(' NAME_P ColLabel ')'
				{ $$ = makeXmlExpr(IS_XMLPI, $4, nil, nil, @1) }
			| XMLPI '(' NAME_P ColLabel ',' a_expr ')'
				{ $$ = makeXmlExpr(IS_XMLPI, $4, nil, []Node{$6}, @1) }
			| XMLROOT '(' a_expr ',' xml_root_version opt_xml_root_standalone ')'
				{
					$$ = makeXmlExpr(IS_XMLROOT, "", nil,
						[]Node{$3, $5, $6}, @1)
				}
			| XMLSERIALIZE '(' document_or_content a_expr AS SimpleTypename xml_indent_option ')'
				{
					n := &XmlSerialize{}

					n.Xmloption = XmlOptionType($3)
					n.Expr = $4
					n.TypeName = as[*TypeName]($6)
					n.Indent = $7
					n.Location = @1
					$$ = n
				}
			| JSON_OBJECT '(' func_arg_list ')'
				{
					/* Support for legacy (non-standard) json_object() */
					$$ = makeFuncCall(systemFuncName("json_object"),
						$3, COERCE_EXPLICIT_CALL, @1)
				}
			| JSON_OBJECT '(' json_name_and_value_list
				json_object_constructor_null_clause_opt
				json_key_uniqueness_constraint_opt
				json_returning_clause_opt ')'
				{
					n := &JsonObjectConstructor{}

					n.Exprs = $3
					n.AbsentOnNull = $4
					n.Unique = $5
					n.Output = as[*JsonOutput]($6)
					n.Location = @1
					$$ = n
				}
			| JSON_OBJECT '(' json_returning_clause_opt ')'
				{
					n := &JsonObjectConstructor{}

					n.Exprs = nil
					n.AbsentOnNull = false
					n.Unique = false
					n.Output = as[*JsonOutput]($3)
					n.Location = @1
					$$ = n
				}
			| JSON_ARRAY '('
				json_value_expr_list
				json_array_constructor_null_clause_opt
				json_returning_clause_opt
			')'
				{
					n := &JsonArrayConstructor{}

					n.Exprs = $3
					n.AbsentOnNull = $4
					n.Output = as[*JsonOutput]($5)
					n.Location = @1
					$$ = n
				}
			| JSON_ARRAY '('
				select_no_parens
				json_format_clause_opt
				/* json_array_constructor_null_clause_opt */
				json_returning_clause_opt
			')'
				{
					n := &JsonArrayQueryConstructor{}

					n.Query = $3
					n.Format = as[*JsonFormat]($4)
					n.AbsentOnNull = true /* XXX */
					n.Output = as[*JsonOutput]($5)
					n.Location = @1
					$$ = n
				}
			| JSON_ARRAY '('
				json_returning_clause_opt
			')'
				{
					n := &JsonArrayConstructor{}

					n.Exprs = nil
					n.AbsentOnNull = true
					n.Output = as[*JsonOutput]($3)
					n.Location = @1
					$$ = n
				}
			| JSON '(' json_value_expr json_key_uniqueness_constraint_opt ')'
				{
					n := &JsonParseExpr{}

					n.Expr = as[*JsonValueExpr]($3)
					n.UniqueKeys = $4
					n.Output = nil
					n.Location = @1
					$$ = n
				}
			| JSON_SCALAR '(' a_expr ')'
				{
					n := &JsonScalarExpr{}

					n.Expr = $3
					n.Output = nil
					n.Location = @1
					$$ = n
				}
			| JSON_SERIALIZE '(' json_value_expr json_returning_clause_opt ')'
				{
					n := &JsonSerializeExpr{}

					n.Expr = as[*JsonValueExpr]($3)
					n.Output = as[*JsonOutput]($4)
					n.Location = @1
					$$ = n
				}
			| MERGE_ACTION '(' ')'
				{
					m := &MergeSupportFunc{}

					m.Msftype = TEXTOID
					m.Location = @1
					$$ = m
				}
			| JSON_QUERY '('
				json_value_expr ',' a_expr json_passing_clause_opt
				json_returning_clause_opt
				json_wrapper_behavior
				json_quotes_clause_opt
				json_behavior_clause_opt
			')'
				{
					n := &JsonFuncExpr{}

					n.Op = JSON_QUERY_OP
					n.ContextItem = as[*JsonValueExpr]($3)
					n.Pathspec = $5
					n.Passing = $6
					n.Output = as[*JsonOutput]($7)
					n.Wrapper = JsonWrapper($8)
					n.Quotes = JsonQuotes($9)
					n.OnEmpty = as[*JsonBehavior](nodeAt($10, 0))
					n.OnError = as[*JsonBehavior](nodeAt($10, 1))
					n.Location = @1
					$$ = n
				}
			| JSON_EXISTS '('
				json_value_expr ',' a_expr json_passing_clause_opt
				json_on_error_clause_opt
			')'
				{
					n := &JsonFuncExpr{}

					n.Op = JSON_EXISTS_OP
					n.ContextItem = as[*JsonValueExpr]($3)
					n.Pathspec = $5
					n.Passing = $6
					n.Output = nil
					n.OnError = as[*JsonBehavior]($7)
					n.Location = @1
					$$ = n
				}
			| JSON_VALUE '('
				json_value_expr ',' a_expr json_passing_clause_opt
				json_returning_clause_opt
				json_behavior_clause_opt
			')'
				{
					n := &JsonFuncExpr{}

					n.Op = JSON_VALUE_OP
					n.ContextItem = as[*JsonValueExpr]($3)
					n.Pathspec = $5
					n.Passing = $6
					n.Output = as[*JsonOutput]($7)
					n.OnEmpty = as[*JsonBehavior](nodeAt($8, 0))
					n.OnError = as[*JsonBehavior](nodeAt($8, 1))
					n.Location = @1
					$$ = n
				}
			;


/*
 * SQL/XML support
 */

