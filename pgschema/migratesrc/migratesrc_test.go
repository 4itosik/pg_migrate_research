package migratesrc

import (
	"errors"
	"io"
	"io/fs"
	"os/exec"
	"strings"
	"testing"

	"github.com/golang-migrate/migrate/v4/source"
)

// memDriver is a source driver with fixed versions.
type memDriver struct {
	up, down map[uint]string
	closed   bool
}

func (m *memDriver) Open(string) (source.Driver, error) { return &memDriver{m.up, m.down, false}, nil }
func (m *memDriver) Close() error                       { m.closed = true; return nil }
func (m *memDriver) First() (uint, error)               { return 1, nil }
func (m *memDriver) Prev(v uint) (uint, error)          { return 0, fs.ErrNotExist }
func (m *memDriver) Next(v uint) (uint, error) {
	if _, ok := m.up[v+1]; ok {
		return v + 1, nil
	}
	return 0, fs.ErrNotExist
}
func (m *memDriver) ReadUp(v uint) (io.ReadCloser, string, error)   { return m.read(m.up, v) }
func (m *memDriver) ReadDown(v uint) (io.ReadCloser, string, error) { return m.read(m.down, v) }
func (m *memDriver) read(files map[uint]string, v uint) (io.ReadCloser, string, error) {
	s, ok := files[v]
	if !ok {
		return nil, "", fs.ErrNotExist
	}
	return io.NopCloser(strings.NewReader(s)), "mem", nil
}

func TestWrap(t *testing.T) {
	src := &memDriver{
		up:   map[uint]string{1: "CREATE TABLE pgschema_placeholder.t (id int);"},
		down: map[uint]string{1: "DROP TABLE pgschema_placeholder.t;"},
	}
	d := Wrap(src, "my schema")
	for name, read := range map[string]func(uint) (io.ReadCloser, string, error){"up": d.ReadUp, "down": d.ReadDown} {
		r, id, err := read(1)
		if err != nil || id != "mem" {
			t.Fatalf("%s: %v, %q", name, err, id)
		}
		b, _ := io.ReadAll(r)
		if !strings.Contains(string(b), `"my schema".t`) || strings.Contains(string(b), "placeholder") {
			t.Errorf("%s: %s", name, b)
		}
	}
	if _, _, err := d.ReadUp(2); !errors.Is(err, fs.ErrNotExist) {
		t.Errorf("a missing version: %v", err)
	}
	if v, err := d.First(); err != nil || v != 1 {
		t.Errorf("First: %d, %v", v, err)
	}
	// Open wraps the new driver in turn
	d2, err := d.Open("mem://")
	if err != nil {
		t.Fatal(err)
	}
	r, _, err := d2.ReadUp(1)
	if err != nil {
		t.Fatal(err)
	}
	if b, _ := io.ReadAll(r); !strings.Contains(string(b), `"my schema".t`) {
		t.Errorf("opened driver: %s", b)
	}
	if err := d.Close(); err != nil || !src.closed {
		t.Errorf("Close: %v, closed %v", err, src.closed)
	}
}

func TestWrapRejectsSchema(t *testing.T) {
	src := &memDriver{up: map[uint]string{1: "SELECT 'pgschema_placeholder'"}}
	for _, bad := range []string{"", "a'b", "a$b"} {
		d := Wrap(src, bad)
		if _, _, err := d.ReadUp(1); err == nil {
			t.Errorf("schema %q: ReadUp succeeded", bad)
		}
	}
}

func TestNew(t *testing.T) {
	src := &memDriver{up: map[uint]string{1: "CREATE TABLE pgschema_placeholder.t (id int);"}}
	d, err := New(src, "auth")
	if err != nil {
		t.Fatal(err)
	}
	r, _, err := d.ReadUp(1)
	if err != nil {
		t.Fatal(err)
	}
	if b, _ := io.ReadAll(r); string(b) != "CREATE TABLE auth.t (id int);" {
		t.Errorf("got %s", b)
	}
	// a bad name is reported before any migration is read: with nothing to
	// apply (ErrNoChange) Wrap would never report it
	for _, bad := range []string{"", "a'b", "pg_x"} {
		if d, err := New(src, bad); err == nil || d != nil {
			t.Errorf("schema %q: %v, %v", bad, d, err)
		}
	}
}

// failDriver fails the way a real driver can.
type failDriver struct {
	memDriver
	readErr  error // returned by ReadUp and ReadDown
	closeErr error // returned by Close of the reader
}

func (f *failDriver) ReadUp(v uint) (io.ReadCloser, string, error) {
	if f.readErr != nil {
		return nil, "", f.readErr
	}
	return closeFails{strings.NewReader("SELECT 1"), f.closeErr}, "f", nil
}

type closeFails struct {
	io.Reader
	err error
}

func (c closeFails) Close() error { return c.err }

func TestReadErrors(t *testing.T) {
	// golang-migrate compares the end of the migrations with os.ErrNotExist:
	// it passes through as it is
	d := Wrap(&failDriver{readErr: fs.ErrNotExist}, "auth")
	if _, _, err := d.ReadUp(7); err != fs.ErrNotExist {
		t.Errorf("ErrNotExist: %v", err)
	}
	// another error of the driver keeps its identity and gets the version
	boom := errors.New("boom")
	d = Wrap(&failDriver{readErr: boom}, "auth")
	if _, _, err := d.ReadUp(7); !errors.Is(err, boom) || !strings.Contains(err.Error(), "version 7") {
		t.Errorf("driver error: %v", err)
	}
	// the error of closing the reader is not dropped
	shut := errors.New("close failed")
	d = Wrap(&failDriver{closeErr: shut}, "auth")
	if _, _, err := d.ReadUp(7); !errors.Is(err, shut) || !strings.Contains(err.Error(), "version 7") {
		t.Errorf("close error: %v", err)
	}
	// a bad schema name names the version too
	d = Wrap(&failDriver{}, "a'b")
	if _, _, err := d.ReadUp(7); err == nil || !strings.Contains(err.Error(), "version 7") {
		t.Errorf("bad schema: %v", err)
	}
}

// TestNoParser: the wrapper is imported by services, which have no parser;
// of this repository it may depend on package subst only.
func TestNoParser(t *testing.T) {
	out, err := exec.Command("go", "list", "-deps", ".").Output()
	if err != nil {
		t.Fatal(err)
	}
	for _, pkg := range strings.Fields(string(out)) {
		if strings.Contains(pkg, "pgschema") && pkg != "github.com/4itosik/pg_migrate_research/pgschema/migratesrc" &&
			pkg != "github.com/4itosik/pg_migrate_research/pgschema/subst" {
			t.Errorf("migratesrc depends on %s", pkg)
		}
	}
}
