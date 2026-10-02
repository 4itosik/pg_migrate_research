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
					{ /*C $$ = makeTypeCast($1, $3, @2); */ }
			| a_expr COLLATE any_name
				{ /*C
					CollateClause *n = makeNode(CollateClause);

					n->arg = $1;
					n->collname = $3;
					n->location = @2;
					$$ = (Node *) n;
				*/ }
			| a_expr AT TIME ZONE a_expr			%prec AT
				{ /*C
					$$ = (Node *) makeFuncCall(SystemFuncName("timezone"),
											   list_make2($5, $1),
											   COERCE_SQL_SYNTAX,
											   @2);
				*/ }
			| a_expr AT LOCAL						%prec AT
				{ /*C
					$$ = (Node *) makeFuncCall(SystemFuncName("timezone"),
											   list_make1($1),
											   COERCE_SQL_SYNTAX,
											   -1);
				*/ }
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
				{ /*C $$ = (Node *) makeSimpleA_Expr(AEXPR_OP, "+", NULL, $2, @1); */ }
			| '-' a_expr					%prec UMINUS
				{ /*C $$ = doNegate($2, @1); */ }
			| a_expr '+' a_expr
				{ /*C $$ = (Node *) makeSimpleA_Expr(AEXPR_OP, "+", $1, $3, @2); */ }
			| a_expr '-' a_expr
				{ /*C $$ = (Node *) makeSimpleA_Expr(AEXPR_OP, "-", $1, $3, @2); */ }
			| a_expr '*' a_expr
				{ /*C $$ = (Node *) makeSimpleA_Expr(AEXPR_OP, "*", $1, $3, @2); */ }
			| a_expr '/' a_expr
				{ /*C $$ = (Node *) makeSimpleA_Expr(AEXPR_OP, "/", $1, $3, @2); */ }
			| a_expr '%' a_expr
				{ /*C $$ = (Node *) makeSimpleA_Expr(AEXPR_OP, "%", $1, $3, @2); */ }
			| a_expr '^' a_expr
				{ /*C $$ = (Node *) makeSimpleA_Expr(AEXPR_OP, "^", $1, $3, @2); */ }
			| a_expr '<' a_expr
				{ /*C $$ = (Node *) makeSimpleA_Expr(AEXPR_OP, "<", $1, $3, @2); */ }
			| a_expr '>' a_expr
				{ /*C $$ = (Node *) makeSimpleA_Expr(AEXPR_OP, ">", $1, $3, @2); */ }
			| a_expr '=' a_expr
				{ /*C $$ = (Node *) makeSimpleA_Expr(AEXPR_OP, "=", $1, $3, @2); */ }
			| a_expr LESS_EQUALS a_expr
				{ /*C $$ = (Node *) makeSimpleA_Expr(AEXPR_OP, "<=", $1, $3, @2); */ }
			| a_expr GREATER_EQUALS a_expr
				{ /*C $$ = (Node *) makeSimpleA_Expr(AEXPR_OP, ">=", $1, $3, @2); */ }
			| a_expr NOT_EQUALS a_expr
				{ /*C $$ = (Node *) makeSimpleA_Expr(AEXPR_OP, "<>", $1, $3, @2); */ }

			| a_expr qual_Op a_expr				%prec Op
				{ /*C $$ = (Node *) makeA_Expr(AEXPR_OP, $2, $1, $3, @2); */ }
			| qual_Op a_expr					%prec Op
				{ /*C $$ = (Node *) makeA_Expr(AEXPR_OP, $1, NULL, $2, @1); */ }

			| a_expr AND a_expr
				{ /*C $$ = makeAndExpr($1, $3, @2); */ }
			| a_expr OR a_expr
				{ /*C $$ = makeOrExpr($1, $3, @2); */ }
			| NOT a_expr
				{ /*C $$ = makeNotExpr($2, @1); */ }
			| NOT_LA a_expr						%prec NOT
				{ /*C $$ = makeNotExpr($2, @1); */ }

			| a_expr LIKE a_expr
				{ /*C
					$$ = (Node *) makeSimpleA_Expr(AEXPR_LIKE, "~~",
												   $1, $3, @2);
				*/ }
			| a_expr LIKE a_expr ESCAPE a_expr					%prec LIKE
				{ /*C
					FuncCall   *n = makeFuncCall(SystemFuncName("like_escape"),
												 list_make2($3, $5),
												 COERCE_EXPLICIT_CALL,
												 @2);
					$$ = (Node *) makeSimpleA_Expr(AEXPR_LIKE, "~~",
												   $1, (Node *) n, @2);
				*/ }
			| a_expr NOT_LA LIKE a_expr							%prec NOT_LA
				{ /*C
					$$ = (Node *) makeSimpleA_Expr(AEXPR_LIKE, "!~~",
												   $1, $4, @2);
				*/ }
			| a_expr NOT_LA LIKE a_expr ESCAPE a_expr			%prec NOT_LA
				{ /*C
					FuncCall   *n = makeFuncCall(SystemFuncName("like_escape"),
												 list_make2($4, $6),
												 COERCE_EXPLICIT_CALL,
												 @2);
					$$ = (Node *) makeSimpleA_Expr(AEXPR_LIKE, "!~~",
												   $1, (Node *) n, @2);
				*/ }
			| a_expr ILIKE a_expr
				{ /*C
					$$ = (Node *) makeSimpleA_Expr(AEXPR_ILIKE, "~~*",
												   $1, $3, @2);
				*/ }
			| a_expr ILIKE a_expr ESCAPE a_expr					%prec ILIKE
				{ /*C
					FuncCall   *n = makeFuncCall(SystemFuncName("like_escape"),
												 list_make2($3, $5),
												 COERCE_EXPLICIT_CALL,
												 @2);
					$$ = (Node *) makeSimpleA_Expr(AEXPR_ILIKE, "~~*",
												   $1, (Node *) n, @2);
				*/ }
			| a_expr NOT_LA ILIKE a_expr						%prec NOT_LA
				{ /*C
					$$ = (Node *) makeSimpleA_Expr(AEXPR_ILIKE, "!~~*",
												   $1, $4, @2);
				*/ }
			| a_expr NOT_LA ILIKE a_expr ESCAPE a_expr			%prec NOT_LA
				{ /*C
					FuncCall   *n = makeFuncCall(SystemFuncName("like_escape"),
												 list_make2($4, $6),
												 COERCE_EXPLICIT_CALL,
												 @2);
					$$ = (Node *) makeSimpleA_Expr(AEXPR_ILIKE, "!~~*",
												   $1, (Node *) n, @2);
				*/ }

			| a_expr SIMILAR TO a_expr							%prec SIMILAR
				{ /*C
					FuncCall   *n = makeFuncCall(SystemFuncName("similar_to_escape"),
												 list_make1($4),
												 COERCE_EXPLICIT_CALL,
												 @2);
					$$ = (Node *) makeSimpleA_Expr(AEXPR_SIMILAR, "~",
												   $1, (Node *) n, @2);
				*/ }
			| a_expr SIMILAR TO a_expr ESCAPE a_expr			%prec SIMILAR
				{ /*C
					FuncCall   *n = makeFuncCall(SystemFuncName("similar_to_escape"),
												 list_make2($4, $6),
												 COERCE_EXPLICIT_CALL,
												 @2);
					$$ = (Node *) makeSimpleA_Expr(AEXPR_SIMILAR, "~",
												   $1, (Node *) n, @2);
				*/ }
			| a_expr NOT_LA SIMILAR TO a_expr					%prec NOT_LA
				{ /*C
					FuncCall   *n = makeFuncCall(SystemFuncName("similar_to_escape"),
												 list_make1($5),
												 COERCE_EXPLICIT_CALL,
												 @2);
					$$ = (Node *) makeSimpleA_Expr(AEXPR_SIMILAR, "!~",
												   $1, (Node *) n, @2);
				*/ }
			| a_expr NOT_LA SIMILAR TO a_expr ESCAPE a_expr		%prec NOT_LA
				{ /*C
					FuncCall   *n = makeFuncCall(SystemFuncName("similar_to_escape"),
												 list_make2($5, $7),
												 COERCE_EXPLICIT_CALL,
												 @2);
					$$ = (Node *) makeSimpleA_Expr(AEXPR_SIMILAR, "!~",
												   $1, (Node *) n, @2);
				*/ }

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
				{ /*C
					NullTest   *n = makeNode(NullTest);

					n->arg = (Expr *) $1;
					n->nulltesttype = IS_NULL;
					n->location = @2;
					$$ = (Node *) n;
				*/ }
			| a_expr ISNULL
				{ /*C
					NullTest   *n = makeNode(NullTest);

					n->arg = (Expr *) $1;
					n->nulltesttype = IS_NULL;
					n->location = @2;
					$$ = (Node *) n;
				*/ }
			| a_expr IS NOT NULL_P						%prec IS
				{ /*C
					NullTest   *n = makeNode(NullTest);

					n->arg = (Expr *) $1;
					n->nulltesttype = IS_NOT_NULL;
					n->location = @2;
					$$ = (Node *) n;
				*/ }
			| a_expr NOTNULL
				{ /*C
					NullTest   *n = makeNode(NullTest);

					n->arg = (Expr *) $1;
					n->nulltesttype = IS_NOT_NULL;
					n->location = @2;
					$$ = (Node *) n;
				*/ }
			| row OVERLAPS row
				{ /*C
					if (list_length($1) != 2)
						ereport(ERROR,
								(errcode(ERRCODE_SYNTAX_ERROR),
								 errmsg("wrong number of parameters on left side of OVERLAPS expression"),
								 parser_errposition(@1)));
					if (list_length($3) != 2)
						ereport(ERROR,
								(errcode(ERRCODE_SYNTAX_ERROR),
								 errmsg("wrong number of parameters on right side of OVERLAPS expression"),
								 parser_errposition(@3)));
					$$ = (Node *) makeFuncCall(SystemFuncName("overlaps"),
											   list_concat($1, $3),
											   COERCE_SQL_SYNTAX,
											   @2);
				*/ }
			| a_expr IS TRUE_P							%prec IS
				{ /*C
					BooleanTest *b = makeNode(BooleanTest);

					b->arg = (Expr *) $1;
					b->booltesttype = IS_TRUE;
					b->location = @2;
					$$ = (Node *) b;
				*/ }
			| a_expr IS NOT TRUE_P						%prec IS
				{ /*C
					BooleanTest *b = makeNode(BooleanTest);

					b->arg = (Expr *) $1;
					b->booltesttype = IS_NOT_TRUE;
					b->location = @2;
					$$ = (Node *) b;
				*/ }
			| a_expr IS FALSE_P							%prec IS
				{ /*C
					BooleanTest *b = makeNode(BooleanTest);

					b->arg = (Expr *) $1;
					b->booltesttype = IS_FALSE;
					b->location = @2;
					$$ = (Node *) b;
				*/ }
			| a_expr IS NOT FALSE_P						%prec IS
				{ /*C
					BooleanTest *b = makeNode(BooleanTest);

					b->arg = (Expr *) $1;
					b->booltesttype = IS_NOT_FALSE;
					b->location = @2;
					$$ = (Node *) b;
				*/ }
			| a_expr IS UNKNOWN							%prec IS
				{ /*C
					BooleanTest *b = makeNode(BooleanTest);

					b->arg = (Expr *) $1;
					b->booltesttype = IS_UNKNOWN;
					b->location = @2;
					$$ = (Node *) b;
				*/ }
			| a_expr IS NOT UNKNOWN						%prec IS
				{ /*C
					BooleanTest *b = makeNode(BooleanTest);

					b->arg = (Expr *) $1;
					b->booltesttype = IS_NOT_UNKNOWN;
					b->location = @2;
					$$ = (Node *) b;
				*/ }
			| a_expr IS DISTINCT FROM a_expr			%prec IS
				{ /*C
					$$ = (Node *) makeSimpleA_Expr(AEXPR_DISTINCT, "=", $1, $5, @2);
				*/ }
			| a_expr IS NOT DISTINCT FROM a_expr		%prec IS
				{ /*C
					$$ = (Node *) makeSimpleA_Expr(AEXPR_NOT_DISTINCT, "=", $1, $6, @2);
				*/ }
			| a_expr BETWEEN opt_asymmetric b_expr AND a_expr		%prec BETWEEN
				{ /*C
					$$ = (Node *) makeSimpleA_Expr(AEXPR_BETWEEN,
												   "BETWEEN",
												   $1,
												   (Node *) list_make2($4, $6),
												   @2);
				*/ }
			| a_expr NOT_LA BETWEEN opt_asymmetric b_expr AND a_expr %prec NOT_LA
				{ /*C
					$$ = (Node *) makeSimpleA_Expr(AEXPR_NOT_BETWEEN,
												   "NOT BETWEEN",
												   $1,
												   (Node *) list_make2($5, $7),
												   @2);
				*/ }
			| a_expr BETWEEN SYMMETRIC b_expr AND a_expr			%prec BETWEEN
				{ /*C
					$$ = (Node *) makeSimpleA_Expr(AEXPR_BETWEEN_SYM,
												   "BETWEEN SYMMETRIC",
												   $1,
												   (Node *) list_make2($4, $6),
												   @2);
				*/ }
			| a_expr NOT_LA BETWEEN SYMMETRIC b_expr AND a_expr		%prec NOT_LA
				{ /*C
					$$ = (Node *) makeSimpleA_Expr(AEXPR_NOT_BETWEEN_SYM,
												   "NOT BETWEEN SYMMETRIC",
												   $1,
												   (Node *) list_make2($5, $7),
												   @2);
				*/ }
			| a_expr IN_P in_expr
				{ /*C
					/* in_expr returns a SubLink or a list of a_exprs * /
					if (IsA($3, SubLink))
					{
						/* generate foo = ANY (subquery) * /
						SubLink	   *n = (SubLink *) $3;

						n->subLinkType = ANY_SUBLINK;
						n->subLinkId = 0;
						n->testexpr = $1;
						n->operName = NIL;		/* show it's IN not = ANY * /
						n->location = @2;
						$$ = (Node *) n;
					}
					else
					{
						/* generate scalar IN expression * /
						$$ = (Node *) makeSimpleA_Expr(AEXPR_IN, "=", $1, $3, @2);
					}
				*/ }
			| a_expr NOT_LA IN_P in_expr						%prec NOT_LA
				{ /*C
					/* in_expr returns a SubLink or a list of a_exprs * /
					if (IsA($4, SubLink))
					{
						/* generate NOT (foo = ANY (subquery)) * /
						/* Make an = ANY node * /
						SubLink	   *n = (SubLink *) $4;

						n->subLinkType = ANY_SUBLINK;
						n->subLinkId = 0;
						n->testexpr = $1;
						n->operName = NIL;		/* show it's IN not = ANY * /
						n->location = @2;
						/* Stick a NOT on top; must have same parse location * /
						$$ = makeNotExpr((Node *) n, @2);
					}
					else
					{
						/* generate scalar NOT IN expression * /
						$$ = (Node *) makeSimpleA_Expr(AEXPR_IN, "<>", $1, $4, @2);
					}
				*/ }
			| a_expr subquery_Op sub_type select_with_parens	%prec Op
				{ /*C
					SubLink	   *n = makeNode(SubLink);

					n->subLinkType = $3;
					n->subLinkId = 0;
					n->testexpr = $1;
					n->operName = $2;
					n->subselect = $4;
					n->location = @2;
					$$ = (Node *) n;
				*/ }
			| a_expr subquery_Op sub_type '(' a_expr ')'		%prec Op
				{ /*C
					if ($3 == ANY_SUBLINK)
						$$ = (Node *) makeA_Expr(AEXPR_OP_ANY, $2, $1, $5, @2);
					else
						$$ = (Node *) makeA_Expr(AEXPR_OP_ALL, $2, $1, $5, @2);
				*/ }
			| UNIQUE opt_unique_null_treatment select_with_parens
				{ /*C
					/* Not sure how to get rid of the parentheses
					 * but there are lots of shift/reduce errors without them.
					 *
					 * Should be able to implement this by plopping the entire
					 * select into a node, then transforming the target expressions
					 * from whatever they are into count(*), and testing the
					 * entire result equal to one.
					 * But, will probably implement a separate node in the executor.
					 * /
					ereport(ERROR,
							(errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
							 errmsg("UNIQUE predicate is not yet implemented"),
							 parser_errposition(@1)));
				*/ }
			| a_expr IS DOCUMENT_P					%prec IS
				{ /*C
					$$ = makeXmlExpr(IS_DOCUMENT, NULL, NIL,
									 list_make1($1), @2);
				*/ }
			| a_expr IS NOT DOCUMENT_P				%prec IS
				{ /*C
					$$ = makeNotExpr(makeXmlExpr(IS_DOCUMENT, NULL, NIL,
												 list_make1($1), @2),
									 @2);
				*/ }
			| a_expr IS NORMALIZED								%prec IS
				{ /*C
					$$ = (Node *) makeFuncCall(SystemFuncName("is_normalized"),
											   list_make1($1),
											   COERCE_SQL_SYNTAX,
											   @2);
				*/ }
			| a_expr IS unicode_normal_form NORMALIZED			%prec IS
				{ /*C
					$$ = (Node *) makeFuncCall(SystemFuncName("is_normalized"),
											   list_make2($1, makeStringConst($3, @3)),
											   COERCE_SQL_SYNTAX,
											   @2);
				*/ }
			| a_expr IS NOT NORMALIZED							%prec IS
				{ /*C
					$$ = makeNotExpr((Node *) makeFuncCall(SystemFuncName("is_normalized"),
														   list_make1($1),
														   COERCE_SQL_SYNTAX,
														   @2),
									 @2);
				*/ }
			| a_expr IS NOT unicode_normal_form NORMALIZED		%prec IS
				{ /*C
					$$ = makeNotExpr((Node *) makeFuncCall(SystemFuncName("is_normalized"),
														   list_make2($1, makeStringConst($4, @4)),
														   COERCE_SQL_SYNTAX,
														   @2),
									 @2);
				*/ }
			| a_expr IS json_predicate_type_constraint
					json_key_uniqueness_constraint_opt		%prec IS
				{ /*C
					JsonFormat *format = makeJsonFormat(JS_FORMAT_DEFAULT, JS_ENC_DEFAULT, -1);

					$$ = makeJsonIsPredicate($1, format, $3, $4, @1);
				*/ }
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
				{ /*C
					JsonFormat *format = makeJsonFormat(JS_FORMAT_DEFAULT, JS_ENC_DEFAULT, -1);

					$$ = makeNotExpr(makeJsonIsPredicate($1, format, $4, $5, @1), @1);
				*/ }
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
				{ /*C
					/*
					 * The SQL spec only allows DEFAULT in "contextually typed
					 * expressions", but for us, it's easier to allow it in
					 * any a_expr and then throw error during parse analysis
					 * if it's in an inappropriate context.  This way also
					 * lets us say something smarter than "syntax error".
					 * /
					SetToDefault *n = makeNode(SetToDefault);

					/* parse analysis will fill in the rest * /
					n->location = @1;
					$$ = (Node *) n;
				*/ }
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
				{ /*C $$ = makeTypeCast($1, $3, @2); */ }
			| '+' b_expr					%prec UMINUS
				{ /*C $$ = (Node *) makeSimpleA_Expr(AEXPR_OP, "+", NULL, $2, @1); */ }
			| '-' b_expr					%prec UMINUS
				{ /*C $$ = doNegate($2, @1); */ }
			| b_expr '+' b_expr
				{ /*C $$ = (Node *) makeSimpleA_Expr(AEXPR_OP, "+", $1, $3, @2); */ }
			| b_expr '-' b_expr
				{ /*C $$ = (Node *) makeSimpleA_Expr(AEXPR_OP, "-", $1, $3, @2); */ }
			| b_expr '*' b_expr
				{ /*C $$ = (Node *) makeSimpleA_Expr(AEXPR_OP, "*", $1, $3, @2); */ }
			| b_expr '/' b_expr
				{ /*C $$ = (Node *) makeSimpleA_Expr(AEXPR_OP, "/", $1, $3, @2); */ }
			| b_expr '%' b_expr
				{ /*C $$ = (Node *) makeSimpleA_Expr(AEXPR_OP, "%", $1, $3, @2); */ }
			| b_expr '^' b_expr
				{ /*C $$ = (Node *) makeSimpleA_Expr(AEXPR_OP, "^", $1, $3, @2); */ }
			| b_expr '<' b_expr
				{ /*C $$ = (Node *) makeSimpleA_Expr(AEXPR_OP, "<", $1, $3, @2); */ }
			| b_expr '>' b_expr
				{ /*C $$ = (Node *) makeSimpleA_Expr(AEXPR_OP, ">", $1, $3, @2); */ }
			| b_expr '=' b_expr
				{ /*C $$ = (Node *) makeSimpleA_Expr(AEXPR_OP, "=", $1, $3, @2); */ }
			| b_expr LESS_EQUALS b_expr
				{ /*C $$ = (Node *) makeSimpleA_Expr(AEXPR_OP, "<=", $1, $3, @2); */ }
			| b_expr GREATER_EQUALS b_expr
				{ /*C $$ = (Node *) makeSimpleA_Expr(AEXPR_OP, ">=", $1, $3, @2); */ }
			| b_expr NOT_EQUALS b_expr
				{ /*C $$ = (Node *) makeSimpleA_Expr(AEXPR_OP, "<>", $1, $3, @2); */ }
			| b_expr qual_Op b_expr				%prec Op
				{ /*C $$ = (Node *) makeA_Expr(AEXPR_OP, $2, $1, $3, @2); */ }
			| qual_Op b_expr					%prec Op
				{ /*C $$ = (Node *) makeA_Expr(AEXPR_OP, $1, NULL, $2, @1); */ }
			| b_expr IS DISTINCT FROM b_expr		%prec IS
				{ /*C
					$$ = (Node *) makeSimpleA_Expr(AEXPR_DISTINCT, "=", $1, $5, @2);
				*/ }
			| b_expr IS NOT DISTINCT FROM b_expr	%prec IS
				{ /*C
					$$ = (Node *) makeSimpleA_Expr(AEXPR_NOT_DISTINCT, "=", $1, $6, @2);
				*/ }
			| b_expr IS DOCUMENT_P					%prec IS
				{ /*C
					$$ = makeXmlExpr(IS_DOCUMENT, NULL, NIL,
									 list_make1($1), @2);
				*/ }
			| b_expr IS NOT DOCUMENT_P				%prec IS
				{ /*C
					$$ = makeNotExpr(makeXmlExpr(IS_DOCUMENT, NULL, NIL,
												 list_make1($1), @2),
									 @2);
				*/ }
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
				{ /*C
					ParamRef   *p = makeNode(ParamRef);

					p->number = $1;
					p->location = @1;
					if ($2)
					{
						A_Indirection *n = makeNode(A_Indirection);

						n->arg = (Node *) p;
						n->indirection = check_indirection($2, yyscanner);
						$$ = (Node *) n;
					}
					else
						$$ = (Node *) p;
				*/ }
			| '(' a_expr ')' opt_indirection
				{ /*C
					if ($4)
					{
						A_Indirection *n = makeNode(A_Indirection);

						n->arg = $2;
						n->indirection = check_indirection($4, yyscanner);
						$$ = (Node *) n;
					}
					else
						$$ = $2;
				*/ }
			| case_expr
				{ $$ = $1 }
			| func_expr
				{ $$ = $1 }
			| select_with_parens			%prec UMINUS
				{ /*C
					SubLink	   *n = makeNode(SubLink);

					n->subLinkType = EXPR_SUBLINK;
					n->subLinkId = 0;
					n->testexpr = NULL;
					n->operName = NIL;
					n->subselect = $1;
					n->location = @1;
					$$ = (Node *) n;
				*/ }
			| select_with_parens indirection
				{ /*C
					/*
					 * Because the select_with_parens nonterminal is designed
					 * to "eat" as many levels of parens as possible, the
					 * '(' a_expr ')' opt_indirection production above will
					 * fail to match a sub-SELECT with indirection decoration;
					 * the sub-SELECT won't be regarded as an a_expr as long
					 * as there are parens around it.  To support applying
					 * subscripting or field selection to a sub-SELECT result,
					 * we need this redundant-looking production.
					 * /
					SubLink	   *n = makeNode(SubLink);
					A_Indirection *a = makeNode(A_Indirection);

					n->subLinkType = EXPR_SUBLINK;
					n->subLinkId = 0;
					n->testexpr = NULL;
					n->operName = NIL;
					n->subselect = $1;
					n->location = @1;
					a->arg = (Node *) n;
					a->indirection = check_indirection($2, yyscanner);
					$$ = (Node *) a;
				*/ }
			| EXISTS select_with_parens
				{ /*C
					SubLink	   *n = makeNode(SubLink);

					n->subLinkType = EXISTS_SUBLINK;
					n->subLinkId = 0;
					n->testexpr = NULL;
					n->operName = NIL;
					n->subselect = $2;
					n->location = @1;
					$$ = (Node *) n;
				*/ }
			| ARRAY select_with_parens
				{ /*C
					SubLink	   *n = makeNode(SubLink);

					n->subLinkType = ARRAY_SUBLINK;
					n->subLinkId = 0;
					n->testexpr = NULL;
					n->operName = NIL;
					n->subselect = $2;
					n->location = @1;
					$$ = (Node *) n;
				*/ }
			| ARRAY array_expr
				{ /*C
					A_ArrayExpr *n = castNode(A_ArrayExpr, $2);

					/* point outermost A_ArrayExpr to the ARRAY keyword * /
					n->location = @1;
					$$ = (Node *) n;
				*/ }
			| explicit_row
				{ /*C
					RowExpr	   *r = makeNode(RowExpr);

					r->args = $1;
					r->row_typeid = InvalidOid;	/* not analyzed yet * /
					r->colnames = NIL;	/* to be filled in during analysis * /
					r->row_format = COERCE_EXPLICIT_CALL; /* abuse * /
					r->location = @1;
					$$ = (Node *) r;
				*/ }
			| implicit_row
				{ /*C
					RowExpr	   *r = makeNode(RowExpr);

					r->args = $1;
					r->row_typeid = InvalidOid;	/* not analyzed yet * /
					r->colnames = NIL;	/* to be filled in during analysis * /
					r->row_format = COERCE_IMPLICIT_CAST; /* abuse * /
					r->location = @1;
					$$ = (Node *) r;
				*/ }
			| GROUPING '(' expr_list ')'
			  { /*C
				  GroupingFunc *g = makeNode(GroupingFunc);

				  g->args = $3;
				  g->location = @1;
				  $$ = (Node *) g;
			  */ }
		;

func_application: func_name '(' ')'
				{ /*C
					$$ = (Node *) makeFuncCall($1, NIL,
											   COERCE_EXPLICIT_CALL,
											   @1);
				*/ }
			| func_name '(' func_arg_list opt_sort_clause ')'
				{ /*C
					FuncCall   *n = makeFuncCall($1, $3,
												 COERCE_EXPLICIT_CALL,
												 @1);

					n->agg_order = $4;
					$$ = (Node *) n;
				*/ }
			| func_name '(' VARIADIC func_arg_expr opt_sort_clause ')'
				{ /*C
					FuncCall   *n = makeFuncCall($1, list_make1($4),
												 COERCE_EXPLICIT_CALL,
												 @1);

					n->func_variadic = true;
					n->agg_order = $5;
					$$ = (Node *) n;
				*/ }
			| func_name '(' func_arg_list ',' VARIADIC func_arg_expr opt_sort_clause ')'
				{ /*C
					FuncCall   *n = makeFuncCall($1, lappend($3, $6),
												 COERCE_EXPLICIT_CALL,
												 @1);

					n->func_variadic = true;
					n->agg_order = $7;
					$$ = (Node *) n;
				*/ }
			| func_name '(' ALL func_arg_list opt_sort_clause ')'
				{ /*C
					FuncCall   *n = makeFuncCall($1, $4,
												 COERCE_EXPLICIT_CALL,
												 @1);

					n->agg_order = $5;
					/* Ideally we'd mark the FuncCall node to indicate
					 * "must be an aggregate", but there's no provision
					 * for that in FuncCall at the moment.
					 * /
					$$ = (Node *) n;
				*/ }
			| func_name '(' DISTINCT func_arg_list opt_sort_clause ')'
				{ /*C
					FuncCall   *n = makeFuncCall($1, $4,
												 COERCE_EXPLICIT_CALL,
												 @1);

					n->agg_order = $5;
					n->agg_distinct = true;
					$$ = (Node *) n;
				*/ }
			| func_name '(' '*' ')'
				{ /*C
					/*
					 * We consider AGGREGATE(*) to invoke a parameterless
					 * aggregate.  This does the right thing for COUNT(*),
					 * and there are no other aggregates in SQL that accept
					 * '*' as parameter.
					 *
					 * The FuncCall node is also marked agg_star = true,
					 * so that later processing can detect what the argument
					 * really was.
					 * /
					FuncCall   *n = makeFuncCall($1, NIL,
												 COERCE_EXPLICIT_CALL,
												 @1);

					n->agg_star = true;
					$$ = (Node *) n;
				*/ }
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
				{ /*C
					FuncCall   *n = (FuncCall *) $1;

					/*
					 * The order clause for WITHIN GROUP and the one for
					 * plain-aggregate ORDER BY share a field, so we have to
					 * check here that at most one is present.  We also check
					 * for DISTINCT and VARIADIC here to give a better error
					 * location.  Other consistency checks are deferred to
					 * parse analysis.
					 * /
					if ($2 != NIL)
					{
						if (n->agg_order != NIL)
							ereport(ERROR,
									(errcode(ERRCODE_SYNTAX_ERROR),
									 errmsg("cannot use multiple ORDER BY clauses with WITHIN GROUP"),
									 parser_errposition(@2)));
						if (n->agg_distinct)
							ereport(ERROR,
									(errcode(ERRCODE_SYNTAX_ERROR),
									 errmsg("cannot use DISTINCT with WITHIN GROUP"),
									 parser_errposition(@2)));
						if (n->func_variadic)
							ereport(ERROR,
									(errcode(ERRCODE_SYNTAX_ERROR),
									 errmsg("cannot use VARIADIC with WITHIN GROUP"),
									 parser_errposition(@2)));
						n->agg_order = $2;
						n->agg_within_group = true;
					}
					n->agg_filter = $3;
					n->over = $4;
					$$ = (Node *) n;
				*/ }
			| json_aggregate_func filter_clause over_clause
				{ /*C
					JsonAggConstructor *n = IsA($1, JsonObjectAgg) ?
						((JsonObjectAgg *) $1)->constructor :
						((JsonArrayAgg *) $1)->constructor;

					n->agg_filter = $2;
					n->over = $3;
					$$ = (Node *) $1;
				*/ }
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
				{ /*C
					$$ = (Node *) makeFuncCall(SystemFuncName("pg_collation_for"),
											   list_make1($4),
											   COERCE_SQL_SYNTAX,
											   @1);
				*/ }
			| CURRENT_DATE
				{ /*C
					$$ = makeSQLValueFunction(SVFOP_CURRENT_DATE, -1, @1);
				*/ }
			| CURRENT_TIME
				{ /*C
					$$ = makeSQLValueFunction(SVFOP_CURRENT_TIME, -1, @1);
				*/ }
			| CURRENT_TIME '(' Iconst ')'
				{ /*C
					$$ = makeSQLValueFunction(SVFOP_CURRENT_TIME_N, $3, @1);
				*/ }
			| CURRENT_TIMESTAMP
				{ /*C
					$$ = makeSQLValueFunction(SVFOP_CURRENT_TIMESTAMP, -1, @1);
				*/ }
			| CURRENT_TIMESTAMP '(' Iconst ')'
				{ /*C
					$$ = makeSQLValueFunction(SVFOP_CURRENT_TIMESTAMP_N, $3, @1);
				*/ }
			| LOCALTIME
				{ /*C
					$$ = makeSQLValueFunction(SVFOP_LOCALTIME, -1, @1);
				*/ }
			| LOCALTIME '(' Iconst ')'
				{ /*C
					$$ = makeSQLValueFunction(SVFOP_LOCALTIME_N, $3, @1);
				*/ }
			| LOCALTIMESTAMP
				{ /*C
					$$ = makeSQLValueFunction(SVFOP_LOCALTIMESTAMP, -1, @1);
				*/ }
			| LOCALTIMESTAMP '(' Iconst ')'
				{ /*C
					$$ = makeSQLValueFunction(SVFOP_LOCALTIMESTAMP_N, $3, @1);
				*/ }
			| CURRENT_ROLE
				{ /*C
					$$ = makeSQLValueFunction(SVFOP_CURRENT_ROLE, -1, @1);
				*/ }
			| CURRENT_USER
				{ /*C
					$$ = makeSQLValueFunction(SVFOP_CURRENT_USER, -1, @1);
				*/ }
			| SESSION_USER
				{ /*C
					$$ = makeSQLValueFunction(SVFOP_SESSION_USER, -1, @1);
				*/ }
			| SYSTEM_USER
				{ /*C
					$$ = (Node *) makeFuncCall(SystemFuncName("system_user"),
											   NIL,
											   COERCE_SQL_SYNTAX,
											   @1);
				*/ }
			| USER
				{ /*C
					$$ = makeSQLValueFunction(SVFOP_USER, -1, @1);
				*/ }
			| CURRENT_CATALOG
				{ /*C
					$$ = makeSQLValueFunction(SVFOP_CURRENT_CATALOG, -1, @1);
				*/ }
			| CURRENT_SCHEMA
				{ /*C
					$$ = makeSQLValueFunction(SVFOP_CURRENT_SCHEMA, -1, @1);
				*/ }
			| CAST '(' a_expr AS Typename ')'
				{ /*C $$ = makeTypeCast($3, $5, @1); */ }
			| EXTRACT '(' extract_list ')'
				{ /*C
					$$ = (Node *) makeFuncCall(SystemFuncName("extract"),
											   $3,
											   COERCE_SQL_SYNTAX,
											   @1);
				*/ }
			| NORMALIZE '(' a_expr ')'
				{ /*C
					$$ = (Node *) makeFuncCall(SystemFuncName("normalize"),
											   list_make1($3),
											   COERCE_SQL_SYNTAX,
											   @1);
				*/ }
			| NORMALIZE '(' a_expr ',' unicode_normal_form ')'
				{ /*C
					$$ = (Node *) makeFuncCall(SystemFuncName("normalize"),
											   list_make2($3, makeStringConst($5, @5)),
											   COERCE_SQL_SYNTAX,
											   @1);
				*/ }
			| OVERLAY '(' overlay_list ')'
				{ /*C
					$$ = (Node *) makeFuncCall(SystemFuncName("overlay"),
											   $3,
											   COERCE_SQL_SYNTAX,
											   @1);
				*/ }
			| OVERLAY '(' func_arg_list_opt ')'
				{ /*C
					/*
					 * allow functions named overlay() to be called without
					 * special syntax
					 * /
					$$ = (Node *) makeFuncCall(list_make1(makeString("overlay")),
											   $3,
											   COERCE_EXPLICIT_CALL,
											   @1);
				*/ }
			| POSITION '(' position_list ')'
				{ /*C
					/*
					 * position(A in B) is converted to position(B, A)
					 *
					 * We deliberately don't offer a "plain syntax" option
					 * for position(), because the reversal of the arguments
					 * creates too much risk of confusion.
					 * /
					$$ = (Node *) makeFuncCall(SystemFuncName("position"),
											   $3,
											   COERCE_SQL_SYNTAX,
											   @1);
				*/ }
			| SUBSTRING '(' substr_list ')'
				{ /*C
					/* substring(A from B for C) is converted to
					 * substring(A, B, C) - thomas 2000-11-28
					 * /
					$$ = (Node *) makeFuncCall(SystemFuncName("substring"),
											   $3,
											   COERCE_SQL_SYNTAX,
											   @1);
				*/ }
			| SUBSTRING '(' func_arg_list_opt ')'
				{ /*C
					/*
					 * allow functions named substring() to be called without
					 * special syntax
					 * /
					$$ = (Node *) makeFuncCall(list_make1(makeString("substring")),
											   $3,
											   COERCE_EXPLICIT_CALL,
											   @1);
				*/ }
			| TREAT '(' a_expr AS Typename ')'
				{ /*C
					/* TREAT(expr AS target) converts expr of a particular type to target,
					 * which is defined to be a subtype of the original expression.
					 * In SQL99, this is intended for use with structured UDTs,
					 * but let's make this a generally useful form allowing stronger
					 * coercions than are handled by implicit casting.
					 *
					 * Convert SystemTypeName() to SystemFuncName() even though
					 * at the moment they result in the same thing.
					 * /
					$$ = (Node *) makeFuncCall(SystemFuncName(strVal(llast($5->names))),
											   list_make1($3),
											   COERCE_EXPLICIT_CALL,
											   @1);
				*/ }
			| TRIM '(' BOTH trim_list ')'
				{ /*C
					/* various trim expressions are defined in SQL
					 * - thomas 1997-07-19
					 * /
					$$ = (Node *) makeFuncCall(SystemFuncName("btrim"),
											   $4,
											   COERCE_SQL_SYNTAX,
											   @1);
				*/ }
			| TRIM '(' LEADING trim_list ')'
				{ /*C
					$$ = (Node *) makeFuncCall(SystemFuncName("ltrim"),
											   $4,
											   COERCE_SQL_SYNTAX,
											   @1);
				*/ }
			| TRIM '(' TRAILING trim_list ')'
				{ /*C
					$$ = (Node *) makeFuncCall(SystemFuncName("rtrim"),
											   $4,
											   COERCE_SQL_SYNTAX,
											   @1);
				*/ }
			| TRIM '(' trim_list ')'
				{ /*C
					$$ = (Node *) makeFuncCall(SystemFuncName("btrim"),
											   $3,
											   COERCE_SQL_SYNTAX,
											   @1);
				*/ }
			| NULLIF '(' a_expr ',' a_expr ')'
				{ /*C
					$$ = (Node *) makeSimpleA_Expr(AEXPR_NULLIF, "=", $3, $5, @1);
				*/ }
			| COALESCE '(' expr_list ')'
				{ /*C
					CoalesceExpr *c = makeNode(CoalesceExpr);

					c->args = $3;
					c->location = @1;
					$$ = (Node *) c;
				*/ }
			| GREATEST '(' expr_list ')'
				{ /*C
					MinMaxExpr *v = makeNode(MinMaxExpr);

					v->args = $3;
					v->op = IS_GREATEST;
					v->location = @1;
					$$ = (Node *) v;
				*/ }
			| LEAST '(' expr_list ')'
				{ /*C
					MinMaxExpr *v = makeNode(MinMaxExpr);

					v->args = $3;
					v->op = IS_LEAST;
					v->location = @1;
					$$ = (Node *) v;
				*/ }
			| XMLCONCAT '(' expr_list ')'
				{ /*C
					$$ = makeXmlExpr(IS_XMLCONCAT, NULL, NIL, $3, @1);
				*/ }
			| XMLELEMENT '(' NAME_P ColLabel ')'
				{ /*C
					$$ = makeXmlExpr(IS_XMLELEMENT, $4, NIL, NIL, @1);
				*/ }
			| XMLELEMENT '(' NAME_P ColLabel ',' xml_attributes ')'
				{ /*C
					$$ = makeXmlExpr(IS_XMLELEMENT, $4, $6, NIL, @1);
				*/ }
			| XMLELEMENT '(' NAME_P ColLabel ',' expr_list ')'
				{ /*C
					$$ = makeXmlExpr(IS_XMLELEMENT, $4, NIL, $6, @1);
				*/ }
			| XMLELEMENT '(' NAME_P ColLabel ',' xml_attributes ',' expr_list ')'
				{ /*C
					$$ = makeXmlExpr(IS_XMLELEMENT, $4, $6, $8, @1);
				*/ }
			| XMLEXISTS '(' c_expr xmlexists_argument ')'
				{ /*C
					/* xmlexists(A PASSING [BY REF] B [BY REF]) is
					 * converted to xmlexists(A, B)* /
					$$ = (Node *) makeFuncCall(SystemFuncName("xmlexists"),
											   list_make2($3, $4),
											   COERCE_SQL_SYNTAX,
											   @1);
				*/ }
			| XMLFOREST '(' xml_attribute_list ')'
				{ /*C
					$$ = makeXmlExpr(IS_XMLFOREST, NULL, $3, NIL, @1);
				*/ }
			| XMLPARSE '(' document_or_content a_expr xml_whitespace_option ')'
				{ /*C
					XmlExpr *x = (XmlExpr *)
						makeXmlExpr(IS_XMLPARSE, NULL, NIL,
									list_make2($4, makeBoolAConst($5, -1)),
									@1);

					x->xmloption = $3;
					$$ = (Node *) x;
				*/ }
			| XMLPI '(' NAME_P ColLabel ')'
				{ /*C
					$$ = makeXmlExpr(IS_XMLPI, $4, NULL, NIL, @1);
				*/ }
			| XMLPI '(' NAME_P ColLabel ',' a_expr ')'
				{ /*C
					$$ = makeXmlExpr(IS_XMLPI, $4, NULL, list_make1($6), @1);
				*/ }
			| XMLROOT '(' a_expr ',' xml_root_version opt_xml_root_standalone ')'
				{ /*C
					$$ = makeXmlExpr(IS_XMLROOT, NULL, NIL,
									 list_make3($3, $5, $6), @1);
				*/ }
			| XMLSERIALIZE '(' document_or_content a_expr AS SimpleTypename xml_indent_option ')'
				{ /*C
					XmlSerialize *n = makeNode(XmlSerialize);

					n->xmloption = $3;
					n->expr = $4;
					n->typeName = $6;
					n->indent = $7;
					n->location = @1;
					$$ = (Node *) n;
				*/ }
			| JSON_OBJECT '(' func_arg_list ')'
				{ /*C
					/* Support for legacy (non-standard) json_object() * /
					$$ = (Node *) makeFuncCall(SystemFuncName("json_object"),
											   $3, COERCE_EXPLICIT_CALL, @1);
				*/ }
			| JSON_OBJECT '(' json_name_and_value_list
				json_object_constructor_null_clause_opt
				json_key_uniqueness_constraint_opt
				json_returning_clause_opt ')'
				{ /*C
					JsonObjectConstructor *n = makeNode(JsonObjectConstructor);

					n->exprs = $3;
					n->absent_on_null = $4;
					n->unique = $5;
					n->output = (JsonOutput *) $6;
					n->location = @1;
					$$ = (Node *) n;
				*/ }
			| JSON_OBJECT '(' json_returning_clause_opt ')'
				{ /*C
					JsonObjectConstructor *n = makeNode(JsonObjectConstructor);

					n->exprs = NULL;
					n->absent_on_null = false;
					n->unique = false;
					n->output = (JsonOutput *) $3;
					n->location = @1;
					$$ = (Node *) n;
				*/ }
			| JSON_ARRAY '('
				json_value_expr_list
				json_array_constructor_null_clause_opt
				json_returning_clause_opt
			')'
				{ /*C
					JsonArrayConstructor *n = makeNode(JsonArrayConstructor);

					n->exprs = $3;
					n->absent_on_null = $4;
					n->output = (JsonOutput *) $5;
					n->location = @1;
					$$ = (Node *) n;
				*/ }
			| JSON_ARRAY '('
				select_no_parens
				json_format_clause_opt
				/* json_array_constructor_null_clause_opt */
				json_returning_clause_opt
			')'
				{ /*C
					JsonArrayQueryConstructor *n = makeNode(JsonArrayQueryConstructor);

					n->query = $3;
					n->format = (JsonFormat *) $4;
					n->absent_on_null = true;	/* XXX * /
					n->output = (JsonOutput *) $5;
					n->location = @1;
					$$ = (Node *) n;
				*/ }
			| JSON_ARRAY '('
				json_returning_clause_opt
			')'
				{ /*C
					JsonArrayConstructor *n = makeNode(JsonArrayConstructor);

					n->exprs = NIL;
					n->absent_on_null = true;
					n->output = (JsonOutput *) $3;
					n->location = @1;
					$$ = (Node *) n;
				*/ }
			| JSON '(' json_value_expr json_key_uniqueness_constraint_opt ')'
				{ /*C
					JsonParseExpr *n = makeNode(JsonParseExpr);

					n->expr = (JsonValueExpr *) $3;
					n->unique_keys = $4;
					n->output = NULL;
					n->location = @1;
					$$ = (Node *) n;
				*/ }
			| JSON_SCALAR '(' a_expr ')'
				{ /*C
					JsonScalarExpr *n = makeNode(JsonScalarExpr);

					n->expr = (Expr *) $3;
					n->output = NULL;
					n->location = @1;
					$$ = (Node *) n;
				*/ }
			| JSON_SERIALIZE '(' json_value_expr json_returning_clause_opt ')'
				{ /*C
					JsonSerializeExpr *n = makeNode(JsonSerializeExpr);

					n->expr = (JsonValueExpr *) $3;
					n->output = (JsonOutput *) $4;
					n->location = @1;
					$$ = (Node *) n;
				*/ }
			| MERGE_ACTION '(' ')'
				{ /*C
					MergeSupportFunc *m = makeNode(MergeSupportFunc);

					m->msftype = TEXTOID;
					m->location = @1;
					$$ = (Node *) m;
				*/ }
			| JSON_QUERY '('
				json_value_expr ',' a_expr json_passing_clause_opt
				json_returning_clause_opt
				json_wrapper_behavior
				json_quotes_clause_opt
				json_behavior_clause_opt
			')'
				{ /*C
					JsonFuncExpr *n = makeNode(JsonFuncExpr);

					n->op = JSON_QUERY_OP;
					n->context_item = (JsonValueExpr *) $3;
					n->pathspec = $5;
					n->passing = $6;
					n->output = (JsonOutput *) $7;
					n->wrapper = $8;
					n->quotes = $9;
					n->on_empty = (JsonBehavior *) linitial($10);
					n->on_error = (JsonBehavior *) lsecond($10);
					n->location = @1;
					$$ = (Node *) n;
				*/ }
			| JSON_EXISTS '('
				json_value_expr ',' a_expr json_passing_clause_opt
				json_on_error_clause_opt
			')'
				{ /*C
					JsonFuncExpr *n = makeNode(JsonFuncExpr);

					n->op = JSON_EXISTS_OP;
					n->context_item = (JsonValueExpr *) $3;
					n->pathspec = $5;
					n->passing = $6;
					n->output = NULL;
					n->on_error = (JsonBehavior *) $7;
					n->location = @1;
					$$ = (Node *) n;
				*/ }
			| JSON_VALUE '('
				json_value_expr ',' a_expr json_passing_clause_opt
				json_returning_clause_opt
				json_behavior_clause_opt
			')'
				{ /*C
					JsonFuncExpr *n = makeNode(JsonFuncExpr);

					n->op = JSON_VALUE_OP;
					n->context_item = (JsonValueExpr *) $3;
					n->pathspec = $5;
					n->passing = $6;
					n->output = (JsonOutput *) $7;
					n->on_empty = (JsonBehavior *) linitial($8);
					n->on_error = (JsonBehavior *) lsecond($8);
					n->location = @1;
					$$ = (Node *) n;
				*/ }
			;


/*
 * SQL/XML support
 */

