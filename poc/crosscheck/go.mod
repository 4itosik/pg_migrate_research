module github.com/4itosik/pg_migrate_research/poc/crosscheck

go 1.26

replace (
	github.com/4itosik/pg_migrate_research/poc/antlr => ../antlr
	github.com/4itosik/pg_migrate_research/poc/harness => ../harness
	github.com/4itosik/pg_migrate_research/poc/multigres => ../multigres
	github.com/4itosik/pg_migrate_research/poc/pgquery => ../pgquery
	github.com/antlr4-go/antlr/v4 => github.com/bytebase/antlr/v4 v4.0.0-20240827034948-8c385f108920
)

require (
	github.com/4itosik/pg_migrate_research/poc/antlr v0.0.0-00010101000000-000000000000
	github.com/4itosik/pg_migrate_research/poc/multigres v0.0.0-00010101000000-000000000000
	github.com/4itosik/pg_migrate_research/poc/pgquery v0.0.0-00010101000000-000000000000
	github.com/multigres/multigres v0.0.0-20261001082527-829712a6430e
	github.com/pganalyze/pg_query_go/v6 v6.2.5
	github.com/wasilibs/go-pgquery v0.0.0-20260915022521-81f99195012b
	google.golang.org/protobuf v1.36.12
)

require (
	github.com/antlr4-go/antlr/v4 v4.13.1 // indirect
	github.com/bytebase/parser v0.0.0-20260417075056-57b6ef7a2640 // indirect
	github.com/cespare/xxhash/v2 v2.3.0 // indirect
	github.com/stretchr/testify v1.12.1 // indirect
	github.com/tetratelabs/wazero v1.12.0 // indirect
	github.com/wasilibs/wazero-helpers v0.0.0-20250123031827-cd30c44769bb // indirect
	go.yaml.in/yaml/v3 v3.0.5 // indirect
	golang.org/x/exp v0.0.0-20250911091902-df9299821621 // indirect
	golang.org/x/sys v0.47.0 // indirect
)
