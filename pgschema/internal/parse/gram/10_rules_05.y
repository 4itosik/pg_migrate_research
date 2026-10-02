/* gram.y lines 7043-8804 */
/*****************************************************************************
 *
 * COMMENT ON <object> IS <text>
 *
 *****************************************************************************/

CommentStmt:
			COMMENT ON object_type_any_name any_name IS comment_text
				{ /*C
					CommentStmt *n = makeNode(CommentStmt);

					n->objtype = $3;
					n->object = (Node *) $4;
					n->comment = $6;
					$$ = (Node *) n;
				*/ }
			| COMMENT ON COLUMN any_name IS comment_text
				{ /*C
					CommentStmt *n = makeNode(CommentStmt);

					n->objtype = OBJECT_COLUMN;
					n->object = (Node *) $4;
					n->comment = $6;
					$$ = (Node *) n;
				*/ }
			| COMMENT ON object_type_name name IS comment_text
				{ /*C
					CommentStmt *n = makeNode(CommentStmt);

					n->objtype = $3;
					n->object = (Node *) makeString($4);
					n->comment = $6;
					$$ = (Node *) n;
				*/ }
			| COMMENT ON TYPE_P Typename IS comment_text
				{ /*C
					CommentStmt *n = makeNode(CommentStmt);

					n->objtype = OBJECT_TYPE;
					n->object = (Node *) $4;
					n->comment = $6;
					$$ = (Node *) n;
				*/ }
			| COMMENT ON DOMAIN_P Typename IS comment_text
				{ /*C
					CommentStmt *n = makeNode(CommentStmt);

					n->objtype = OBJECT_DOMAIN;
					n->object = (Node *) $4;
					n->comment = $6;
					$$ = (Node *) n;
				*/ }
			| COMMENT ON AGGREGATE aggregate_with_argtypes IS comment_text
				{ /*C
					CommentStmt *n = makeNode(CommentStmt);

					n->objtype = OBJECT_AGGREGATE;
					n->object = (Node *) $4;
					n->comment = $6;
					$$ = (Node *) n;
				*/ }
			| COMMENT ON FUNCTION function_with_argtypes IS comment_text
				{ /*C
					CommentStmt *n = makeNode(CommentStmt);

					n->objtype = OBJECT_FUNCTION;
					n->object = (Node *) $4;
					n->comment = $6;
					$$ = (Node *) n;
				*/ }
			| COMMENT ON OPERATOR operator_with_argtypes IS comment_text
				{ /*C
					CommentStmt *n = makeNode(CommentStmt);

					n->objtype = OBJECT_OPERATOR;
					n->object = (Node *) $4;
					n->comment = $6;
					$$ = (Node *) n;
				*/ }
			| COMMENT ON CONSTRAINT name ON any_name IS comment_text
				{ /*C
					CommentStmt *n = makeNode(CommentStmt);

					n->objtype = OBJECT_TABCONSTRAINT;
					n->object = (Node *) lappend($6, makeString($4));
					n->comment = $8;
					$$ = (Node *) n;
				*/ }
			| COMMENT ON CONSTRAINT name ON DOMAIN_P any_name IS comment_text
				{ /*C
					CommentStmt *n = makeNode(CommentStmt);

					n->objtype = OBJECT_DOMCONSTRAINT;
					/*
					 * should use Typename not any_name in the production, but
					 * there's a shift/reduce conflict if we do that, so fix it
					 * up here.
					 * /
					n->object = (Node *) list_make2(makeTypeNameFromNameList($7), makeString($4));
					n->comment = $9;
					$$ = (Node *) n;
				*/ }
			| COMMENT ON object_type_name_on_any_name name ON any_name IS comment_text
				{ /*C
					CommentStmt *n = makeNode(CommentStmt);

					n->objtype = $3;
					n->object = (Node *) lappend($6, makeString($4));
					n->comment = $8;
					$$ = (Node *) n;
				*/ }
			| COMMENT ON PROCEDURE function_with_argtypes IS comment_text
				{ /*C
					CommentStmt *n = makeNode(CommentStmt);

					n->objtype = OBJECT_PROCEDURE;
					n->object = (Node *) $4;
					n->comment = $6;
					$$ = (Node *) n;
				*/ }
			| COMMENT ON ROUTINE function_with_argtypes IS comment_text
				{ /*C
					CommentStmt *n = makeNode(CommentStmt);

					n->objtype = OBJECT_ROUTINE;
					n->object = (Node *) $4;
					n->comment = $6;
					$$ = (Node *) n;
				*/ }
			| COMMENT ON TRANSFORM FOR Typename LANGUAGE name IS comment_text
				{ /*C
					CommentStmt *n = makeNode(CommentStmt);

					n->objtype = OBJECT_TRANSFORM;
					n->object = (Node *) list_make2($5, makeString($7));
					n->comment = $9;
					$$ = (Node *) n;
				*/ }
			| COMMENT ON OPERATOR CLASS any_name USING name IS comment_text
				{ /*C
					CommentStmt *n = makeNode(CommentStmt);

					n->objtype = OBJECT_OPCLASS;
					n->object = (Node *) lcons(makeString($7), $5);
					n->comment = $9;
					$$ = (Node *) n;
				*/ }
			| COMMENT ON OPERATOR FAMILY any_name USING name IS comment_text
				{ /*C
					CommentStmt *n = makeNode(CommentStmt);

					n->objtype = OBJECT_OPFAMILY;
					n->object = (Node *) lcons(makeString($7), $5);
					n->comment = $9;
					$$ = (Node *) n;
				*/ }
			| COMMENT ON LARGE_P OBJECT_P NumericOnly IS comment_text
				{ /*C
					CommentStmt *n = makeNode(CommentStmt);

					n->objtype = OBJECT_LARGEOBJECT;
					n->object = (Node *) $5;
					n->comment = $7;
					$$ = (Node *) n;
				*/ }
			| COMMENT ON CAST '(' Typename AS Typename ')' IS comment_text
				{ /*C
					CommentStmt *n = makeNode(CommentStmt);

					n->objtype = OBJECT_CAST;
					n->object = (Node *) list_make2($5, $7);
					n->comment = $10;
					$$ = (Node *) n;
				*/ }
		;

comment_text:
			Sconst								{ $$ = $1 }
			| NULL_P							{ $$ = "" }
		;


/*****************************************************************************
 *
 *  SECURITY LABEL [FOR <provider>] ON <object> IS <label>
 *
 *  As with COMMENT ON, <object> can refer to various types of database
 *  objects (e.g. TABLE, COLUMN, etc.).
 *
 *****************************************************************************/

SecLabelStmt:
			SECURITY LABEL opt_provider ON object_type_any_name any_name
			IS security_label
				{ /*C
					SecLabelStmt *n = makeNode(SecLabelStmt);

					n->provider = $3;
					n->objtype = $5;
					n->object = (Node *) $6;
					n->label = $8;
					$$ = (Node *) n;
				*/ }
			| SECURITY LABEL opt_provider ON COLUMN any_name
			  IS security_label
				{ /*C
					SecLabelStmt *n = makeNode(SecLabelStmt);

					n->provider = $3;
					n->objtype = OBJECT_COLUMN;
					n->object = (Node *) $6;
					n->label = $8;
					$$ = (Node *) n;
				*/ }
			| SECURITY LABEL opt_provider ON object_type_name name
			  IS security_label
				{ /*C
					SecLabelStmt *n = makeNode(SecLabelStmt);

					n->provider = $3;
					n->objtype = $5;
					n->object = (Node *) makeString($6);
					n->label = $8;
					$$ = (Node *) n;
				*/ }
			| SECURITY LABEL opt_provider ON TYPE_P Typename
			  IS security_label
				{ /*C
					SecLabelStmt *n = makeNode(SecLabelStmt);

					n->provider = $3;
					n->objtype = OBJECT_TYPE;
					n->object = (Node *) $6;
					n->label = $8;
					$$ = (Node *) n;
				*/ }
			| SECURITY LABEL opt_provider ON DOMAIN_P Typename
			  IS security_label
				{ /*C
					SecLabelStmt *n = makeNode(SecLabelStmt);

					n->provider = $3;
					n->objtype = OBJECT_DOMAIN;
					n->object = (Node *) $6;
					n->label = $8;
					$$ = (Node *) n;
				*/ }
			| SECURITY LABEL opt_provider ON AGGREGATE aggregate_with_argtypes
			  IS security_label
				{ /*C
					SecLabelStmt *n = makeNode(SecLabelStmt);

					n->provider = $3;
					n->objtype = OBJECT_AGGREGATE;
					n->object = (Node *) $6;
					n->label = $8;
					$$ = (Node *) n;
				*/ }
			| SECURITY LABEL opt_provider ON FUNCTION function_with_argtypes
			  IS security_label
				{ /*C
					SecLabelStmt *n = makeNode(SecLabelStmt);

					n->provider = $3;
					n->objtype = OBJECT_FUNCTION;
					n->object = (Node *) $6;
					n->label = $8;
					$$ = (Node *) n;
				*/ }
			| SECURITY LABEL opt_provider ON LARGE_P OBJECT_P NumericOnly
			  IS security_label
				{ /*C
					SecLabelStmt *n = makeNode(SecLabelStmt);

					n->provider = $3;
					n->objtype = OBJECT_LARGEOBJECT;
					n->object = (Node *) $7;
					n->label = $9;
					$$ = (Node *) n;
				*/ }
			| SECURITY LABEL opt_provider ON PROCEDURE function_with_argtypes
			  IS security_label
				{ /*C
					SecLabelStmt *n = makeNode(SecLabelStmt);

					n->provider = $3;
					n->objtype = OBJECT_PROCEDURE;
					n->object = (Node *) $6;
					n->label = $8;
					$$ = (Node *) n;
				*/ }
			| SECURITY LABEL opt_provider ON ROUTINE function_with_argtypes
			  IS security_label
				{ /*C
					SecLabelStmt *n = makeNode(SecLabelStmt);

					n->provider = $3;
					n->objtype = OBJECT_ROUTINE;
					n->object = (Node *) $6;
					n->label = $8;
					$$ = (Node *) n;
				*/ }
		;

opt_provider:	FOR NonReservedWord_or_Sconst	{ $$ = $2 }
				| /* EMPTY */					{ $$ = "" }
		;

security_label:	Sconst				{ $$ = $1 }
				| NULL_P			{ $$ = "" }
		;

/*****************************************************************************
 *
 *		QUERY:
 *			fetch/move
 *
 *****************************************************************************/

FetchStmt:	FETCH fetch_args
				{ /*C
					FetchStmt *n = (FetchStmt *) $2;

					n->ismove = false;
					$$ = (Node *) n;
				*/ }
			| MOVE fetch_args
				{ /*C
					FetchStmt *n = (FetchStmt *) $2;

					n->ismove = true;
					$$ = (Node *) n;
				*/ }
		;

fetch_args:	cursor_name
				{ /*C
					FetchStmt *n = makeNode(FetchStmt);

					n->portalname = $1;
					n->direction = FETCH_FORWARD;
					n->howMany = 1;
					$$ = (Node *) n;
				*/ }
			| from_in cursor_name
				{ /*C
					FetchStmt *n = makeNode(FetchStmt);

					n->portalname = $2;
					n->direction = FETCH_FORWARD;
					n->howMany = 1;
					$$ = (Node *) n;
				*/ }
			| NEXT opt_from_in cursor_name
				{ /*C
					FetchStmt *n = makeNode(FetchStmt);

					n->portalname = $3;
					n->direction = FETCH_FORWARD;
					n->howMany = 1;
					$$ = (Node *) n;
				*/ }
			| PRIOR opt_from_in cursor_name
				{ /*C
					FetchStmt *n = makeNode(FetchStmt);

					n->portalname = $3;
					n->direction = FETCH_BACKWARD;
					n->howMany = 1;
					$$ = (Node *) n;
				*/ }
			| FIRST_P opt_from_in cursor_name
				{ /*C
					FetchStmt *n = makeNode(FetchStmt);

					n->portalname = $3;
					n->direction = FETCH_ABSOLUTE;
					n->howMany = 1;
					$$ = (Node *) n;
				*/ }
			| LAST_P opt_from_in cursor_name
				{ /*C
					FetchStmt *n = makeNode(FetchStmt);

					n->portalname = $3;
					n->direction = FETCH_ABSOLUTE;
					n->howMany = -1;
					$$ = (Node *) n;
				*/ }
			| ABSOLUTE_P SignedIconst opt_from_in cursor_name
				{ /*C
					FetchStmt *n = makeNode(FetchStmt);

					n->portalname = $4;
					n->direction = FETCH_ABSOLUTE;
					n->howMany = $2;
					$$ = (Node *) n;
				*/ }
			| RELATIVE_P SignedIconst opt_from_in cursor_name
				{ /*C
					FetchStmt *n = makeNode(FetchStmt);

					n->portalname = $4;
					n->direction = FETCH_RELATIVE;
					n->howMany = $2;
					$$ = (Node *) n;
				*/ }
			| SignedIconst opt_from_in cursor_name
				{ /*C
					FetchStmt *n = makeNode(FetchStmt);

					n->portalname = $3;
					n->direction = FETCH_FORWARD;
					n->howMany = $1;
					$$ = (Node *) n;
				*/ }
			| ALL opt_from_in cursor_name
				{ /*C
					FetchStmt *n = makeNode(FetchStmt);

					n->portalname = $3;
					n->direction = FETCH_FORWARD;
					n->howMany = FETCH_ALL;
					$$ = (Node *) n;
				*/ }
			| FORWARD opt_from_in cursor_name
				{ /*C
					FetchStmt *n = makeNode(FetchStmt);

					n->portalname = $3;
					n->direction = FETCH_FORWARD;
					n->howMany = 1;
					$$ = (Node *) n;
				*/ }
			| FORWARD SignedIconst opt_from_in cursor_name
				{ /*C
					FetchStmt *n = makeNode(FetchStmt);

					n->portalname = $4;
					n->direction = FETCH_FORWARD;
					n->howMany = $2;
					$$ = (Node *) n;
				*/ }
			| FORWARD ALL opt_from_in cursor_name
				{ /*C
					FetchStmt *n = makeNode(FetchStmt);

					n->portalname = $4;
					n->direction = FETCH_FORWARD;
					n->howMany = FETCH_ALL;
					$$ = (Node *) n;
				*/ }
			| BACKWARD opt_from_in cursor_name
				{ /*C
					FetchStmt *n = makeNode(FetchStmt);

					n->portalname = $3;
					n->direction = FETCH_BACKWARD;
					n->howMany = 1;
					$$ = (Node *) n;
				*/ }
			| BACKWARD SignedIconst opt_from_in cursor_name
				{ /*C
					FetchStmt *n = makeNode(FetchStmt);

					n->portalname = $4;
					n->direction = FETCH_BACKWARD;
					n->howMany = $2;
					$$ = (Node *) n;
				*/ }
			| BACKWARD ALL opt_from_in cursor_name
				{ /*C
					FetchStmt *n = makeNode(FetchStmt);

					n->portalname = $4;
					n->direction = FETCH_BACKWARD;
					n->howMany = FETCH_ALL;
					$$ = (Node *) n;
				*/ }
		;

from_in:	FROM
			| IN_P
		;

opt_from_in:	from_in
			| /* EMPTY */
		;


/*****************************************************************************
 *
 * GRANT and REVOKE statements
 *
 *****************************************************************************/

GrantStmt:	GRANT privileges ON privilege_target TO grantee_list
			opt_grant_grant_option opt_granted_by
				{ /*C
					GrantStmt *n = makeNode(GrantStmt);

					n->is_grant = true;
					n->privileges = $2;
					n->targtype = ($4)->targtype;
					n->objtype = ($4)->objtype;
					n->objects = ($4)->objs;
					n->grantees = $6;
					n->grant_option = $7;
					n->grantor = $8;
					$$ = (Node *) n;
				*/ }
		;

RevokeStmt:
			REVOKE privileges ON privilege_target
			FROM grantee_list opt_granted_by opt_drop_behavior
				{ /*C
					GrantStmt *n = makeNode(GrantStmt);

					n->is_grant = false;
					n->grant_option = false;
					n->privileges = $2;
					n->targtype = ($4)->targtype;
					n->objtype = ($4)->objtype;
					n->objects = ($4)->objs;
					n->grantees = $6;
					n->grantor = $7;
					n->behavior = $8;
					$$ = (Node *) n;
				*/ }
			| REVOKE GRANT OPTION FOR privileges ON privilege_target
			FROM grantee_list opt_granted_by opt_drop_behavior
				{ /*C
					GrantStmt *n = makeNode(GrantStmt);

					n->is_grant = false;
					n->grant_option = true;
					n->privileges = $5;
					n->targtype = ($7)->targtype;
					n->objtype = ($7)->objtype;
					n->objects = ($7)->objs;
					n->grantees = $9;
					n->grantor = $10;
					n->behavior = $11;
					$$ = (Node *) n;
				*/ }
		;


/*
 * Privilege names are represented as strings; the validity of the privilege
 * names gets checked at execution.  This is a bit annoying but we have little
 * choice because of the syntactic conflict with lists of role names in
 * GRANT/REVOKE.  What's more, we have to call out in the "privilege"
 * production any reserved keywords that need to be usable as privilege names.
 */

/* either ALL [PRIVILEGES] or a list of individual privileges */
privileges: privilege_list
				{ $$ = $1 }
			| ALL
				{ $$ = nil }
			| ALL PRIVILEGES
				{ $$ = nil }
			| ALL '(' columnList ')'
				{ /*C
					AccessPriv *n = makeNode(AccessPriv);

					n->priv_name = NULL;
					n->cols = $3;
					$$ = list_make1(n);
				*/ }
			| ALL PRIVILEGES '(' columnList ')'
				{ /*C
					AccessPriv *n = makeNode(AccessPriv);

					n->priv_name = NULL;
					n->cols = $4;
					$$ = list_make1(n);
				*/ }
		;

privilege_list:	privilege							{ $$ = []Node{$1} }
			| privilege_list ',' privilege			{ $$ = append($1, $3) }
		;

privilege:	SELECT opt_column_list
			{ /*C
				AccessPriv *n = makeNode(AccessPriv);

				n->priv_name = pstrdup($1);
				n->cols = $2;
				$$ = n;
			*/ }
		| REFERENCES opt_column_list
			{ /*C
				AccessPriv *n = makeNode(AccessPriv);

				n->priv_name = pstrdup($1);
				n->cols = $2;
				$$ = n;
			*/ }
		| CREATE opt_column_list
			{ /*C
				AccessPriv *n = makeNode(AccessPriv);

				n->priv_name = pstrdup($1);
				n->cols = $2;
				$$ = n;
			*/ }
		| ALTER SYSTEM_P
			{ /*C
				AccessPriv *n = makeNode(AccessPriv);
				n->priv_name = pstrdup("alter system");
				n->cols = NIL;
				$$ = n;
			*/ }
		| ColId opt_column_list
			{ /*C
				AccessPriv *n = makeNode(AccessPriv);

				n->priv_name = $1;
				n->cols = $2;
				$$ = n;
			*/ }
		;

parameter_name_list:
		parameter_name
			{ /*C
				$$ = list_make1(makeString($1));
			*/ }
		| parameter_name_list ',' parameter_name
			{ /*C
				$$ = lappend($1, makeString($3));
			*/ }
		;

parameter_name:
		ColId
			{ $$ = $1 }
		| parameter_name '.' ColId
			{ /*C
				$$ = psprintf("%s.%s", $1, $3);
			*/ }
		;


/* Don't bother trying to fold the first two rules into one using
 * opt_table.  You're going to get conflicts.
 */
privilege_target:
			qualified_name_list
				{ /*C
					PrivTarget *n = (PrivTarget *) palloc(sizeof(PrivTarget));

					n->targtype = ACL_TARGET_OBJECT;
					n->objtype = OBJECT_TABLE;
					n->objs = $1;
					$$ = n;
				*/ }
			| TABLE qualified_name_list
				{ /*C
					PrivTarget *n = (PrivTarget *) palloc(sizeof(PrivTarget));

					n->targtype = ACL_TARGET_OBJECT;
					n->objtype = OBJECT_TABLE;
					n->objs = $2;
					$$ = n;
				*/ }
			| SEQUENCE qualified_name_list
				{ /*C
					PrivTarget *n = (PrivTarget *) palloc(sizeof(PrivTarget));

					n->targtype = ACL_TARGET_OBJECT;
					n->objtype = OBJECT_SEQUENCE;
					n->objs = $2;
					$$ = n;
				*/ }
			| FOREIGN DATA_P WRAPPER name_list
				{ /*C
					PrivTarget *n = (PrivTarget *) palloc(sizeof(PrivTarget));

					n->targtype = ACL_TARGET_OBJECT;
					n->objtype = OBJECT_FDW;
					n->objs = $4;
					$$ = n;
				*/ }
			| FOREIGN SERVER name_list
				{ /*C
					PrivTarget *n = (PrivTarget *) palloc(sizeof(PrivTarget));

					n->targtype = ACL_TARGET_OBJECT;
					n->objtype = OBJECT_FOREIGN_SERVER;
					n->objs = $3;
					$$ = n;
				*/ }
			| FUNCTION function_with_argtypes_list
				{ /*C
					PrivTarget *n = (PrivTarget *) palloc(sizeof(PrivTarget));

					n->targtype = ACL_TARGET_OBJECT;
					n->objtype = OBJECT_FUNCTION;
					n->objs = $2;
					$$ = n;
				*/ }
			| PROCEDURE function_with_argtypes_list
				{ /*C
					PrivTarget *n = (PrivTarget *) palloc(sizeof(PrivTarget));

					n->targtype = ACL_TARGET_OBJECT;
					n->objtype = OBJECT_PROCEDURE;
					n->objs = $2;
					$$ = n;
				*/ }
			| ROUTINE function_with_argtypes_list
				{ /*C
					PrivTarget *n = (PrivTarget *) palloc(sizeof(PrivTarget));

					n->targtype = ACL_TARGET_OBJECT;
					n->objtype = OBJECT_ROUTINE;
					n->objs = $2;
					$$ = n;
				*/ }
			| DATABASE name_list
				{ /*C
					PrivTarget *n = (PrivTarget *) palloc(sizeof(PrivTarget));

					n->targtype = ACL_TARGET_OBJECT;
					n->objtype = OBJECT_DATABASE;
					n->objs = $2;
					$$ = n;
				*/ }
			| DOMAIN_P any_name_list
				{ /*C
					PrivTarget *n = (PrivTarget *) palloc(sizeof(PrivTarget));

					n->targtype = ACL_TARGET_OBJECT;
					n->objtype = OBJECT_DOMAIN;
					n->objs = $2;
					$$ = n;
				*/ }
			| LANGUAGE name_list
				{ /*C
					PrivTarget *n = (PrivTarget *) palloc(sizeof(PrivTarget));

					n->targtype = ACL_TARGET_OBJECT;
					n->objtype = OBJECT_LANGUAGE;
					n->objs = $2;
					$$ = n;
				*/ }
			| LARGE_P OBJECT_P NumericOnly_list
				{ /*C
					PrivTarget *n = (PrivTarget *) palloc(sizeof(PrivTarget));

					n->targtype = ACL_TARGET_OBJECT;
					n->objtype = OBJECT_LARGEOBJECT;
					n->objs = $3;
					$$ = n;
				*/ }
			| PARAMETER parameter_name_list
				{ /*C
					PrivTarget *n = (PrivTarget *) palloc(sizeof(PrivTarget));
					n->targtype = ACL_TARGET_OBJECT;
					n->objtype = OBJECT_PARAMETER_ACL;
					n->objs = $2;
					$$ = n;
				*/ }
			| SCHEMA name_list
				{ /*C
					PrivTarget *n = (PrivTarget *) palloc(sizeof(PrivTarget));

					n->targtype = ACL_TARGET_OBJECT;
					n->objtype = OBJECT_SCHEMA;
					n->objs = $2;
					$$ = n;
				*/ }
			| TABLESPACE name_list
				{ /*C
					PrivTarget *n = (PrivTarget *) palloc(sizeof(PrivTarget));

					n->targtype = ACL_TARGET_OBJECT;
					n->objtype = OBJECT_TABLESPACE;
					n->objs = $2;
					$$ = n;
				*/ }
			| TYPE_P any_name_list
				{ /*C
					PrivTarget *n = (PrivTarget *) palloc(sizeof(PrivTarget));

					n->targtype = ACL_TARGET_OBJECT;
					n->objtype = OBJECT_TYPE;
					n->objs = $2;
					$$ = n;
				*/ }
			| ALL TABLES IN_P SCHEMA name_list
				{ /*C
					PrivTarget *n = (PrivTarget *) palloc(sizeof(PrivTarget));

					n->targtype = ACL_TARGET_ALL_IN_SCHEMA;
					n->objtype = OBJECT_TABLE;
					n->objs = $5;
					$$ = n;
				*/ }
			| ALL SEQUENCES IN_P SCHEMA name_list
				{ /*C
					PrivTarget *n = (PrivTarget *) palloc(sizeof(PrivTarget));

					n->targtype = ACL_TARGET_ALL_IN_SCHEMA;
					n->objtype = OBJECT_SEQUENCE;
					n->objs = $5;
					$$ = n;
				*/ }
			| ALL FUNCTIONS IN_P SCHEMA name_list
				{ /*C
					PrivTarget *n = (PrivTarget *) palloc(sizeof(PrivTarget));

					n->targtype = ACL_TARGET_ALL_IN_SCHEMA;
					n->objtype = OBJECT_FUNCTION;
					n->objs = $5;
					$$ = n;
				*/ }
			| ALL PROCEDURES IN_P SCHEMA name_list
				{ /*C
					PrivTarget *n = (PrivTarget *) palloc(sizeof(PrivTarget));

					n->targtype = ACL_TARGET_ALL_IN_SCHEMA;
					n->objtype = OBJECT_PROCEDURE;
					n->objs = $5;
					$$ = n;
				*/ }
			| ALL ROUTINES IN_P SCHEMA name_list
				{ /*C
					PrivTarget *n = (PrivTarget *) palloc(sizeof(PrivTarget));

					n->targtype = ACL_TARGET_ALL_IN_SCHEMA;
					n->objtype = OBJECT_ROUTINE;
					n->objs = $5;
					$$ = n;
				*/ }
		;


grantee_list:
			grantee									{ $$ = []Node{$1} }
			| grantee_list ',' grantee				{ $$ = append($1, $3) }
		;

grantee:
			RoleSpec								{ $$ = $1 }
			| GROUP_P RoleSpec						{ $$ = $2 }
		;


opt_grant_grant_option:
			WITH GRANT OPTION { $$ = true }
			| /*EMPTY*/ { $$ = false }
		;

/*****************************************************************************
 *
 * GRANT and REVOKE ROLE statements
 *
 *****************************************************************************/

GrantRoleStmt:
			GRANT privilege_list TO role_list opt_granted_by
				{ /*C
					GrantRoleStmt *n = makeNode(GrantRoleStmt);

					n->is_grant = true;
					n->granted_roles = $2;
					n->grantee_roles = $4;
					n->opt = NIL;
					n->grantor = $5;
					$$ = (Node *) n;
				*/ }
		  | GRANT privilege_list TO role_list WITH grant_role_opt_list opt_granted_by
				{ /*C
					GrantRoleStmt *n = makeNode(GrantRoleStmt);

					n->is_grant = true;
					n->granted_roles = $2;
					n->grantee_roles = $4;
					n->opt = $6;
					n->grantor = $7;
					$$ = (Node *) n;
				*/ }
		;

RevokeRoleStmt:
			REVOKE privilege_list FROM role_list opt_granted_by opt_drop_behavior
				{ /*C
					GrantRoleStmt *n = makeNode(GrantRoleStmt);

					n->is_grant = false;
					n->opt = NIL;
					n->granted_roles = $2;
					n->grantee_roles = $4;
					n->grantor = $5;
					n->behavior = $6;
					$$ = (Node *) n;
				*/ }
			| REVOKE ColId OPTION FOR privilege_list FROM role_list opt_granted_by opt_drop_behavior
				{ /*C
					GrantRoleStmt *n = makeNode(GrantRoleStmt);
					DefElem *opt;

					opt = makeDefElem(pstrdup($2),
									  (Node *) makeBoolean(false), @2);
					n->is_grant = false;
					n->opt = list_make1(opt);
					n->granted_roles = $5;
					n->grantee_roles = $7;
					n->grantor = $8;
					n->behavior = $9;
					$$ = (Node *) n;
				*/ }
		;

grant_role_opt_list:
			grant_role_opt_list ',' grant_role_opt	{ $$ = append($1, $3) }
			| grant_role_opt						{ $$ = []Node{$1} }
		;

grant_role_opt:
		ColLabel grant_role_opt_value
			{ /*C
				$$ = makeDefElem(pstrdup($1), $2, @1);
			*/ }
		;

grant_role_opt_value:
		OPTION			{ /*C $$ = (Node *) makeBoolean(true); */ }
		| TRUE_P		{ /*C $$ = (Node *) makeBoolean(true); */ }
		| FALSE_P		{ /*C $$ = (Node *) makeBoolean(false); */ }
		;

opt_granted_by: GRANTED BY RoleSpec						{ $$ = $3 }
			| /*EMPTY*/									{ $$ = nil }
		;

/*****************************************************************************
 *
 * ALTER DEFAULT PRIVILEGES statement
 *
 *****************************************************************************/

AlterDefaultPrivilegesStmt:
			ALTER DEFAULT PRIVILEGES DefACLOptionList DefACLAction
				{ /*C
					AlterDefaultPrivilegesStmt *n = makeNode(AlterDefaultPrivilegesStmt);

					n->options = $4;
					n->action = (GrantStmt *) $5;
					$$ = (Node *) n;
				*/ }
		;

DefACLOptionList:
			DefACLOptionList DefACLOption			{ $$ = append($1, $2) }
			| /* EMPTY */							{ $$ = nil }
		;

DefACLOption:
			IN_P SCHEMA name_list
				{ /*C
					$$ = makeDefElem("schemas", (Node *) $3, @1);
				*/ }
			| FOR ROLE role_list
				{ /*C
					$$ = makeDefElem("roles", (Node *) $3, @1);
				*/ }
			| FOR USER role_list
				{ /*C
					$$ = makeDefElem("roles", (Node *) $3, @1);
				*/ }
		;

/*
 * This should match GRANT/REVOKE, except that individual target objects
 * are not mentioned and we only allow a subset of object types.
 */
DefACLAction:
			GRANT privileges ON defacl_privilege_target TO grantee_list
			opt_grant_grant_option
				{ /*C
					GrantStmt *n = makeNode(GrantStmt);

					n->is_grant = true;
					n->privileges = $2;
					n->targtype = ACL_TARGET_DEFAULTS;
					n->objtype = $4;
					n->objects = NIL;
					n->grantees = $6;
					n->grant_option = $7;
					$$ = (Node *) n;
				*/ }
			| REVOKE privileges ON defacl_privilege_target
			FROM grantee_list opt_drop_behavior
				{ /*C
					GrantStmt *n = makeNode(GrantStmt);

					n->is_grant = false;
					n->grant_option = false;
					n->privileges = $2;
					n->targtype = ACL_TARGET_DEFAULTS;
					n->objtype = $4;
					n->objects = NIL;
					n->grantees = $6;
					n->behavior = $7;
					$$ = (Node *) n;
				*/ }
			| REVOKE GRANT OPTION FOR privileges ON defacl_privilege_target
			FROM grantee_list opt_drop_behavior
				{ /*C
					GrantStmt *n = makeNode(GrantStmt);

					n->is_grant = false;
					n->grant_option = true;
					n->privileges = $5;
					n->targtype = ACL_TARGET_DEFAULTS;
					n->objtype = $7;
					n->objects = NIL;
					n->grantees = $9;
					n->behavior = $10;
					$$ = (Node *) n;
				*/ }
		;

defacl_privilege_target:
			TABLES			{ /*C $$ = OBJECT_TABLE; */ }
			| FUNCTIONS		{ /*C $$ = OBJECT_FUNCTION; */ }
			| ROUTINES		{ /*C $$ = OBJECT_FUNCTION; */ }
			| SEQUENCES		{ /*C $$ = OBJECT_SEQUENCE; */ }
			| TYPES_P		{ /*C $$ = OBJECT_TYPE; */ }
			| SCHEMAS		{ /*C $$ = OBJECT_SCHEMA; */ }
		;


/*****************************************************************************
 *
 *		QUERY: CREATE INDEX
 *
 * Note: we cannot put TABLESPACE clause after WHERE clause unless we are
 * willing to make TABLESPACE a fully reserved word.
 *****************************************************************************/

IndexStmt:	CREATE opt_unique INDEX opt_concurrently opt_single_name
			ON relation_expr access_method_clause '(' index_params ')'
			opt_include opt_unique_null_treatment opt_reloptions OptTableSpace where_clause
				{ /*C
					IndexStmt *n = makeNode(IndexStmt);

					n->unique = $2;
					n->concurrent = $4;
					n->idxname = $5;
					n->relation = $7;
					n->accessMethod = $8;
					n->indexParams = $10;
					n->indexIncludingParams = $12;
					n->nulls_not_distinct = !$13;
					n->options = $14;
					n->tableSpace = $15;
					n->whereClause = $16;
					n->excludeOpNames = NIL;
					n->idxcomment = NULL;
					n->indexOid = InvalidOid;
					n->oldNumber = InvalidRelFileNumber;
					n->oldCreateSubid = InvalidSubTransactionId;
					n->oldFirstRelfilelocatorSubid = InvalidSubTransactionId;
					n->primary = false;
					n->isconstraint = false;
					n->deferrable = false;
					n->initdeferred = false;
					n->transformed = false;
					n->if_not_exists = false;
					n->reset_default_tblspc = false;
					$$ = (Node *) n;
				*/ }
			| CREATE opt_unique INDEX opt_concurrently IF_P NOT EXISTS name
			ON relation_expr access_method_clause '(' index_params ')'
			opt_include opt_unique_null_treatment opt_reloptions OptTableSpace where_clause
				{ /*C
					IndexStmt *n = makeNode(IndexStmt);

					n->unique = $2;
					n->concurrent = $4;
					n->idxname = $8;
					n->relation = $10;
					n->accessMethod = $11;
					n->indexParams = $13;
					n->indexIncludingParams = $15;
					n->nulls_not_distinct = !$16;
					n->options = $17;
					n->tableSpace = $18;
					n->whereClause = $19;
					n->excludeOpNames = NIL;
					n->idxcomment = NULL;
					n->indexOid = InvalidOid;
					n->oldNumber = InvalidRelFileNumber;
					n->oldCreateSubid = InvalidSubTransactionId;
					n->oldFirstRelfilelocatorSubid = InvalidSubTransactionId;
					n->primary = false;
					n->isconstraint = false;
					n->deferrable = false;
					n->initdeferred = false;
					n->transformed = false;
					n->if_not_exists = true;
					n->reset_default_tblspc = false;
					$$ = (Node *) n;
				*/ }
		;

opt_unique:
			UNIQUE									{ $$ = true }
			| /*EMPTY*/								{ $$ = false }
		;

access_method_clause:
			USING name								{ $$ = $2 }
			| /*EMPTY*/								{ /*C $$ = DEFAULT_INDEX_TYPE; */ }
		;

index_params:	index_elem							{ $$ = []Node{$1} }
			| index_params ',' index_elem			{ $$ = append($1, $3) }
		;


index_elem_options:
	opt_collate opt_qualified_name opt_asc_desc opt_nulls_order
		{ /*C
			$$ = makeNode(IndexElem);
			$$->name = NULL;
			$$->expr = NULL;
			$$->indexcolname = NULL;
			$$->collation = $1;
			$$->opclass = $2;
			$$->opclassopts = NIL;
			$$->ordering = $3;
			$$->nulls_ordering = $4;
		*/ }
	| opt_collate any_name reloptions opt_asc_desc opt_nulls_order
		{ /*C
			$$ = makeNode(IndexElem);
			$$->name = NULL;
			$$->expr = NULL;
			$$->indexcolname = NULL;
			$$->collation = $1;
			$$->opclass = $2;
			$$->opclassopts = $3;
			$$->ordering = $4;
			$$->nulls_ordering = $5;
		*/ }
	;

/*
 * Index attributes can be either simple column references, or arbitrary
 * expressions in parens.  For backwards-compatibility reasons, we allow
 * an expression that's just a function call to be written without parens.
 */
index_elem: ColId index_elem_options
				{ /*C
					$$ = $2;
					$$->name = $1;
				*/ }
			| func_expr_windowless index_elem_options
				{ /*C
					$$ = $2;
					$$->expr = $1;
				*/ }
			| '(' a_expr ')' index_elem_options
				{ /*C
					$$ = $4;
					$$->expr = $2;
				*/ }
		;

opt_include:		INCLUDE '(' index_including_params ')'			{ $$ = $3 }
			 |		/* EMPTY */						{ $$ = nil }
		;

index_including_params:	index_elem						{ $$ = []Node{$1} }
			| index_including_params ',' index_elem		{ $$ = append($1, $3) }
		;

opt_collate: COLLATE any_name						{ $$ = $2 }
			| /*EMPTY*/								{ $$ = nil }
		;


opt_asc_desc: ASC							{ /*C $$ = SORTBY_ASC; */ }
			| DESC							{ /*C $$ = SORTBY_DESC; */ }
			| /*EMPTY*/						{ /*C $$ = SORTBY_DEFAULT; */ }
		;

opt_nulls_order: NULLS_LA FIRST_P			{ /*C $$ = SORTBY_NULLS_FIRST; */ }
			| NULLS_LA LAST_P				{ /*C $$ = SORTBY_NULLS_LAST; */ }
			| /*EMPTY*/						{ /*C $$ = SORTBY_NULLS_DEFAULT; */ }
		;


/*****************************************************************************
 *
 *		QUERY:
 *				create [or replace] function <fname>
 *						[(<type-1> { , <type-n>})]
 *						returns <type-r>
 *						as <filename or code in language as appropriate>
 *						language <lang> [with parameters]
 *
 *****************************************************************************/

CreateFunctionStmt:
			CREATE opt_or_replace FUNCTION func_name func_args_with_defaults
			RETURNS func_return opt_createfunc_opt_list opt_routine_body
				{ /*C
					CreateFunctionStmt *n = makeNode(CreateFunctionStmt);

					n->is_procedure = false;
					n->replace = $2;
					n->funcname = $4;
					n->parameters = $5;
					n->returnType = $7;
					n->options = $8;
					n->sql_body = $9;
					$$ = (Node *) n;
				*/ }
			| CREATE opt_or_replace FUNCTION func_name func_args_with_defaults
			  RETURNS TABLE '(' table_func_column_list ')' opt_createfunc_opt_list opt_routine_body
				{ /*C
					CreateFunctionStmt *n = makeNode(CreateFunctionStmt);

					n->is_procedure = false;
					n->replace = $2;
					n->funcname = $4;
					n->parameters = mergeTableFuncParameters($5, $9);
					n->returnType = TableFuncTypeName($9);
					n->returnType->location = @7;
					n->options = $11;
					n->sql_body = $12;
					$$ = (Node *) n;
				*/ }
			| CREATE opt_or_replace FUNCTION func_name func_args_with_defaults
			  opt_createfunc_opt_list opt_routine_body
				{ /*C
					CreateFunctionStmt *n = makeNode(CreateFunctionStmt);

					n->is_procedure = false;
					n->replace = $2;
					n->funcname = $4;
					n->parameters = $5;
					n->returnType = NULL;
					n->options = $6;
					n->sql_body = $7;
					$$ = (Node *) n;
				*/ }
			| CREATE opt_or_replace PROCEDURE func_name func_args_with_defaults
			  opt_createfunc_opt_list opt_routine_body
				{ /*C
					CreateFunctionStmt *n = makeNode(CreateFunctionStmt);

					n->is_procedure = true;
					n->replace = $2;
					n->funcname = $4;
					n->parameters = $5;
					n->returnType = NULL;
					n->options = $6;
					n->sql_body = $7;
					$$ = (Node *) n;
				*/ }
		;

opt_or_replace:
			OR REPLACE								{ $$ = true }
			| /*EMPTY*/								{ $$ = false }
		;

func_args:	'(' func_args_list ')'					{ $$ = $2 }
			| '(' ')'								{ $$ = nil }
		;

func_args_list:
			func_arg								{ $$ = []Node{$1} }
			| func_args_list ',' func_arg			{ $$ = append($1, $3) }
		;

function_with_argtypes_list:
			function_with_argtypes					{ $$ = []Node{$1} }
			| function_with_argtypes_list ',' function_with_argtypes
													{ $$ = append($1, $3) }
		;

function_with_argtypes:
			func_name func_args
				{ /*C
					ObjectWithArgs *n = makeNode(ObjectWithArgs);

					n->objname = $1;
					n->objargs = extractArgTypes($2);
					n->objfuncargs = $2;
					$$ = n;
				*/ }
			/*
			 * Because of reduce/reduce conflicts, we can't use func_name
			 * below, but we can write it out the long way, which actually
			 * allows more cases.
			 */
			| type_func_name_keyword
				{ /*C
					ObjectWithArgs *n = makeNode(ObjectWithArgs);

					n->objname = list_make1(makeString(pstrdup($1)));
					n->args_unspecified = true;
					$$ = n;
				*/ }
			| ColId
				{ /*C
					ObjectWithArgs *n = makeNode(ObjectWithArgs);

					n->objname = list_make1(makeString($1));
					n->args_unspecified = true;
					$$ = n;
				*/ }
			| ColId indirection
				{ /*C
					ObjectWithArgs *n = makeNode(ObjectWithArgs);

					n->objname = check_func_name(lcons(makeString($1), $2),
												  yyscanner);
					n->args_unspecified = true;
					$$ = n;
				*/ }
		;

/*
 * func_args_with_defaults is separate because we only want to accept
 * defaults in CREATE FUNCTION, not in ALTER etc.
 */
func_args_with_defaults:
		'(' func_args_with_defaults_list ')'		{ $$ = $2 }
		| '(' ')'									{ $$ = nil }
		;

func_args_with_defaults_list:
		func_arg_with_default						{ $$ = []Node{$1} }
		| func_args_with_defaults_list ',' func_arg_with_default
													{ $$ = append($1, $3) }
		;

/*
 * The style with arg_class first is SQL99 standard, but Oracle puts
 * param_name first; accept both since it's likely people will try both
 * anyway.  Don't bother trying to save productions by letting arg_class
 * have an empty alternative ... you'll get shift/reduce conflicts.
 *
 * We can catch over-specified arguments here if we want to,
 * but for now better to silently swallow typmod, etc.
 * - thomas 2000-03-22
 */
func_arg:
			arg_class param_name func_type
				{ /*C
					FunctionParameter *n = makeNode(FunctionParameter);

					n->name = $2;
					n->argType = $3;
					n->mode = $1;
					n->defexpr = NULL;
					$$ = n;
				*/ }
			| param_name arg_class func_type
				{ /*C
					FunctionParameter *n = makeNode(FunctionParameter);

					n->name = $1;
					n->argType = $3;
					n->mode = $2;
					n->defexpr = NULL;
					$$ = n;
				*/ }
			| param_name func_type
				{ /*C
					FunctionParameter *n = makeNode(FunctionParameter);

					n->name = $1;
					n->argType = $2;
					n->mode = FUNC_PARAM_DEFAULT;
					n->defexpr = NULL;
					$$ = n;
				*/ }
			| arg_class func_type
				{ /*C
					FunctionParameter *n = makeNode(FunctionParameter);

					n->name = NULL;
					n->argType = $2;
					n->mode = $1;
					n->defexpr = NULL;
					$$ = n;
				*/ }
			| func_type
				{ /*C
					FunctionParameter *n = makeNode(FunctionParameter);

					n->name = NULL;
					n->argType = $1;
					n->mode = FUNC_PARAM_DEFAULT;
					n->defexpr = NULL;
					$$ = n;
				*/ }
		;

/* INOUT is SQL99 standard, IN OUT is for Oracle compatibility */
arg_class:	IN_P								{ $$ = int32(FUNC_PARAM_IN) }
			| OUT_P								{ $$ = int32(FUNC_PARAM_OUT) }
			| INOUT								{ $$ = int32(FUNC_PARAM_INOUT) }
			| IN_P OUT_P						{ $$ = int32(FUNC_PARAM_INOUT) }
			| VARIADIC							{ $$ = int32(FUNC_PARAM_VARIADIC) }
		;

/*
 * Ideally param_name should be ColId, but that causes too many conflicts.
 */
param_name:	type_function_name
		;

func_return:
			func_type
				{ /*C
					/* We can catch over-specified results here if we want to,
					 * but for now better to silently swallow typmod, etc.
					 * - thomas 2000-03-22
					 * /
					$$ = $1;
				*/ }
		;

/*
 * We would like to make the %TYPE productions here be ColId attrs etc,
 * but that causes reduce/reduce conflicts.  type_function_name
 * is next best choice.
 */
func_type:	Typename								{ $$ = $1 }
			| type_function_name attrs '%' TYPE_P
				{ /*C
					$$ = makeTypeNameFromNameList(lcons(makeString($1), $2));
					$$->pct_type = true;
					$$->location = @1;
				*/ }
			| SETOF type_function_name attrs '%' TYPE_P
				{ /*C
					$$ = makeTypeNameFromNameList(lcons(makeString($2), $3));
					$$->pct_type = true;
					$$->setof = true;
					$$->location = @2;
				*/ }
		;

func_arg_with_default:
		func_arg
				{ $$ = $1 }
		| func_arg DEFAULT a_expr
				{ /*C
					$$ = $1;
					$$->defexpr = $3;
				*/ }
		| func_arg '=' a_expr
				{ /*C
					$$ = $1;
					$$->defexpr = $3;
				*/ }
		;

/* Aggregate args can be most things that function args can be */
aggr_arg:	func_arg
				{ /*C
					if (!($1->mode == FUNC_PARAM_DEFAULT ||
						  $1->mode == FUNC_PARAM_IN ||
						  $1->mode == FUNC_PARAM_VARIADIC))
						ereport(ERROR,
								(errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
								 errmsg("aggregates cannot have output arguments"),
								 parser_errposition(@1)));
					$$ = $1;
				*/ }
		;

/*
 * The SQL standard offers no guidance on how to declare aggregate argument
 * lists, since it doesn't have CREATE AGGREGATE etc.  We accept these cases:
 *
 * (*)									- normal agg with no args
 * (aggr_arg,...)						- normal agg with args
 * (ORDER BY aggr_arg,...)				- ordered-set agg with no direct args
 * (aggr_arg,... ORDER BY aggr_arg,...)	- ordered-set agg with direct args
 *
 * The zero-argument case is spelled with '*' for consistency with COUNT(*).
 *
 * An additional restriction is that if the direct-args list ends in a
 * VARIADIC item, the ordered-args list must contain exactly one item that
 * is also VARIADIC with the same type.  This allows us to collapse the two
 * VARIADIC items into one, which is necessary to represent the aggregate in
 * pg_proc.  We check this at the grammar stage so that we can return a list
 * in which the second VARIADIC item is already discarded, avoiding extra work
 * in cases such as DROP AGGREGATE.
 *
 * The return value of this production is a two-element list, in which the
 * first item is a sublist of FunctionParameter nodes (with any duplicate
 * VARIADIC item already dropped, as per above) and the second is an Integer
 * node, containing -1 if there was no ORDER BY and otherwise the number
 * of argument declarations before the ORDER BY.  (If this number is equal
 * to the first sublist's length, then we dropped a duplicate VARIADIC item.)
 * This representation is passed as-is to CREATE AGGREGATE; for operations
 * on existing aggregates, we can just apply extractArgTypes to the first
 * sublist.
 */
aggr_args:	'(' '*' ')'
				{ /*C
					$$ = list_make2(NIL, makeInteger(-1));
				*/ }
			| '(' aggr_args_list ')'
				{ /*C
					$$ = list_make2($2, makeInteger(-1));
				*/ }
			| '(' ORDER BY aggr_args_list ')'
				{ /*C
					$$ = list_make2($4, makeInteger(0));
				*/ }
			| '(' aggr_args_list ORDER BY aggr_args_list ')'
				{ /*C
					/* this is the only case requiring consistency checking * /
					$$ = makeOrderedSetArgs($2, $5, yyscanner);
				*/ }
		;

aggr_args_list:
			aggr_arg								{ $$ = []Node{$1} }
			| aggr_args_list ',' aggr_arg			{ $$ = append($1, $3) }
		;

aggregate_with_argtypes:
			func_name aggr_args
				{ /*C
					ObjectWithArgs *n = makeNode(ObjectWithArgs);

					n->objname = $1;
					n->objargs = extractAggrArgTypes($2);
					n->objfuncargs = (List *) linitial($2);
					$$ = n;
				*/ }
		;

aggregate_with_argtypes_list:
			aggregate_with_argtypes					{ $$ = []Node{$1} }
			| aggregate_with_argtypes_list ',' aggregate_with_argtypes
													{ $$ = append($1, $3) }
		;

opt_createfunc_opt_list:
			createfunc_opt_list
			| /*EMPTY*/ { $$ = nil }
	;

createfunc_opt_list:
			/* Must be at least one to prevent conflict */
			createfunc_opt_item						{ $$ = []Node{$1} }
			| createfunc_opt_list createfunc_opt_item { $$ = append($1, $2) }
	;

/*
 * Options common to both CREATE FUNCTION and ALTER FUNCTION
 */
common_func_opt_item:
			CALLED ON NULL_P INPUT_P
				{ /*C
					$$ = makeDefElem("strict", (Node *) makeBoolean(false), @1);
				*/ }
			| RETURNS NULL_P ON NULL_P INPUT_P
				{ /*C
					$$ = makeDefElem("strict", (Node *) makeBoolean(true), @1);
				*/ }
			| STRICT_P
				{ /*C
					$$ = makeDefElem("strict", (Node *) makeBoolean(true), @1);
				*/ }
			| IMMUTABLE
				{ /*C
					$$ = makeDefElem("volatility", (Node *) makeString("immutable"), @1);
				*/ }
			| STABLE
				{ /*C
					$$ = makeDefElem("volatility", (Node *) makeString("stable"), @1);
				*/ }
			| VOLATILE
				{ /*C
					$$ = makeDefElem("volatility", (Node *) makeString("volatile"), @1);
				*/ }
			| EXTERNAL SECURITY DEFINER
				{ /*C
					$$ = makeDefElem("security", (Node *) makeBoolean(true), @1);
				*/ }
			| EXTERNAL SECURITY INVOKER
				{ /*C
					$$ = makeDefElem("security", (Node *) makeBoolean(false), @1);
				*/ }
			| SECURITY DEFINER
				{ /*C
					$$ = makeDefElem("security", (Node *) makeBoolean(true), @1);
				*/ }
			| SECURITY INVOKER
				{ /*C
					$$ = makeDefElem("security", (Node *) makeBoolean(false), @1);
				*/ }
			| LEAKPROOF
				{ /*C
					$$ = makeDefElem("leakproof", (Node *) makeBoolean(true), @1);
				*/ }
			| NOT LEAKPROOF
				{ /*C
					$$ = makeDefElem("leakproof", (Node *) makeBoolean(false), @1);
				*/ }
			| COST NumericOnly
				{ /*C
					$$ = makeDefElem("cost", (Node *) $2, @1);
				*/ }
			| ROWS NumericOnly
				{ /*C
					$$ = makeDefElem("rows", (Node *) $2, @1);
				*/ }
			| SUPPORT any_name
				{ /*C
					$$ = makeDefElem("support", (Node *) $2, @1);
				*/ }
			| FunctionSetResetClause
				{ /*C
					/* we abuse the normal content of a DefElem here * /
					$$ = makeDefElem("set", (Node *) $1, @1);
				*/ }
			| PARALLEL ColId
				{ /*C
					$$ = makeDefElem("parallel", (Node *) makeString($2), @1);
				*/ }
		;

createfunc_opt_item:
			AS func_as
				{ /*C
					$$ = makeDefElem("as", (Node *) $2, @1);
				*/ }
			| LANGUAGE NonReservedWord_or_Sconst
				{ /*C
					$$ = makeDefElem("language", (Node *) makeString($2), @1);
				*/ }
			| TRANSFORM transform_type_list
				{ /*C
					$$ = makeDefElem("transform", (Node *) $2, @1);
				*/ }
			| WINDOW
				{ /*C
					$$ = makeDefElem("window", (Node *) makeBoolean(true), @1);
				*/ }
			| common_func_opt_item
				{ $$ = $1 }
		;

func_as:	Sconst						{ /*C $$ = list_make1(makeString($1)); */ }
			| Sconst ',' Sconst
				{ /*C
					$$ = list_make2(makeString($1), makeString($3));
				*/ }
		;

ReturnStmt:	RETURN a_expr
				{ /*C
					ReturnStmt *r = makeNode(ReturnStmt);

					r->returnval = (Node *) $2;
					$$ = (Node *) r;
				*/ }
		;

opt_routine_body:
			ReturnStmt
				{ $$ = $1 }
			| BEGIN_P ATOMIC routine_body_stmt_list END_P
				{ /*C
					/*
					 * A compound statement is stored as a single-item list
					 * containing the list of statements as its member.  That
					 * way, the parse analysis code can tell apart an empty
					 * body from no body at all.
					 * /
					$$ = (Node *) list_make1($3);
				*/ }
			| /*EMPTY*/
				{ $$ = nil }
		;

routine_body_stmt_list:
			routine_body_stmt_list routine_body_stmt ';'
				{ /*C
					/* As in stmtmulti, discard empty statements * /
					if ($2 != NULL)
						$$ = lappend($1, $2);
					else
						$$ = $1;
				*/ }
			| /*EMPTY*/
				{ $$ = nil }
		;

routine_body_stmt:
			stmt
			| ReturnStmt
		;

transform_type_list:
			FOR TYPE_P Typename { $$ = []Node{$3} }
			| transform_type_list ',' FOR TYPE_P Typename { $$ = append($1, $5) }
		;

opt_definition:
			WITH definition							{ $$ = $2 }
			| /*EMPTY*/								{ $$ = nil }
		;

table_func_column:	param_name func_type
				{ /*C
					FunctionParameter *n = makeNode(FunctionParameter);

					n->name = $1;
					n->argType = $2;
					n->mode = FUNC_PARAM_TABLE;
					n->defexpr = NULL;
					$$ = n;
				*/ }
		;

table_func_column_list:
			table_func_column
				{ $$ = []Node{$1} }
			| table_func_column_list ',' table_func_column
				{ $$ = append($1, $3) }
		;

