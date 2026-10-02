/* gram.y lines 7043-8804 */
/*****************************************************************************
 *
 * COMMENT ON <object> IS <text>
 *
 *****************************************************************************/

CommentStmt:
			COMMENT ON object_type_any_name any_name IS comment_text
				{
					n := &CommentStmt{}

					n.Objtype = ObjectType($3)
					n.Object = listNode($4)
					n.Comment = $6
					$$ = n
				}
			| COMMENT ON COLUMN any_name IS comment_text
				{
					n := &CommentStmt{}

					n.Objtype = OBJECT_COLUMN
					n.Object = listNode($4)
					n.Comment = $6
					$$ = n
				}
			| COMMENT ON object_type_name name IS comment_text
				{
					n := &CommentStmt{}

					n.Objtype = ObjectType($3)
					n.Object = makeString($4, @4)
					n.Comment = $6
					$$ = n
				}
			| COMMENT ON TYPE_P Typename IS comment_text
				{
					n := &CommentStmt{}

					n.Objtype = OBJECT_TYPE
					n.Object = $4
					n.Comment = $6
					$$ = n
				}
			| COMMENT ON DOMAIN_P Typename IS comment_text
				{
					n := &CommentStmt{}

					n.Objtype = OBJECT_DOMAIN
					n.Object = $4
					n.Comment = $6
					$$ = n
				}
			| COMMENT ON AGGREGATE aggregate_with_argtypes IS comment_text
				{
					n := &CommentStmt{}

					n.Objtype = OBJECT_AGGREGATE
					n.Object = $4
					n.Comment = $6
					$$ = n
				}
			| COMMENT ON FUNCTION function_with_argtypes IS comment_text
				{
					n := &CommentStmt{}

					n.Objtype = OBJECT_FUNCTION
					n.Object = $4
					n.Comment = $6
					$$ = n
				}
			| COMMENT ON OPERATOR operator_with_argtypes IS comment_text
				{
					n := &CommentStmt{}

					n.Objtype = OBJECT_OPERATOR
					n.Object = $4
					n.Comment = $6
					$$ = n
				}
			| COMMENT ON CONSTRAINT name ON any_name IS comment_text
				{
					n := &CommentStmt{}

					n.Objtype = OBJECT_TABCONSTRAINT
					n.Object = listNode(append($6, makeString($4, @4)))
					n.Comment = $8
					$$ = n
				}
			| COMMENT ON CONSTRAINT name ON DOMAIN_P any_name IS comment_text
				{
					n := &CommentStmt{}

					n.Objtype = OBJECT_DOMCONSTRAINT
					/*
					 * should use Typename not any_name in the production, but
					 * there's a shift/reduce conflict if we do that, so fix it
					 * up here.
					 */
					n.Object = listNode([]Node{makeTypeNameFromNameList($7), makeString($4, @4)})
					n.Comment = $9
					$$ = n
				}
			| COMMENT ON object_type_name_on_any_name name ON any_name IS comment_text
				{
					n := &CommentStmt{}

					n.Objtype = ObjectType($3)
					n.Object = listNode(append($6, makeString($4, @4)))
					n.Comment = $8
					$$ = n
				}
			| COMMENT ON PROCEDURE function_with_argtypes IS comment_text
				{
					n := &CommentStmt{}

					n.Objtype = OBJECT_PROCEDURE
					n.Object = $4
					n.Comment = $6
					$$ = n
				}
			| COMMENT ON ROUTINE function_with_argtypes IS comment_text
				{
					n := &CommentStmt{}

					n.Objtype = OBJECT_ROUTINE
					n.Object = $4
					n.Comment = $6
					$$ = n
				}
			| COMMENT ON TRANSFORM FOR Typename LANGUAGE name IS comment_text
				{
					n := &CommentStmt{}

					n.Objtype = OBJECT_TRANSFORM
					n.Object = listNode([]Node{$5, makeString($7, @7)})
					n.Comment = $9
					$$ = n
				}
			| COMMENT ON OPERATOR CLASS any_name USING name IS comment_text
				{
					n := &CommentStmt{}

					n.Objtype = OBJECT_OPCLASS
					n.Object = listNode(append([]Node{makeString($7, @7)}, $5...))
					n.Comment = $9
					$$ = n
				}
			| COMMENT ON OPERATOR FAMILY any_name USING name IS comment_text
				{
					n := &CommentStmt{}

					n.Objtype = OBJECT_OPFAMILY
					n.Object = listNode(append([]Node{makeString($7, @7)}, $5...))
					n.Comment = $9
					$$ = n
				}
			| COMMENT ON LARGE_P OBJECT_P NumericOnly IS comment_text
				{
					n := &CommentStmt{}

					n.Objtype = OBJECT_LARGEOBJECT
					n.Object = $5
					n.Comment = $7
					$$ = n
				}
			| COMMENT ON CAST '(' Typename AS Typename ')' IS comment_text
				{
					n := &CommentStmt{}

					n.Objtype = OBJECT_CAST
					n.Object = listNode([]Node{$5, $7})
					n.Comment = $10
					$$ = n
				}
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
				{
					n := &SecLabelStmt{}

					n.Provider = $3
					n.Objtype = ObjectType($5)
					n.Object = listNode($6)
					n.Label = $8
					$$ = n
				}
			| SECURITY LABEL opt_provider ON COLUMN any_name
			  IS security_label
				{
					n := &SecLabelStmt{}

					n.Provider = $3
					n.Objtype = OBJECT_COLUMN
					n.Object = listNode($6)
					n.Label = $8
					$$ = n
				}
			| SECURITY LABEL opt_provider ON object_type_name name
			  IS security_label
				{
					n := &SecLabelStmt{}

					n.Provider = $3
					n.Objtype = ObjectType($5)
					n.Object = makeString($6, @6)
					n.Label = $8
					$$ = n
				}
			| SECURITY LABEL opt_provider ON TYPE_P Typename
			  IS security_label
				{
					n := &SecLabelStmt{}

					n.Provider = $3
					n.Objtype = OBJECT_TYPE
					n.Object = $6
					n.Label = $8
					$$ = n
				}
			| SECURITY LABEL opt_provider ON DOMAIN_P Typename
			  IS security_label
				{
					n := &SecLabelStmt{}

					n.Provider = $3
					n.Objtype = OBJECT_DOMAIN
					n.Object = $6
					n.Label = $8
					$$ = n
				}
			| SECURITY LABEL opt_provider ON AGGREGATE aggregate_with_argtypes
			  IS security_label
				{
					n := &SecLabelStmt{}

					n.Provider = $3
					n.Objtype = OBJECT_AGGREGATE
					n.Object = $6
					n.Label = $8
					$$ = n
				}
			| SECURITY LABEL opt_provider ON FUNCTION function_with_argtypes
			  IS security_label
				{
					n := &SecLabelStmt{}

					n.Provider = $3
					n.Objtype = OBJECT_FUNCTION
					n.Object = $6
					n.Label = $8
					$$ = n
				}
			| SECURITY LABEL opt_provider ON LARGE_P OBJECT_P NumericOnly
			  IS security_label
				{
					n := &SecLabelStmt{}

					n.Provider = $3
					n.Objtype = OBJECT_LARGEOBJECT
					n.Object = $7
					n.Label = $9
					$$ = n
				}
			| SECURITY LABEL opt_provider ON PROCEDURE function_with_argtypes
			  IS security_label
				{
					n := &SecLabelStmt{}

					n.Provider = $3
					n.Objtype = OBJECT_PROCEDURE
					n.Object = $6
					n.Label = $8
					$$ = n
				}
			| SECURITY LABEL opt_provider ON ROUTINE function_with_argtypes
			  IS security_label
				{
					n := &SecLabelStmt{}

					n.Provider = $3
					n.Objtype = OBJECT_ROUTINE
					n.Object = $6
					n.Label = $8
					$$ = n
				}
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
				{
					n := as[*FetchStmt]($2)

					n.Ismove = false
					$$ = n
				}
			| MOVE fetch_args
				{
					n := as[*FetchStmt]($2)

					n.Ismove = true
					$$ = n
				}
		;

fetch_args:	cursor_name
				{
					n := &FetchStmt{}

					n.Portalname = $1
					n.Direction = FETCH_FORWARD
					n.HowMany = 1
					$$ = n
				}
			| from_in cursor_name
				{
					n := &FetchStmt{}

					n.Portalname = $2
					n.Direction = FETCH_FORWARD
					n.HowMany = 1
					$$ = n
				}
			| NEXT opt_from_in cursor_name
				{
					n := &FetchStmt{}

					n.Portalname = $3
					n.Direction = FETCH_FORWARD
					n.HowMany = 1
					$$ = n
				}
			| PRIOR opt_from_in cursor_name
				{
					n := &FetchStmt{}

					n.Portalname = $3
					n.Direction = FETCH_BACKWARD
					n.HowMany = 1
					$$ = n
				}
			| FIRST_P opt_from_in cursor_name
				{
					n := &FetchStmt{}

					n.Portalname = $3
					n.Direction = FETCH_ABSOLUTE
					n.HowMany = 1
					$$ = n
				}
			| LAST_P opt_from_in cursor_name
				{
					n := &FetchStmt{}

					n.Portalname = $3
					n.Direction = FETCH_ABSOLUTE
					n.HowMany = -1
					$$ = n
				}
			| ABSOLUTE_P SignedIconst opt_from_in cursor_name
				{
					n := &FetchStmt{}

					n.Portalname = $4
					n.Direction = FETCH_ABSOLUTE
					n.HowMany = int64($2)
					$$ = n
				}
			| RELATIVE_P SignedIconst opt_from_in cursor_name
				{
					n := &FetchStmt{}

					n.Portalname = $4
					n.Direction = FETCH_RELATIVE
					n.HowMany = int64($2)
					$$ = n
				}
			| SignedIconst opt_from_in cursor_name
				{
					n := &FetchStmt{}

					n.Portalname = $3
					n.Direction = FETCH_FORWARD
					n.HowMany = int64($1)
					$$ = n
				}
			| ALL opt_from_in cursor_name
				{
					n := &FetchStmt{}

					n.Portalname = $3
					n.Direction = FETCH_FORWARD
					n.HowMany = fetchAll
					$$ = n
				}
			| FORWARD opt_from_in cursor_name
				{
					n := &FetchStmt{}

					n.Portalname = $3
					n.Direction = FETCH_FORWARD
					n.HowMany = 1
					$$ = n
				}
			| FORWARD SignedIconst opt_from_in cursor_name
				{
					n := &FetchStmt{}

					n.Portalname = $4
					n.Direction = FETCH_FORWARD
					n.HowMany = int64($2)
					$$ = n
				}
			| FORWARD ALL opt_from_in cursor_name
				{
					n := &FetchStmt{}

					n.Portalname = $4
					n.Direction = FETCH_FORWARD
					n.HowMany = fetchAll
					$$ = n
				}
			| BACKWARD opt_from_in cursor_name
				{
					n := &FetchStmt{}

					n.Portalname = $3
					n.Direction = FETCH_BACKWARD
					n.HowMany = 1
					$$ = n
				}
			| BACKWARD SignedIconst opt_from_in cursor_name
				{
					n := &FetchStmt{}

					n.Portalname = $4
					n.Direction = FETCH_BACKWARD
					n.HowMany = int64($2)
					$$ = n
				}
			| BACKWARD ALL opt_from_in cursor_name
				{
					n := &FetchStmt{}

					n.Portalname = $4
					n.Direction = FETCH_BACKWARD
					n.HowMany = fetchAll
					$$ = n
				}
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
				{
					n := &GrantStmt{}

					n.IsGrant = true
					n.Privileges = $2
					n.Targtype = as[*privTarget]($4).targtype
					n.Objtype = as[*privTarget]($4).objtype
					n.Objects = as[*privTarget]($4).objs
					n.Grantees = $6
					n.GrantOption = $7
					n.Grantor = as[*RoleSpec]($8)
					$$ = n
				}
		;

RevokeStmt:
			REVOKE privileges ON privilege_target
			FROM grantee_list opt_granted_by opt_drop_behavior
				{
					n := &GrantStmt{}

					n.IsGrant = false
					n.GrantOption = false
					n.Privileges = $2
					n.Targtype = as[*privTarget]($4).targtype
					n.Objtype = as[*privTarget]($4).objtype
					n.Objects = as[*privTarget]($4).objs
					n.Grantees = $6
					n.Grantor = as[*RoleSpec]($7)
					n.Behavior = DropBehavior($8)
					$$ = n
				}
			| REVOKE GRANT OPTION FOR privileges ON privilege_target
			FROM grantee_list opt_granted_by opt_drop_behavior
				{
					n := &GrantStmt{}

					n.IsGrant = false
					n.GrantOption = true
					n.Privileges = $5
					n.Targtype = as[*privTarget]($7).targtype
					n.Objtype = as[*privTarget]($7).objtype
					n.Objects = as[*privTarget]($7).objs
					n.Grantees = $9
					n.Grantor = as[*RoleSpec]($10)
					n.Behavior = DropBehavior($11)
					$$ = n
				}
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
				{
					n := &AccessPriv{}

					n.PrivName = ""
					n.Cols = $3
					$$ = []Node{n}
				}
			| ALL PRIVILEGES '(' columnList ')'
				{
					n := &AccessPriv{}

					n.PrivName = ""
					n.Cols = $4
					$$ = []Node{n}
				}
		;

privilege_list:	privilege							{ $$ = []Node{$1} }
			| privilege_list ',' privilege			{ $$ = append($1, $3) }
		;

privilege:	SELECT opt_column_list
			{
				n := &AccessPriv{}

				n.PrivName = $1
				n.Cols = $2
				$$ = n
			}
		| REFERENCES opt_column_list
			{
				n := &AccessPriv{}

				n.PrivName = $1
				n.Cols = $2
				$$ = n
			}
		| CREATE opt_column_list
			{
				n := &AccessPriv{}

				n.PrivName = $1
				n.Cols = $2
				$$ = n
			}
		| ALTER SYSTEM_P
			{
				n := &AccessPriv{}
				n.PrivName = "alter system"
				n.Cols = nil
				$$ = n
			}
		| ColId opt_column_list
			{
				n := &AccessPriv{}

				n.PrivName = $1
				n.Cols = $2
				$$ = n
			}
		;

parameter_name_list:
		parameter_name
			{
				$$ = []Node{makeString($1, @1)}
			}
		| parameter_name_list ',' parameter_name
			{
				$$ = append($1, makeString($3, @3))
			}
		;

parameter_name:
		ColId
			{ $$ = $1 }
		| parameter_name '.' ColId
			{
				$$ = fmt.Sprintf("%s.%s", $1, $3)
			}
		;


/* Don't bother trying to fold the first two rules into one using
 * opt_table.  You're going to get conflicts.
 */
privilege_target:
			qualified_name_list
				{
					n := &privTarget{}

					n.targtype = ACL_TARGET_OBJECT
					n.objtype = OBJECT_TABLE
					n.objs = $1
					$$ = n
				}
			| TABLE qualified_name_list
				{
					n := &privTarget{}

					n.targtype = ACL_TARGET_OBJECT
					n.objtype = OBJECT_TABLE
					n.objs = $2
					$$ = n
				}
			| SEQUENCE qualified_name_list
				{
					n := &privTarget{}

					n.targtype = ACL_TARGET_OBJECT
					n.objtype = OBJECT_SEQUENCE
					n.objs = $2
					$$ = n
				}
			| FOREIGN DATA_P WRAPPER name_list
				{
					n := &privTarget{}

					n.targtype = ACL_TARGET_OBJECT
					n.objtype = OBJECT_FDW
					n.objs = $4
					$$ = n
				}
			| FOREIGN SERVER name_list
				{
					n := &privTarget{}

					n.targtype = ACL_TARGET_OBJECT
					n.objtype = OBJECT_FOREIGN_SERVER
					n.objs = $3
					$$ = n
				}
			| FUNCTION function_with_argtypes_list
				{
					n := &privTarget{}

					n.targtype = ACL_TARGET_OBJECT
					n.objtype = OBJECT_FUNCTION
					n.objs = $2
					$$ = n
				}
			| PROCEDURE function_with_argtypes_list
				{
					n := &privTarget{}

					n.targtype = ACL_TARGET_OBJECT
					n.objtype = OBJECT_PROCEDURE
					n.objs = $2
					$$ = n
				}
			| ROUTINE function_with_argtypes_list
				{
					n := &privTarget{}

					n.targtype = ACL_TARGET_OBJECT
					n.objtype = OBJECT_ROUTINE
					n.objs = $2
					$$ = n
				}
			| DATABASE name_list
				{
					n := &privTarget{}

					n.targtype = ACL_TARGET_OBJECT
					n.objtype = OBJECT_DATABASE
					n.objs = $2
					$$ = n
				}
			| DOMAIN_P any_name_list
				{
					n := &privTarget{}

					n.targtype = ACL_TARGET_OBJECT
					n.objtype = OBJECT_DOMAIN
					n.objs = $2
					$$ = n
				}
			| LANGUAGE name_list
				{
					n := &privTarget{}

					n.targtype = ACL_TARGET_OBJECT
					n.objtype = OBJECT_LANGUAGE
					n.objs = $2
					$$ = n
				}
			| LARGE_P OBJECT_P NumericOnly_list
				{
					n := &privTarget{}

					n.targtype = ACL_TARGET_OBJECT
					n.objtype = OBJECT_LARGEOBJECT
					n.objs = $3
					$$ = n
				}
			| PARAMETER parameter_name_list
				{
					n := &privTarget{}
					n.targtype = ACL_TARGET_OBJECT
					n.objtype = OBJECT_PARAMETER_ACL
					n.objs = $2
					$$ = n
				}
			| SCHEMA name_list
				{
					n := &privTarget{}

					n.targtype = ACL_TARGET_OBJECT
					n.objtype = OBJECT_SCHEMA
					n.objs = $2
					$$ = n
				}
			| TABLESPACE name_list
				{
					n := &privTarget{}

					n.targtype = ACL_TARGET_OBJECT
					n.objtype = OBJECT_TABLESPACE
					n.objs = $2
					$$ = n
				}
			| TYPE_P any_name_list
				{
					n := &privTarget{}

					n.targtype = ACL_TARGET_OBJECT
					n.objtype = OBJECT_TYPE
					n.objs = $2
					$$ = n
				}
			| ALL TABLES IN_P SCHEMA name_list
				{
					n := &privTarget{}

					n.targtype = ACL_TARGET_ALL_IN_SCHEMA
					n.objtype = OBJECT_TABLE
					n.objs = $5
					$$ = n
				}
			| ALL SEQUENCES IN_P SCHEMA name_list
				{
					n := &privTarget{}

					n.targtype = ACL_TARGET_ALL_IN_SCHEMA
					n.objtype = OBJECT_SEQUENCE
					n.objs = $5
					$$ = n
				}
			| ALL FUNCTIONS IN_P SCHEMA name_list
				{
					n := &privTarget{}

					n.targtype = ACL_TARGET_ALL_IN_SCHEMA
					n.objtype = OBJECT_FUNCTION
					n.objs = $5
					$$ = n
				}
			| ALL PROCEDURES IN_P SCHEMA name_list
				{
					n := &privTarget{}

					n.targtype = ACL_TARGET_ALL_IN_SCHEMA
					n.objtype = OBJECT_PROCEDURE
					n.objs = $5
					$$ = n
				}
			| ALL ROUTINES IN_P SCHEMA name_list
				{
					n := &privTarget{}

					n.targtype = ACL_TARGET_ALL_IN_SCHEMA
					n.objtype = OBJECT_ROUTINE
					n.objs = $5
					$$ = n
				}
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
				{
					n := &GrantRoleStmt{}

					n.IsGrant = true
					n.GrantedRoles = $2
					n.GranteeRoles = $4
					n.Opt = nil
					n.Grantor = as[*RoleSpec]($5)
					$$ = n
				}
		  | GRANT privilege_list TO role_list WITH grant_role_opt_list opt_granted_by
				{
					n := &GrantRoleStmt{}

					n.IsGrant = true
					n.GrantedRoles = $2
					n.GranteeRoles = $4
					n.Opt = $6
					n.Grantor = as[*RoleSpec]($7)
					$$ = n
				}
		;

RevokeRoleStmt:
			REVOKE privilege_list FROM role_list opt_granted_by opt_drop_behavior
				{
					n := &GrantRoleStmt{}

					n.IsGrant = false
					n.Opt = nil
					n.GrantedRoles = $2
					n.GranteeRoles = $4
					n.Grantor = as[*RoleSpec]($5)
					n.Behavior = DropBehavior($6)
					$$ = n
				}
			| REVOKE ColId OPTION FOR privilege_list FROM role_list opt_granted_by opt_drop_behavior
				{
					n := &GrantRoleStmt{}

					opt := makeDefElem($2, makeBoolean(false), @2)
					n.IsGrant = false
					n.Opt = []Node{opt}
					n.GrantedRoles = $5
					n.GranteeRoles = $7
					n.Grantor = as[*RoleSpec]($8)
					n.Behavior = DropBehavior($9)
					$$ = n
				}
		;

grant_role_opt_list:
			grant_role_opt_list ',' grant_role_opt	{ $$ = append($1, $3) }
			| grant_role_opt						{ $$ = []Node{$1} }
		;

grant_role_opt:
		ColLabel grant_role_opt_value
			{
				$$ = makeDefElem($1, $2, @1)
			}
		;

grant_role_opt_value:
		OPTION			{ $$ = makeBoolean(true) }
		| TRUE_P		{ $$ = makeBoolean(true) }
		| FALSE_P		{ $$ = makeBoolean(false) }
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
				{
					n := &AlterDefaultPrivilegesStmt{}

					n.Options = $4
					n.Action = as[*GrantStmt]($5)
					$$ = n
				}
		;

DefACLOptionList:
			DefACLOptionList DefACLOption			{ $$ = append($1, $2) }
			| /* EMPTY */							{ $$ = nil }
		;

DefACLOption:
			IN_P SCHEMA name_list
				{
					$$ = makeDefElem("schemas", listNode($3), @1)
				}
			| FOR ROLE role_list
				{
					$$ = makeDefElem("roles", listNode($3), @1)
				}
			| FOR USER role_list
				{
					$$ = makeDefElem("roles", listNode($3), @1)
				}
		;

/*
 * This should match GRANT/REVOKE, except that individual target objects
 * are not mentioned and we only allow a subset of object types.
 */
DefACLAction:
			GRANT privileges ON defacl_privilege_target TO grantee_list
			opt_grant_grant_option
				{
					n := &GrantStmt{}

					n.IsGrant = true
					n.Privileges = $2
					n.Targtype = ACL_TARGET_DEFAULTS
					n.Objtype = ObjectType($4)
					n.Objects = nil
					n.Grantees = $6
					n.GrantOption = $7
					$$ = n
				}
			| REVOKE privileges ON defacl_privilege_target
			FROM grantee_list opt_drop_behavior
				{
					n := &GrantStmt{}

					n.IsGrant = false
					n.GrantOption = false
					n.Privileges = $2
					n.Targtype = ACL_TARGET_DEFAULTS
					n.Objtype = ObjectType($4)
					n.Objects = nil
					n.Grantees = $6
					n.Behavior = DropBehavior($7)
					$$ = n
				}
			| REVOKE GRANT OPTION FOR privileges ON defacl_privilege_target
			FROM grantee_list opt_drop_behavior
				{
					n := &GrantStmt{}

					n.IsGrant = false
					n.GrantOption = true
					n.Privileges = $5
					n.Targtype = ACL_TARGET_DEFAULTS
					n.Objtype = ObjectType($7)
					n.Objects = nil
					n.Grantees = $9
					n.Behavior = DropBehavior($10)
					$$ = n
				}
		;

defacl_privilege_target:
			TABLES			{ $$ = int32(OBJECT_TABLE) }
			| FUNCTIONS		{ $$ = int32(OBJECT_FUNCTION) }
			| ROUTINES		{ $$ = int32(OBJECT_FUNCTION) }
			| SEQUENCES		{ $$ = int32(OBJECT_SEQUENCE) }
			| TYPES_P		{ $$ = int32(OBJECT_TYPE) }
			| SCHEMAS		{ $$ = int32(OBJECT_SCHEMA) }
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
				{
					n := &IndexStmt{}

					n.Unique = $2
					n.Concurrent = $4
					n.Idxname = $5
					n.Relation = as[*RangeVar]($7)
					n.AccessMethod = $8
					n.IndexParams = $10
					n.IndexIncludingParams = $12
					n.NullsNotDistinct = !$13
					n.Options = $14
					n.TableSpace = $15
					n.WhereClause = $16
					n.ExcludeOpNames = nil
					n.Idxcomment = ""
					n.IndexOid = 0
					n.OldNumber = 0
					n.OldCreateSubid = 0
					n.OldFirstRelfilelocatorSubid = 0
					n.Primary = false
					n.Isconstraint = false
					n.Deferrable = false
					n.Initdeferred = false
					n.Transformed = false
					n.IfNotExists = false
					n.ResetDefaultTblspc = false
					$$ = n
				}
			| CREATE opt_unique INDEX opt_concurrently IF_P NOT EXISTS name
			ON relation_expr access_method_clause '(' index_params ')'
			opt_include opt_unique_null_treatment opt_reloptions OptTableSpace where_clause
				{
					n := &IndexStmt{}

					n.Unique = $2
					n.Concurrent = $4
					n.Idxname = $8
					n.Relation = as[*RangeVar]($10)
					n.AccessMethod = $11
					n.IndexParams = $13
					n.IndexIncludingParams = $15
					n.NullsNotDistinct = !$16
					n.Options = $17
					n.TableSpace = $18
					n.WhereClause = $19
					n.ExcludeOpNames = nil
					n.Idxcomment = ""
					n.IndexOid = 0
					n.OldNumber = 0
					n.OldCreateSubid = 0
					n.OldFirstRelfilelocatorSubid = 0
					n.Primary = false
					n.Isconstraint = false
					n.Deferrable = false
					n.Initdeferred = false
					n.Transformed = false
					n.IfNotExists = true
					n.ResetDefaultTblspc = false
					$$ = n
				}
		;

opt_unique:
			UNIQUE									{ $$ = true }
			| /*EMPTY*/								{ $$ = false }
		;

access_method_clause:
			USING name								{ $$ = $2 }
			| /*EMPTY*/								{ $$ = "btree" }
		;

index_params:	index_elem							{ $$ = []Node{$1} }
			| index_params ',' index_elem			{ $$ = append($1, $3) }
		;


index_elem_options:
	opt_collate opt_qualified_name opt_asc_desc opt_nulls_order
		{
			n := &IndexElem{}

			n.Name = ""
			n.Expr = nil
			n.Indexcolname = ""
			n.Collation = $1
			n.Opclass = $2
			n.Opclassopts = nil
			n.Ordering = SortByDir($3)
			n.NullsOrdering = SortByNulls($4)
			$$ = n
		}
	| opt_collate any_name reloptions opt_asc_desc opt_nulls_order
		{
			n := &IndexElem{}

			n.Name = ""
			n.Expr = nil
			n.Indexcolname = ""
			n.Collation = $1
			n.Opclass = $2
			n.Opclassopts = $3
			n.Ordering = SortByDir($4)
			n.NullsOrdering = SortByNulls($5)
			$$ = n
		}
	;

/*
 * Index attributes can be either simple column references, or arbitrary
 * expressions in parens.  For backwards-compatibility reasons, we allow
 * an expression that's just a function call to be written without parens.
 */
index_elem: ColId index_elem_options
				{
					n := as[*IndexElem]($2)

					n.Name = $1
					$$ = n
				}
			| func_expr_windowless index_elem_options
				{
					n := as[*IndexElem]($2)

					n.Expr = $1
					$$ = n
				}
			| '(' a_expr ')' index_elem_options
				{
					n := as[*IndexElem]($4)

					n.Expr = $2
					$$ = n
				}
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


opt_asc_desc: ASC							{ $$ = int32(SORTBY_ASC) }
			| DESC							{ $$ = int32(SORTBY_DESC) }
			| /*EMPTY*/						{ $$ = int32(SORTBY_DEFAULT) }
		;

opt_nulls_order: NULLS_LA FIRST_P			{ $$ = int32(SORTBY_NULLS_FIRST) }
			| NULLS_LA LAST_P				{ $$ = int32(SORTBY_NULLS_LAST) }
			| /*EMPTY*/						{ $$ = int32(SORTBY_NULLS_DEFAULT) }
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
				{
					n := &CreateFunctionStmt{}

					n.IsProcedure = false
					n.Replace = $2
					n.Funcname = $4
					n.Parameters = $5
					n.ReturnType = as[*TypeName]($7)
					n.Options = $8
					n.SqlBody = $9
					$$ = n
				}
			| CREATE opt_or_replace FUNCTION func_name func_args_with_defaults
			  RETURNS TABLE '(' table_func_column_list ')' opt_createfunc_opt_list opt_routine_body
				{
					n := &CreateFunctionStmt{}

					n.IsProcedure = false
					n.Replace = $2
					n.Funcname = $4
					n.Parameters = p.mergeTableFuncParameters($5, $9)
					n.ReturnType = tableFuncTypeName($9)
					n.ReturnType.Location = @7
					n.Options = $11
					n.SqlBody = $12
					$$ = n
				}
			| CREATE opt_or_replace FUNCTION func_name func_args_with_defaults
			  opt_createfunc_opt_list opt_routine_body
				{
					n := &CreateFunctionStmt{}

					n.IsProcedure = false
					n.Replace = $2
					n.Funcname = $4
					n.Parameters = $5
					n.ReturnType = nil
					n.Options = $6
					n.SqlBody = $7
					$$ = n
				}
			| CREATE opt_or_replace PROCEDURE func_name func_args_with_defaults
			  opt_createfunc_opt_list opt_routine_body
				{
					n := &CreateFunctionStmt{}

					n.IsProcedure = true
					n.Replace = $2
					n.Funcname = $4
					n.Parameters = $5
					n.ReturnType = nil
					n.Options = $6
					n.SqlBody = $7
					$$ = n
				}
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
				{
					n := &ObjectWithArgs{}

					n.Objname = $1
					n.Objargs = extractArgTypes($2)
					n.Objfuncargs = $2
					$$ = n
				}
			/*
			 * Because of reduce/reduce conflicts, we can't use func_name
			 * below, but we can write it out the long way, which actually
			 * allows more cases.
			 */
			| type_func_name_keyword
				{
					n := &ObjectWithArgs{}

					n.Objname = []Node{makeString($1, @1)}
					n.ArgsUnspecified = true
					$$ = n
				}
			| ColId
				{
					n := &ObjectWithArgs{}

					n.Objname = []Node{makeString($1, @1)}
					n.ArgsUnspecified = true
					$$ = n
				}
			| ColId indirection
				{
					n := &ObjectWithArgs{}

					n.Objname = p.checkFuncName(append([]Node{makeString($1, @1)}, $2...))
					n.ArgsUnspecified = true
					$$ = n
				}
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
				{
					n := &FunctionParameter{}

					n.Name = $2
					n.ArgType = as[*TypeName]($3)
					n.Mode = FunctionParameterMode($1)
					n.Defexpr = nil
					$$ = n
				}
			| param_name arg_class func_type
				{
					n := &FunctionParameter{}

					n.Name = $1
					n.ArgType = as[*TypeName]($3)
					n.Mode = FunctionParameterMode($2)
					n.Defexpr = nil
					$$ = n
				}
			| param_name func_type
				{
					n := &FunctionParameter{}

					n.Name = $1
					n.ArgType = as[*TypeName]($2)
					n.Mode = FUNC_PARAM_DEFAULT
					n.Defexpr = nil
					$$ = n
				}
			| arg_class func_type
				{
					n := &FunctionParameter{}

					n.Name = ""
					n.ArgType = as[*TypeName]($2)
					n.Mode = FunctionParameterMode($1)
					n.Defexpr = nil
					$$ = n
				}
			| func_type
				{
					n := &FunctionParameter{}

					n.Name = ""
					n.ArgType = as[*TypeName]($1)
					n.Mode = FUNC_PARAM_DEFAULT
					n.Defexpr = nil
					$$ = n
				}
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
				{
					/* We can catch over-specified results here if we want to,
					 * but for now better to silently swallow typmod, etc.
					 * - thomas 2000-03-22
					 */
					$$ = $1
				}
		;

/*
 * We would like to make the %TYPE productions here be ColId attrs etc,
 * but that causes reduce/reduce conflicts.  type_function_name
 * is next best choice.
 */
func_type:	Typename								{ $$ = $1 }
			| type_function_name attrs '%' TYPE_P
				{
					t := makeTypeNameFromNameList(append([]Node{makeString($1, @1)}, $2...))
					t.PctType = true
					t.Location = @1
					$$ = t
				}
			| SETOF type_function_name attrs '%' TYPE_P
				{
					t := makeTypeNameFromNameList(append([]Node{makeString($2, @2)}, $3...))
					t.PctType = true
					t.Setof = true
					t.Location = @2
					$$ = t
				}
		;

func_arg_with_default:
		func_arg
				{ $$ = $1 }
		| func_arg DEFAULT a_expr
				{
					n := as[*FunctionParameter]($1)

					n.Defexpr = $3
					$$ = n
				}
		| func_arg '=' a_expr
				{
					n := as[*FunctionParameter]($1)

					n.Defexpr = $3
					$$ = n
				}
		;

/* Aggregate args can be most things that function args can be */
aggr_arg:	func_arg
				{
					prm := as[*FunctionParameter]($1)

					if !(prm.Mode == FUNC_PARAM_DEFAULT ||
						prm.Mode == FUNC_PARAM_IN ||
						prm.Mode == FUNC_PARAM_VARIADIC) {
						p.fail(@1, "aggregates cannot have output arguments")
					}
					$$ = $1
				}
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
				{
					$$ = []Node{nil, makeInteger(-1)}
				}
			| '(' aggr_args_list ')'
				{
					$$ = []Node{listNode($2), makeInteger(-1)}
				}
			| '(' ORDER BY aggr_args_list ')'
				{
					$$ = []Node{listNode($4), makeInteger(0)}
				}
			| '(' aggr_args_list ORDER BY aggr_args_list ')'
				{
					/* this is the only case requiring consistency checking */
					$$ = p.makeOrderedSetArgs($2, $5)
				}
		;

aggr_args_list:
			aggr_arg								{ $$ = []Node{$1} }
			| aggr_args_list ',' aggr_arg			{ $$ = append($1, $3) }
		;

aggregate_with_argtypes:
			func_name aggr_args
				{
					n := &ObjectWithArgs{}

					n.Objname = $1
					n.Objargs = extractAggrArgTypes($2)
					n.Objfuncargs = asList($2[0])
					$$ = n
				}
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
				{
					$$ = makeDefElem("strict", makeBoolean(false), @1)
				}
			| RETURNS NULL_P ON NULL_P INPUT_P
				{
					$$ = makeDefElem("strict", makeBoolean(true), @1)
				}
			| STRICT_P
				{
					$$ = makeDefElem("strict", makeBoolean(true), @1)
				}
			| IMMUTABLE
				{
					$$ = makeDefElem("volatility", makeString("immutable", -1), @1)
				}
			| STABLE
				{
					$$ = makeDefElem("volatility", makeString("stable", -1), @1)
				}
			| VOLATILE
				{
					$$ = makeDefElem("volatility", makeString("volatile", -1), @1)
				}
			| EXTERNAL SECURITY DEFINER
				{
					$$ = makeDefElem("security", makeBoolean(true), @1)
				}
			| EXTERNAL SECURITY INVOKER
				{
					$$ = makeDefElem("security", makeBoolean(false), @1)
				}
			| SECURITY DEFINER
				{
					$$ = makeDefElem("security", makeBoolean(true), @1)
				}
			| SECURITY INVOKER
				{
					$$ = makeDefElem("security", makeBoolean(false), @1)
				}
			| LEAKPROOF
				{
					$$ = makeDefElem("leakproof", makeBoolean(true), @1)
				}
			| NOT LEAKPROOF
				{
					$$ = makeDefElem("leakproof", makeBoolean(false), @1)
				}
			| COST NumericOnly
				{
					$$ = makeDefElem("cost", $2, @1)
				}
			| ROWS NumericOnly
				{
					$$ = makeDefElem("rows", $2, @1)
				}
			| SUPPORT any_name
				{
					$$ = makeDefElem("support", listNode($2), @1)
				}
			| FunctionSetResetClause
				{
					/* we abuse the normal content of a DefElem here */
					$$ = makeDefElem("set", $1, @1)
				}
			| PARALLEL ColId
				{
					$$ = makeDefElem("parallel", makeString($2, @2), @1)
				}
		;

createfunc_opt_item:
			AS func_as
				{
					$$ = makeDefElem("as", listNode($2), @1)
				}
			| LANGUAGE NonReservedWord_or_Sconst
				{
					$$ = makeDefElem("language", makeString($2, @2), @1)
				}
			| TRANSFORM transform_type_list
				{
					$$ = makeDefElem("transform", listNode($2), @1)
				}
			| WINDOW
				{
					$$ = makeDefElem("window", makeBoolean(true), @1)
				}
			| common_func_opt_item
				{ $$ = $1 }
		;

func_as:	Sconst						{ $$ = []Node{makeString($1, @1)} }
			| Sconst ',' Sconst
				{
					$$ = []Node{makeString($1, @1), makeString($3, @3)}
				}
		;

ReturnStmt:	RETURN a_expr
				{
					r := &ReturnStmt{}

					r.Returnval = $2
					$$ = r
				}
		;

opt_routine_body:
			ReturnStmt
				{ $$ = $1 }
			| BEGIN_P ATOMIC routine_body_stmt_list END_P
				{
					/*
					 * A compound statement is stored as a single-item list
					 * containing the list of statements as its member.  That
					 * way, the parse analysis code can tell apart an empty
					 * body from no body at all.
					 */
					$$ = listNode([]Node{listNode($3)})
				}
			| /*EMPTY*/
				{ $$ = nil }
		;

routine_body_stmt_list:
			routine_body_stmt_list routine_body_stmt ';'
				{
					/* As in stmtmulti, discard empty statements */
					if $2 != nil {
						$$ = append($1, $2)
					} else {
						$$ = $1
					}
				}
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
				{
					n := &FunctionParameter{}

					n.Name = $1
					n.ArgType = as[*TypeName]($2)
					n.Mode = FUNC_PARAM_TABLE
					n.Defexpr = nil
					$$ = n
				}
		;

table_func_column_list:
			table_func_column
				{ $$ = []Node{$1} }
			| table_func_column_list ',' table_func_column
				{ $$ = append($1, $3) }
		;

