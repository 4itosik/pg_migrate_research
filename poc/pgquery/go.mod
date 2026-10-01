module github.com/4itosik/pg_migrate_research/poc/pgquery

go 1.25.1

replace github.com/4itosik/pg_migrate_research/poc/harness => ../harness

require (
	github.com/4itosik/pg_migrate_research/poc/harness v0.0.0
	github.com/pganalyze/pg_query_go/v6 v6.2.2
	github.com/wasilibs/go-pgquery v0.0.0-20260915022521-81f99195012b
	google.golang.org/protobuf v1.36.12
)

require (
	github.com/jackc/pgpassfile v1.0.0 // indirect
	github.com/jackc/pgservicefile v0.0.0-20240606120523-5a60cdf6a761 // indirect
	github.com/jackc/pgx/v5 v5.11.0 // indirect
	github.com/tetratelabs/wazero v1.12.0 // indirect
	github.com/wasilibs/wazero-helpers v0.0.0-20250123031827-cd30c44769bb // indirect
	go.yaml.in/yaml/v3 v3.0.5 // indirect
	golang.org/x/sys v0.47.0 // indirect
	golang.org/x/text v0.29.0 // indirect
)
