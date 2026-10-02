/* gram.y lines 12079-13424 */
/*****************************************************************************
 *
 *		QUERY:
 *				DEALLOCATE [PREPARE] <plan_name>
 *
 *****************************************************************************/

DeallocateStmt: DEALLOCATE name
					{
						n := &DeallocateStmt{}

						n.Name = $2
						n.Isall = false
						n.Location = @2
						$$ = n
					}
				| DEALLOCATE PREPARE name
					{
						n := &DeallocateStmt{}

						n.Name = $3
						n.Isall = false
						n.Location = @3
						$$ = n
					}
				| DEALLOCATE ALL
					{
						n := &DeallocateStmt{}

						n.Name = ""
						n.Isall = true
						n.Location = -1
						$$ = n
					}
				| DEALLOCATE PREPARE ALL
					{
						n := &DeallocateStmt{}

						n.Name = ""
						n.Isall = true
						n.Location = -1
						$$ = n
					}
		;

/*****************************************************************************
 *
 *		QUERY:
 *				INSERT STATEMENTS
 *
 *****************************************************************************/

InsertStmt:
			opt_with_clause INSERT INTO insert_target insert_rest
			opt_on_conflict returning_clause
				{
					n := as[*InsertStmt]($5)

					n.Relation = as[*RangeVar]($4)
					n.OnConflictClause = as[*OnConflictClause]($6)
					n.ReturningList = $7
					n.WithClause = as[*WithClause]($1)
					$$ = n
				}
		;

/*
 * Can't easily make AS optional here, because VALUES in insert_rest would
 * have a shift/reduce conflict with VALUES as an optional alias.  We could
 * easily allow unreserved_keywords as optional aliases, but that'd be an odd
 * divergence from other places.  So just require AS for now.
 */
insert_target:
			qualified_name
				{ $$ = $1 }
			| qualified_name AS ColId
				{
					r := as[*RangeVar]($1)

					r.Alias = &Alias{Aliasname: $3}
					$$ = r
				}
		;

insert_rest:
			SelectStmt
				{
					n := &InsertStmt{}
					n.Cols = nil
					n.SelectStmt = $1
					$$ = n
				}
			| OVERRIDING override_kind VALUE_P SelectStmt
				{
					n := &InsertStmt{}
					n.Cols = nil
					n.Override = OverridingKind($2)
					n.SelectStmt = $4
					$$ = n
				}
			| '(' insert_column_list ')' SelectStmt
				{
					n := &InsertStmt{}
					n.Cols = $2
					n.SelectStmt = $4
					$$ = n
				}
			| '(' insert_column_list ')' OVERRIDING override_kind VALUE_P SelectStmt
				{
					n := &InsertStmt{}
					n.Cols = $2
					n.Override = OverridingKind($5)
					n.SelectStmt = $7
					$$ = n
				}
			| DEFAULT VALUES
				{
					n := &InsertStmt{}
					n.Cols = nil
					n.SelectStmt = nil
					$$ = n
				}
		;

override_kind:
			USER		{ $$ = int32(OVERRIDING_USER_VALUE) }
			| SYSTEM_P	{ $$ = int32(OVERRIDING_SYSTEM_VALUE) }
		;

insert_column_list:
			insert_column_item
					{ $$ = []Node{$1} }
			| insert_column_list ',' insert_column_item
					{ $$ = append($1, $3) }
		;

insert_column_item:
			ColId opt_indirection
				{
					n := &ResTarget{}
					n.Name = $1
					n.Indirection = p.checkIndirection($2)
					n.Val = nil
					n.Location = @1
					$$ = n
				}
		;

opt_on_conflict:
			ON CONFLICT opt_conf_expr DO UPDATE SET set_clause_list	where_clause
				{
					n := &OnConflictClause{}
					n.Action = ONCONFLICT_UPDATE
					n.Infer = as[*InferClause]($3)
					n.TargetList = $7
					n.WhereClause = $8
					n.Location = @1
					$$ = n
				}
			|
			ON CONFLICT opt_conf_expr DO NOTHING
				{
					n := &OnConflictClause{}
					n.Action = ONCONFLICT_NOTHING
					n.Infer = as[*InferClause]($3)
					n.TargetList = nil
					n.WhereClause = nil
					n.Location = @1
					$$ = n
				}
			| /*EMPTY*/
				{ $$ = nil }
		;

opt_conf_expr:
			'(' index_params ')' where_clause
				{
					n := &InferClause{}
					n.IndexElems = $2
					n.WhereClause = $4
					n.Conname = ""
					n.Location = @1
					$$ = n
				}
			|
			ON CONSTRAINT name
				{
					n := &InferClause{}
					n.IndexElems = nil
					n.WhereClause = nil
					n.Conname = $3
					n.Location = @1
					$$ = n
				}
			| /*EMPTY*/
				{ $$ = nil }
		;

returning_clause:
			RETURNING target_list		{ $$ = $2 }
			| /* EMPTY */				{ $$ = nil }
		;


/*****************************************************************************
 *
 *		QUERY:
 *				DELETE STATEMENTS
 *
 *****************************************************************************/

DeleteStmt: opt_with_clause DELETE_P FROM relation_expr_opt_alias
			using_clause where_or_current_clause returning_clause
				{
					n := &DeleteStmt{}

					n.Relation = as[*RangeVar]($4)
					n.UsingClause = $5
					n.WhereClause = $6
					n.ReturningList = $7
					n.WithClause = as[*WithClause]($1)
					$$ = n
				}
		;

using_clause:
				USING from_list						{ $$ = $2 }
			| /*EMPTY*/								{ $$ = nil }
		;


/*****************************************************************************
 *
 *		QUERY:
 *				LOCK TABLE
 *
 *****************************************************************************/

LockStmt:	LOCK_P opt_table relation_expr_list opt_lock opt_nowait
				{
					n := &LockStmt{}

					n.Relations = $3
					n.Mode = $4
					n.Nowait = $5
					$$ = n
				}
		;

opt_lock:	IN_P lock_type MODE				{ $$ = $2 }
			| /*EMPTY*/						{ $$ = AccessExclusiveLock }
		;

lock_type:	ACCESS SHARE					{ $$ = AccessShareLock }
			| ROW SHARE						{ $$ = RowShareLock }
			| ROW EXCLUSIVE					{ $$ = RowExclusiveLock }
			| SHARE UPDATE EXCLUSIVE		{ $$ = ShareUpdateExclusiveLock }
			| SHARE							{ $$ = ShareLock }
			| SHARE ROW EXCLUSIVE			{ $$ = ShareRowExclusiveLock }
			| EXCLUSIVE						{ $$ = ExclusiveLock }
			| ACCESS EXCLUSIVE				{ $$ = AccessExclusiveLock }
		;

opt_nowait:	NOWAIT							{ $$ = true }
			| /*EMPTY*/						{ $$ = false }
		;

opt_nowait_or_skip:
			NOWAIT							{ $$ = int32(LockWaitError) }
			| SKIP LOCKED					{ $$ = int32(LockWaitSkip) }
			| /*EMPTY*/						{ $$ = int32(LockWaitBlock) }
		;


/*****************************************************************************
 *
 *		QUERY:
 *				UpdateStmt (UPDATE)
 *
 *****************************************************************************/

UpdateStmt: opt_with_clause UPDATE relation_expr_opt_alias
			SET set_clause_list
			from_clause
			where_or_current_clause
			returning_clause
				{
					n := &UpdateStmt{}

					n.Relation = as[*RangeVar]($3)
					n.TargetList = $5
					n.FromClause = $6
					n.WhereClause = $7
					n.ReturningList = $8
					n.WithClause = as[*WithClause]($1)
					$$ = n
				}
		;

set_clause_list:
			set_clause							{ $$ = $1 }
			| set_clause_list ',' set_clause	{ $$ = append($1, $3...) }
		;

set_clause:
			set_target '=' a_expr
				{
					as[*ResTarget]($1).Val = $3
					$$ = []Node{$1}
				}
			| '(' set_target_list ')' '=' a_expr
				{
					ncolumns := int32(len($2))
					i := int32(1)

					/* Create a MultiAssignRef source for each target */
					for _, c := range $2 {
						resCol := as[*ResTarget](c)
						r := &MultiAssignRef{}

						r.Source = $5
						r.Colno = i
						r.Ncolumns = ncolumns
						resCol.Val = r
						i++
					}

					$$ = $2
				}
		;

set_target:
			ColId opt_indirection
				{
					n := &ResTarget{}
					n.Name = $1
					n.Indirection = p.checkIndirection($2)
					n.Val = nil /* upper production sets this */
					n.Location = @1
					$$ = n
				}
		;

set_target_list:
			set_target								{ $$ = []Node{$1} }
			| set_target_list ',' set_target		{ $$ = append($1, $3) }
		;


/*****************************************************************************
 *
 *		QUERY:
 *				MERGE
 *
 *****************************************************************************/

MergeStmt:
			opt_with_clause MERGE INTO relation_expr_opt_alias
			USING table_ref
			ON a_expr
			merge_when_list
			returning_clause
				{
					m := &MergeStmt{}

					m.WithClause = as[*WithClause]($1)
					m.Relation = as[*RangeVar]($4)
					m.SourceRelation = $6
					m.JoinCondition = $8
					m.MergeWhenClauses = $9
					m.ReturningList = $10

					$$ = m
				}
		;

merge_when_list:
			merge_when_clause						{ $$ = []Node{$1} }
			| merge_when_list merge_when_clause		{ $$ = append($1, $2) }
		;

/*
 * A WHEN clause may be WHEN MATCHED, WHEN NOT MATCHED BY SOURCE, or WHEN NOT
 * MATCHED [BY TARGET]. The first two cases match target tuples, and support
 * UPDATE/DELETE/DO NOTHING actions. The third case does not match target
 * tuples, and only supports INSERT/DO NOTHING actions.
 */
merge_when_clause:
			merge_when_tgt_matched opt_merge_when_condition THEN merge_update
				{
					n := as[*MergeWhenClause]($4)

					n.MatchKind = MergeMatchKind($1)
					n.Condition = $2

					$$ = n
				}
			| merge_when_tgt_matched opt_merge_when_condition THEN merge_delete
				{
					n := as[*MergeWhenClause]($4)

					n.MatchKind = MergeMatchKind($1)
					n.Condition = $2

					$$ = n
				}
			| merge_when_tgt_not_matched opt_merge_when_condition THEN merge_insert
				{
					n := as[*MergeWhenClause]($4)

					n.MatchKind = MergeMatchKind($1)
					n.Condition = $2

					$$ = n
				}
			| merge_when_tgt_matched opt_merge_when_condition THEN DO NOTHING
				{
					m := &MergeWhenClause{}

					m.MatchKind = MergeMatchKind($1)
					m.CommandType = CMD_NOTHING
					m.Condition = $2

					$$ = m
				}
			| merge_when_tgt_not_matched opt_merge_when_condition THEN DO NOTHING
				{
					m := &MergeWhenClause{}

					m.MatchKind = MergeMatchKind($1)
					m.CommandType = CMD_NOTHING
					m.Condition = $2

					$$ = m
				}
		;

merge_when_tgt_matched:
			WHEN MATCHED					{ $$ = int32(MERGE_WHEN_MATCHED) }
			| WHEN NOT MATCHED BY SOURCE	{ $$ = int32(MERGE_WHEN_NOT_MATCHED_BY_SOURCE) }
		;

merge_when_tgt_not_matched:
			WHEN NOT MATCHED				{ $$ = int32(MERGE_WHEN_NOT_MATCHED_BY_TARGET) }
			| WHEN NOT MATCHED BY TARGET	{ $$ = int32(MERGE_WHEN_NOT_MATCHED_BY_TARGET) }
		;

opt_merge_when_condition:
			AND a_expr				{ $$ = $2 }
			|						{ $$ = nil }
		;

merge_update:
			UPDATE SET set_clause_list
				{
					n := &MergeWhenClause{}
					n.CommandType = CMD_UPDATE
					n.Override = OVERRIDING_NOT_SET
					n.TargetList = $3
					n.Values = nil

					$$ = n
				}
		;

merge_delete:
			DELETE_P
				{
					n := &MergeWhenClause{}
					n.CommandType = CMD_DELETE
					n.Override = OVERRIDING_NOT_SET
					n.TargetList = nil
					n.Values = nil

					$$ = n
				}
		;

merge_insert:
			INSERT merge_values_clause
				{
					n := &MergeWhenClause{}
					n.CommandType = CMD_INSERT
					n.Override = OVERRIDING_NOT_SET
					n.TargetList = nil
					n.Values = $2
					$$ = n
				}
			| INSERT OVERRIDING override_kind VALUE_P merge_values_clause
				{
					n := &MergeWhenClause{}
					n.CommandType = CMD_INSERT
					n.Override = OverridingKind($3)
					n.TargetList = nil
					n.Values = $5
					$$ = n
				}
			| INSERT '(' insert_column_list ')' merge_values_clause
				{
					n := &MergeWhenClause{}
					n.CommandType = CMD_INSERT
					n.Override = OVERRIDING_NOT_SET
					n.TargetList = $3
					n.Values = $5
					$$ = n
				}
			| INSERT '(' insert_column_list ')' OVERRIDING override_kind VALUE_P merge_values_clause
				{
					n := &MergeWhenClause{}
					n.CommandType = CMD_INSERT
					n.Override = OverridingKind($6)
					n.TargetList = $3
					n.Values = $8
					$$ = n
				}
			| INSERT DEFAULT VALUES
				{
					n := &MergeWhenClause{}
					n.CommandType = CMD_INSERT
					n.Override = OVERRIDING_NOT_SET
					n.TargetList = nil
					n.Values = nil
					$$ = n
				}
		;

merge_values_clause:
			VALUES '(' expr_list ')'
				{ $$ = $3 }
		;

/*****************************************************************************
 *
 *		QUERY:
 *				CURSOR STATEMENTS
 *
 *****************************************************************************/
DeclareCursorStmt: DECLARE cursor_name cursor_options CURSOR opt_hold FOR SelectStmt
				{
					n := &DeclareCursorStmt{}

					n.Portalname = $2
					/* currently we always set FAST_PLAN option */
					n.Options = $3 | $5 | CURSOR_OPT_FAST_PLAN
					n.Query = $7
					$$ = n
				}
		;

cursor_name:	name						{ $$ = $1 }
		;

cursor_options: /*EMPTY*/					{ $$ = 0 }
			| cursor_options NO SCROLL		{ $$ = $1 | CURSOR_OPT_NO_SCROLL }
			| cursor_options SCROLL			{ $$ = $1 | CURSOR_OPT_SCROLL }
			| cursor_options BINARY			{ $$ = $1 | CURSOR_OPT_BINARY }
			| cursor_options ASENSITIVE		{ $$ = $1 | CURSOR_OPT_ASENSITIVE }
			| cursor_options INSENSITIVE	{ $$ = $1 | CURSOR_OPT_INSENSITIVE }
		;

opt_hold: /* EMPTY */						{ $$ = 0 }
			| WITH HOLD						{ $$ = CURSOR_OPT_HOLD }
			| WITHOUT HOLD					{ $$ = 0 }
		;

/*****************************************************************************
 *
 *		QUERY:
 *				SELECT STATEMENTS
 *
 *****************************************************************************/

/* A complete SELECT statement looks like this.
 *
 * The rule returns either a single SelectStmt node or a tree of them,
 * representing a set-operation tree.
 *
 * There is an ambiguity when a sub-SELECT is within an a_expr and there
 * are excess parentheses: do the parentheses belong to the sub-SELECT or
 * to the surrounding a_expr?  We don't really care, but bison wants to know.
 * To resolve the ambiguity, we are careful to define the grammar so that
 * the decision is staved off as long as possible: as long as we can keep
 * absorbing parentheses into the sub-SELECT, we will do so, and only when
 * it's no longer possible to do that will we decide that parens belong to
 * the expression.	For example, in "SELECT (((SELECT 2)) + 3)" the extra
 * parentheses are treated as part of the sub-select.  The necessity of doing
 * it that way is shown by "SELECT (((SELECT 2)) UNION SELECT 2)".	Had we
 * parsed "((SELECT 2))" as an a_expr, it'd be too late to go back to the
 * SELECT viewpoint when we see the UNION.
 *
 * This approach is implemented by defining a nonterminal select_with_parens,
 * which represents a SELECT with at least one outer layer of parentheses,
 * and being careful to use select_with_parens, never '(' SelectStmt ')',
 * in the expression grammar.  We will then have shift-reduce conflicts
 * which we can resolve in favor of always treating '(' <select> ')' as
 * a select_with_parens.  To resolve the conflicts, the productions that
 * conflict with the select_with_parens productions are manually given
 * precedences lower than the precedence of ')', thereby ensuring that we
 * shift ')' (and then reduce to select_with_parens) rather than trying to
 * reduce the inner <select> nonterminal to something else.  We use UMINUS
 * precedence for this, which is a fairly arbitrary choice.
 *
 * To be able to define select_with_parens itself without ambiguity, we need
 * a nonterminal select_no_parens that represents a SELECT structure with no
 * outermost parentheses.  This is a little bit tedious, but it works.
 *
 * In non-expression contexts, we use SelectStmt which can represent a SELECT
 * with or without outer parentheses.
 */

SelectStmt: select_no_parens			%prec UMINUS
			| select_with_parens		%prec UMINUS
		;

select_with_parens:
			'(' select_no_parens ')'				{ $$ = $2 }
			| '(' select_with_parens ')'			{ $$ = $2 }
		;

/*
 * This rule parses the equivalent of the standard's <query expression>.
 * The duplicative productions are annoying, but hard to get rid of without
 * creating shift/reduce conflicts.
 *
 *	The locking clause (FOR UPDATE etc) may be before or after LIMIT/OFFSET.
 *	In <=7.2.X, LIMIT/OFFSET had to be after FOR UPDATE
 *	We now support both orderings, but prefer LIMIT/OFFSET before the locking
 * clause.
 *	2002-08-28 bjm
 */
select_no_parens:
			simple_select						{ $$ = $1 }
			| select_clause sort_clause
				{
					p.insertSelectOptions(as[*SelectStmt]($1), $2, nil, nil, nil)
					$$ = $1
				}
			| select_clause opt_sort_clause for_locking_clause opt_select_limit
				{
					p.insertSelectOptions(as[*SelectStmt]($1), $2, $3,
						as[*selectLimit]($4),
						nil)
					$$ = $1
				}
			| select_clause opt_sort_clause select_limit opt_for_locking_clause
				{
					p.insertSelectOptions(as[*SelectStmt]($1), $2, $4,
						as[*selectLimit]($3),
						nil)
					$$ = $1
				}
			| with_clause select_clause
				{
					p.insertSelectOptions(as[*SelectStmt]($2), nil, nil,
						nil,
						as[*WithClause]($1))
					$$ = $2
				}
			| with_clause select_clause sort_clause
				{
					p.insertSelectOptions(as[*SelectStmt]($2), $3, nil,
						nil,
						as[*WithClause]($1))
					$$ = $2
				}
			| with_clause select_clause opt_sort_clause for_locking_clause opt_select_limit
				{
					p.insertSelectOptions(as[*SelectStmt]($2), $3, $4,
						as[*selectLimit]($5),
						as[*WithClause]($1))
					$$ = $2
				}
			| with_clause select_clause opt_sort_clause select_limit opt_for_locking_clause
				{
					p.insertSelectOptions(as[*SelectStmt]($2), $3, $5,
						as[*selectLimit]($4),
						as[*WithClause]($1))
					$$ = $2
				}
		;

select_clause:
			simple_select							{ $$ = $1 }
			| select_with_parens					{ $$ = $1 }
		;

/*
 * This rule parses SELECT statements that can appear within set operations,
 * including UNION, INTERSECT and EXCEPT.  '(' and ')' can be used to specify
 * the ordering of the set operations.	Without '(' and ')' we want the
 * operations to be ordered per the precedence specs at the head of this file.
 *
 * As with select_no_parens, simple_select cannot have outer parentheses,
 * but can have parenthesized subclauses.
 *
 * It might appear that we could fold the first two alternatives into one
 * by using opt_distinct_clause.  However, that causes a shift/reduce conflict
 * against INSERT ... SELECT ... ON CONFLICT.  We avoid the ambiguity by
 * requiring SELECT DISTINCT [ON] to be followed by a non-empty target_list.
 *
 * Note that sort clauses cannot be included at this level --- SQL requires
 *		SELECT foo UNION SELECT bar ORDER BY baz
 * to be parsed as
 *		(SELECT foo UNION SELECT bar) ORDER BY baz
 * not
 *		SELECT foo UNION (SELECT bar ORDER BY baz)
 * Likewise for WITH, FOR UPDATE and LIMIT.  Therefore, those clauses are
 * described as part of the select_no_parens production, not simple_select.
 * This does not limit functionality, because you can reintroduce these
 * clauses inside parentheses.
 *
 * NOTE: only the leftmost component SelectStmt should have INTO.
 * However, this is not checked by the grammar; parse analysis must check it.
 */
simple_select:
			SELECT opt_all_clause opt_target_list
			into_clause from_clause where_clause
			group_clause having_clause window_clause
				{
					n := &SelectStmt{}
					g := as[*groupClause]($7)

					n.TargetList = $3
					n.IntoClause = as[*IntoClause]($4)
					n.FromClause = $5
					n.WhereClause = $6
					n.GroupClause = g.list
					n.GroupDistinct = g.distinct
					n.HavingClause = $8
					n.WindowClause = $9
					$$ = n
				}
			| SELECT distinct_clause target_list
			into_clause from_clause where_clause
			group_clause having_clause window_clause
				{
					n := &SelectStmt{}
					g := as[*groupClause]($7)

					n.DistinctClause = $2
					n.TargetList = $3
					n.IntoClause = as[*IntoClause]($4)
					n.FromClause = $5
					n.WhereClause = $6
					n.GroupClause = g.list
					n.GroupDistinct = g.distinct
					n.HavingClause = $8
					n.WindowClause = $9
					$$ = n
				}
			| values_clause							{ $$ = $1 }
			| TABLE relation_expr
				{
					/* same as SELECT * FROM relation_expr */
					cr := &ColumnRef{}
					rt := &ResTarget{}
					n := &SelectStmt{}

					cr.Fields = []Node{&A_Star{}}
					cr.Location = -1

					rt.Name = ""
					rt.Indirection = nil
					rt.Val = cr
					rt.Location = -1

					n.TargetList = []Node{rt}
					n.FromClause = []Node{$2}
					$$ = n
				}
			| select_clause UNION set_quantifier select_clause
				{ $$ = makeSetOp(SETOP_UNION, SetQuantifier($3) == SET_QUANTIFIER_ALL, $1, $4) }
			| select_clause INTERSECT set_quantifier select_clause
				{ $$ = makeSetOp(SETOP_INTERSECT, SetQuantifier($3) == SET_QUANTIFIER_ALL, $1, $4) }
			| select_clause EXCEPT set_quantifier select_clause
				{ $$ = makeSetOp(SETOP_EXCEPT, SetQuantifier($3) == SET_QUANTIFIER_ALL, $1, $4) }
		;

/*
 * SQL standard WITH clause looks like:
 *
 * WITH [ RECURSIVE ] <query name> [ (<column>,...) ]
 *		AS (query) [ SEARCH or CYCLE clause ]
 *
 * Recognizing WITH_LA here allows a CTE to be named TIME or ORDINALITY.
 */
with_clause:
		WITH cte_list
			{
				n := &WithClause{}
				n.Ctes = $2
				n.Recursive = false
				n.Location = @1
				$$ = n
			}
		| WITH_LA cte_list
			{
				n := &WithClause{}
				n.Ctes = $2
				n.Recursive = false
				n.Location = @1
				$$ = n
			}
		| WITH RECURSIVE cte_list
			{
				n := &WithClause{}
				n.Ctes = $3
				n.Recursive = true
				n.Location = @1
				$$ = n
			}
		;

cte_list:
		common_table_expr						{ $$ = []Node{$1} }
		| cte_list ',' common_table_expr		{ $$ = append($1, $3) }
		;

common_table_expr:  name opt_name_list AS opt_materialized '(' PreparableStmt ')' opt_search_clause opt_cycle_clause
			{
				n := &CommonTableExpr{}

				n.Ctename = $1
				n.Aliascolnames = $2
				n.Ctematerialized = CTEMaterialize($4)
				n.Ctequery = $6
				n.SearchClause = as[*CTESearchClause]($8)
				n.CycleClause = as[*CTECycleClause]($9)
				n.Location = @1
				$$ = n
			}
		;

opt_materialized:
		MATERIALIZED							{ $$ = int32(CTEMaterializeAlways) }
		| NOT MATERIALIZED						{ $$ = int32(CTEMaterializeNever) }
		| /*EMPTY*/								{ $$ = int32(CTEMaterializeDefault) }
		;

opt_search_clause:
		SEARCH DEPTH FIRST_P BY columnList SET ColId
			{
				n := &CTESearchClause{}

				n.SearchColList = $5
				n.SearchBreadthFirst = false
				n.SearchSeqColumn = $7
				n.Location = @1
				$$ = n
			}
		| SEARCH BREADTH FIRST_P BY columnList SET ColId
			{
				n := &CTESearchClause{}

				n.SearchColList = $5
				n.SearchBreadthFirst = true
				n.SearchSeqColumn = $7
				n.Location = @1
				$$ = n
			}
		| /*EMPTY*/
			{ $$ = nil }
		;

opt_cycle_clause:
		CYCLE columnList SET ColId TO AexprConst DEFAULT AexprConst USING ColId
			{
				n := &CTECycleClause{}

				n.CycleColList = $2
				n.CycleMarkColumn = $4
				n.CycleMarkValue = $6
				n.CycleMarkDefault = $8
				n.CyclePathColumn = $10
				n.Location = @1
				$$ = n
			}
		| CYCLE columnList SET ColId USING ColId
			{
				n := &CTECycleClause{}

				n.CycleColList = $2
				n.CycleMarkColumn = $4
				n.CycleMarkValue = makeBoolAConst(true, -1)
				n.CycleMarkDefault = makeBoolAConst(false, -1)
				n.CyclePathColumn = $6
				n.Location = @1
				$$ = n
			}
		| /*EMPTY*/
			{ $$ = nil }
		;

opt_with_clause:
		with_clause								{ $$ = $1 }
		| /*EMPTY*/								{ $$ = nil }
		;

into_clause:
			INTO OptTempTableName
				{
					n := &IntoClause{}
					n.Rel = as[*RangeVar]($2)
					n.ColNames = nil
					n.Options = nil
					n.OnCommit = ONCOMMIT_NOOP
					n.TableSpaceName = ""
					n.ViewQuery = nil
					n.SkipData = false
					$$ = n
				}
			| /*EMPTY*/
				{ $$ = nil }
		;

/*
 * Redundancy here is needed to avoid shift/reduce conflicts,
 * since TEMP is not a reserved word.  See also OptTemp.
 */
OptTempTableName:
			TEMPORARY opt_table qualified_name
				{
					r := as[*RangeVar]($3)
					r.Relpersistence = relpersistenceTemp
					$$ = r
				}
			| TEMP opt_table qualified_name
				{
					r := as[*RangeVar]($3)
					r.Relpersistence = relpersistenceTemp
					$$ = r
				}
			| LOCAL TEMPORARY opt_table qualified_name
				{
					r := as[*RangeVar]($4)
					r.Relpersistence = relpersistenceTemp
					$$ = r
				}
			| LOCAL TEMP opt_table qualified_name
				{
					r := as[*RangeVar]($4)
					r.Relpersistence = relpersistenceTemp
					$$ = r
				}
			| GLOBAL TEMPORARY opt_table qualified_name
				{
					/* ereport(WARNING, "GLOBAL is deprecated in temporary table creation"): no effect on the tree */
					r := as[*RangeVar]($4)
					r.Relpersistence = relpersistenceTemp
					$$ = r
				}
			| GLOBAL TEMP opt_table qualified_name
				{
					/* ereport(WARNING, "GLOBAL is deprecated in temporary table creation"): no effect on the tree */
					r := as[*RangeVar]($4)
					r.Relpersistence = relpersistenceTemp
					$$ = r
				}
			| UNLOGGED opt_table qualified_name
				{
					r := as[*RangeVar]($3)
					r.Relpersistence = relpersistenceUnlogged
					$$ = r
				}
			| TABLE qualified_name
				{
					r := as[*RangeVar]($2)
					r.Relpersistence = relpersistencePermanent
					$$ = r
				}
			| qualified_name
				{
					r := as[*RangeVar]($1)
					r.Relpersistence = relpersistencePermanent
					$$ = r
				}
		;

opt_table:	TABLE
			| /*EMPTY*/
		;

set_quantifier:
			ALL										{ $$ = int32(SET_QUANTIFIER_ALL) }
			| DISTINCT								{ $$ = int32(SET_QUANTIFIER_DISTINCT) }
			| /*EMPTY*/								{ $$ = int32(SET_QUANTIFIER_DEFAULT) }
		;

/* We use (NIL) as a placeholder to indicate that all target expressions
 * should be placed in the DISTINCT list during parsetree analysis.
 */
distinct_clause:
			DISTINCT								{ $$ = []Node{nil} }
			| DISTINCT ON '(' expr_list ')'			{ $$ = $4 }
		;

opt_all_clause:
			ALL
			| /*EMPTY*/
		;

opt_distinct_clause:
			distinct_clause							{ $$ = $1 }
			| opt_all_clause						{ $$ = nil }
		;

opt_sort_clause:
			sort_clause								{ $$ = $1 }
			| /*EMPTY*/								{ $$ = nil }
		;

sort_clause:
			ORDER BY sortby_list					{ $$ = $3 }
		;

sortby_list:
			sortby									{ $$ = []Node{$1} }
			| sortby_list ',' sortby				{ $$ = append($1, $3) }
		;

sortby:		a_expr USING qual_all_Op opt_nulls_order
				{
					n := &SortBy{}
					n.Node = $1
					n.SortbyDir = SORTBY_USING
					n.SortbyNulls = SortByNulls($4)
					n.UseOp = $3
					n.Location = @3
					$$ = n
				}
			| a_expr opt_asc_desc opt_nulls_order
				{
					n := &SortBy{}
					n.Node = $1
					n.SortbyDir = SortByDir($2)
					n.SortbyNulls = SortByNulls($3)
					n.UseOp = nil
					n.Location = -1 /* no operator */
					$$ = n
				}
		;


select_limit:
			limit_clause offset_clause
				{
					n := as[*selectLimit]($1)
					n.limitOffset = $2
					$$ = n
				}
			| offset_clause limit_clause
				{
					n := as[*selectLimit]($2)
					n.limitOffset = $1
					$$ = n
				}
			| limit_clause
				{ $$ = $1 }
			| offset_clause
				{
					n := &selectLimit{}

					n.limitOffset = $1
					n.limitCount = nil
					n.limitOption = LIMIT_OPTION_COUNT
					$$ = n
				}
		;

opt_select_limit:
			select_limit						{ $$ = $1 }
			| /* EMPTY */						{ $$ = nil }
		;

limit_clause:
			LIMIT select_limit_value
				{
					n := &selectLimit{}

					n.limitOffset = nil
					n.limitCount = $2
					n.limitOption = LIMIT_OPTION_COUNT
					$$ = n
				}
			| LIMIT select_limit_value ',' select_offset_value
				{
					/* Disabled because it was too confusing, bjm 2002-02-18 */
					p.fail(@1, "LIMIT #,# syntax is not supported")
				}
			/* SQL:2008 syntax */
			/* to avoid shift/reduce conflicts, handle the optional value with
			 * a separate production rather than an opt_ expression.  The fact
			 * that ONLY is fully reserved means that this way, we defer any
			 * decision about what rule reduces ROW or ROWS to the point where
			 * we can see the ONLY token in the lookahead slot.
			 */
			| FETCH first_or_next select_fetch_first_value row_or_rows ONLY
				{
					n := &selectLimit{}

					n.limitOffset = nil
					n.limitCount = $3
					n.limitOption = LIMIT_OPTION_COUNT
					$$ = n
				}
			| FETCH first_or_next select_fetch_first_value row_or_rows WITH TIES
				{
					n := &selectLimit{}

					n.limitOffset = nil
					n.limitCount = $3
					n.limitOption = LIMIT_OPTION_WITH_TIES
					$$ = n
				}
			| FETCH first_or_next row_or_rows ONLY
				{
					n := &selectLimit{}

					n.limitOffset = nil
					n.limitCount = makeIntConst(1, -1)
					n.limitOption = LIMIT_OPTION_COUNT
					$$ = n
				}
			| FETCH first_or_next row_or_rows WITH TIES
				{
					n := &selectLimit{}

					n.limitOffset = nil
					n.limitCount = makeIntConst(1, -1)
					n.limitOption = LIMIT_OPTION_WITH_TIES
					$$ = n
				}
		;

offset_clause:
			OFFSET select_offset_value
				{ $$ = $2 }
			/* SQL:2008 syntax */
			| OFFSET select_fetch_first_value row_or_rows
				{ $$ = $2 }
		;

select_limit_value:
			a_expr									{ $$ = $1 }
			| ALL
				{
					/* LIMIT ALL is represented as a NULL constant */
					$$ = makeNullAConst(@1)
				}
		;

select_offset_value:
			a_expr									{ $$ = $1 }
		;

/*
 * Allowing full expressions without parentheses causes various parsing
 * problems with the trailing ROW/ROWS key words.  SQL spec only calls for
 * <simple value specification>, which is either a literal or a parameter (but
 * an <SQL parameter reference> could be an identifier, bringing up conflicts
 * with ROW/ROWS). We solve this by leveraging the presence of ONLY (see above)
 * to determine whether the expression is missing rather than trying to make it
 * optional in this rule.
 *
 * c_expr covers almost all the spec-required cases (and more), but it doesn't
 * cover signed numeric literals, which are allowed by the spec. So we include
 * those here explicitly. We need FCONST as well as ICONST because values that
 * don't fit in the platform's "long", but do fit in bigint, should still be
 * accepted here. (This is possible in 64-bit Windows as well as all 32-bit
 * builds.)
 */
select_fetch_first_value:
			c_expr									{ $$ = $1 }
			| '+' I_or_F_const
				{ $$ = makeSimpleA_Expr(AEXPR_OP, "+", nil, $2, @1) }
			| '-' I_or_F_const
				{ $$ = doNegate($2, @1) }
		;

I_or_F_const:
			Iconst									{ $$ = makeIntConst($1, @1) }
			| FCONST								{ $$ = makeFloatConst($1, @1) }
		;

/* noise words */
row_or_rows: ROW									{ $$ = 0 }
			| ROWS									{ $$ = 0 }
		;

first_or_next: FIRST_P								{ $$ = 0 }
			| NEXT									{ $$ = 0 }
		;


/*
 * This syntax for group_clause tries to follow the spec quite closely.
 * However, the spec allows only column references, not expressions,
 * which introduces an ambiguity between implicit row constructors
 * (a,b) and lists of column references.
 *
 * We handle this by using the a_expr production for what the spec calls
 * <ordinary grouping set>, which in the spec represents either one column
 * reference or a parenthesized list of column references. Then, we check the
 * top node of the a_expr to see if it's an implicit RowExpr, and if so, just
 * grab and use the list, discarding the node. (this is done in parse analysis,
 * not here)
 *
 * (we abuse the row_format field of RowExpr to distinguish implicit and
 * explicit row constructors; it's debatable if anyone sanely wants to use them
 * in a group clause, but if they have a reason to, we make it possible.)
 *
 * Each item in the group_clause list is either an expression tree or a
 * GroupingSet node of some type.
 */
group_clause:
			GROUP_P BY set_quantifier group_by_list
				{
					n := &groupClause{}

					n.distinct = SetQuantifier($3) == SET_QUANTIFIER_DISTINCT
					n.list = $4
					$$ = n
				}
			| /*EMPTY*/
				{
					n := &groupClause{}

					n.distinct = false
					n.list = nil
					$$ = n
				}
		;

group_by_list:
			group_by_item							{ $$ = []Node{$1} }
			| group_by_list ',' group_by_item		{ $$ = append($1, $3) }
		;

group_by_item:
			a_expr									{ $$ = $1 }
			| empty_grouping_set					{ $$ = $1 }
			| cube_clause							{ $$ = $1 }
			| rollup_clause							{ $$ = $1 }
			| grouping_sets_clause					{ $$ = $1 }
		;

empty_grouping_set:
			'(' ')'
				{ $$ = makeGroupingSet(GROUPING_SET_EMPTY, nil, @1) }
		;

/*
 * These hacks rely on setting precedence of CUBE and ROLLUP below that of '(',
 * so that they shift in these rules rather than reducing the conflicting
 * unreserved_keyword rule.
 */

rollup_clause:
			ROLLUP '(' expr_list ')'
				{ $$ = makeGroupingSet(GROUPING_SET_ROLLUP, $3, @1) }
		;

cube_clause:
			CUBE '(' expr_list ')'
				{ $$ = makeGroupingSet(GROUPING_SET_CUBE, $3, @1) }
		;

grouping_sets_clause:
			GROUPING SETS '(' group_by_list ')'
				{ $$ = makeGroupingSet(GROUPING_SET_SETS, $4, @1) }
		;

having_clause:
			HAVING a_expr							{ $$ = $2 }
			| /*EMPTY*/								{ $$ = nil }
		;

for_locking_clause:
			for_locking_items						{ $$ = $1 }
			| FOR READ ONLY							{ $$ = nil }
		;

opt_for_locking_clause:
			for_locking_clause						{ $$ = $1 }
			| /* EMPTY */							{ $$ = nil }
		;

for_locking_items:
			for_locking_item						{ $$ = []Node{$1} }
			| for_locking_items for_locking_item	{ $$ = append($1, $2) }
		;

for_locking_item:
			for_locking_strength locked_rels_list opt_nowait_or_skip
				{
					n := &LockingClause{}

					n.LockedRels = $2
					n.Strength = LockClauseStrength($1)
					n.WaitPolicy = LockWaitPolicy($3)
					$$ = n
				}
		;

for_locking_strength:
			FOR UPDATE							{ $$ = int32(LCS_FORUPDATE) }
			| FOR NO KEY UPDATE					{ $$ = int32(LCS_FORNOKEYUPDATE) }
			| FOR SHARE							{ $$ = int32(LCS_FORSHARE) }
			| FOR KEY SHARE						{ $$ = int32(LCS_FORKEYSHARE) }
		;

locked_rels_list:
			OF qualified_name_list					{ $$ = $2 }
			| /* EMPTY */							{ $$ = nil }
		;


/*
 * We should allow ROW '(' expr_list ')' too, but that seems to require
 * making VALUES a fully reserved word, which will probably break more apps
 * than allowing the noise-word is worth.
 */
values_clause:
			VALUES '(' expr_list ')'
				{
					n := &SelectStmt{}

					n.ValuesLists = []Node{listNode($3)}
					$$ = n
				}
			| values_clause ',' '(' expr_list ')'
				{
					n := as[*SelectStmt]($1)

					n.ValuesLists = append(n.ValuesLists, listNode($4))
					$$ = n
				}
		;

