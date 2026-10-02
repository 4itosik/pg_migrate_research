/* gram.y lines 16112-17079 */
xml_root_version: VERSION_P a_expr
				{ $$ = $2 }
			| VERSION_P NO VALUE_P
				{ /*C $$ = makeNullAConst(-1); */ }
		;

opt_xml_root_standalone: ',' STANDALONE_P YES_P
				{ /*C $$ = makeIntConst(XML_STANDALONE_YES, -1); */ }
			| ',' STANDALONE_P NO
				{ /*C $$ = makeIntConst(XML_STANDALONE_NO, -1); */ }
			| ',' STANDALONE_P NO VALUE_P
				{ /*C $$ = makeIntConst(XML_STANDALONE_NO_VALUE, -1); */ }
			| /*EMPTY*/
				{ /*C $$ = makeIntConst(XML_STANDALONE_OMITTED, -1); */ }
		;

xml_attributes: XMLATTRIBUTES '(' xml_attribute_list ')'	{ $$ = $3 }
		;

xml_attribute_list:	xml_attribute_el					{ $$ = []Node{$1} }
			| xml_attribute_list ',' xml_attribute_el	{ $$ = append($1, $3) }
		;

xml_attribute_el: a_expr AS ColLabel
				{ /*C
					$$ = makeNode(ResTarget);
					$$->name = $3;
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
		;

document_or_content: DOCUMENT_P						{ /*C $$ = XMLOPTION_DOCUMENT; */ }
			| CONTENT_P								{ /*C $$ = XMLOPTION_CONTENT; */ }
		;

xml_indent_option: INDENT							{ $$ = true }
			| NO INDENT								{ $$ = false }
			| /*EMPTY*/								{ $$ = false }
		;

xml_whitespace_option: PRESERVE WHITESPACE_P		{ $$ = true }
			| STRIP_P WHITESPACE_P					{ $$ = false }
			| /*EMPTY*/								{ $$ = false }
		;

/* We allow several variants for SQL and other compatibility. */
xmlexists_argument:
			PASSING c_expr
				{ $$ = $2 }
			| PASSING c_expr xml_passing_mech
				{ $$ = $2 }
			| PASSING xml_passing_mech c_expr
				{ $$ = $3 }
			| PASSING xml_passing_mech c_expr xml_passing_mech
				{ $$ = $3 }
		;

xml_passing_mech:
			BY REF_P
			| BY VALUE_P
		;


/*
 * Aggregate decoration clauses
 */
within_group_clause:
			WITHIN GROUP_P '(' sort_clause ')'		{ $$ = $4 }
			| /*EMPTY*/								{ $$ = nil }
		;

filter_clause:
			FILTER '(' WHERE a_expr ')'				{ $$ = $4 }
			| /*EMPTY*/								{ $$ = nil }
		;


/*
 * Window Definitions
 */
window_clause:
			WINDOW window_definition_list			{ $$ = $2 }
			| /*EMPTY*/								{ $$ = nil }
		;

window_definition_list:
			window_definition						{ $$ = []Node{$1} }
			| window_definition_list ',' window_definition
													{ $$ = append($1, $3) }
		;

window_definition:
			ColId AS window_specification
				{ /*C
					WindowDef  *n = $3;

					n->name = $1;
					$$ = n;
				*/ }
		;

over_clause: OVER window_specification
				{ $$ = $2 }
			| OVER ColId
				{ /*C
					WindowDef  *n = makeNode(WindowDef);

					n->name = $2;
					n->refname = NULL;
					n->partitionClause = NIL;
					n->orderClause = NIL;
					n->frameOptions = FRAMEOPTION_DEFAULTS;
					n->startOffset = NULL;
					n->endOffset = NULL;
					n->location = @2;
					$$ = n;
				*/ }
			| /*EMPTY*/
				{ $$ = nil }
		;

window_specification: '(' opt_existing_window_name opt_partition_clause
						opt_sort_clause opt_frame_clause ')'
				{ /*C
					WindowDef  *n = makeNode(WindowDef);

					n->name = NULL;
					n->refname = $2;
					n->partitionClause = $3;
					n->orderClause = $4;
					/* copy relevant fields of opt_frame_clause * /
					n->frameOptions = $5->frameOptions;
					n->startOffset = $5->startOffset;
					n->endOffset = $5->endOffset;
					n->location = @1;
					$$ = n;
				*/ }
		;

/*
 * If we see PARTITION, RANGE, ROWS or GROUPS as the first token after the '('
 * of a window_specification, we want the assumption to be that there is
 * no existing_window_name; but those keywords are unreserved and so could
 * be ColIds.  We fix this by making them have the same precedence as IDENT
 * and giving the empty production here a slightly higher precedence, so
 * that the shift/reduce conflict is resolved in favor of reducing the rule.
 * These keywords are thus precluded from being an existing_window_name but
 * are not reserved for any other purpose.
 */
opt_existing_window_name: ColId						{ $$ = $1 }
			| /*EMPTY*/				%prec Op		{ $$ = "" }
		;

opt_partition_clause: PARTITION BY expr_list		{ $$ = $3 }
			| /*EMPTY*/								{ $$ = nil }
		;

/*
 * For frame clauses, we return a WindowDef, but only some fields are used:
 * frameOptions, startOffset, and endOffset.
 */
opt_frame_clause:
			RANGE frame_extent opt_window_exclusion_clause
				{ /*C
					WindowDef  *n = $2;

					n->frameOptions |= FRAMEOPTION_NONDEFAULT | FRAMEOPTION_RANGE;
					n->frameOptions |= $3;
					$$ = n;
				*/ }
			| ROWS frame_extent opt_window_exclusion_clause
				{ /*C
					WindowDef  *n = $2;

					n->frameOptions |= FRAMEOPTION_NONDEFAULT | FRAMEOPTION_ROWS;
					n->frameOptions |= $3;
					$$ = n;
				*/ }
			| GROUPS frame_extent opt_window_exclusion_clause
				{ /*C
					WindowDef  *n = $2;

					n->frameOptions |= FRAMEOPTION_NONDEFAULT | FRAMEOPTION_GROUPS;
					n->frameOptions |= $3;
					$$ = n;
				*/ }
			| /*EMPTY*/
				{ /*C
					WindowDef  *n = makeNode(WindowDef);

					n->frameOptions = FRAMEOPTION_DEFAULTS;
					n->startOffset = NULL;
					n->endOffset = NULL;
					$$ = n;
				*/ }
		;

frame_extent: frame_bound
				{ /*C
					WindowDef  *n = $1;

					/* reject invalid cases * /
					if (n->frameOptions & FRAMEOPTION_START_UNBOUNDED_FOLLOWING)
						ereport(ERROR,
								(errcode(ERRCODE_WINDOWING_ERROR),
								 errmsg("frame start cannot be UNBOUNDED FOLLOWING"),
								 parser_errposition(@1)));
					if (n->frameOptions & FRAMEOPTION_START_OFFSET_FOLLOWING)
						ereport(ERROR,
								(errcode(ERRCODE_WINDOWING_ERROR),
								 errmsg("frame starting from following row cannot end with current row"),
								 parser_errposition(@1)));
					n->frameOptions |= FRAMEOPTION_END_CURRENT_ROW;
					$$ = n;
				*/ }
			| BETWEEN frame_bound AND frame_bound
				{ /*C
					WindowDef  *n1 = $2;
					WindowDef  *n2 = $4;

					/* form merged options * /
					int		frameOptions = n1->frameOptions;
					/* shift converts START_ options to END_ options * /
					frameOptions |= n2->frameOptions << 1;
					frameOptions |= FRAMEOPTION_BETWEEN;
					/* reject invalid cases * /
					if (frameOptions & FRAMEOPTION_START_UNBOUNDED_FOLLOWING)
						ereport(ERROR,
								(errcode(ERRCODE_WINDOWING_ERROR),
								 errmsg("frame start cannot be UNBOUNDED FOLLOWING"),
								 parser_errposition(@2)));
					if (frameOptions & FRAMEOPTION_END_UNBOUNDED_PRECEDING)
						ereport(ERROR,
								(errcode(ERRCODE_WINDOWING_ERROR),
								 errmsg("frame end cannot be UNBOUNDED PRECEDING"),
								 parser_errposition(@4)));
					if ((frameOptions & FRAMEOPTION_START_CURRENT_ROW) &&
						(frameOptions & FRAMEOPTION_END_OFFSET_PRECEDING))
						ereport(ERROR,
								(errcode(ERRCODE_WINDOWING_ERROR),
								 errmsg("frame starting from current row cannot have preceding rows"),
								 parser_errposition(@4)));
					if ((frameOptions & FRAMEOPTION_START_OFFSET_FOLLOWING) &&
						(frameOptions & (FRAMEOPTION_END_OFFSET_PRECEDING |
										 FRAMEOPTION_END_CURRENT_ROW)))
						ereport(ERROR,
								(errcode(ERRCODE_WINDOWING_ERROR),
								 errmsg("frame starting from following row cannot have preceding rows"),
								 parser_errposition(@4)));
					n1->frameOptions = frameOptions;
					n1->endOffset = n2->startOffset;
					$$ = n1;
				*/ }
		;

/*
 * This is used for both frame start and frame end, with output set up on
 * the assumption it's frame start; the frame_extent productions must reject
 * invalid cases.
 */
frame_bound:
			UNBOUNDED PRECEDING
				{ /*C
					WindowDef  *n = makeNode(WindowDef);

					n->frameOptions = FRAMEOPTION_START_UNBOUNDED_PRECEDING;
					n->startOffset = NULL;
					n->endOffset = NULL;
					$$ = n;
				*/ }
			| UNBOUNDED FOLLOWING
				{ /*C
					WindowDef  *n = makeNode(WindowDef);

					n->frameOptions = FRAMEOPTION_START_UNBOUNDED_FOLLOWING;
					n->startOffset = NULL;
					n->endOffset = NULL;
					$$ = n;
				*/ }
			| CURRENT_P ROW
				{ /*C
					WindowDef  *n = makeNode(WindowDef);

					n->frameOptions = FRAMEOPTION_START_CURRENT_ROW;
					n->startOffset = NULL;
					n->endOffset = NULL;
					$$ = n;
				*/ }
			| a_expr PRECEDING
				{ /*C
					WindowDef  *n = makeNode(WindowDef);

					n->frameOptions = FRAMEOPTION_START_OFFSET_PRECEDING;
					n->startOffset = $1;
					n->endOffset = NULL;
					$$ = n;
				*/ }
			| a_expr FOLLOWING
				{ /*C
					WindowDef  *n = makeNode(WindowDef);

					n->frameOptions = FRAMEOPTION_START_OFFSET_FOLLOWING;
					n->startOffset = $1;
					n->endOffset = NULL;
					$$ = n;
				*/ }
		;

opt_window_exclusion_clause:
			EXCLUDE CURRENT_P ROW	{ /*C $$ = FRAMEOPTION_EXCLUDE_CURRENT_ROW; */ }
			| EXCLUDE GROUP_P		{ /*C $$ = FRAMEOPTION_EXCLUDE_GROUP; */ }
			| EXCLUDE TIES			{ /*C $$ = FRAMEOPTION_EXCLUDE_TIES; */ }
			| EXCLUDE NO OTHERS		{ $$ = 0 }
			| /*EMPTY*/				{ $$ = 0 }
		;


/*
 * Supporting nonterminals for expressions.
 */

/* Explicit row production.
 *
 * SQL99 allows an optional ROW keyword, so we can now do single-element rows
 * without conflicting with the parenthesized a_expr production.  Without the
 * ROW keyword, there must be more than one a_expr inside the parens.
 */
row:		ROW '(' expr_list ')'					{ $$ = $3 }
			| ROW '(' ')'							{ $$ = nil }
			| '(' expr_list ',' a_expr ')'			{ $$ = append($2, $4) }
		;

explicit_row:	ROW '(' expr_list ')'				{ $$ = $3 }
			| ROW '(' ')'							{ $$ = nil }
		;

implicit_row:	'(' expr_list ',' a_expr ')'		{ $$ = append($2, $4) }
		;

sub_type:	ANY										{ /*C $$ = ANY_SUBLINK; */ }
			| SOME									{ /*C $$ = ANY_SUBLINK; */ }
			| ALL									{ /*C $$ = ALL_SUBLINK; */ }
		;

all_Op:		Op										{ $$ = $1 }
			| MathOp								{ $$ = $1 }
		;

MathOp:		 '+'									{ $$ = "+" }
			| '-'									{ $$ = "-" }
			| '*'									{ $$ = "*" }
			| '/'									{ $$ = "/" }
			| '%'									{ $$ = "%" }
			| '^'									{ $$ = "^" }
			| '<'									{ $$ = "<" }
			| '>'									{ $$ = ">" }
			| '='									{ $$ = "=" }
			| LESS_EQUALS							{ $$ = "<=" }
			| GREATER_EQUALS						{ $$ = ">=" }
			| NOT_EQUALS							{ $$ = "<>" }
		;

qual_Op:	Op
					{ /*C $$ = list_make1(makeString($1)); */ }
			| OPERATOR '(' any_operator ')'
					{ $$ = $3 }
		;

qual_all_Op:
			all_Op
					{ /*C $$ = list_make1(makeString($1)); */ }
			| OPERATOR '(' any_operator ')'
					{ $$ = $3 }
		;

subquery_Op:
			all_Op
					{ /*C $$ = list_make1(makeString($1)); */ }
			| OPERATOR '(' any_operator ')'
					{ $$ = $3 }
			| LIKE
					{ /*C $$ = list_make1(makeString("~~")); */ }
			| NOT_LA LIKE
					{ /*C $$ = list_make1(makeString("!~~")); */ }
			| ILIKE
					{ /*C $$ = list_make1(makeString("~~*")); */ }
			| NOT_LA ILIKE
					{ /*C $$ = list_make1(makeString("!~~*")); */ }
/* cannot put SIMILAR TO here, because SIMILAR TO is a hack.
 * the regular expression is preprocessed by a function (similar_to_escape),
 * and the ~ operator for posix regular expressions is used.
 *        x SIMILAR TO y     ->    x ~ similar_to_escape(y)
 * this transformation is made on the fly by the parser upwards.
 * however the SubLink structure which handles any/some/all stuff
 * is not ready for such a thing.
 */
			;

expr_list:	a_expr
				{ $$ = []Node{$1} }
			| expr_list ',' a_expr
				{ $$ = append($1, $3) }
		;

/* function arguments can have names */
func_arg_list:  func_arg_expr
				{ $$ = []Node{$1} }
			| func_arg_list ',' func_arg_expr
				{ $$ = append($1, $3) }
		;

func_arg_expr:  a_expr
				{ $$ = $1 }
			| param_name COLON_EQUALS a_expr
				{ /*C
					NamedArgExpr *na = makeNode(NamedArgExpr);

					na->name = $1;
					na->arg = (Expr *) $3;
					na->argnumber = -1;		/* until determined * /
					na->location = @1;
					$$ = (Node *) na;
				*/ }
			| param_name EQUALS_GREATER a_expr
				{ /*C
					NamedArgExpr *na = makeNode(NamedArgExpr);

					na->name = $1;
					na->arg = (Expr *) $3;
					na->argnumber = -1;		/* until determined * /
					na->location = @1;
					$$ = (Node *) na;
				*/ }
		;

func_arg_list_opt:	func_arg_list					{ $$ = $1 }
			| /*EMPTY*/								{ $$ = nil }
		;

type_list:	Typename								{ $$ = []Node{$1} }
			| type_list ',' Typename				{ $$ = append($1, $3) }
		;

array_expr: '[' expr_list ']'
				{ /*C
					$$ = makeAArrayExpr($2, @1);
				*/ }
			| '[' array_expr_list ']'
				{ /*C
					$$ = makeAArrayExpr($2, @1);
				*/ }
			| '[' ']'
				{ /*C
					$$ = makeAArrayExpr(NIL, @1);
				*/ }
		;

array_expr_list: array_expr							{ $$ = []Node{$1} }
			| array_expr_list ',' array_expr		{ $$ = append($1, $3) }
		;


extract_list:
			extract_arg FROM a_expr
				{ /*C
					$$ = list_make2(makeStringConst($1, @1), $3);
				*/ }
		;

/* Allow delimited string Sconst in extract_arg as an SQL extension.
 * - thomas 2001-04-12
 */
extract_arg:
			IDENT									{ $$ = $1 }
			| YEAR_P								{ $$ = "year" }
			| MONTH_P								{ $$ = "month" }
			| DAY_P									{ $$ = "day" }
			| HOUR_P								{ $$ = "hour" }
			| MINUTE_P								{ $$ = "minute" }
			| SECOND_P								{ $$ = "second" }
			| Sconst								{ $$ = $1 }
		;

unicode_normal_form:
			NFC										{ $$ = "NFC" }
			| NFD									{ $$ = "NFD" }
			| NFKC									{ $$ = "NFKC" }
			| NFKD									{ $$ = "NFKD" }
		;

/* OVERLAY() arguments */
overlay_list:
			a_expr PLACING a_expr FROM a_expr FOR a_expr
				{ /*C
					/* overlay(A PLACING B FROM C FOR D) is converted to overlay(A, B, C, D) * /
					$$ = list_make4($1, $3, $5, $7);
				*/ }
			| a_expr PLACING a_expr FROM a_expr
				{ /*C
					/* overlay(A PLACING B FROM C) is converted to overlay(A, B, C) * /
					$$ = list_make3($1, $3, $5);
				*/ }
		;

/* position_list uses b_expr not a_expr to avoid conflict with general IN */
position_list:
			b_expr IN_P b_expr						{ /*C $$ = list_make2($3, $1); */ }
		;

/*
 * SUBSTRING() arguments
 *
 * Note that SQL:1999 has both
 *     text FROM int FOR int
 * and
 *     text FROM pattern FOR escape
 *
 * In the parser we map them both to a call to the substring() function and
 * rely on type resolution to pick the right one.
 *
 * In SQL:2003, the second variant was changed to
 *     text SIMILAR pattern ESCAPE escape
 * We could in theory map that to a different function internally, but
 * since we still support the SQL:1999 version, we don't.  However,
 * ruleutils.c will reverse-list the call in the newer style.
 */
substr_list:
			a_expr FROM a_expr FOR a_expr
				{ /*C
					$$ = list_make3($1, $3, $5);
				*/ }
			| a_expr FOR a_expr FROM a_expr
				{ /*C
					/* not legal per SQL, but might as well allow it * /
					$$ = list_make3($1, $5, $3);
				*/ }
			| a_expr FROM a_expr
				{ /*C
					/*
					 * Because we aren't restricting data types here, this
					 * syntax can end up resolving to textregexsubstr().
					 * We've historically allowed that to happen, so continue
					 * to accept it.  However, ruleutils.c will reverse-list
					 * such a call in regular function call syntax.
					 * /
					$$ = list_make2($1, $3);
				*/ }
			| a_expr FOR a_expr
				{ /*C
					/* not legal per SQL * /

					/*
					 * Since there are no cases where this syntax allows
					 * a textual FOR value, we forcibly cast the argument
					 * to int4.  The possible matches in pg_proc are
					 * substring(text,int4) and substring(text,text),
					 * and we don't want the parser to choose the latter,
					 * which it is likely to do if the second argument
					 * is unknown or doesn't have an implicit cast to int4.
					 * /
					$$ = list_make3($1, makeIntConst(1, -1),
									makeTypeCast($3,
												 SystemTypeName("int4"), -1));
				*/ }
			| a_expr SIMILAR a_expr ESCAPE a_expr
				{ /*C
					$$ = list_make3($1, $3, $5);
				*/ }
		;

trim_list:	a_expr FROM expr_list					{ $$ = append($3, $1) }
			| FROM expr_list						{ $$ = $2 }
			| expr_list								{ $$ = $1 }
		;

in_expr:	select_with_parens
				{ /*C
					SubLink	   *n = makeNode(SubLink);

					n->subselect = $1;
					/* other fields will be filled later * /
					$$ = (Node *) n;
				*/ }
			| '(' expr_list ')'						{ /*C $$ = (Node *) $2; */ }
		;

/*
 * Define SQL-style CASE clause.
 * - Full specification
 *	CASE WHEN a = b THEN c ... ELSE d END
 * - Implicit argument
 *	CASE a WHEN b THEN c ... ELSE d END
 */
case_expr:	CASE case_arg when_clause_list case_default END_P
				{ /*C
					CaseExpr   *c = makeNode(CaseExpr);

					c->casetype = InvalidOid; /* not analyzed yet * /
					c->arg = (Expr *) $2;
					c->args = $3;
					c->defresult = (Expr *) $4;
					c->location = @1;
					$$ = (Node *) c;
				*/ }
		;

when_clause_list:
			/* There must be at least one */
			when_clause								{ $$ = []Node{$1} }
			| when_clause_list when_clause			{ $$ = append($1, $2) }
		;

when_clause:
			WHEN a_expr THEN a_expr
				{ /*C
					CaseWhen   *w = makeNode(CaseWhen);

					w->expr = (Expr *) $2;
					w->result = (Expr *) $4;
					w->location = @1;
					$$ = (Node *) w;
				*/ }
		;

case_default:
			ELSE a_expr								{ $$ = $2 }
			| /*EMPTY*/								{ $$ = nil }
		;

case_arg:	a_expr									{ $$ = $1 }
			| /*EMPTY*/								{ $$ = nil }
		;

columnref:	ColId
				{ /*C
					$$ = makeColumnRef($1, NIL, @1, yyscanner);
				*/ }
			| ColId indirection
				{ /*C
					$$ = makeColumnRef($1, $2, @1, yyscanner);
				*/ }
		;

indirection_el:
			'.' attr_name
				{ /*C
					$$ = (Node *) makeString($2);
				*/ }
			| '.' '*'
				{ /*C
					$$ = (Node *) makeNode(A_Star);
				*/ }
			| '[' a_expr ']'
				{ /*C
					A_Indices *ai = makeNode(A_Indices);

					ai->is_slice = false;
					ai->lidx = NULL;
					ai->uidx = $2;
					$$ = (Node *) ai;
				*/ }
			| '[' opt_slice_bound ':' opt_slice_bound ']'
				{ /*C
					A_Indices *ai = makeNode(A_Indices);

					ai->is_slice = true;
					ai->lidx = $2;
					ai->uidx = $4;
					$$ = (Node *) ai;
				*/ }
		;

opt_slice_bound:
			a_expr									{ $$ = $1 }
			| /*EMPTY*/								{ $$ = nil }
		;

indirection:
			indirection_el							{ $$ = []Node{$1} }
			| indirection indirection_el			{ $$ = append($1, $2) }
		;

opt_indirection:
			/*EMPTY*/								{ $$ = nil }
			| opt_indirection indirection_el		{ $$ = append($1, $2) }
		;

opt_asymmetric: ASYMMETRIC
			| /*EMPTY*/
		;

/* SQL/JSON support */
json_passing_clause_opt:
			PASSING json_arguments					{ $$ = $2 }
			| /*EMPTY*/								{ $$ = nil }
		;

json_arguments:
			json_argument							{ $$ = []Node{$1} }
			| json_arguments ',' json_argument		{ $$ = append($1, $3) }
		;

json_argument:
			json_value_expr AS ColLabel
			{ /*C
				JsonArgument *n = makeNode(JsonArgument);

				n->val = (JsonValueExpr *) $1;
				n->name = $3;
				$$ = (Node *) n;
			*/ }
		;

/* ARRAY is a noise word */
json_wrapper_behavior:
			  WITHOUT WRAPPER					{ /*C $$ = JSW_NONE; */ }
			| WITHOUT ARRAY	WRAPPER				{ /*C $$ = JSW_NONE; */ }
			| WITH WRAPPER						{ /*C $$ = JSW_UNCONDITIONAL; */ }
			| WITH ARRAY WRAPPER				{ /*C $$ = JSW_UNCONDITIONAL; */ }
			| WITH CONDITIONAL ARRAY WRAPPER	{ /*C $$ = JSW_CONDITIONAL; */ }
			| WITH UNCONDITIONAL ARRAY WRAPPER	{ /*C $$ = JSW_UNCONDITIONAL; */ }
			| WITH CONDITIONAL WRAPPER			{ /*C $$ = JSW_CONDITIONAL; */ }
			| WITH UNCONDITIONAL WRAPPER		{ /*C $$ = JSW_UNCONDITIONAL; */ }
			| /* empty */						{ /*C $$ = JSW_UNSPEC; */ }
		;

json_behavior:
			DEFAULT a_expr
				{ /*C $$ = (Node *) makeJsonBehavior(JSON_BEHAVIOR_DEFAULT, $2, @1); */ }
			| json_behavior_type
				{ /*C $$ = (Node *) makeJsonBehavior($1, NULL, @1); */ }
		;

json_behavior_type:
			ERROR_P		{ /*C $$ = JSON_BEHAVIOR_ERROR; */ }
			| NULL_P	{ /*C $$ = JSON_BEHAVIOR_NULL; */ }
			| TRUE_P	{ /*C $$ = JSON_BEHAVIOR_TRUE; */ }
			| FALSE_P	{ /*C $$ = JSON_BEHAVIOR_FALSE; */ }
			| UNKNOWN	{ /*C $$ = JSON_BEHAVIOR_UNKNOWN; */ }
			| EMPTY_P ARRAY	{ /*C $$ = JSON_BEHAVIOR_EMPTY_ARRAY; */ }
			| EMPTY_P OBJECT_P	{ /*C $$ = JSON_BEHAVIOR_EMPTY_OBJECT; */ }
			/* non-standard, for Oracle compatibility only */
			| EMPTY_P	{ /*C $$ = JSON_BEHAVIOR_EMPTY_ARRAY; */ }
		;

json_behavior_clause_opt:
			json_behavior ON EMPTY_P
				{ /*C $$ = list_make2($1, NULL); */ }
			| json_behavior ON ERROR_P
				{ /*C $$ = list_make2(NULL, $1); */ }
			| json_behavior ON EMPTY_P json_behavior ON ERROR_P
				{ /*C $$ = list_make2($1, $4); */ }
			| /* EMPTY */
				{ /*C $$ = list_make2(NULL, NULL); */ }
		;

json_on_error_clause_opt:
			json_behavior ON ERROR_P
				{ $$ = $1 }
			| /* EMPTY */
				{ $$ = nil }
		;

json_value_expr:
			a_expr json_format_clause_opt
			{ /*C
				/* formatted_expr will be set during parse-analysis. * /
				$$ = (Node *) makeJsonValueExpr((Expr *) $1, NULL,
												castNode(JsonFormat, $2));
			*/ }
		;

json_format_clause:
			FORMAT_LA JSON ENCODING name
				{ /*C
					int		encoding;

					if (!pg_strcasecmp($4, "utf8"))
						encoding = JS_ENC_UTF8;
					else if (!pg_strcasecmp($4, "utf16"))
						encoding = JS_ENC_UTF16;
					else if (!pg_strcasecmp($4, "utf32"))
						encoding = JS_ENC_UTF32;
					else
						ereport(ERROR,
								errcode(ERRCODE_INVALID_PARAMETER_VALUE),
								errmsg("unrecognized JSON encoding: %s", $4));

					$$ = (Node *) makeJsonFormat(JS_FORMAT_JSON, encoding, @1);
				*/ }
			| FORMAT_LA JSON
				{ /*C
					$$ = (Node *) makeJsonFormat(JS_FORMAT_JSON, JS_ENC_DEFAULT, @1);
				*/ }
		;

json_format_clause_opt:
			json_format_clause
				{ $$ = $1 }
			| /* EMPTY */
				{ /*C
					$$ = (Node *) makeJsonFormat(JS_FORMAT_DEFAULT, JS_ENC_DEFAULT, -1);
				*/ }
		;

json_quotes_clause_opt:
			KEEP QUOTES ON SCALAR STRING_P		{ /*C $$ = JS_QUOTES_KEEP; */ }
			| KEEP QUOTES						{ /*C $$ = JS_QUOTES_KEEP; */ }
			| OMIT QUOTES ON SCALAR STRING_P	{ /*C $$ = JS_QUOTES_OMIT; */ }
			| OMIT QUOTES						{ /*C $$ = JS_QUOTES_OMIT; */ }
			| /* EMPTY */						{ /*C $$ = JS_QUOTES_UNSPEC; */ }
		;

json_returning_clause_opt:
			RETURNING Typename json_format_clause_opt
				{ /*C
					JsonOutput *n = makeNode(JsonOutput);

					n->typeName = $2;
					n->returning = makeNode(JsonReturning);
					n->returning->format = (JsonFormat *) $3;
					$$ = (Node *) n;
				*/ }
			| /* EMPTY */							{ $$ = nil }
		;

/*
 * We must assign the only-JSON production a precedence less than IDENT in
 * order to favor shifting over reduction when JSON is followed by VALUE_P,
 * OBJECT_P, or SCALAR.  (ARRAY doesn't need that treatment, because it's a
 * fully reserved word.)  Because json_predicate_type_constraint is always
 * followed by json_key_uniqueness_constraint_opt, we also need the only-JSON
 * production to have precedence less than WITH and WITHOUT.  UNBOUNDED isn't
 * really related to this syntax, but it's a convenient choice because it
 * already has a precedence less than IDENT for other reasons.
 */
json_predicate_type_constraint:
			JSON					%prec UNBOUNDED	{ /*C $$ = JS_TYPE_ANY; */ }
			| JSON VALUE_P							{ /*C $$ = JS_TYPE_ANY; */ }
			| JSON ARRAY							{ /*C $$ = JS_TYPE_ARRAY; */ }
			| JSON OBJECT_P							{ /*C $$ = JS_TYPE_OBJECT; */ }
			| JSON SCALAR							{ /*C $$ = JS_TYPE_SCALAR; */ }
		;

/*
 * KEYS is a noise word here.  To avoid shift/reduce conflicts, assign the
 * KEYS-less productions a precedence less than IDENT (i.e., less than KEYS).
 * This prevents reducing them when the next token is KEYS.
 */
json_key_uniqueness_constraint_opt:
			WITH UNIQUE KEYS							{ $$ = true }
			| WITH UNIQUE				%prec UNBOUNDED	{ $$ = true }
			| WITHOUT UNIQUE KEYS						{ $$ = false }
			| WITHOUT UNIQUE			%prec UNBOUNDED	{ $$ = false }
			| /* EMPTY */ 				%prec UNBOUNDED	{ $$ = false }
		;

json_name_and_value_list:
			json_name_and_value
				{ $$ = []Node{$1} }
			| json_name_and_value_list ',' json_name_and_value
				{ $$ = append($1, $3) }
		;

json_name_and_value:
/* Supporting this syntax seems to require major surgery
			KEY c_expr VALUE_P json_value_expr
				{ $$ = makeJsonKeyValue($2, $4); }
			|
*/
			c_expr VALUE_P json_value_expr
				{ /*C $$ = makeJsonKeyValue($1, $3); */ }
			|
			a_expr ':' json_value_expr
				{ /*C $$ = makeJsonKeyValue($1, $3); */ }
		;

/* empty means false for objects, true for arrays */
json_object_constructor_null_clause_opt:
			NULL_P ON NULL_P					{ $$ = false }
			| ABSENT ON NULL_P					{ $$ = true }
			| /* EMPTY */						{ $$ = false }
		;

json_array_constructor_null_clause_opt:
			NULL_P ON NULL_P						{ $$ = false }
			| ABSENT ON NULL_P						{ $$ = true }
			| /* EMPTY */							{ $$ = true }
		;

json_value_expr_list:
			json_value_expr								{ $$ = []Node{$1} }
			| json_value_expr_list ',' json_value_expr	{ $$ = append($1, $3) }
		;

json_aggregate_func:
			JSON_OBJECTAGG '('
				json_name_and_value
				json_object_constructor_null_clause_opt
				json_key_uniqueness_constraint_opt
				json_returning_clause_opt
			')'
				{ /*C
					JsonObjectAgg *n = makeNode(JsonObjectAgg);

					n->arg = (JsonKeyValue *) $3;
					n->absent_on_null = $4;
					n->unique = $5;
					n->constructor = makeNode(JsonAggConstructor);
					n->constructor->output = (JsonOutput *) $6;
					n->constructor->agg_order = NULL;
					n->constructor->location = @1;
					$$ = (Node *) n;
				*/ }
			| JSON_ARRAYAGG '('
				json_value_expr
				json_array_aggregate_order_by_clause_opt
				json_array_constructor_null_clause_opt
				json_returning_clause_opt
			')'
				{ /*C
					JsonArrayAgg *n = makeNode(JsonArrayAgg);

					n->arg = (JsonValueExpr *) $3;
					n->absent_on_null = $5;
					n->constructor = makeNode(JsonAggConstructor);
					n->constructor->agg_order = $4;
					n->constructor->output = (JsonOutput *) $6;
					n->constructor->location = @1;
					$$ = (Node *) n;
				*/ }
		;

json_array_aggregate_order_by_clause_opt:
			ORDER BY sortby_list					{ $$ = $3 }
			| /* EMPTY */							{ $$ = nil }
		;

