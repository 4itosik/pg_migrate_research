/* gram.y lines 16112-17079 */
xml_root_version: VERSION_P a_expr
				{ $$ = $2 }
			| VERSION_P NO VALUE_P
				{ $$ = makeNullAConst(-1) }
		;

opt_xml_root_standalone: ',' STANDALONE_P YES_P
				{ $$ = makeIntConst(xmlStandaloneYes, -1) }
			| ',' STANDALONE_P NO
				{ $$ = makeIntConst(xmlStandaloneNo, -1) }
			| ',' STANDALONE_P NO VALUE_P
				{ $$ = makeIntConst(xmlStandaloneNoValue, -1) }
			| /*EMPTY*/
				{ $$ = makeIntConst(xmlStandaloneOmitted, -1) }
		;

xml_attributes: XMLATTRIBUTES '(' xml_attribute_list ')'	{ $$ = $3 }
		;

xml_attribute_list:	xml_attribute_el					{ $$ = []Node{$1} }
			| xml_attribute_list ',' xml_attribute_el	{ $$ = append($1, $3) }
		;

xml_attribute_el: a_expr AS ColLabel
				{
					n := &ResTarget{}
					n.Name = $3
					n.Indirection = nil
					n.Val = $1
					n.Location = @1
					$$ = n
				}
			| a_expr
				{
					n := &ResTarget{}
					n.Name = ""
					n.Indirection = nil
					n.Val = $1
					n.Location = @1
					$$ = n
				}
		;

document_or_content: DOCUMENT_P						{ $$ = int32(XMLOPTION_DOCUMENT) }
			| CONTENT_P								{ $$ = int32(XMLOPTION_CONTENT) }
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
				{
					n := as[*WindowDef]($3)

					n.Name = $1
					$$ = n
				}
		;

over_clause: OVER window_specification
				{ $$ = $2 }
			| OVER ColId
				{
					n := &WindowDef{}

					n.Name = $2
					n.Refname = ""
					n.PartitionClause = nil
					n.OrderClause = nil
					n.FrameOptions = frameoptionDefaults
					n.StartOffset = nil
					n.EndOffset = nil
					n.Location = @2
					$$ = n
				}
			| /*EMPTY*/
				{ $$ = nil }
		;

window_specification: '(' opt_existing_window_name opt_partition_clause
						opt_sort_clause opt_frame_clause ')'
				{
					n := &WindowDef{}

					n.Name = ""
					n.Refname = $2
					n.PartitionClause = $3
					n.OrderClause = $4
					/* copy relevant fields of opt_frame_clause */
					f := as[*WindowDef]($5)
					n.FrameOptions = f.FrameOptions
					n.StartOffset = f.StartOffset
					n.EndOffset = f.EndOffset
					n.Location = @1
					$$ = n
				}
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
				{
					n := as[*WindowDef]($2)

					n.FrameOptions |= frameoptionNondefault | frameoptionRange
					n.FrameOptions |= $3
					$$ = n
				}
			| ROWS frame_extent opt_window_exclusion_clause
				{
					n := as[*WindowDef]($2)

					n.FrameOptions |= frameoptionNondefault | frameoptionRows
					n.FrameOptions |= $3
					$$ = n
				}
			| GROUPS frame_extent opt_window_exclusion_clause
				{
					n := as[*WindowDef]($2)

					n.FrameOptions |= frameoptionNondefault | frameoptionGroups
					n.FrameOptions |= $3
					$$ = n
				}
			| /*EMPTY*/
				{
					n := &WindowDef{}

					n.FrameOptions = frameoptionDefaults
					n.StartOffset = nil
					n.EndOffset = nil
					$$ = n
				}
		;

frame_extent: frame_bound
				{
					n := as[*WindowDef]($1)

					/* reject invalid cases */
					if n.FrameOptions&frameoptionStartUnboundedFollowing != 0 {
						p.fail(@1, "frame start cannot be UNBOUNDED FOLLOWING")
					}
					if n.FrameOptions&frameoptionStartOffsetFollowing != 0 {
						p.fail(@1, "frame starting from following row cannot end with current row")
					}
					n.FrameOptions |= frameoptionEndCurrentRow
					$$ = n
				}
			| BETWEEN frame_bound AND frame_bound
				{
					n1 := as[*WindowDef]($2)
					n2 := as[*WindowDef]($4)

					/* form merged options */
					frameOptions := n1.FrameOptions
					/* shift converts START_ options to END_ options */
					frameOptions |= n2.FrameOptions << 1
					frameOptions |= frameoptionBetween
					/* reject invalid cases */
					if frameOptions&frameoptionStartUnboundedFollowing != 0 {
						p.fail(@2, "frame start cannot be UNBOUNDED FOLLOWING")
					}
					if frameOptions&frameoptionEndUnboundedPreceding != 0 {
						p.fail(@4, "frame end cannot be UNBOUNDED PRECEDING")
					}
					if (frameOptions&frameoptionStartCurrentRow != 0) &&
						(frameOptions&frameoptionEndOffsetPreceding != 0) {
						p.fail(@4, "frame starting from current row cannot have preceding rows")
					}
					if (frameOptions&frameoptionStartOffsetFollowing != 0) &&
						(frameOptions&(frameoptionEndOffsetPreceding|
							frameoptionEndCurrentRow) != 0) {
						p.fail(@4, "frame starting from following row cannot have preceding rows")
					}
					n1.FrameOptions = frameOptions
					n1.EndOffset = n2.StartOffset
					$$ = n1
				}
		;

/*
 * This is used for both frame start and frame end, with output set up on
 * the assumption it's frame start; the frame_extent productions must reject
 * invalid cases.
 */
frame_bound:
			UNBOUNDED PRECEDING
				{
					n := &WindowDef{}

					n.FrameOptions = frameoptionStartUnboundedPreceding
					n.StartOffset = nil
					n.EndOffset = nil
					$$ = n
				}
			| UNBOUNDED FOLLOWING
				{
					n := &WindowDef{}

					n.FrameOptions = frameoptionStartUnboundedFollowing
					n.StartOffset = nil
					n.EndOffset = nil
					$$ = n
				}
			| CURRENT_P ROW
				{
					n := &WindowDef{}

					n.FrameOptions = frameoptionStartCurrentRow
					n.StartOffset = nil
					n.EndOffset = nil
					$$ = n
				}
			| a_expr PRECEDING
				{
					n := &WindowDef{}

					n.FrameOptions = frameoptionStartOffsetPreceding
					n.StartOffset = $1
					n.EndOffset = nil
					$$ = n
				}
			| a_expr FOLLOWING
				{
					n := &WindowDef{}

					n.FrameOptions = frameoptionStartOffsetFollowing
					n.StartOffset = $1
					n.EndOffset = nil
					$$ = n
				}
		;

opt_window_exclusion_clause:
			EXCLUDE CURRENT_P ROW	{ $$ = frameoptionExcludeCurrentRow }
			| EXCLUDE GROUP_P		{ $$ = frameoptionExcludeGroup }
			| EXCLUDE TIES			{ $$ = frameoptionExcludeTies }
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

sub_type:	ANY										{ $$ = int32(ANY_SUBLINK) }
			| SOME									{ $$ = int32(ANY_SUBLINK) }
			| ALL									{ $$ = int32(ALL_SUBLINK) }
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
					{ $$ = []Node{makeString($1, @1)} }
			| OPERATOR '(' any_operator ')'
					{ $$ = $3 }
		;

qual_all_Op:
			all_Op
					{ $$ = []Node{makeString($1, @1)} }
			| OPERATOR '(' any_operator ')'
					{ $$ = $3 }
		;

subquery_Op:
			all_Op
					{ $$ = []Node{makeString($1, @1)} }
			| OPERATOR '(' any_operator ')'
					{ $$ = $3 }
			| LIKE
					{ $$ = []Node{makeString("~~", -1)} }
			| NOT_LA LIKE
					{ $$ = []Node{makeString("!~~", -1)} }
			| ILIKE
					{ $$ = []Node{makeString("~~*", -1)} }
			| NOT_LA ILIKE
					{ $$ = []Node{makeString("!~~*", -1)} }
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
				{
					na := &NamedArgExpr{}

					na.Name = $1
					na.Arg = $3
					na.Argnumber = -1 /* until determined */
					na.Location = @1
					$$ = na
				}
			| param_name EQUALS_GREATER a_expr
				{
					na := &NamedArgExpr{}

					na.Name = $1
					na.Arg = $3
					na.Argnumber = -1 /* until determined */
					na.Location = @1
					$$ = na
				}
		;

func_arg_list_opt:	func_arg_list					{ $$ = $1 }
			| /*EMPTY*/								{ $$ = nil }
		;

type_list:	Typename								{ $$ = []Node{$1} }
			| type_list ',' Typename				{ $$ = append($1, $3) }
		;

array_expr: '[' expr_list ']'
				{ $$ = makeAArrayExpr($2, @1) }
			| '[' array_expr_list ']'
				{ $$ = makeAArrayExpr($2, @1) }
			| '[' ']'
				{ $$ = makeAArrayExpr(nil, @1) }
		;

array_expr_list: array_expr							{ $$ = []Node{$1} }
			| array_expr_list ',' array_expr		{ $$ = append($1, $3) }
		;


extract_list:
			extract_arg FROM a_expr
				{ $$ = []Node{makeStringConst($1, @1), $3} }
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
				{
					/* overlay(A PLACING B FROM C FOR D) is converted to overlay(A, B, C, D) */
					$$ = []Node{$1, $3, $5, $7}
				}
			| a_expr PLACING a_expr FROM a_expr
				{
					/* overlay(A PLACING B FROM C) is converted to overlay(A, B, C) */
					$$ = []Node{$1, $3, $5}
				}
		;

/* position_list uses b_expr not a_expr to avoid conflict with general IN */
position_list:
			b_expr IN_P b_expr						{ $$ = []Node{$3, $1} }
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
				{ $$ = []Node{$1, $3, $5} }
			| a_expr FOR a_expr FROM a_expr
				{
					/* not legal per SQL, but might as well allow it */
					$$ = []Node{$1, $5, $3}
				}
			| a_expr FROM a_expr
				{
					/*
					 * Because we aren't restricting data types here, this
					 * syntax can end up resolving to textregexsubstr().
					 * We've historically allowed that to happen, so continue
					 * to accept it.  However, ruleutils.c will reverse-list
					 * such a call in regular function call syntax.
					 */
					$$ = []Node{$1, $3}
				}
			| a_expr FOR a_expr
				{
					/* not legal per SQL */

					/*
					 * Since there are no cases where this syntax allows
					 * a textual FOR value, we forcibly cast the argument
					 * to int4.  The possible matches in pg_proc are
					 * substring(text,int4) and substring(text,text),
					 * and we don't want the parser to choose the latter,
					 * which it is likely to do if the second argument
					 * is unknown or doesn't have an implicit cast to int4.
					 */
					$$ = []Node{$1, makeIntConst(1, -1),
						makeTypeCast($3,
							systemTypeName("int4"), -1)}
				}
			| a_expr SIMILAR a_expr ESCAPE a_expr
				{ $$ = []Node{$1, $3, $5} }
		;

trim_list:	a_expr FROM expr_list					{ $$ = append($3, $1) }
			| FROM expr_list						{ $$ = $2 }
			| expr_list								{ $$ = $1 }
		;

in_expr:	select_with_parens
				{
					n := &SubLink{}

					n.Subselect = $1
					/* other fields will be filled later */
					$$ = n
				}
			| '(' expr_list ')'						{ $$ = listNode($2) }
		;

/*
 * Define SQL-style CASE clause.
 * - Full specification
 *	CASE WHEN a = b THEN c ... ELSE d END
 * - Implicit argument
 *	CASE a WHEN b THEN c ... ELSE d END
 */
case_expr:	CASE case_arg when_clause_list case_default END_P
				{
					c := &CaseExpr{}

					c.Casetype = 0 /* not analyzed yet */
					c.Arg = $2
					c.Args = $3
					c.Defresult = $4
					c.Location = @1
					$$ = c
				}
		;

when_clause_list:
			/* There must be at least one */
			when_clause								{ $$ = []Node{$1} }
			| when_clause_list when_clause			{ $$ = append($1, $2) }
		;

when_clause:
			WHEN a_expr THEN a_expr
				{
					w := &CaseWhen{}

					w.Expr = $2
					w.Result = $4
					w.Location = @1
					$$ = w
				}
		;

case_default:
			ELSE a_expr								{ $$ = $2 }
			| /*EMPTY*/								{ $$ = nil }
		;

case_arg:	a_expr									{ $$ = $1 }
			| /*EMPTY*/								{ $$ = nil }
		;

columnref:	ColId
				{ $$ = p.makeColumnRef($1, nil, @1) }
			| ColId indirection
				{ $$ = p.makeColumnRef($1, $2, @1) }
		;

indirection_el:
			'.' attr_name
				{ $$ = makeString($2, @2) }
			| '.' '*'
				{ $$ = &A_Star{} }
			| '[' a_expr ']'
				{
					ai := &A_Indices{}

					ai.IsSlice = false
					ai.Lidx = nil
					ai.Uidx = $2
					$$ = ai
				}
			| '[' opt_slice_bound ':' opt_slice_bound ']'
				{
					ai := &A_Indices{}

					ai.IsSlice = true
					ai.Lidx = $2
					ai.Uidx = $4
					$$ = ai
				}
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
			{
				n := &JsonArgument{}

				n.Val = as[*JsonValueExpr]($1)
				n.Name = $3
				$$ = n
			}
		;

/* ARRAY is a noise word */
json_wrapper_behavior:
			  WITHOUT WRAPPER					{ $$ = int32(JSW_NONE) }
			| WITHOUT ARRAY	WRAPPER				{ $$ = int32(JSW_NONE) }
			| WITH WRAPPER						{ $$ = int32(JSW_UNCONDITIONAL) }
			| WITH ARRAY WRAPPER				{ $$ = int32(JSW_UNCONDITIONAL) }
			| WITH CONDITIONAL ARRAY WRAPPER	{ $$ = int32(JSW_CONDITIONAL) }
			| WITH UNCONDITIONAL ARRAY WRAPPER	{ $$ = int32(JSW_UNCONDITIONAL) }
			| WITH CONDITIONAL WRAPPER			{ $$ = int32(JSW_CONDITIONAL) }
			| WITH UNCONDITIONAL WRAPPER		{ $$ = int32(JSW_UNCONDITIONAL) }
			| /* empty */						{ $$ = int32(JSW_UNSPEC) }
		;

json_behavior:
			DEFAULT a_expr
				{ $$ = makeJsonBehavior(JSON_BEHAVIOR_DEFAULT, $2, @1) }
			| json_behavior_type
				{ $$ = makeJsonBehavior(JsonBehaviorType($1), nil, @1) }
		;

json_behavior_type:
			ERROR_P		{ $$ = int32(JSON_BEHAVIOR_ERROR) }
			| NULL_P	{ $$ = int32(JSON_BEHAVIOR_NULL) }
			| TRUE_P	{ $$ = int32(JSON_BEHAVIOR_TRUE) }
			| FALSE_P	{ $$ = int32(JSON_BEHAVIOR_FALSE) }
			| UNKNOWN	{ $$ = int32(JSON_BEHAVIOR_UNKNOWN) }
			| EMPTY_P ARRAY	{ $$ = int32(JSON_BEHAVIOR_EMPTY_ARRAY) }
			| EMPTY_P OBJECT_P	{ $$ = int32(JSON_BEHAVIOR_EMPTY_OBJECT) }
			/* non-standard, for Oracle compatibility only */
			| EMPTY_P	{ $$ = int32(JSON_BEHAVIOR_EMPTY_ARRAY) }
		;

json_behavior_clause_opt:
			json_behavior ON EMPTY_P
				{ $$ = []Node{$1, nil} }
			| json_behavior ON ERROR_P
				{ $$ = []Node{nil, $1} }
			| json_behavior ON EMPTY_P json_behavior ON ERROR_P
				{ $$ = []Node{$1, $4} }
			| /* EMPTY */
				{ $$ = []Node{nil, nil} }
		;

json_on_error_clause_opt:
			json_behavior ON ERROR_P
				{ $$ = $1 }
			| /* EMPTY */
				{ $$ = nil }
		;

json_value_expr:
			a_expr json_format_clause_opt
			{
				/* formatted_expr will be set during parse-analysis. */
				$$ = makeJsonValueExpr($1, nil,
					as[*JsonFormat]($2))
			}
		;

json_format_clause:
			FORMAT_LA JSON ENCODING name
				{
					var encoding JsonEncoding

					switch {
					case strings.EqualFold($4, "utf8"):
						encoding = JS_ENC_UTF8
					case strings.EqualFold($4, "utf16"):
						encoding = JS_ENC_UTF16
					case strings.EqualFold($4, "utf32"):
						encoding = JS_ENC_UTF32
					default:
						p.fail(-1, "unrecognized JSON encoding: "+$4)
					}

					$$ = makeJsonFormat(JS_FORMAT_JSON, encoding, @1)
				}
			| FORMAT_LA JSON
				{ $$ = makeJsonFormat(JS_FORMAT_JSON, JS_ENC_DEFAULT, @1) }
		;

json_format_clause_opt:
			json_format_clause
				{ $$ = $1 }
			| /* EMPTY */
				{ $$ = makeJsonFormat(JS_FORMAT_DEFAULT, JS_ENC_DEFAULT, -1) }
		;

json_quotes_clause_opt:
			KEEP QUOTES ON SCALAR STRING_P		{ $$ = int32(JS_QUOTES_KEEP) }
			| KEEP QUOTES						{ $$ = int32(JS_QUOTES_KEEP) }
			| OMIT QUOTES ON SCALAR STRING_P	{ $$ = int32(JS_QUOTES_OMIT) }
			| OMIT QUOTES						{ $$ = int32(JS_QUOTES_OMIT) }
			| /* EMPTY */						{ $$ = int32(JS_QUOTES_UNSPEC) }
		;

json_returning_clause_opt:
			RETURNING Typename json_format_clause_opt
				{
					n := &JsonOutput{}

					n.TypeName = as[*TypeName]($2)
					n.Returning = &JsonReturning{}
					n.Returning.Format = as[*JsonFormat]($3)
					$$ = n
				}
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
			JSON					%prec UNBOUNDED	{ $$ = int32(JS_TYPE_ANY) }
			| JSON VALUE_P							{ $$ = int32(JS_TYPE_ANY) }
			| JSON ARRAY							{ $$ = int32(JS_TYPE_ARRAY) }
			| JSON OBJECT_P							{ $$ = int32(JS_TYPE_OBJECT) }
			| JSON SCALAR							{ $$ = int32(JS_TYPE_SCALAR) }
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
				{ $$ = makeJsonKeyValue($1, $3) }
			|
			a_expr ':' json_value_expr
				{ $$ = makeJsonKeyValue($1, $3) }
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
				{
					n := &JsonObjectAgg{}

					n.Arg = as[*JsonKeyValue]($3)
					n.AbsentOnNull = $4
					n.Unique = $5
					n.Constructor = &JsonAggConstructor{}
					n.Constructor.Output = as[*JsonOutput]($6)
					n.Constructor.AggOrder = nil
					n.Constructor.Location = @1
					$$ = n
				}
			| JSON_ARRAYAGG '('
				json_value_expr
				json_array_aggregate_order_by_clause_opt
				json_array_constructor_null_clause_opt
				json_returning_clause_opt
			')'
				{
					n := &JsonArrayAgg{}

					n.Arg = as[*JsonValueExpr]($3)
					n.AbsentOnNull = $5
					n.Constructor = &JsonAggConstructor{}
					n.Constructor.AggOrder = $4
					n.Constructor.Output = as[*JsonOutput]($6)
					n.Constructor.Location = @1
					$$ = n
				}
		;

json_array_aggregate_order_by_clause_opt:
			ORDER BY sortby_list					{ $$ = $3 }
			| /* EMPTY */							{ $$ = nil }
		;

