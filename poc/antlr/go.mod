module github.com/4itosik/pg_migrate_research/poc/antlr

go 1.25.1

replace (
	github.com/4itosik/pg_migrate_research/poc/harness => ../harness
	// bytebase/parser is generated for the bytebase fork of the ANTLR runtime;
	// every consumer has to repeat this replace.
	github.com/antlr4-go/antlr/v4 => github.com/bytebase/antlr/v4 v4.0.0-20240827034948-8c385f108920
)

require (
	github.com/4itosik/pg_migrate_research/poc/harness v0.0.0
	github.com/antlr4-go/antlr/v4 v4.13.1
	github.com/bytebase/parser v0.0.0-20260417075056-57b6ef7a2640
)

require (
	github.com/jackc/pgpassfile v1.0.0 // indirect
	github.com/jackc/pgservicefile v0.0.0-20240606120523-5a60cdf6a761 // indirect
	github.com/jackc/pgx/v5 v5.11.0 // indirect
	golang.org/x/exp v0.0.0-20240506185415-9bf2ced13842 // indirect
	golang.org/x/text v0.29.0 // indirect
)
