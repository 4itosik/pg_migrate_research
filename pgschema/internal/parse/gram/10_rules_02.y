/* gram.y lines 2073-3291 */
/*****************************************************************************
 *
 *	ALTER [ TABLE | INDEX | SEQUENCE | VIEW | MATERIALIZED VIEW | FOREIGN TABLE ] variations
 *
 * Note: we accept all subcommands for each of the variants, and sort
 * out what's really legal at execution time.
 *****************************************************************************/

AlterTableStmt:
			ALTER TABLE relation_expr alter_table_cmds
				{
					n := &AlterTableStmt{}

					n.Relation = as[*RangeVar]($3)
					n.Cmds = $4
					n.Objtype = OBJECT_TABLE
					n.MissingOk = false
					$$ = n
				}
		|	ALTER TABLE IF_P EXISTS relation_expr alter_table_cmds
				{
					n := &AlterTableStmt{}

					n.Relation = as[*RangeVar]($5)
					n.Cmds = $6
					n.Objtype = OBJECT_TABLE
					n.MissingOk = true
					$$ = n
				}
		|	ALTER TABLE relation_expr partition_cmd
				{
					n := &AlterTableStmt{}

					n.Relation = as[*RangeVar]($3)
					n.Cmds = []Node{$4}
					n.Objtype = OBJECT_TABLE
					n.MissingOk = false
					$$ = n
				}
		|	ALTER TABLE IF_P EXISTS relation_expr partition_cmd
				{
					n := &AlterTableStmt{}

					n.Relation = as[*RangeVar]($5)
					n.Cmds = []Node{$6}
					n.Objtype = OBJECT_TABLE
					n.MissingOk = true
					$$ = n
				}
		|	ALTER TABLE ALL IN_P TABLESPACE name SET TABLESPACE name opt_nowait
				{
					n := &AlterTableMoveAllStmt{}

					n.OrigTablespacename = $6
					n.Objtype = OBJECT_TABLE
					n.Roles = nil
					n.NewTablespacename = $9
					n.Nowait = $10
					$$ = n
				}
		|	ALTER TABLE ALL IN_P TABLESPACE name OWNED BY role_list SET TABLESPACE name opt_nowait
				{
					n := &AlterTableMoveAllStmt{}

					n.OrigTablespacename = $6
					n.Objtype = OBJECT_TABLE
					n.Roles = $9
					n.NewTablespacename = $12
					n.Nowait = $13
					$$ = n
				}
		|	ALTER INDEX qualified_name alter_table_cmds
				{
					n := &AlterTableStmt{}

					n.Relation = as[*RangeVar]($3)
					n.Cmds = $4
					n.Objtype = OBJECT_INDEX
					n.MissingOk = false
					$$ = n
				}
		|	ALTER INDEX IF_P EXISTS qualified_name alter_table_cmds
				{
					n := &AlterTableStmt{}

					n.Relation = as[*RangeVar]($5)
					n.Cmds = $6
					n.Objtype = OBJECT_INDEX
					n.MissingOk = true
					$$ = n
				}
		|	ALTER INDEX qualified_name index_partition_cmd
				{
					n := &AlterTableStmt{}

					n.Relation = as[*RangeVar]($3)
					n.Cmds = []Node{$4}
					n.Objtype = OBJECT_INDEX
					n.MissingOk = false
					$$ = n
				}
		|	ALTER INDEX ALL IN_P TABLESPACE name SET TABLESPACE name opt_nowait
				{
					n := &AlterTableMoveAllStmt{}

					n.OrigTablespacename = $6
					n.Objtype = OBJECT_INDEX
					n.Roles = nil
					n.NewTablespacename = $9
					n.Nowait = $10
					$$ = n
				}
		|	ALTER INDEX ALL IN_P TABLESPACE name OWNED BY role_list SET TABLESPACE name opt_nowait
				{
					n := &AlterTableMoveAllStmt{}

					n.OrigTablespacename = $6
					n.Objtype = OBJECT_INDEX
					n.Roles = $9
					n.NewTablespacename = $12
					n.Nowait = $13
					$$ = n
				}
		|	ALTER SEQUENCE qualified_name alter_table_cmds
				{
					n := &AlterTableStmt{}

					n.Relation = as[*RangeVar]($3)
					n.Cmds = $4
					n.Objtype = OBJECT_SEQUENCE
					n.MissingOk = false
					$$ = n
				}
		|	ALTER SEQUENCE IF_P EXISTS qualified_name alter_table_cmds
				{
					n := &AlterTableStmt{}

					n.Relation = as[*RangeVar]($5)
					n.Cmds = $6
					n.Objtype = OBJECT_SEQUENCE
					n.MissingOk = true
					$$ = n
				}
		|	ALTER VIEW qualified_name alter_table_cmds
				{
					n := &AlterTableStmt{}

					n.Relation = as[*RangeVar]($3)
					n.Cmds = $4
					n.Objtype = OBJECT_VIEW
					n.MissingOk = false
					$$ = n
				}
		|	ALTER VIEW IF_P EXISTS qualified_name alter_table_cmds
				{
					n := &AlterTableStmt{}

					n.Relation = as[*RangeVar]($5)
					n.Cmds = $6
					n.Objtype = OBJECT_VIEW
					n.MissingOk = true
					$$ = n
				}
		|	ALTER MATERIALIZED VIEW qualified_name alter_table_cmds
				{
					n := &AlterTableStmt{}

					n.Relation = as[*RangeVar]($4)
					n.Cmds = $5
					n.Objtype = OBJECT_MATVIEW
					n.MissingOk = false
					$$ = n
				}
		|	ALTER MATERIALIZED VIEW IF_P EXISTS qualified_name alter_table_cmds
				{
					n := &AlterTableStmt{}

					n.Relation = as[*RangeVar]($6)
					n.Cmds = $7
					n.Objtype = OBJECT_MATVIEW
					n.MissingOk = true
					$$ = n
				}
		|	ALTER MATERIALIZED VIEW ALL IN_P TABLESPACE name SET TABLESPACE name opt_nowait
				{
					n := &AlterTableMoveAllStmt{}

					n.OrigTablespacename = $7
					n.Objtype = OBJECT_MATVIEW
					n.Roles = nil
					n.NewTablespacename = $10
					n.Nowait = $11
					$$ = n
				}
		|	ALTER MATERIALIZED VIEW ALL IN_P TABLESPACE name OWNED BY role_list SET TABLESPACE name opt_nowait
				{
					n := &AlterTableMoveAllStmt{}

					n.OrigTablespacename = $7
					n.Objtype = OBJECT_MATVIEW
					n.Roles = $10
					n.NewTablespacename = $13
					n.Nowait = $14
					$$ = n
				}
		|	ALTER FOREIGN TABLE relation_expr alter_table_cmds
				{
					n := &AlterTableStmt{}

					n.Relation = as[*RangeVar]($4)
					n.Cmds = $5
					n.Objtype = OBJECT_FOREIGN_TABLE
					n.MissingOk = false
					$$ = n
				}
		|	ALTER FOREIGN TABLE IF_P EXISTS relation_expr alter_table_cmds
				{
					n := &AlterTableStmt{}

					n.Relation = as[*RangeVar]($6)
					n.Cmds = $7
					n.Objtype = OBJECT_FOREIGN_TABLE
					n.MissingOk = true
					$$ = n
				}
		;

alter_table_cmds:
			alter_table_cmd							{ $$ = []Node{$1} }
			| alter_table_cmds ',' alter_table_cmd	{ $$ = append($1, $3) }
		;

partition_cmd:
			/* ALTER TABLE <name> ATTACH PARTITION <table_name> FOR VALUES */
			ATTACH PARTITION qualified_name PartitionBoundSpec
				{
					n := &AlterTableCmd{}
					cmd := &PartitionCmd{}

					n.Subtype = AT_AttachPartition
					cmd.Name = as[*RangeVar]($3)
					cmd.Bound = as[*PartitionBoundSpec]($4)
					cmd.Concurrent = false
					n.Def = cmd

					$$ = n
				}
			/* ALTER TABLE <name> DETACH PARTITION <partition_name> [CONCURRENTLY] */
			| DETACH PARTITION qualified_name opt_concurrently
				{
					n := &AlterTableCmd{}
					cmd := &PartitionCmd{}

					n.Subtype = AT_DetachPartition
					cmd.Name = as[*RangeVar]($3)
					cmd.Bound = nil
					cmd.Concurrent = $4
					n.Def = cmd

					$$ = n
				}
			| DETACH PARTITION qualified_name FINALIZE
				{
					n := &AlterTableCmd{}
					cmd := &PartitionCmd{}

					n.Subtype = AT_DetachPartitionFinalize
					cmd.Name = as[*RangeVar]($3)
					cmd.Bound = nil
					cmd.Concurrent = false
					n.Def = cmd

					$$ = n
				}
		;

index_partition_cmd:
			/* ALTER INDEX <name> ATTACH PARTITION <index_name> */
			ATTACH PARTITION qualified_name
				{
					n := &AlterTableCmd{}
					cmd := &PartitionCmd{}

					n.Subtype = AT_AttachPartition
					cmd.Name = as[*RangeVar]($3)
					cmd.Bound = nil
					cmd.Concurrent = false
					n.Def = cmd

					$$ = n
				}
		;

alter_table_cmd:
			/* ALTER TABLE <name> ADD <coldef> */
			ADD_P columnDef
				{
					n := &AlterTableCmd{}

					n.Subtype = AT_AddColumn
					n.Def = $2
					n.MissingOk = false
					$$ = n
				}
			/* ALTER TABLE <name> ADD IF NOT EXISTS <coldef> */
			| ADD_P IF_P NOT EXISTS columnDef
				{
					n := &AlterTableCmd{}

					n.Subtype = AT_AddColumn
					n.Def = $5
					n.MissingOk = true
					$$ = n
				}
			/* ALTER TABLE <name> ADD COLUMN <coldef> */
			| ADD_P COLUMN columnDef
				{
					n := &AlterTableCmd{}

					n.Subtype = AT_AddColumn
					n.Def = $3
					n.MissingOk = false
					$$ = n
				}
			/* ALTER TABLE <name> ADD COLUMN IF NOT EXISTS <coldef> */
			| ADD_P COLUMN IF_P NOT EXISTS columnDef
				{
					n := &AlterTableCmd{}

					n.Subtype = AT_AddColumn
					n.Def = $6
					n.MissingOk = true
					$$ = n
				}
			/* ALTER TABLE <name> ALTER [COLUMN] <colname> {SET DEFAULT <expr>|DROP DEFAULT} */
			| ALTER opt_column ColId alter_column_default
				{
					n := &AlterTableCmd{}

					n.Subtype = AT_ColumnDefault
					n.Name = $3
					n.Def = $4
					$$ = n
				}
			/* ALTER TABLE <name> ALTER [COLUMN] <colname> DROP NOT NULL */
			| ALTER opt_column ColId DROP NOT NULL_P
				{
					n := &AlterTableCmd{}

					n.Subtype = AT_DropNotNull
					n.Name = $3
					$$ = n
				}
			/* ALTER TABLE <name> ALTER [COLUMN] <colname> SET NOT NULL */
			| ALTER opt_column ColId SET NOT NULL_P
				{
					n := &AlterTableCmd{}

					n.Subtype = AT_SetNotNull
					n.Name = $3
					$$ = n
				}
			/* ALTER TABLE <name> ALTER [COLUMN] <colname> SET EXPRESSION AS <expr> */
			| ALTER opt_column ColId SET EXPRESSION AS '(' a_expr ')'
				{
					n := &AlterTableCmd{}

					n.Subtype = AT_SetExpression
					n.Name = $3
					n.Def = $8
					$$ = n
				}
			/* ALTER TABLE <name> ALTER [COLUMN] <colname> DROP EXPRESSION */
			| ALTER opt_column ColId DROP EXPRESSION
				{
					n := &AlterTableCmd{}

					n.Subtype = AT_DropExpression
					n.Name = $3
					$$ = n
				}
			/* ALTER TABLE <name> ALTER [COLUMN] <colname> DROP EXPRESSION IF EXISTS */
			| ALTER opt_column ColId DROP EXPRESSION IF_P EXISTS
				{
					n := &AlterTableCmd{}

					n.Subtype = AT_DropExpression
					n.Name = $3
					n.MissingOk = true
					$$ = n
				}
			/* ALTER TABLE <name> ALTER [COLUMN] <colname> SET STATISTICS */
			| ALTER opt_column ColId SET STATISTICS set_statistics_value
				{
					n := &AlterTableCmd{}

					n.Subtype = AT_SetStatistics
					n.Name = $3
					n.Def = $6
					$$ = n
				}
			/* ALTER TABLE <name> ALTER [COLUMN] <colnum> SET STATISTICS */
			| ALTER opt_column Iconst SET STATISTICS set_statistics_value
				{
					n := &AlterTableCmd{}

					if $3 <= 0 || $3 > 32767 /* PG_INT16_MAX */ {
						p.fail(@3, fmt.Sprintf("column number must be in range from 1 to %d", 32767 /* PG_INT16_MAX */))
					}

					n.Subtype = AT_SetStatistics
					n.Num = int32(int16($3))
					n.Def = $6
					$$ = n
				}
			/* ALTER TABLE <name> ALTER [COLUMN] <colname> SET ( column_parameter = value [, ... ] ) */
			| ALTER opt_column ColId SET reloptions
				{
					n := &AlterTableCmd{}

					n.Subtype = AT_SetOptions
					n.Name = $3
					n.Def = listNode($5)
					$$ = n
				}
			/* ALTER TABLE <name> ALTER [COLUMN] <colname> RESET ( column_parameter [, ... ] ) */
			| ALTER opt_column ColId RESET reloptions
				{
					n := &AlterTableCmd{}

					n.Subtype = AT_ResetOptions
					n.Name = $3
					n.Def = listNode($5)
					$$ = n
				}
			/* ALTER TABLE <name> ALTER [COLUMN] <colname> SET STORAGE <storagemode> */
			| ALTER opt_column ColId SET column_storage
				{
					n := &AlterTableCmd{}

					n.Subtype = AT_SetStorage
					n.Name = $3
					n.Def = makeString($5, @5)
					$$ = n
				}
			/* ALTER TABLE <name> ALTER [COLUMN] <colname> SET COMPRESSION <cm> */
			| ALTER opt_column ColId SET column_compression
				{
					n := &AlterTableCmd{}

					n.Subtype = AT_SetCompression
					n.Name = $3
					n.Def = makeString($5, @5)
					$$ = n
				}
			/* ALTER TABLE <name> ALTER [COLUMN] <colname> ADD GENERATED ... AS IDENTITY ... */
			| ALTER opt_column ColId ADD_P GENERATED generated_when AS IDENTITY_P OptParenthesizedSeqOptList
				{
					n := &AlterTableCmd{}
					c := &Constraint{}

					c.Contype = CONSTR_IDENTITY
					c.GeneratedWhen = string(rune($6))
					c.Options = $9
					c.Location = @5

					n.Subtype = AT_AddIdentity
					n.Name = $3
					n.Def = c

					$$ = n
				}
			/* ALTER TABLE <name> ALTER [COLUMN] <colname> SET <sequence options>/RESET */
			| ALTER opt_column ColId alter_identity_column_option_list
				{
					n := &AlterTableCmd{}

					n.Subtype = AT_SetIdentity
					n.Name = $3
					n.Def = listNode($4)
					$$ = n
				}
			/* ALTER TABLE <name> ALTER [COLUMN] <colname> DROP IDENTITY */
			| ALTER opt_column ColId DROP IDENTITY_P
				{
					n := &AlterTableCmd{}

					n.Subtype = AT_DropIdentity
					n.Name = $3
					n.MissingOk = false
					$$ = n
				}
			/* ALTER TABLE <name> ALTER [COLUMN] <colname> DROP IDENTITY IF EXISTS */
			| ALTER opt_column ColId DROP IDENTITY_P IF_P EXISTS
				{
					n := &AlterTableCmd{}

					n.Subtype = AT_DropIdentity
					n.Name = $3
					n.MissingOk = true
					$$ = n
				}
			/* ALTER TABLE <name> DROP [COLUMN] IF EXISTS <colname> [RESTRICT|CASCADE] */
			| DROP opt_column IF_P EXISTS ColId opt_drop_behavior
				{
					n := &AlterTableCmd{}

					n.Subtype = AT_DropColumn
					n.Name = $5
					n.Behavior = DropBehavior($6)
					n.MissingOk = true
					$$ = n
				}
			/* ALTER TABLE <name> DROP [COLUMN] <colname> [RESTRICT|CASCADE] */
			| DROP opt_column ColId opt_drop_behavior
				{
					n := &AlterTableCmd{}

					n.Subtype = AT_DropColumn
					n.Name = $3
					n.Behavior = DropBehavior($4)
					n.MissingOk = false
					$$ = n
				}
			/*
			 * ALTER TABLE <name> ALTER [COLUMN] <colname> [SET DATA] TYPE <typename>
			 *		[ USING <expression> ]
			 */
			| ALTER opt_column ColId opt_set_data TYPE_P Typename opt_collate_clause alter_using
				{
					n := &AlterTableCmd{}
					def := &ColumnDef{}

					n.Subtype = AT_AlterColumnType
					n.Name = $3
					n.Def = def
					/* We only use these fields of the ColumnDef node */
					def.TypeName = as[*TypeName]($6)
					def.CollClause = as[*CollateClause]($7)
					def.RawDefault = $8
					def.Location = @3
					$$ = n
				}
			/* ALTER FOREIGN TABLE <name> ALTER [COLUMN] <colname> OPTIONS */
			| ALTER opt_column ColId alter_generic_options
				{
					n := &AlterTableCmd{}

					n.Subtype = AT_AlterColumnGenericOptions
					n.Name = $3
					n.Def = listNode($4)
					$$ = n
				}
			/* ALTER TABLE <name> ADD CONSTRAINT ... */
			| ADD_P TableConstraint
				{
					n := &AlterTableCmd{}

					n.Subtype = AT_AddConstraint
					n.Def = $2
					$$ = n
				}
			/* ALTER TABLE <name> ALTER CONSTRAINT ... */
			| ALTER CONSTRAINT name ConstraintAttributeSpec
				{
					n := &AlterTableCmd{}
					c := &Constraint{}

					n.Subtype = AT_AlterConstraint
					n.Def = c
					c.Contype = CONSTR_FOREIGN /* others not supported, yet */
					c.Conname = $3
					p.processCASbits($4, @4, "FOREIGN KEY",
						&c.Deferrable,
						&c.Initdeferred,
						nil, nil)
					$$ = n
				}
			/* ALTER TABLE <name> VALIDATE CONSTRAINT ... */
			| VALIDATE CONSTRAINT name
				{
					n := &AlterTableCmd{}

					n.Subtype = AT_ValidateConstraint
					n.Name = $3
					$$ = n
				}
			/* ALTER TABLE <name> DROP CONSTRAINT IF EXISTS <name> [RESTRICT|CASCADE] */
			| DROP CONSTRAINT IF_P EXISTS name opt_drop_behavior
				{
					n := &AlterTableCmd{}

					n.Subtype = AT_DropConstraint
					n.Name = $5
					n.Behavior = DropBehavior($6)
					n.MissingOk = true
					$$ = n
				}
			/* ALTER TABLE <name> DROP CONSTRAINT <name> [RESTRICT|CASCADE] */
			| DROP CONSTRAINT name opt_drop_behavior
				{
					n := &AlterTableCmd{}

					n.Subtype = AT_DropConstraint
					n.Name = $3
					n.Behavior = DropBehavior($4)
					n.MissingOk = false
					$$ = n
				}
			/* ALTER TABLE <name> SET WITHOUT OIDS, for backward compat */
			| SET WITHOUT OIDS
				{
					n := &AlterTableCmd{}

					n.Subtype = AT_DropOids
					$$ = n
				}
			/* ALTER TABLE <name> CLUSTER ON <indexname> */
			| CLUSTER ON name
				{
					n := &AlterTableCmd{}

					n.Subtype = AT_ClusterOn
					n.Name = $3
					$$ = n
				}
			/* ALTER TABLE <name> SET WITHOUT CLUSTER */
			| SET WITHOUT CLUSTER
				{
					n := &AlterTableCmd{}

					n.Subtype = AT_DropCluster
					n.Name = ""
					$$ = n
				}
			/* ALTER TABLE <name> SET LOGGED */
			| SET LOGGED
				{
					n := &AlterTableCmd{}

					n.Subtype = AT_SetLogged
					$$ = n
				}
			/* ALTER TABLE <name> SET UNLOGGED */
			| SET UNLOGGED
				{
					n := &AlterTableCmd{}

					n.Subtype = AT_SetUnLogged
					$$ = n
				}
			/* ALTER TABLE <name> ENABLE TRIGGER <trig> */
			| ENABLE_P TRIGGER name
				{
					n := &AlterTableCmd{}

					n.Subtype = AT_EnableTrig
					n.Name = $3
					$$ = n
				}
			/* ALTER TABLE <name> ENABLE ALWAYS TRIGGER <trig> */
			| ENABLE_P ALWAYS TRIGGER name
				{
					n := &AlterTableCmd{}

					n.Subtype = AT_EnableAlwaysTrig
					n.Name = $4
					$$ = n
				}
			/* ALTER TABLE <name> ENABLE REPLICA TRIGGER <trig> */
			| ENABLE_P REPLICA TRIGGER name
				{
					n := &AlterTableCmd{}

					n.Subtype = AT_EnableReplicaTrig
					n.Name = $4
					$$ = n
				}
			/* ALTER TABLE <name> ENABLE TRIGGER ALL */
			| ENABLE_P TRIGGER ALL
				{
					n := &AlterTableCmd{}

					n.Subtype = AT_EnableTrigAll
					$$ = n
				}
			/* ALTER TABLE <name> ENABLE TRIGGER USER */
			| ENABLE_P TRIGGER USER
				{
					n := &AlterTableCmd{}

					n.Subtype = AT_EnableTrigUser
					$$ = n
				}
			/* ALTER TABLE <name> DISABLE TRIGGER <trig> */
			| DISABLE_P TRIGGER name
				{
					n := &AlterTableCmd{}

					n.Subtype = AT_DisableTrig
					n.Name = $3
					$$ = n
				}
			/* ALTER TABLE <name> DISABLE TRIGGER ALL */
			| DISABLE_P TRIGGER ALL
				{
					n := &AlterTableCmd{}

					n.Subtype = AT_DisableTrigAll
					$$ = n
				}
			/* ALTER TABLE <name> DISABLE TRIGGER USER */
			| DISABLE_P TRIGGER USER
				{
					n := &AlterTableCmd{}

					n.Subtype = AT_DisableTrigUser
					$$ = n
				}
			/* ALTER TABLE <name> ENABLE RULE <rule> */
			| ENABLE_P RULE name
				{
					n := &AlterTableCmd{}

					n.Subtype = AT_EnableRule
					n.Name = $3
					$$ = n
				}
			/* ALTER TABLE <name> ENABLE ALWAYS RULE <rule> */
			| ENABLE_P ALWAYS RULE name
				{
					n := &AlterTableCmd{}

					n.Subtype = AT_EnableAlwaysRule
					n.Name = $4
					$$ = n
				}
			/* ALTER TABLE <name> ENABLE REPLICA RULE <rule> */
			| ENABLE_P REPLICA RULE name
				{
					n := &AlterTableCmd{}

					n.Subtype = AT_EnableReplicaRule
					n.Name = $4
					$$ = n
				}
			/* ALTER TABLE <name> DISABLE RULE <rule> */
			| DISABLE_P RULE name
				{
					n := &AlterTableCmd{}

					n.Subtype = AT_DisableRule
					n.Name = $3
					$$ = n
				}
			/* ALTER TABLE <name> INHERIT <parent> */
			| INHERIT qualified_name
				{
					n := &AlterTableCmd{}

					n.Subtype = AT_AddInherit
					n.Def = $2
					$$ = n
				}
			/* ALTER TABLE <name> NO INHERIT <parent> */
			| NO INHERIT qualified_name
				{
					n := &AlterTableCmd{}

					n.Subtype = AT_DropInherit
					n.Def = $3
					$$ = n
				}
			/* ALTER TABLE <name> OF <type_name> */
			| OF any_name
				{
					n := &AlterTableCmd{}
					def := makeTypeNameFromNameList($2)

					def.Location = @2
					n.Subtype = AT_AddOf
					n.Def = def
					$$ = n
				}
			/* ALTER TABLE <name> NOT OF */
			| NOT OF
				{
					n := &AlterTableCmd{}

					n.Subtype = AT_DropOf
					$$ = n
				}
			/* ALTER TABLE <name> OWNER TO RoleSpec */
			| OWNER TO RoleSpec
				{
					n := &AlterTableCmd{}

					n.Subtype = AT_ChangeOwner
					n.Newowner = as[*RoleSpec]($3)
					$$ = n
				}
			/* ALTER TABLE <name> SET ACCESS METHOD { <amname> | DEFAULT } */
			| SET ACCESS METHOD set_access_method_name
				{
					n := &AlterTableCmd{}

					n.Subtype = AT_SetAccessMethod
					n.Name = $4
					$$ = n
				}
			/* ALTER TABLE <name> SET TABLESPACE <tablespacename> */
			| SET TABLESPACE name
				{
					n := &AlterTableCmd{}

					n.Subtype = AT_SetTableSpace
					n.Name = $3
					$$ = n
				}
			/* ALTER TABLE <name> SET (...) */
			| SET reloptions
				{
					n := &AlterTableCmd{}

					n.Subtype = AT_SetRelOptions
					n.Def = listNode($2)
					$$ = n
				}
			/* ALTER TABLE <name> RESET (...) */
			| RESET reloptions
				{
					n := &AlterTableCmd{}

					n.Subtype = AT_ResetRelOptions
					n.Def = listNode($2)
					$$ = n
				}
			/* ALTER TABLE <name> REPLICA IDENTITY */
			| REPLICA IDENTITY_P replica_identity
				{
					n := &AlterTableCmd{}

					n.Subtype = AT_ReplicaIdentity
					n.Def = $3
					$$ = n
				}
			/* ALTER TABLE <name> ENABLE ROW LEVEL SECURITY */
			| ENABLE_P ROW LEVEL SECURITY
				{
					n := &AlterTableCmd{}

					n.Subtype = AT_EnableRowSecurity
					$$ = n
				}
			/* ALTER TABLE <name> DISABLE ROW LEVEL SECURITY */
			| DISABLE_P ROW LEVEL SECURITY
				{
					n := &AlterTableCmd{}

					n.Subtype = AT_DisableRowSecurity
					$$ = n
				}
			/* ALTER TABLE <name> FORCE ROW LEVEL SECURITY */
			| FORCE ROW LEVEL SECURITY
				{
					n := &AlterTableCmd{}

					n.Subtype = AT_ForceRowSecurity
					$$ = n
				}
			/* ALTER TABLE <name> NO FORCE ROW LEVEL SECURITY */
			| NO FORCE ROW LEVEL SECURITY
				{
					n := &AlterTableCmd{}

					n.Subtype = AT_NoForceRowSecurity
					$$ = n
				}
			| alter_generic_options
				{
					n := &AlterTableCmd{}

					n.Subtype = AT_GenericOptions
					n.Def = listNode($1)
					$$ = n
				}
		;

alter_column_default:
			SET DEFAULT a_expr			{ $$ = $3 }
			| DROP DEFAULT				{ $$ = nil }
		;

opt_collate_clause:
			COLLATE any_name
				{
					n := &CollateClause{}

					n.Arg = nil
					n.Collname = $2
					n.Location = @1
					$$ = n
				}
			| /* EMPTY */				{ $$ = nil }
		;

alter_using:
			USING a_expr				{ $$ = $2 }
			| /* EMPTY */				{ $$ = nil }
		;

replica_identity:
			NOTHING
				{
					n := &ReplicaIdentityStmt{}

					n.IdentityType = "n" /* REPLICA_IDENTITY_NOTHING */
					n.Name = ""
					$$ = n
				}
			| FULL
				{
					n := &ReplicaIdentityStmt{}

					n.IdentityType = "f" /* REPLICA_IDENTITY_FULL */
					n.Name = ""
					$$ = n
				}
			| DEFAULT
				{
					n := &ReplicaIdentityStmt{}

					n.IdentityType = "d" /* REPLICA_IDENTITY_DEFAULT */
					n.Name = ""
					$$ = n
				}
			| USING INDEX name
				{
					n := &ReplicaIdentityStmt{}

					n.IdentityType = "i" /* REPLICA_IDENTITY_INDEX */
					n.Name = $3
					$$ = n
				}
;

reloptions:
			'(' reloption_list ')'					{ $$ = $2 }
		;

opt_reloptions:		WITH reloptions					{ $$ = $2 }
			 |		/* EMPTY */						{ $$ = nil }
		;

reloption_list:
			reloption_elem							{ $$ = []Node{$1} }
			| reloption_list ',' reloption_elem		{ $$ = append($1, $3) }
		;

/* This should match def_elem and also allow qualified names */
reloption_elem:
			ColLabel '=' def_arg
				{
					$$ = makeDefElem($1, $3, @1)
				}
			| ColLabel
				{
					$$ = makeDefElem($1, nil, @1)
				}
			| ColLabel '.' ColLabel '=' def_arg
				{
					$$ = makeDefElemExtended($1, $3, $5,
											 DEFELEM_UNSPEC, @1)
				}
			| ColLabel '.' ColLabel
				{
					$$ = makeDefElemExtended($1, $3, nil, DEFELEM_UNSPEC, @1)
				}
		;

alter_identity_column_option_list:
			alter_identity_column_option
				{ $$ = []Node{$1} }
			| alter_identity_column_option_list alter_identity_column_option
				{ $$ = append($1, $2) }
		;

alter_identity_column_option:
			RESTART
				{
					$$ = makeDefElem("restart", nil, @1)
				}
			| RESTART opt_with NumericOnly
				{
					$$ = makeDefElem("restart", $3, @1)
				}
			| SET SeqOptElem
				{
					opt := as[*DefElem]($2)
					if opt != nil && (opt.Defname == "as" ||
						opt.Defname == "restart" ||
						opt.Defname == "owned_by") {
						p.fail(@2, fmt.Sprintf("sequence option \"%s\" not supported here", opt.Defname))
					}
					$$ = $2
				}
			| SET GENERATED generated_when
				{
					$$ = makeDefElem("generated", makeInteger($3), @1)
				}
		;

set_statistics_value:
			SignedIconst					{ $$ = makeInteger($1) }
			| DEFAULT						{ $$ = nil }
		;

set_access_method_name:
			ColId							{ $$ = $1 }
			| DEFAULT						{ $$ = "" }
		;

PartitionBoundSpec:
			/* a HASH partition */
			FOR VALUES WITH '(' hash_partbound ')'
				{
					n := &PartitionBoundSpec{}

					n.Strategy = "h" /* PARTITION_STRATEGY_HASH */
					n.Modulus, n.Remainder = -1, -1

					for _, lc := range $5 {
						opt := as[*DefElem](lc)

						if opt.Defname == "modulus" {
							if n.Modulus != -1 {
								p.fail(opt.Location, "modulus for hash partition provided more than once")
							}
							n.Modulus = p.defGetInt32(opt)
						} else if opt.Defname == "remainder" {
							if n.Remainder != -1 {
								p.fail(opt.Location, "remainder for hash partition provided more than once")
							}
							n.Remainder = p.defGetInt32(opt)
						} else {
							p.fail(opt.Location,
								fmt.Sprintf("unrecognized hash partition bound specification \"%s\"",
									opt.Defname))
						}
					}

					if n.Modulus == -1 {
						p.fail(-1, "modulus for hash partition must be specified")
					}
					if n.Remainder == -1 {
						p.fail(-1, "remainder for hash partition must be specified")
					}

					n.Location = @3

					$$ = n
				}

			/* a LIST partition */
			| FOR VALUES IN_P '(' expr_list ')'
				{
					n := &PartitionBoundSpec{}

					n.Strategy = "l" /* PARTITION_STRATEGY_LIST */
					n.IsDefault = false
					n.Listdatums = $5
					n.Location = @3

					$$ = n
				}

			/* a RANGE partition */
			| FOR VALUES FROM '(' expr_list ')' TO '(' expr_list ')'
				{
					n := &PartitionBoundSpec{}

					n.Strategy = "r" /* PARTITION_STRATEGY_RANGE */
					n.IsDefault = false
					n.Lowerdatums = $5
					n.Upperdatums = $9
					n.Location = @3

					$$ = n
				}

			/* a DEFAULT partition */
			| DEFAULT
				{
					n := &PartitionBoundSpec{}

					n.IsDefault = true
					n.Location = @1

					$$ = n
				}
		;

hash_partbound_elem:
		NonReservedWord Iconst
			{
				$$ = makeDefElem($1, makeInteger($2), @1)
			}
		;

hash_partbound:
		hash_partbound_elem
			{ $$ = []Node{$1} }
		| hash_partbound ',' hash_partbound_elem
			{ $$ = append($1, $3) }
		;

/*****************************************************************************
 *
 *	ALTER TYPE
 *
 * really variants of the ALTER TABLE subcommands with different spellings
 *****************************************************************************/

AlterCompositeTypeStmt:
			ALTER TYPE_P any_name alter_type_cmds
				{
					n := &AlterTableStmt{}

					/* can't use qualified_name, sigh */
					n.Relation = p.makeRangeVarFromAnyName($3, @3)
					n.Cmds = $4
					n.Objtype = OBJECT_TYPE
					$$ = n
				}
			;

alter_type_cmds:
			alter_type_cmd							{ $$ = []Node{$1} }
			| alter_type_cmds ',' alter_type_cmd	{ $$ = append($1, $3) }
		;

alter_type_cmd:
			/* ALTER TYPE <name> ADD ATTRIBUTE <coldef> [RESTRICT|CASCADE] */
			ADD_P ATTRIBUTE TableFuncElement opt_drop_behavior
				{
					n := &AlterTableCmd{}

					n.Subtype = AT_AddColumn
					n.Def = $3
					n.Behavior = DropBehavior($4)
					$$ = n
				}
			/* ALTER TYPE <name> DROP ATTRIBUTE IF EXISTS <attname> [RESTRICT|CASCADE] */
			| DROP ATTRIBUTE IF_P EXISTS ColId opt_drop_behavior
				{
					n := &AlterTableCmd{}

					n.Subtype = AT_DropColumn
					n.Name = $5
					n.Behavior = DropBehavior($6)
					n.MissingOk = true
					$$ = n
				}
			/* ALTER TYPE <name> DROP ATTRIBUTE <attname> [RESTRICT|CASCADE] */
			| DROP ATTRIBUTE ColId opt_drop_behavior
				{
					n := &AlterTableCmd{}

					n.Subtype = AT_DropColumn
					n.Name = $3
					n.Behavior = DropBehavior($4)
					n.MissingOk = false
					$$ = n
				}
			/* ALTER TYPE <name> ALTER ATTRIBUTE <attname> [SET DATA] TYPE <typename> [RESTRICT|CASCADE] */
			| ALTER ATTRIBUTE ColId opt_set_data TYPE_P Typename opt_collate_clause opt_drop_behavior
				{
					n := &AlterTableCmd{}
					def := &ColumnDef{}

					n.Subtype = AT_AlterColumnType
					n.Name = $3
					n.Def = def
					n.Behavior = DropBehavior($8)
					/* We only use these fields of the ColumnDef node */
					def.TypeName = as[*TypeName]($6)
					def.CollClause = as[*CollateClause]($7)
					def.RawDefault = nil
					def.Location = @3
					$$ = n
				}
		;

