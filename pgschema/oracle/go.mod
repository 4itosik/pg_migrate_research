module github.com/4itosik/pg_migrate_research/pgschema/oracle

go 1.25.1

require (
	github.com/4itosik/pg_migrate_research/poc/harness v0.0.0
	github.com/4itosik/pg_migrate_research/poc/pgquery v0.0.0-00010101000000-000000000000
	github.com/pganalyze/pg_query_go/v6 v6.2.2
	github.com/wasilibs/go-pgquery v0.0.0-20260915022521-81f99195012b
)

require (
	github.com/jackc/pgpassfile v1.0.0 // indirect
	github.com/jackc/pgservicefile v0.0.0-20240606120523-5a60cdf6a761 // indirect
	github.com/jackc/pgx/v5 v5.11.0 // indirect
	github.com/tetratelabs/wazero v1.12.0 // indirect
	github.com/wasilibs/wazero-helpers v0.0.0-20250123031827-cd30c44769bb // indirect
	golang.org/x/sys v0.47.0 // indirect
	golang.org/x/text v0.29.0 // indirect
	google.golang.org/protobuf v1.36.12
)

// The library never depends on this module; the oracle depends on the
// library, on the libpg_query prototype (the rewriting reference) and on the
// live PostgreSQL harness.
replace (
	github.com/4itosik/pg_migrate_research/pgschema => ../
	github.com/4itosik/pg_migrate_research/poc/harness => ../../poc/harness
	github.com/4itosik/pg_migrate_research/poc/pgquery => ../../poc/pgquery
)
