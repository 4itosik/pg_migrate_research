/* gram.y lines 12079-13424 */
/*****************************************************************************
 *
 *		QUERY:
 *				DEALLOCATE [PREPARE] <plan_name>
 *
 *****************************************************************************/

DeallocateStmt: DEALLOCATE name
					{ /*C
						DeallocateStmt *n = makeNode(DeallocateStmt);

						n->name = $2;
						n->isall = false;
						n->location = @2;
						$$ = (Node *) n;
					*/ }
				| DEALLOCATE PREPARE name
					{ /*C
						DeallocateStmt *n = makeNode(DeallocateStmt);

						n->name = $3;
						n->isall = false;
						n->location = @3;
						$$ = (Node *) n;
					*/ }
				| DEALLOCATE ALL
					{ /*C
						DeallocateStmt *n = makeNode(DeallocateStmt);

						n->name = NULL;
						n->isall = true;
						n->location = -1;
						$$ = (Node *) n;
					*/ }
				| DEALLOCATE PREPARE ALL
					{ /*C
						DeallocateStmt *n = makeNode(DeallocateStmt);

						n->name = NULL;
						n->isall = true;
						n->location = -1;
						$$ = (Node *) n;
					*/ }
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
				{ /*C
					$5->relation = $4;
					$5->onConflictClause = $6;
					$5->returningList = $7;
					$5->withClause = $1;
					$$ = (Node *) $5;
				*/ }
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
				{ /*C
					$1->alias = makeAlias($3, NIL);
					$$ = $1;
				*/ }
		;

insert_rest:
			SelectStmt
				{ /*C
					$$ = makeNode(InsertStmt);
					$$->cols = NIL;
					$$->selectStmt = $1;
				*/ }
			| OVERRIDING override_kind VALUE_P SelectStmt
				{ /*C
					$$ = makeNode(InsertStmt);
					$$->cols = NIL;
					$$->override = $2;
					$$->selectStmt = $4;
				*/ }
			| '(' insert_column_list ')' SelectStmt
				{ /*C
					$$ = makeNode(InsertStmt);
					$$->cols = $2;
					$$->selectStmt = $4;
				*/ }
			| '(' insert_column_list ')' OVERRIDING override_kind VALUE_P SelectStmt
				{ /*C
					$$ = makeNode(InsertStmt);
					$$->cols = $2;
					$$->override = $5;
					$$->selectStmt = $7;
				*/ }
			| DEFAULT VALUES
				{ /*C
					$$ = makeNode(InsertStmt);
					$$->cols = NIL;
					$$->selectStmt = NULL;
				*/ }
		;

override_kind:
			USER		{ /*C $$ = OVERRIDING_USER_VALUE; */ }
			| SYSTEM_P	{ /*C $$ = OVERRIDING_SYSTEM_VALUE; */ }
		;

insert_column_list:
			insert_column_item
					{ $$ = []Node{$1} }
			| insert_column_list ',' insert_column_item
					{ $$ = append($1, $3) }
		;

insert_column_item:
			ColId opt_indirection
				{ /*C
					$$ = makeNode(ResTarget);
					$$->name = $1;
					$$->indirection = check_indirection($2, yyscanner);
					$$->val = NULL;
					$$->location = @1;
				*/ }
		;

opt_on_conflict:
			ON CONFLICT opt_conf_expr DO UPDATE SET set_clause_list	where_clause
				{ /*C
					$$ = makeNode(OnConflictClause);
					$$->action = ONCONFLICT_UPDATE;
					$$->infer = $3;
					$$->targetList = $7;
					$$->whereClause = $8;
					$$->location = @1;
				*/ }
			|
			ON CONFLICT opt_conf_expr DO NOTHING
				{ /*C
					$$ = makeNode(OnConflictClause);
					$$->action = ONCONFLICT_NOTHING;
					$$->infer = $3;
					$$->targetList = NIL;
					$$->whereClause = NULL;
					$$->location = @1;
				*/ }
			| /*EMPTY*/
				{ $$ = nil }
		;

opt_conf_expr:
			'(' index_params ')' where_clause
				{ /*C
					$$ = makeNode(InferClause);
					$$->indexElems = $2;
					$$->whereClause = $4;
					$$->conname = NULL;
					$$->location = @1;
				*/ }
			|
			ON CONSTRAINT name
				{ /*C
					$$ = makeNode(InferClause);
					$$->indexElems = NIL;
					$$->whereClause = NULL;
					$$->conname = $3;
					$$->location = @1;
				*/ }
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
				{ /*C
					DeleteStmt *n = makeNode(DeleteStmt);

					n->relation = $4;
					n->usingClause = $5;
					n->whereClause = $6;
					n->returningList = $7;
					n->withClause = $1;
					$$ = (Node *) n;
				*/ }
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
				{ /*C
					LockStmt   *n = makeNode(LockStmt);

					n->relations = $3;
					n->mode = $4;
					n->nowait = $5;
					$$ = (Node *) n;
				*/ }
		;

opt_lock:	IN_P lock_type MODE				{ $$ = $2 }
			| /*EMPTY*/						{ /*C $$ = AccessExclusiveLock; */ }
		;

lock_type:	ACCESS SHARE					{ /*C $$ = AccessShareLock; */ }
			| ROW SHARE						{ /*C $$ = RowShareLock; */ }
			| ROW EXCLUSIVE					{ /*C $$ = RowExclusiveLock; */ }
			| SHARE UPDATE EXCLUSIVE		{ /*C $$ = ShareUpdateExclusiveLock; */ }
			| SHARE							{ /*C $$ = ShareLock; */ }
			| SHARE ROW EXCLUSIVE			{ /*C $$ = ShareRowExclusiveLock; */ }
			| EXCLUSIVE						{ /*C $$ = ExclusiveLock; */ }
			| ACCESS EXCLUSIVE				{ /*C $$ = AccessExclusiveLock; */ }
		;

opt_nowait:	NOWAIT							{ $$ = true }
			| /*EMPTY*/						{ $$ = false }
		;

opt_nowait_or_skip:
			NOWAIT							{ /*C $$ = LockWaitError; */ }
			| SKIP LOCKED					{ /*C $$ = LockWaitSkip; */ }
			| /*EMPTY*/						{ /*C $$ = LockWaitBlock; */ }
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
				{ /*C
					UpdateStmt *n = makeNode(UpdateStmt);

					n->relation = $3;
					n->targetList = $5;
					n->fromClause = $6;
					n->whereClause = $7;
					n->returningList = $8;
					n->withClause = $1;
					$$ = (Node *) n;
				*/ }
		;

set_clause_list:
			set_clause							{ $$ = $1 }
			| set_clause_list ',' set_clause	{ /*C $$ = list_concat($1,$3); */ }
		;

set_clause:
			set_target '=' a_expr
				{ /*C
					$1->val = (Node *) $3;
					$$ = list_make1($1);
				*/ }
			| '(' set_target_list ')' '=' a_expr
				{ /*C
					int			ncolumns = list_length($2);
					int			i = 1;
					ListCell   *col_cell;

					/* Create a MultiAssignRef source for each target * /
					foreach(col_cell, $2)
					{
						ResTarget  *res_col = (ResTarget *) lfirst(col_cell);
						MultiAssignRef *r = makeNode(MultiAssignRef);

						r->source = (Node *) $5;
						r->colno = i;
						r->ncolumns = ncolumns;
						res_col->val = (Node *) r;
						i++;
					}

					$$ = $2;
				*/ }
		;

set_target:
			ColId opt_indirection
				{ /*C
					$$ = makeNode(ResTarget);
					$$->name = $1;
					$$->indirection = check_indirection($2, yyscanner);
					$$->val = NULL;	/* upper production sets this * /
					$$->location = @1;
				*/ }
		;

set_target_list:
			set_target								{ $$ = []Node{$1} }
			| set_target_list ',' set_target		{ /*C $$ = lappend($1,$3); */ }
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
				{ /*C
					MergeStmt  *m = makeNode(MergeStmt);

					m->withClause = $1;
					m->relation = $4;
					m->sourceRelation = $6;
					m->joinCondition = $8;
					m->mergeWhenClauses = $9;
					m->returningList = $10;

					$$ = (Node *) m;
				*/ }
		;

merge_when_list:
			merge_when_clause						{ $$ = []Node{$1} }
			| merge_when_list merge_when_clause		{ /*C $$ = lappend($1,$2); */ }
		;

/*
 * A WHEN clause may be WHEN MATCHED, WHEN NOT MATCHED BY SOURCE, or WHEN NOT
 * MATCHED [BY TARGET]. The first two cases match target tuples, and support
 * UPDATE/DELETE/DO NOTHING actions. The third case does not match target
 * tuples, and only supports INSERT/DO NOTHING actions.
 */
merge_when_clause:
			merge_when_tgt_matched opt_merge_when_condition THEN merge_update
				{ /*C
					$4->matchKind = $1;
					$4->condition = $2;

					$$ = (Node *) $4;
				*/ }
			| merge_when_tgt_matched opt_merge_when_condition THEN merge_delete
				{ /*C
					$4->matchKind = $1;
					$4->condition = $2;

					$$ = (Node *) $4;
				*/ }
			| merge_when_tgt_not_matched opt_merge_when_condition THEN merge_insert
				{ /*C
					$4->matchKind = $1;
					$4->condition = $2;

					$$ = (Node *) $4;
				*/ }
			| merge_when_tgt_matched opt_merge_when_condition THEN DO NOTHING
				{ /*C
					MergeWhenClause *m = makeNode(MergeWhenClause);

					m->matchKind = $1;
					m->commandType = CMD_NOTHING;
					m->condition = $2;

					$$ = (Node *) m;
				*/ }
			| merge_when_tgt_not_matched opt_merge_when_condition THEN DO NOTHING
				{ /*C
					MergeWhenClause *m = makeNode(MergeWhenClause);

					m->matchKind = $1;
					m->commandType = CMD_NOTHING;
					m->condition = $2;

					$$ = (Node *) m;
				*/ }
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
				{ /*C
					MergeWhenClause *n = makeNode(MergeWhenClause);
					n->commandType = CMD_UPDATE;
					n->override = OVERRIDING_NOT_SET;
					n->targetList = $3;
					n->values = NIL;

					$$ = n;
				*/ }
		;

merge_delete:
			DELETE_P
				{ /*C
					MergeWhenClause *n = makeNode(MergeWhenClause);
					n->commandType = CMD_DELETE;
					n->override = OVERRIDING_NOT_SET;
					n->targetList = NIL;
					n->values = NIL;

					$$ = n;
				*/ }
		;

merge_insert:
			INSERT merge_values_clause
				{ /*C
					MergeWhenClause *n = makeNode(MergeWhenClause);
					n->commandType = CMD_INSERT;
					n->override = OVERRIDING_NOT_SET;
					n->targetList = NIL;
					n->values = $2;
					$$ = n;
				*/ }
			| INSERT OVERRIDING override_kind VALUE_P merge_values_clause
				{ /*C
					MergeWhenClause *n = makeNode(MergeWhenClause);
					n->commandType = CMD_INSERT;
					n->override = $3;
					n->targetList = NIL;
					n->values = $5;
					$$ = n;
				*/ }
			| INSERT '(' insert_column_list ')' merge_values_clause
				{ /*C
					MergeWhenClause *n = makeNode(MergeWhenClause);
					n->commandType = CMD_INSERT;
					n->override = OVERRIDING_NOT_SET;
					n->targetList = $3;
					n->values = $5;
					$$ = n;
				*/ }
			| INSERT '(' insert_column_list ')' OVERRIDING override_kind VALUE_P merge_values_clause
				{ /*C
					MergeWhenClause *n = makeNode(MergeWhenClause);
					n->commandType = CMD_INSERT;
					n->override = $6;
					n->targetList = $3;
					n->values = $8;
					$$ = n;
				*/ }
			| INSERT DEFAULT VALUES
				{ /*C
					MergeWhenClause *n = makeNode(MergeWhenClause);
					n->commandType = CMD_INSERT;
					n->override = OVERRIDING_NOT_SET;
					n->targetList = NIL;
					n->values = NIL;
					$$ = n;
				*/ }
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
				{ /*C
					DeclareCursorStmt *n = makeNode(DeclareCursorStmt);

					n->portalname = $2;
					/* currently we always set FAST_PLAN option * /
					n->options = $3 | $5 | CURSOR_OPT_FAST_PLAN;
					n->query = $7;
					$$ = (Node *) n;
				*/ }
		;

cursor_name:	name						{ $$ = $1 }
		;

cursor_options: /*EMPTY*/					{ $$ = 0 }
			| cursor_options NO SCROLL		{ /*C $$ = $1 | CURSOR_OPT_NO_SCROLL; */ }
			| cursor_options SCROLL			{ /*C $$ = $1 | CURSOR_OPT_SCROLL; */ }
			| cursor_options BINARY			{ /*C $$ = $1 | CURSOR_OPT_BINARY; */ }
			| cursor_options ASENSITIVE		{ /*C $$ = $1 | CURSOR_OPT_ASENSITIVE; */ }
			| cursor_options INSENSITIVE	{ /*C $$ = $1 | CURSOR_OPT_INSENSITIVE; */ }
		;

opt_hold: /* EMPTY */						{ $$ = 0 }
			| WITH HOLD						{ /*C $$ = CURSOR_OPT_HOLD; */ }
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
				{ /*C
					insertSelectOptions((SelectStmt *) $1, $2, NIL,
										NULL, NULL,
										yyscanner);
					$$ = $1;
				*/ }
			| select_clause opt_sort_clause for_locking_clause opt_select_limit
				{ /*C
					insertSelectOptions((SelectStmt *) $1, $2, $3,
										$4,
										NULL,
										yyscanner);
					$$ = $1;
				*/ }
			| select_clause opt_sort_clause select_limit opt_for_locking_clause
				{ /*C
					insertSelectOptions((SelectStmt *) $1, $2, $4,
										$3,
										NULL,
										yyscanner);
					$$ = $1;
				*/ }
			| with_clause select_clause
				{ /*C
					insertSelectOptions((SelectStmt *) $2, NULL, NIL,
										NULL,
										$1,
										yyscanner);
					$$ = $2;
				*/ }
			| with_clause select_clause sort_clause
				{ /*C
					insertSelectOptions((SelectStmt *) $2, $3, NIL,
										NULL,
										$1,
										yyscanner);
					$$ = $2;
				*/ }
			| with_clause select_clause opt_sort_clause for_locking_clause opt_select_limit
				{ /*C
					insertSelectOptions((SelectStmt *) $2, $3, $4,
										$5,
										$1,
										yyscanner);
					$$ = $2;
				*/ }
			| with_clause select_clause opt_sort_clause select_limit opt_for_locking_clause
				{ /*C
					insertSelectOptions((SelectStmt *) $2, $3, $5,
										$4,
										$1,
										yyscanner);
					$$ = $2;
				*/ }
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
				{ /*C
					SelectStmt *n = makeNode(SelectStmt);

					n->targetList = $3;
					n->intoClause = $4;
					n->fromClause = $5;
					n->whereClause = $6;
					n->groupClause = ($7)->list;
					n->groupDistinct = ($7)->distinct;
					n->havingClause = $8;
					n->windowClause = $9;
					$$ = (Node *) n;
				*/ }
			| SELECT distinct_clause target_list
			into_clause from_clause where_clause
			group_clause having_clause window_clause
				{ /*C
					SelectStmt *n = makeNode(SelectStmt);

					n->distinctClause = $2;
					n->targetList = $3;
					n->intoClause = $4;
					n->fromClause = $5;
					n->whereClause = $6;
					n->groupClause = ($7)->list;
					n->groupDistinct = ($7)->distinct;
					n->havingClause = $8;
					n->windowClause = $9;
					$$ = (Node *) n;
				*/ }
			| values_clause							{ $$ = $1 }
			| TABLE relation_expr
				{ /*C
					/* same as SELECT * FROM relation_expr * /
					ColumnRef  *cr = makeNode(ColumnRef);
					ResTarget  *rt = makeNode(ResTarget);
					SelectStmt *n = makeNode(SelectStmt);

					cr->fields = list_make1(makeNode(A_Star));
					cr->location = -1;

					rt->name = NULL;
					rt->indirection = NIL;
					rt->val = (Node *) cr;
					rt->location = -1;

					n->targetList = list_make1(rt);
					n->fromClause = list_make1($2);
					$$ = (Node *) n;
				*/ }
			| select_clause UNION set_quantifier select_clause
				{ /*C
					$$ = makeSetOp(SETOP_UNION, $3 == SET_QUANTIFIER_ALL, $1, $4);
				*/ }
			| select_clause INTERSECT set_quantifier select_clause
				{ /*C
					$$ = makeSetOp(SETOP_INTERSECT, $3 == SET_QUANTIFIER_ALL, $1, $4);
				*/ }
			| select_clause EXCEPT set_quantifier select_clause
				{ /*C
					$$ = makeSetOp(SETOP_EXCEPT, $3 == SET_QUANTIFIER_ALL, $1, $4);
				*/ }
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
			{ /*C
				$$ = makeNode(WithClause);
				$$->ctes = $2;
				$$->recursive = false;
				$$->location = @1;
			*/ }
		| WITH_LA cte_list
			{ /*C
				$$ = makeNode(WithClause);
				$$->ctes = $2;
				$$->recursive = false;
				$$->location = @1;
			*/ }
		| WITH RECURSIVE cte_list
			{ /*C
				$$ = makeNode(WithClause);
				$$->ctes = $3;
				$$->recursive = true;
				$$->location = @1;
			*/ }
		;

cte_list:
		common_table_expr						{ $$ = []Node{$1} }
		| cte_list ',' common_table_expr		{ $$ = append($1, $3) }
		;

common_table_expr:  name opt_name_list AS opt_materialized '(' PreparableStmt ')' opt_search_clause opt_cycle_clause
			{ /*C
				CommonTableExpr *n = makeNode(CommonTableExpr);

				n->ctename = $1;
				n->aliascolnames = $2;
				n->ctematerialized = $4;
				n->ctequery = $6;
				n->search_clause = castNode(CTESearchClause, $8);
				n->cycle_clause = castNode(CTECycleClause, $9);
				n->location = @1;
				$$ = (Node *) n;
			*/ }
		;

opt_materialized:
		MATERIALIZED							{ /*C $$ = CTEMaterializeAlways; */ }
		| NOT MATERIALIZED						{ /*C $$ = CTEMaterializeNever; */ }
		| /*EMPTY*/								{ /*C $$ = CTEMaterializeDefault; */ }
		;

opt_search_clause:
		SEARCH DEPTH FIRST_P BY columnList SET ColId
			{ /*C
				CTESearchClause *n = makeNode(CTESearchClause);

				n->search_col_list = $5;
				n->search_breadth_first = false;
				n->search_seq_column = $7;
				n->location = @1;
				$$ = (Node *) n;
			*/ }
		| SEARCH BREADTH FIRST_P BY columnList SET ColId
			{ /*C
				CTESearchClause *n = makeNode(CTESearchClause);

				n->search_col_list = $5;
				n->search_breadth_first = true;
				n->search_seq_column = $7;
				n->location = @1;
				$$ = (Node *) n;
			*/ }
		| /*EMPTY*/
			{ $$ = nil }
		;

opt_cycle_clause:
		CYCLE columnList SET ColId TO AexprConst DEFAULT AexprConst USING ColId
			{ /*C
				CTECycleClause *n = makeNode(CTECycleClause);

				n->cycle_col_list = $2;
				n->cycle_mark_column = $4;
				n->cycle_mark_value = $6;
				n->cycle_mark_default = $8;
				n->cycle_path_column = $10;
				n->location = @1;
				$$ = (Node *) n;
			*/ }
		| CYCLE columnList SET ColId USING ColId
			{ /*C
				CTECycleClause *n = makeNode(CTECycleClause);

				n->cycle_col_list = $2;
				n->cycle_mark_column = $4;
				n->cycle_mark_value = makeBoolAConst(true, -1);
				n->cycle_mark_default = makeBoolAConst(false, -1);
				n->cycle_path_column = $6;
				n->location = @1;
				$$ = (Node *) n;
			*/ }
		| /*EMPTY*/
			{ $$ = nil }
		;

opt_with_clause:
		with_clause								{ $$ = $1 }
		| /*EMPTY*/								{ $$ = nil }
		;

into_clause:
			INTO OptTempTableName
				{ /*C
					$$ = makeNode(IntoClause);
					$$->rel = $2;
					$$->colNames = NIL;
					$$->options = NIL;
					$$->onCommit = ONCOMMIT_NOOP;
					$$->tableSpaceName = NULL;
					$$->viewQuery = NULL;
					$$->skipData = false;
				*/ }
			| /*EMPTY*/
				{ $$ = nil }
		;

/*
 * Redundancy here is needed to avoid shift/reduce conflicts,
 * since TEMP is not a reserved word.  See also OptTemp.
 */
OptTempTableName:
			TEMPORARY opt_table qualified_name
				{ /*C
					$$ = $3;
					$$->relpersistence = RELPERSISTENCE_TEMP;
				*/ }
			| TEMP opt_table qualified_name
				{ /*C
					$$ = $3;
					$$->relpersistence = RELPERSISTENCE_TEMP;
				*/ }
			| LOCAL TEMPORARY opt_table qualified_name
				{ /*C
					$$ = $4;
					$$->relpersistence = RELPERSISTENCE_TEMP;
				*/ }
			| LOCAL TEMP opt_table qualified_name
				{ /*C
					$$ = $4;
					$$->relpersistence = RELPERSISTENCE_TEMP;
				*/ }
			| GLOBAL TEMPORARY opt_table qualified_name
				{ /*C
					ereport(WARNING,
							(errmsg("GLOBAL is deprecated in temporary table creation"),
							 parser_errposition(@1)));
					$$ = $4;
					$$->relpersistence = RELPERSISTENCE_TEMP;
				*/ }
			| GLOBAL TEMP opt_table qualified_name
				{ /*C
					ereport(WARNING,
							(errmsg("GLOBAL is deprecated in temporary table creation"),
							 parser_errposition(@1)));
					$$ = $4;
					$$->relpersistence = RELPERSISTENCE_TEMP;
				*/ }
			| UNLOGGED opt_table qualified_name
				{ /*C
					$$ = $3;
					$$->relpersistence = RELPERSISTENCE_UNLOGGED;
				*/ }
			| TABLE qualified_name
				{ /*C
					$$ = $2;
					$$->relpersistence = RELPERSISTENCE_PERMANENT;
				*/ }
			| qualified_name
				{ /*C
					$$ = $1;
					$$->relpersistence = RELPERSISTENCE_PERMANENT;
				*/ }
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
			DISTINCT								{ /*C $$ = list_make1(NIL); */ }
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
				{ /*C
					$$ = makeNode(SortBy);
					$$->node = $1;
					$$->sortby_dir = SORTBY_USING;
					$$->sortby_nulls = $4;
					$$->useOp = $3;
					$$->location = @3;
				*/ }
			| a_expr opt_asc_desc opt_nulls_order
				{ /*C
					$$ = makeNode(SortBy);
					$$->node = $1;
					$$->sortby_dir = $2;
					$$->sortby_nulls = $3;
					$$->useOp = NIL;
					$$->location = -1;		/* no operator * /
				*/ }
		;


select_limit:
			limit_clause offset_clause
				{ /*C
					$$ = $1;
					($$)->limitOffset = $2;
				*/ }
			| offset_clause limit_clause
				{ /*C
					$$ = $2;
					($$)->limitOffset = $1;
				*/ }
			| limit_clause
				{ $$ = $1 }
			| offset_clause
				{ /*C
					SelectLimit *n = (SelectLimit *) palloc(sizeof(SelectLimit));

					n->limitOffset = $1;
					n->limitCount = NULL;
					n->limitOption = LIMIT_OPTION_COUNT;
					$$ = n;
				*/ }
		;

opt_select_limit:
			select_limit						{ $$ = $1 }
			| /* EMPTY */						{ $$ = nil }
		;

limit_clause:
			LIMIT select_limit_value
				{ /*C
					SelectLimit *n = (SelectLimit *) palloc(sizeof(SelectLimit));

					n->limitOffset = NULL;
					n->limitCount = $2;
					n->limitOption = LIMIT_OPTION_COUNT;
					$$ = n;
				*/ }
			| LIMIT select_limit_value ',' select_offset_value
				{ /*C
					/* Disabled because it was too confusing, bjm 2002-02-18 * /
					ereport(ERROR,
							(errcode(ERRCODE_SYNTAX_ERROR),
							 errmsg("LIMIT #,# syntax is not supported"),
							 errhint("Use separate LIMIT and OFFSET clauses."),
							 parser_errposition(@1)));
				*/ }
			/* SQL:2008 syntax */
			/* to avoid shift/reduce conflicts, handle the optional value with
			 * a separate production rather than an opt_ expression.  The fact
			 * that ONLY is fully reserved means that this way, we defer any
			 * decision about what rule reduces ROW or ROWS to the point where
			 * we can see the ONLY token in the lookahead slot.
			 */
			| FETCH first_or_next select_fetch_first_value row_or_rows ONLY
				{ /*C
					SelectLimit *n = (SelectLimit *) palloc(sizeof(SelectLimit));

					n->limitOffset = NULL;
					n->limitCount = $3;
					n->limitOption = LIMIT_OPTION_COUNT;
					$$ = n;
				*/ }
			| FETCH first_or_next select_fetch_first_value row_or_rows WITH TIES
				{ /*C
					SelectLimit *n = (SelectLimit *) palloc(sizeof(SelectLimit));

					n->limitOffset = NULL;
					n->limitCount = $3;
					n->limitOption = LIMIT_OPTION_WITH_TIES;
					$$ = n;
				*/ }
			| FETCH first_or_next row_or_rows ONLY
				{ /*C
					SelectLimit *n = (SelectLimit *) palloc(sizeof(SelectLimit));

					n->limitOffset = NULL;
					n->limitCount = makeIntConst(1, -1);
					n->limitOption = LIMIT_OPTION_COUNT;
					$$ = n;
				*/ }
			| FETCH first_or_next row_or_rows WITH TIES
				{ /*C
					SelectLimit *n = (SelectLimit *) palloc(sizeof(SelectLimit));

					n->limitOffset = NULL;
					n->limitCount = makeIntConst(1, -1);
					n->limitOption = LIMIT_OPTION_WITH_TIES;
					$$ = n;
				*/ }
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
				{ /*C
					/* LIMIT ALL is represented as a NULL constant * /
					$$ = makeNullAConst(@1);
				*/ }
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
				{ /*C $$ = (Node *) makeSimpleA_Expr(AEXPR_OP, "+", NULL, $2, @1); */ }
			| '-' I_or_F_const
				{ /*C $$ = doNegate($2, @1); */ }
		;

I_or_F_const:
			Iconst									{ /*C $$ = makeIntConst($1,@1); */ }
			| FCONST								{ /*C $$ = makeFloatConst($1,@1); */ }
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
				{ /*C
					GroupClause *n = (GroupClause *) palloc(sizeof(GroupClause));

					n->distinct = $3 == SET_QUANTIFIER_DISTINCT;
					n->list = $4;
					$$ = n;
				*/ }
			| /*EMPTY*/
				{ /*C
					GroupClause *n = (GroupClause *) palloc(sizeof(GroupClause));

					n->distinct = false;
					n->list = NIL;
					$$ = n;
				*/ }
		;

group_by_list:
			group_by_item							{ $$ = []Node{$1} }
			| group_by_list ',' group_by_item		{ /*C $$ = lappend($1,$3); */ }
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
				{ /*C
					$$ = (Node *) makeGroupingSet(GROUPING_SET_EMPTY, NIL, @1);
				*/ }
		;

/*
 * These hacks rely on setting precedence of CUBE and ROLLUP below that of '(',
 * so that they shift in these rules rather than reducing the conflicting
 * unreserved_keyword rule.
 */

rollup_clause:
			ROLLUP '(' expr_list ')'
				{ /*C
					$$ = (Node *) makeGroupingSet(GROUPING_SET_ROLLUP, $3, @1);
				*/ }
		;

cube_clause:
			CUBE '(' expr_list ')'
				{ /*C
					$$ = (Node *) makeGroupingSet(GROUPING_SET_CUBE, $3, @1);
				*/ }
		;

grouping_sets_clause:
			GROUPING SETS '(' group_by_list ')'
				{ /*C
					$$ = (Node *) makeGroupingSet(GROUPING_SET_SETS, $4, @1);
				*/ }
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
				{ /*C
					LockingClause *n = makeNode(LockingClause);

					n->lockedRels = $2;
					n->strength = $1;
					n->waitPolicy = $3;
					$$ = (Node *) n;
				*/ }
		;

for_locking_strength:
			FOR UPDATE							{ /*C $$ = LCS_FORUPDATE; */ }
			| FOR NO KEY UPDATE					{ /*C $$ = LCS_FORNOKEYUPDATE; */ }
			| FOR SHARE							{ /*C $$ = LCS_FORSHARE; */ }
			| FOR KEY SHARE						{ /*C $$ = LCS_FORKEYSHARE; */ }
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
				{ /*C
					SelectStmt *n = makeNode(SelectStmt);

					n->valuesLists = list_make1($3);
					$$ = (Node *) n;
				*/ }
			| values_clause ',' '(' expr_list ')'
				{ /*C
					SelectStmt *n = (SelectStmt *) $1;

					n->valuesLists = lappend(n->valuesLists, $4);
					$$ = (Node *) n;
				*/ }
		;

