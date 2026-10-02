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
				{ /*C
					AlterTableStmt *n = makeNode(AlterTableStmt);

					n->relation = $3;
					n->cmds = $4;
					n->objtype = OBJECT_TABLE;
					n->missing_ok = false;
					$$ = (Node *) n;
				*/ }
		|	ALTER TABLE IF_P EXISTS relation_expr alter_table_cmds
				{ /*C
					AlterTableStmt *n = makeNode(AlterTableStmt);

					n->relation = $5;
					n->cmds = $6;
					n->objtype = OBJECT_TABLE;
					n->missing_ok = true;
					$$ = (Node *) n;
				*/ }
		|	ALTER TABLE relation_expr partition_cmd
				{ /*C
					AlterTableStmt *n = makeNode(AlterTableStmt);

					n->relation = $3;
					n->cmds = list_make1($4);
					n->objtype = OBJECT_TABLE;
					n->missing_ok = false;
					$$ = (Node *) n;
				*/ }
		|	ALTER TABLE IF_P EXISTS relation_expr partition_cmd
				{ /*C
					AlterTableStmt *n = makeNode(AlterTableStmt);

					n->relation = $5;
					n->cmds = list_make1($6);
					n->objtype = OBJECT_TABLE;
					n->missing_ok = true;
					$$ = (Node *) n;
				*/ }
		|	ALTER TABLE ALL IN_P TABLESPACE name SET TABLESPACE name opt_nowait
				{ /*C
					AlterTableMoveAllStmt *n =
						makeNode(AlterTableMoveAllStmt);

					n->orig_tablespacename = $6;
					n->objtype = OBJECT_TABLE;
					n->roles = NIL;
					n->new_tablespacename = $9;
					n->nowait = $10;
					$$ = (Node *) n;
				*/ }
		|	ALTER TABLE ALL IN_P TABLESPACE name OWNED BY role_list SET TABLESPACE name opt_nowait
				{ /*C
					AlterTableMoveAllStmt *n =
						makeNode(AlterTableMoveAllStmt);

					n->orig_tablespacename = $6;
					n->objtype = OBJECT_TABLE;
					n->roles = $9;
					n->new_tablespacename = $12;
					n->nowait = $13;
					$$ = (Node *) n;
				*/ }
		|	ALTER INDEX qualified_name alter_table_cmds
				{ /*C
					AlterTableStmt *n = makeNode(AlterTableStmt);

					n->relation = $3;
					n->cmds = $4;
					n->objtype = OBJECT_INDEX;
					n->missing_ok = false;
					$$ = (Node *) n;
				*/ }
		|	ALTER INDEX IF_P EXISTS qualified_name alter_table_cmds
				{ /*C
					AlterTableStmt *n = makeNode(AlterTableStmt);

					n->relation = $5;
					n->cmds = $6;
					n->objtype = OBJECT_INDEX;
					n->missing_ok = true;
					$$ = (Node *) n;
				*/ }
		|	ALTER INDEX qualified_name index_partition_cmd
				{ /*C
					AlterTableStmt *n = makeNode(AlterTableStmt);

					n->relation = $3;
					n->cmds = list_make1($4);
					n->objtype = OBJECT_INDEX;
					n->missing_ok = false;
					$$ = (Node *) n;
				*/ }
		|	ALTER INDEX ALL IN_P TABLESPACE name SET TABLESPACE name opt_nowait
				{ /*C
					AlterTableMoveAllStmt *n =
						makeNode(AlterTableMoveAllStmt);

					n->orig_tablespacename = $6;
					n->objtype = OBJECT_INDEX;
					n->roles = NIL;
					n->new_tablespacename = $9;
					n->nowait = $10;
					$$ = (Node *) n;
				*/ }
		|	ALTER INDEX ALL IN_P TABLESPACE name OWNED BY role_list SET TABLESPACE name opt_nowait
				{ /*C
					AlterTableMoveAllStmt *n =
						makeNode(AlterTableMoveAllStmt);

					n->orig_tablespacename = $6;
					n->objtype = OBJECT_INDEX;
					n->roles = $9;
					n->new_tablespacename = $12;
					n->nowait = $13;
					$$ = (Node *) n;
				*/ }
		|	ALTER SEQUENCE qualified_name alter_table_cmds
				{ /*C
					AlterTableStmt *n = makeNode(AlterTableStmt);

					n->relation = $3;
					n->cmds = $4;
					n->objtype = OBJECT_SEQUENCE;
					n->missing_ok = false;
					$$ = (Node *) n;
				*/ }
		|	ALTER SEQUENCE IF_P EXISTS qualified_name alter_table_cmds
				{ /*C
					AlterTableStmt *n = makeNode(AlterTableStmt);

					n->relation = $5;
					n->cmds = $6;
					n->objtype = OBJECT_SEQUENCE;
					n->missing_ok = true;
					$$ = (Node *) n;
				*/ }
		|	ALTER VIEW qualified_name alter_table_cmds
				{ /*C
					AlterTableStmt *n = makeNode(AlterTableStmt);

					n->relation = $3;
					n->cmds = $4;
					n->objtype = OBJECT_VIEW;
					n->missing_ok = false;
					$$ = (Node *) n;
				*/ }
		|	ALTER VIEW IF_P EXISTS qualified_name alter_table_cmds
				{ /*C
					AlterTableStmt *n = makeNode(AlterTableStmt);

					n->relation = $5;
					n->cmds = $6;
					n->objtype = OBJECT_VIEW;
					n->missing_ok = true;
					$$ = (Node *) n;
				*/ }
		|	ALTER MATERIALIZED VIEW qualified_name alter_table_cmds
				{ /*C
					AlterTableStmt *n = makeNode(AlterTableStmt);

					n->relation = $4;
					n->cmds = $5;
					n->objtype = OBJECT_MATVIEW;
					n->missing_ok = false;
					$$ = (Node *) n;
				*/ }
		|	ALTER MATERIALIZED VIEW IF_P EXISTS qualified_name alter_table_cmds
				{ /*C
					AlterTableStmt *n = makeNode(AlterTableStmt);

					n->relation = $6;
					n->cmds = $7;
					n->objtype = OBJECT_MATVIEW;
					n->missing_ok = true;
					$$ = (Node *) n;
				*/ }
		|	ALTER MATERIALIZED VIEW ALL IN_P TABLESPACE name SET TABLESPACE name opt_nowait
				{ /*C
					AlterTableMoveAllStmt *n =
						makeNode(AlterTableMoveAllStmt);

					n->orig_tablespacename = $7;
					n->objtype = OBJECT_MATVIEW;
					n->roles = NIL;
					n->new_tablespacename = $10;
					n->nowait = $11;
					$$ = (Node *) n;
				*/ }
		|	ALTER MATERIALIZED VIEW ALL IN_P TABLESPACE name OWNED BY role_list SET TABLESPACE name opt_nowait
				{ /*C
					AlterTableMoveAllStmt *n =
						makeNode(AlterTableMoveAllStmt);

					n->orig_tablespacename = $7;
					n->objtype = OBJECT_MATVIEW;
					n->roles = $10;
					n->new_tablespacename = $13;
					n->nowait = $14;
					$$ = (Node *) n;
				*/ }
		|	ALTER FOREIGN TABLE relation_expr alter_table_cmds
				{ /*C
					AlterTableStmt *n = makeNode(AlterTableStmt);

					n->relation = $4;
					n->cmds = $5;
					n->objtype = OBJECT_FOREIGN_TABLE;
					n->missing_ok = false;
					$$ = (Node *) n;
				*/ }
		|	ALTER FOREIGN TABLE IF_P EXISTS relation_expr alter_table_cmds
				{ /*C
					AlterTableStmt *n = makeNode(AlterTableStmt);

					n->relation = $6;
					n->cmds = $7;
					n->objtype = OBJECT_FOREIGN_TABLE;
					n->missing_ok = true;
					$$ = (Node *) n;
				*/ }
		;

alter_table_cmds:
			alter_table_cmd							{ $$ = []Node{$1} }
			| alter_table_cmds ',' alter_table_cmd	{ $$ = append($1, $3) }
		;

partition_cmd:
			/* ALTER TABLE <name> ATTACH PARTITION <table_name> FOR VALUES */
			ATTACH PARTITION qualified_name PartitionBoundSpec
				{ /*C
					AlterTableCmd *n = makeNode(AlterTableCmd);
					PartitionCmd *cmd = makeNode(PartitionCmd);

					n->subtype = AT_AttachPartition;
					cmd->name = $3;
					cmd->bound = $4;
					cmd->concurrent = false;
					n->def = (Node *) cmd;

					$$ = (Node *) n;
				*/ }
			/* ALTER TABLE <name> DETACH PARTITION <partition_name> [CONCURRENTLY] */
			| DETACH PARTITION qualified_name opt_concurrently
				{ /*C
					AlterTableCmd *n = makeNode(AlterTableCmd);
					PartitionCmd *cmd = makeNode(PartitionCmd);

					n->subtype = AT_DetachPartition;
					cmd->name = $3;
					cmd->bound = NULL;
					cmd->concurrent = $4;
					n->def = (Node *) cmd;

					$$ = (Node *) n;
				*/ }
			| DETACH PARTITION qualified_name FINALIZE
				{ /*C
					AlterTableCmd *n = makeNode(AlterTableCmd);
					PartitionCmd *cmd = makeNode(PartitionCmd);

					n->subtype = AT_DetachPartitionFinalize;
					cmd->name = $3;
					cmd->bound = NULL;
					cmd->concurrent = false;
					n->def = (Node *) cmd;
					$$ = (Node *) n;
				*/ }
		;

index_partition_cmd:
			/* ALTER INDEX <name> ATTACH PARTITION <index_name> */
			ATTACH PARTITION qualified_name
				{ /*C
					AlterTableCmd *n = makeNode(AlterTableCmd);
					PartitionCmd *cmd = makeNode(PartitionCmd);

					n->subtype = AT_AttachPartition;
					cmd->name = $3;
					cmd->bound = NULL;
					cmd->concurrent = false;
					n->def = (Node *) cmd;

					$$ = (Node *) n;
				*/ }
		;

alter_table_cmd:
			/* ALTER TABLE <name> ADD <coldef> */
			ADD_P columnDef
				{ /*C
					AlterTableCmd *n = makeNode(AlterTableCmd);

					n->subtype = AT_AddColumn;
					n->def = $2;
					n->missing_ok = false;
					$$ = (Node *) n;
				*/ }
			/* ALTER TABLE <name> ADD IF NOT EXISTS <coldef> */
			| ADD_P IF_P NOT EXISTS columnDef
				{ /*C
					AlterTableCmd *n = makeNode(AlterTableCmd);

					n->subtype = AT_AddColumn;
					n->def = $5;
					n->missing_ok = true;
					$$ = (Node *) n;
				*/ }
			/* ALTER TABLE <name> ADD COLUMN <coldef> */
			| ADD_P COLUMN columnDef
				{ /*C
					AlterTableCmd *n = makeNode(AlterTableCmd);

					n->subtype = AT_AddColumn;
					n->def = $3;
					n->missing_ok = false;
					$$ = (Node *) n;
				*/ }
			/* ALTER TABLE <name> ADD COLUMN IF NOT EXISTS <coldef> */
			| ADD_P COLUMN IF_P NOT EXISTS columnDef
				{ /*C
					AlterTableCmd *n = makeNode(AlterTableCmd);

					n->subtype = AT_AddColumn;
					n->def = $6;
					n->missing_ok = true;
					$$ = (Node *) n;
				*/ }
			/* ALTER TABLE <name> ALTER [COLUMN] <colname> {SET DEFAULT <expr>|DROP DEFAULT} */
			| ALTER opt_column ColId alter_column_default
				{ /*C
					AlterTableCmd *n = makeNode(AlterTableCmd);

					n->subtype = AT_ColumnDefault;
					n->name = $3;
					n->def = $4;
					$$ = (Node *) n;
				*/ }
			/* ALTER TABLE <name> ALTER [COLUMN] <colname> DROP NOT NULL */
			| ALTER opt_column ColId DROP NOT NULL_P
				{ /*C
					AlterTableCmd *n = makeNode(AlterTableCmd);

					n->subtype = AT_DropNotNull;
					n->name = $3;
					$$ = (Node *) n;
				*/ }
			/* ALTER TABLE <name> ALTER [COLUMN] <colname> SET NOT NULL */
			| ALTER opt_column ColId SET NOT NULL_P
				{ /*C
					AlterTableCmd *n = makeNode(AlterTableCmd);

					n->subtype = AT_SetNotNull;
					n->name = $3;
					$$ = (Node *) n;
				*/ }
			/* ALTER TABLE <name> ALTER [COLUMN] <colname> SET EXPRESSION AS <expr> */
			| ALTER opt_column ColId SET EXPRESSION AS '(' a_expr ')'
				{ /*C
					AlterTableCmd *n = makeNode(AlterTableCmd);

					n->subtype = AT_SetExpression;
					n->name = $3;
					n->def = $8;
					$$ = (Node *) n;
				*/ }
			/* ALTER TABLE <name> ALTER [COLUMN] <colname> DROP EXPRESSION */
			| ALTER opt_column ColId DROP EXPRESSION
				{ /*C
					AlterTableCmd *n = makeNode(AlterTableCmd);

					n->subtype = AT_DropExpression;
					n->name = $3;
					$$ = (Node *) n;
				*/ }
			/* ALTER TABLE <name> ALTER [COLUMN] <colname> DROP EXPRESSION IF EXISTS */
			| ALTER opt_column ColId DROP EXPRESSION IF_P EXISTS
				{ /*C
					AlterTableCmd *n = makeNode(AlterTableCmd);

					n->subtype = AT_DropExpression;
					n->name = $3;
					n->missing_ok = true;
					$$ = (Node *) n;
				*/ }
			/* ALTER TABLE <name> ALTER [COLUMN] <colname> SET STATISTICS */
			| ALTER opt_column ColId SET STATISTICS set_statistics_value
				{ /*C
					AlterTableCmd *n = makeNode(AlterTableCmd);

					n->subtype = AT_SetStatistics;
					n->name = $3;
					n->def = $6;
					$$ = (Node *) n;
				*/ }
			/* ALTER TABLE <name> ALTER [COLUMN] <colnum> SET STATISTICS */
			| ALTER opt_column Iconst SET STATISTICS set_statistics_value
				{ /*C
					AlterTableCmd *n = makeNode(AlterTableCmd);

					if ($3 <= 0 || $3 > PG_INT16_MAX)
						ereport(ERROR,
								(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
								 errmsg("column number must be in range from 1 to %d", PG_INT16_MAX),
								 parser_errposition(@3)));

					n->subtype = AT_SetStatistics;
					n->num = (int16) $3;
					n->def = $6;
					$$ = (Node *) n;
				*/ }
			/* ALTER TABLE <name> ALTER [COLUMN] <colname> SET ( column_parameter = value [, ... ] ) */
			| ALTER opt_column ColId SET reloptions
				{ /*C
					AlterTableCmd *n = makeNode(AlterTableCmd);

					n->subtype = AT_SetOptions;
					n->name = $3;
					n->def = (Node *) $5;
					$$ = (Node *) n;
				*/ }
			/* ALTER TABLE <name> ALTER [COLUMN] <colname> RESET ( column_parameter [, ... ] ) */
			| ALTER opt_column ColId RESET reloptions
				{ /*C
					AlterTableCmd *n = makeNode(AlterTableCmd);

					n->subtype = AT_ResetOptions;
					n->name = $3;
					n->def = (Node *) $5;
					$$ = (Node *) n;
				*/ }
			/* ALTER TABLE <name> ALTER [COLUMN] <colname> SET STORAGE <storagemode> */
			| ALTER opt_column ColId SET column_storage
				{ /*C
					AlterTableCmd *n = makeNode(AlterTableCmd);

					n->subtype = AT_SetStorage;
					n->name = $3;
					n->def = (Node *) makeString($5);
					$$ = (Node *) n;
				*/ }
			/* ALTER TABLE <name> ALTER [COLUMN] <colname> SET COMPRESSION <cm> */
			| ALTER opt_column ColId SET column_compression
				{ /*C
					AlterTableCmd *n = makeNode(AlterTableCmd);

					n->subtype = AT_SetCompression;
					n->name = $3;
					n->def = (Node *) makeString($5);
					$$ = (Node *) n;
				*/ }
			/* ALTER TABLE <name> ALTER [COLUMN] <colname> ADD GENERATED ... AS IDENTITY ... */
			| ALTER opt_column ColId ADD_P GENERATED generated_when AS IDENTITY_P OptParenthesizedSeqOptList
				{ /*C
					AlterTableCmd *n = makeNode(AlterTableCmd);
					Constraint *c = makeNode(Constraint);

					c->contype = CONSTR_IDENTITY;
					c->generated_when = $6;
					c->options = $9;
					c->location = @5;

					n->subtype = AT_AddIdentity;
					n->name = $3;
					n->def = (Node *) c;

					$$ = (Node *) n;
				*/ }
			/* ALTER TABLE <name> ALTER [COLUMN] <colname> SET <sequence options>/RESET */
			| ALTER opt_column ColId alter_identity_column_option_list
				{ /*C
					AlterTableCmd *n = makeNode(AlterTableCmd);

					n->subtype = AT_SetIdentity;
					n->name = $3;
					n->def = (Node *) $4;
					$$ = (Node *) n;
				*/ }
			/* ALTER TABLE <name> ALTER [COLUMN] <colname> DROP IDENTITY */
			| ALTER opt_column ColId DROP IDENTITY_P
				{ /*C
					AlterTableCmd *n = makeNode(AlterTableCmd);

					n->subtype = AT_DropIdentity;
					n->name = $3;
					n->missing_ok = false;
					$$ = (Node *) n;
				*/ }
			/* ALTER TABLE <name> ALTER [COLUMN] <colname> DROP IDENTITY IF EXISTS */
			| ALTER opt_column ColId DROP IDENTITY_P IF_P EXISTS
				{ /*C
					AlterTableCmd *n = makeNode(AlterTableCmd);

					n->subtype = AT_DropIdentity;
					n->name = $3;
					n->missing_ok = true;
					$$ = (Node *) n;
				*/ }
			/* ALTER TABLE <name> DROP [COLUMN] IF EXISTS <colname> [RESTRICT|CASCADE] */
			| DROP opt_column IF_P EXISTS ColId opt_drop_behavior
				{ /*C
					AlterTableCmd *n = makeNode(AlterTableCmd);

					n->subtype = AT_DropColumn;
					n->name = $5;
					n->behavior = $6;
					n->missing_ok = true;
					$$ = (Node *) n;
				*/ }
			/* ALTER TABLE <name> DROP [COLUMN] <colname> [RESTRICT|CASCADE] */
			| DROP opt_column ColId opt_drop_behavior
				{ /*C
					AlterTableCmd *n = makeNode(AlterTableCmd);

					n->subtype = AT_DropColumn;
					n->name = $3;
					n->behavior = $4;
					n->missing_ok = false;
					$$ = (Node *) n;
				*/ }
			/*
			 * ALTER TABLE <name> ALTER [COLUMN] <colname> [SET DATA] TYPE <typename>
			 *		[ USING <expression> ]
			 */
			| ALTER opt_column ColId opt_set_data TYPE_P Typename opt_collate_clause alter_using
				{ /*C
					AlterTableCmd *n = makeNode(AlterTableCmd);
					ColumnDef *def = makeNode(ColumnDef);

					n->subtype = AT_AlterColumnType;
					n->name = $3;
					n->def = (Node *) def;
					/* We only use these fields of the ColumnDef node * /
					def->typeName = $6;
					def->collClause = (CollateClause *) $7;
					def->raw_default = $8;
					def->location = @3;
					$$ = (Node *) n;
				*/ }
			/* ALTER FOREIGN TABLE <name> ALTER [COLUMN] <colname> OPTIONS */
			| ALTER opt_column ColId alter_generic_options
				{ /*C
					AlterTableCmd *n = makeNode(AlterTableCmd);

					n->subtype = AT_AlterColumnGenericOptions;
					n->name = $3;
					n->def = (Node *) $4;
					$$ = (Node *) n;
				*/ }
			/* ALTER TABLE <name> ADD CONSTRAINT ... */
			| ADD_P TableConstraint
				{ /*C
					AlterTableCmd *n = makeNode(AlterTableCmd);

					n->subtype = AT_AddConstraint;
					n->def = $2;
					$$ = (Node *) n;
				*/ }
			/* ALTER TABLE <name> ALTER CONSTRAINT ... */
			| ALTER CONSTRAINT name ConstraintAttributeSpec
				{ /*C
					AlterTableCmd *n = makeNode(AlterTableCmd);
					Constraint *c = makeNode(Constraint);

					n->subtype = AT_AlterConstraint;
					n->def = (Node *) c;
					c->contype = CONSTR_FOREIGN; /* others not supported, yet * /
					c->conname = $3;
					processCASbits($4, @4, "FOREIGN KEY",
									&c->deferrable,
									&c->initdeferred,
									NULL, NULL, yyscanner);
					$$ = (Node *) n;
				*/ }
			/* ALTER TABLE <name> VALIDATE CONSTRAINT ... */
			| VALIDATE CONSTRAINT name
				{ /*C
					AlterTableCmd *n = makeNode(AlterTableCmd);

					n->subtype = AT_ValidateConstraint;
					n->name = $3;
					$$ = (Node *) n;
				*/ }
			/* ALTER TABLE <name> DROP CONSTRAINT IF EXISTS <name> [RESTRICT|CASCADE] */
			| DROP CONSTRAINT IF_P EXISTS name opt_drop_behavior
				{ /*C
					AlterTableCmd *n = makeNode(AlterTableCmd);

					n->subtype = AT_DropConstraint;
					n->name = $5;
					n->behavior = $6;
					n->missing_ok = true;
					$$ = (Node *) n;
				*/ }
			/* ALTER TABLE <name> DROP CONSTRAINT <name> [RESTRICT|CASCADE] */
			| DROP CONSTRAINT name opt_drop_behavior
				{ /*C
					AlterTableCmd *n = makeNode(AlterTableCmd);

					n->subtype = AT_DropConstraint;
					n->name = $3;
					n->behavior = $4;
					n->missing_ok = false;
					$$ = (Node *) n;
				*/ }
			/* ALTER TABLE <name> SET WITHOUT OIDS, for backward compat */
			| SET WITHOUT OIDS
				{ /*C
					AlterTableCmd *n = makeNode(AlterTableCmd);

					n->subtype = AT_DropOids;
					$$ = (Node *) n;
				*/ }
			/* ALTER TABLE <name> CLUSTER ON <indexname> */
			| CLUSTER ON name
				{ /*C
					AlterTableCmd *n = makeNode(AlterTableCmd);

					n->subtype = AT_ClusterOn;
					n->name = $3;
					$$ = (Node *) n;
				*/ }
			/* ALTER TABLE <name> SET WITHOUT CLUSTER */
			| SET WITHOUT CLUSTER
				{ /*C
					AlterTableCmd *n = makeNode(AlterTableCmd);

					n->subtype = AT_DropCluster;
					n->name = NULL;
					$$ = (Node *) n;
				*/ }
			/* ALTER TABLE <name> SET LOGGED */
			| SET LOGGED
				{ /*C
					AlterTableCmd *n = makeNode(AlterTableCmd);

					n->subtype = AT_SetLogged;
					$$ = (Node *) n;
				*/ }
			/* ALTER TABLE <name> SET UNLOGGED */
			| SET UNLOGGED
				{ /*C
					AlterTableCmd *n = makeNode(AlterTableCmd);

					n->subtype = AT_SetUnLogged;
					$$ = (Node *) n;
				*/ }
			/* ALTER TABLE <name> ENABLE TRIGGER <trig> */
			| ENABLE_P TRIGGER name
				{ /*C
					AlterTableCmd *n = makeNode(AlterTableCmd);

					n->subtype = AT_EnableTrig;
					n->name = $3;
					$$ = (Node *) n;
				*/ }
			/* ALTER TABLE <name> ENABLE ALWAYS TRIGGER <trig> */
			| ENABLE_P ALWAYS TRIGGER name
				{ /*C
					AlterTableCmd *n = makeNode(AlterTableCmd);

					n->subtype = AT_EnableAlwaysTrig;
					n->name = $4;
					$$ = (Node *) n;
				*/ }
			/* ALTER TABLE <name> ENABLE REPLICA TRIGGER <trig> */
			| ENABLE_P REPLICA TRIGGER name
				{ /*C
					AlterTableCmd *n = makeNode(AlterTableCmd);

					n->subtype = AT_EnableReplicaTrig;
					n->name = $4;
					$$ = (Node *) n;
				*/ }
			/* ALTER TABLE <name> ENABLE TRIGGER ALL */
			| ENABLE_P TRIGGER ALL
				{ /*C
					AlterTableCmd *n = makeNode(AlterTableCmd);

					n->subtype = AT_EnableTrigAll;
					$$ = (Node *) n;
				*/ }
			/* ALTER TABLE <name> ENABLE TRIGGER USER */
			| ENABLE_P TRIGGER USER
				{ /*C
					AlterTableCmd *n = makeNode(AlterTableCmd);

					n->subtype = AT_EnableTrigUser;
					$$ = (Node *) n;
				*/ }
			/* ALTER TABLE <name> DISABLE TRIGGER <trig> */
			| DISABLE_P TRIGGER name
				{ /*C
					AlterTableCmd *n = makeNode(AlterTableCmd);

					n->subtype = AT_DisableTrig;
					n->name = $3;
					$$ = (Node *) n;
				*/ }
			/* ALTER TABLE <name> DISABLE TRIGGER ALL */
			| DISABLE_P TRIGGER ALL
				{ /*C
					AlterTableCmd *n = makeNode(AlterTableCmd);

					n->subtype = AT_DisableTrigAll;
					$$ = (Node *) n;
				*/ }
			/* ALTER TABLE <name> DISABLE TRIGGER USER */
			| DISABLE_P TRIGGER USER
				{ /*C
					AlterTableCmd *n = makeNode(AlterTableCmd);

					n->subtype = AT_DisableTrigUser;
					$$ = (Node *) n;
				*/ }
			/* ALTER TABLE <name> ENABLE RULE <rule> */
			| ENABLE_P RULE name
				{ /*C
					AlterTableCmd *n = makeNode(AlterTableCmd);

					n->subtype = AT_EnableRule;
					n->name = $3;
					$$ = (Node *) n;
				*/ }
			/* ALTER TABLE <name> ENABLE ALWAYS RULE <rule> */
			| ENABLE_P ALWAYS RULE name
				{ /*C
					AlterTableCmd *n = makeNode(AlterTableCmd);

					n->subtype = AT_EnableAlwaysRule;
					n->name = $4;
					$$ = (Node *) n;
				*/ }
			/* ALTER TABLE <name> ENABLE REPLICA RULE <rule> */
			| ENABLE_P REPLICA RULE name
				{ /*C
					AlterTableCmd *n = makeNode(AlterTableCmd);

					n->subtype = AT_EnableReplicaRule;
					n->name = $4;
					$$ = (Node *) n;
				*/ }
			/* ALTER TABLE <name> DISABLE RULE <rule> */
			| DISABLE_P RULE name
				{ /*C
					AlterTableCmd *n = makeNode(AlterTableCmd);

					n->subtype = AT_DisableRule;
					n->name = $3;
					$$ = (Node *) n;
				*/ }
			/* ALTER TABLE <name> INHERIT <parent> */
			| INHERIT qualified_name
				{ /*C
					AlterTableCmd *n = makeNode(AlterTableCmd);

					n->subtype = AT_AddInherit;
					n->def = (Node *) $2;
					$$ = (Node *) n;
				*/ }
			/* ALTER TABLE <name> NO INHERIT <parent> */
			| NO INHERIT qualified_name
				{ /*C
					AlterTableCmd *n = makeNode(AlterTableCmd);

					n->subtype = AT_DropInherit;
					n->def = (Node *) $3;
					$$ = (Node *) n;
				*/ }
			/* ALTER TABLE <name> OF <type_name> */
			| OF any_name
				{ /*C
					AlterTableCmd *n = makeNode(AlterTableCmd);
					TypeName   *def = makeTypeNameFromNameList($2);

					def->location = @2;
					n->subtype = AT_AddOf;
					n->def = (Node *) def;
					$$ = (Node *) n;
				*/ }
			/* ALTER TABLE <name> NOT OF */
			| NOT OF
				{ /*C
					AlterTableCmd *n = makeNode(AlterTableCmd);

					n->subtype = AT_DropOf;
					$$ = (Node *) n;
				*/ }
			/* ALTER TABLE <name> OWNER TO RoleSpec */
			| OWNER TO RoleSpec
				{ /*C
					AlterTableCmd *n = makeNode(AlterTableCmd);

					n->subtype = AT_ChangeOwner;
					n->newowner = $3;
					$$ = (Node *) n;
				*/ }
			/* ALTER TABLE <name> SET ACCESS METHOD { <amname> | DEFAULT } */
			| SET ACCESS METHOD set_access_method_name
				{ /*C
					AlterTableCmd *n = makeNode(AlterTableCmd);

					n->subtype = AT_SetAccessMethod;
					n->name = $4;
					$$ = (Node *) n;
				*/ }
			/* ALTER TABLE <name> SET TABLESPACE <tablespacename> */
			| SET TABLESPACE name
				{ /*C
					AlterTableCmd *n = makeNode(AlterTableCmd);

					n->subtype = AT_SetTableSpace;
					n->name = $3;
					$$ = (Node *) n;
				*/ }
			/* ALTER TABLE <name> SET (...) */
			| SET reloptions
				{ /*C
					AlterTableCmd *n = makeNode(AlterTableCmd);

					n->subtype = AT_SetRelOptions;
					n->def = (Node *) $2;
					$$ = (Node *) n;
				*/ }
			/* ALTER TABLE <name> RESET (...) */
			| RESET reloptions
				{ /*C
					AlterTableCmd *n = makeNode(AlterTableCmd);

					n->subtype = AT_ResetRelOptions;
					n->def = (Node *) $2;
					$$ = (Node *) n;
				*/ }
			/* ALTER TABLE <name> REPLICA IDENTITY */
			| REPLICA IDENTITY_P replica_identity
				{ /*C
					AlterTableCmd *n = makeNode(AlterTableCmd);

					n->subtype = AT_ReplicaIdentity;
					n->def = $3;
					$$ = (Node *) n;
				*/ }
			/* ALTER TABLE <name> ENABLE ROW LEVEL SECURITY */
			| ENABLE_P ROW LEVEL SECURITY
				{ /*C
					AlterTableCmd *n = makeNode(AlterTableCmd);

					n->subtype = AT_EnableRowSecurity;
					$$ = (Node *) n;
				*/ }
			/* ALTER TABLE <name> DISABLE ROW LEVEL SECURITY */
			| DISABLE_P ROW LEVEL SECURITY
				{ /*C
					AlterTableCmd *n = makeNode(AlterTableCmd);

					n->subtype = AT_DisableRowSecurity;
					$$ = (Node *) n;
				*/ }
			/* ALTER TABLE <name> FORCE ROW LEVEL SECURITY */
			| FORCE ROW LEVEL SECURITY
				{ /*C
					AlterTableCmd *n = makeNode(AlterTableCmd);

					n->subtype = AT_ForceRowSecurity;
					$$ = (Node *) n;
				*/ }
			/* ALTER TABLE <name> NO FORCE ROW LEVEL SECURITY */
			| NO FORCE ROW LEVEL SECURITY
				{ /*C
					AlterTableCmd *n = makeNode(AlterTableCmd);

					n->subtype = AT_NoForceRowSecurity;
					$$ = (Node *) n;
				*/ }
			| alter_generic_options
				{ /*C
					AlterTableCmd *n = makeNode(AlterTableCmd);

					n->subtype = AT_GenericOptions;
					n->def = (Node *) $1;
					$$ = (Node *) n;
				*/ }
		;

alter_column_default:
			SET DEFAULT a_expr			{ $$ = $3 }
			| DROP DEFAULT				{ $$ = nil }
		;

opt_collate_clause:
			COLLATE any_name
				{ /*C
					CollateClause *n = makeNode(CollateClause);

					n->arg = NULL;
					n->collname = $2;
					n->location = @1;
					$$ = (Node *) n;
				*/ }
			| /* EMPTY */				{ $$ = nil }
		;

alter_using:
			USING a_expr				{ $$ = $2 }
			| /* EMPTY */				{ $$ = nil }
		;

replica_identity:
			NOTHING
				{ /*C
					ReplicaIdentityStmt *n = makeNode(ReplicaIdentityStmt);

					n->identity_type = REPLICA_IDENTITY_NOTHING;
					n->name = NULL;
					$$ = (Node *) n;
				*/ }
			| FULL
				{ /*C
					ReplicaIdentityStmt *n = makeNode(ReplicaIdentityStmt);

					n->identity_type = REPLICA_IDENTITY_FULL;
					n->name = NULL;
					$$ = (Node *) n;
				*/ }
			| DEFAULT
				{ /*C
					ReplicaIdentityStmt *n = makeNode(ReplicaIdentityStmt);

					n->identity_type = REPLICA_IDENTITY_DEFAULT;
					n->name = NULL;
					$$ = (Node *) n;
				*/ }
			| USING INDEX name
				{ /*C
					ReplicaIdentityStmt *n = makeNode(ReplicaIdentityStmt);

					n->identity_type = REPLICA_IDENTITY_INDEX;
					n->name = $3;
					$$ = (Node *) n;
				*/ }
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
				{ /*C
					$$ = makeDefElem($1, (Node *) $3, @1);
				*/ }
			| ColLabel
				{ /*C
					$$ = makeDefElem($1, NULL, @1);
				*/ }
			| ColLabel '.' ColLabel '=' def_arg
				{ /*C
					$$ = makeDefElemExtended($1, $3, (Node *) $5,
											 DEFELEM_UNSPEC, @1);
				*/ }
			| ColLabel '.' ColLabel
				{ /*C
					$$ = makeDefElemExtended($1, $3, NULL, DEFELEM_UNSPEC, @1);
				*/ }
		;

alter_identity_column_option_list:
			alter_identity_column_option
				{ $$ = []Node{$1} }
			| alter_identity_column_option_list alter_identity_column_option
				{ $$ = append($1, $2) }
		;

alter_identity_column_option:
			RESTART
				{ /*C
					$$ = makeDefElem("restart", NULL, @1);
				*/ }
			| RESTART opt_with NumericOnly
				{ /*C
					$$ = makeDefElem("restart", (Node *) $3, @1);
				*/ }
			| SET SeqOptElem
				{ /*C
					if (strcmp($2->defname, "as") == 0 ||
						strcmp($2->defname, "restart") == 0 ||
						strcmp($2->defname, "owned_by") == 0)
						ereport(ERROR,
								(errcode(ERRCODE_SYNTAX_ERROR),
								 errmsg("sequence option \"%s\" not supported here", $2->defname),
								 parser_errposition(@2)));
					$$ = $2;
				*/ }
			| SET GENERATED generated_when
				{ /*C
					$$ = makeDefElem("generated", (Node *) makeInteger($3), @1);
				*/ }
		;

set_statistics_value:
			SignedIconst					{ /*C $$ = (Node *) makeInteger($1); */ }
			| DEFAULT						{ $$ = nil }
		;

set_access_method_name:
			ColId							{ $$ = $1 }
			| DEFAULT						{ $$ = "" }
		;

PartitionBoundSpec:
			/* a HASH partition */
			FOR VALUES WITH '(' hash_partbound ')'
				{ /*C
					ListCell   *lc;
					PartitionBoundSpec *n = makeNode(PartitionBoundSpec);

					n->strategy = PARTITION_STRATEGY_HASH;
					n->modulus = n->remainder = -1;

					foreach (lc, $5)
					{
						DefElem    *opt = lfirst_node(DefElem, lc);

						if (strcmp(opt->defname, "modulus") == 0)
						{
							if (n->modulus != -1)
								ereport(ERROR,
										(errcode(ERRCODE_DUPLICATE_OBJECT),
										 errmsg("modulus for hash partition provided more than once"),
										 parser_errposition(opt->location)));
							n->modulus = defGetInt32(opt);
						}
						else if (strcmp(opt->defname, "remainder") == 0)
						{
							if (n->remainder != -1)
								ereport(ERROR,
										(errcode(ERRCODE_DUPLICATE_OBJECT),
										 errmsg("remainder for hash partition provided more than once"),
										 parser_errposition(opt->location)));
							n->remainder = defGetInt32(opt);
						}
						else
							ereport(ERROR,
									(errcode(ERRCODE_SYNTAX_ERROR),
									 errmsg("unrecognized hash partition bound specification \"%s\"",
											opt->defname),
									 parser_errposition(opt->location)));
					}

					if (n->modulus == -1)
						ereport(ERROR,
								(errcode(ERRCODE_SYNTAX_ERROR),
								 errmsg("modulus for hash partition must be specified")));
					if (n->remainder == -1)
						ereport(ERROR,
								(errcode(ERRCODE_SYNTAX_ERROR),
								 errmsg("remainder for hash partition must be specified")));

					n->location = @3;

					$$ = n;
				*/ }

			/* a LIST partition */
			| FOR VALUES IN_P '(' expr_list ')'
				{ /*C
					PartitionBoundSpec *n = makeNode(PartitionBoundSpec);

					n->strategy = PARTITION_STRATEGY_LIST;
					n->is_default = false;
					n->listdatums = $5;
					n->location = @3;

					$$ = n;
				*/ }

			/* a RANGE partition */
			| FOR VALUES FROM '(' expr_list ')' TO '(' expr_list ')'
				{ /*C
					PartitionBoundSpec *n = makeNode(PartitionBoundSpec);

					n->strategy = PARTITION_STRATEGY_RANGE;
					n->is_default = false;
					n->lowerdatums = $5;
					n->upperdatums = $9;
					n->location = @3;

					$$ = n;
				*/ }

			/* a DEFAULT partition */
			| DEFAULT
				{ /*C
					PartitionBoundSpec *n = makeNode(PartitionBoundSpec);

					n->is_default = true;
					n->location = @1;

					$$ = n;
				*/ }
		;

hash_partbound_elem:
		NonReservedWord Iconst
			{ /*C
				$$ = makeDefElem($1, (Node *) makeInteger($2), @1);
			*/ }
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
				{ /*C
					AlterTableStmt *n = makeNode(AlterTableStmt);

					/* can't use qualified_name, sigh * /
					n->relation = makeRangeVarFromAnyName($3, @3, yyscanner);
					n->cmds = $4;
					n->objtype = OBJECT_TYPE;
					$$ = (Node *) n;
				*/ }
			;

alter_type_cmds:
			alter_type_cmd							{ $$ = []Node{$1} }
			| alter_type_cmds ',' alter_type_cmd	{ $$ = append($1, $3) }
		;

alter_type_cmd:
			/* ALTER TYPE <name> ADD ATTRIBUTE <coldef> [RESTRICT|CASCADE] */
			ADD_P ATTRIBUTE TableFuncElement opt_drop_behavior
				{ /*C
					AlterTableCmd *n = makeNode(AlterTableCmd);

					n->subtype = AT_AddColumn;
					n->def = $3;
					n->behavior = $4;
					$$ = (Node *) n;
				*/ }
			/* ALTER TYPE <name> DROP ATTRIBUTE IF EXISTS <attname> [RESTRICT|CASCADE] */
			| DROP ATTRIBUTE IF_P EXISTS ColId opt_drop_behavior
				{ /*C
					AlterTableCmd *n = makeNode(AlterTableCmd);

					n->subtype = AT_DropColumn;
					n->name = $5;
					n->behavior = $6;
					n->missing_ok = true;
					$$ = (Node *) n;
				*/ }
			/* ALTER TYPE <name> DROP ATTRIBUTE <attname> [RESTRICT|CASCADE] */
			| DROP ATTRIBUTE ColId opt_drop_behavior
				{ /*C
					AlterTableCmd *n = makeNode(AlterTableCmd);

					n->subtype = AT_DropColumn;
					n->name = $3;
					n->behavior = $4;
					n->missing_ok = false;
					$$ = (Node *) n;
				*/ }
			/* ALTER TYPE <name> ALTER ATTRIBUTE <attname> [SET DATA] TYPE <typename> [RESTRICT|CASCADE] */
			| ALTER ATTRIBUTE ColId opt_set_data TYPE_P Typename opt_collate_clause opt_drop_behavior
				{ /*C
					AlterTableCmd *n = makeNode(AlterTableCmd);
					ColumnDef *def = makeNode(ColumnDef);

					n->subtype = AT_AlterColumnType;
					n->name = $3;
					n->def = (Node *) def;
					n->behavior = $8;
					/* We only use these fields of the ColumnDef node * /
					def->typeName = $6;
					def->collClause = (CollateClause *) $7;
					def->raw_default = NULL;
					def->location = @3;
					$$ = (Node *) n;
				*/ }
		;

