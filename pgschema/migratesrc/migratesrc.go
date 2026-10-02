// Package migratesrc wraps a golang-migrate source driver so that the
// migrations it reads get their schema.
//
// The migrations are templates written by "pgschema rewrite -placeholder":
// the placeholder stands where the schema goes. Wrap replaces it with the
// schema of the service when a migration is read, with no parser:
//
//	src, err := source.Open("file://migrations.tmpl")
//	...
//	m, err := migrate.NewWithSourceInstance("file", migratesrc.Wrap(src, "auth"), dbURL)
//
// The package is a module of its own so that the library does not depend on
// golang-migrate. It imports golang-migrate's source package and package
// subst, nothing else, and no parser.
package migratesrc

import (
	"bytes"
	"io"

	"github.com/golang-migrate/migrate/v4/source"

	"github.com/4itosik/pg_migrate_research/pgschema/subst"
)

// Wrap returns a driver that reads the migrations from src and puts schema in
// place of the placeholder. A schema name that cannot be substituted safely
// (see subst.ValidSchema) makes ReadUp and ReadDown fail with the reason; the
// driver then applies no migration.
//
// Open on the wrapper opens a new driver of src and wraps it in turn.
func Wrap(src source.Driver, schema string) source.Driver {
	return &driver{src: src, schema: schema, err: subst.ValidSchema(schema)}
}

type driver struct {
	src    source.Driver
	schema string
	err    error // the schema is not valid
}

func (d *driver) Open(url string) (source.Driver, error) {
	src, err := d.src.Open(url)
	if err != nil {
		return nil, err
	}
	return &driver{src: src, schema: d.schema, err: d.err}, nil
}

func (d *driver) Close() error                    { return d.src.Close() }
func (d *driver) First() (uint, error)            { return d.src.First() }
func (d *driver) Prev(version uint) (uint, error) { return d.src.Prev(version) }
func (d *driver) Next(version uint) (uint, error) { return d.src.Next(version) }
func (d *driver) ReadUp(v uint) (io.ReadCloser, string, error) {
	return d.read(d.src.ReadUp, v)
}
func (d *driver) ReadDown(v uint) (io.ReadCloser, string, error) {
	return d.read(d.src.ReadDown, v)
}

func (d *driver) read(read func(uint) (io.ReadCloser, string, error), version uint) (io.ReadCloser, string, error) {
	r, id, err := read(version)
	if err != nil {
		return nil, id, err // os.ErrNotExist and the like pass through unchanged
	}
	defer r.Close()
	if d.err != nil {
		return nil, id, d.err
	}
	tmpl, err := io.ReadAll(r)
	if err != nil {
		return nil, id, err
	}
	sql, err := subst.Apply(string(tmpl), d.schema)
	if err != nil {
		return nil, id, err
	}
	return io.NopCloser(bytes.NewReader([]byte(sql))), id, nil
}
