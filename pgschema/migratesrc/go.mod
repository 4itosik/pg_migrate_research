module github.com/4itosik/pg_migrate_research/pgschema/migratesrc

// go 1.25.11: golang-migrate v4.20.1 requires it (the library itself needs
// Go 1.25.1, see ../go.mod).
go 1.25.11

require github.com/4itosik/pg_migrate_research/pgschema v0.1.0

require github.com/golang-migrate/migrate/v4 v4.20.1

// For development in this repository: the library next to this module. A
// consumer's build ignores a replace in a dependency and fetches the
// required version, the tag pgschema/v0.1.0 of the library; keep the
// require above at the version released with this module.
replace github.com/4itosik/pg_migrate_research/pgschema => ../
