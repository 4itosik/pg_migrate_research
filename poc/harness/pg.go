package harness

import (
	"context"
	"fmt"
	"math/rand"
	"os"
	"os/exec"
	"os/user"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/jackc/pgx/v5/pgconn"
)

// Server is a PostgreSQL server used for validation.
//
// If PG_DSN is set it is used as is (the role must be allowed to create
// databases and roles). Otherwise a throwaway cluster is created with initdb
// from PG_BIN, PATH or /usr/lib/postgresql/*/bin. pg_dump is looked up
// separately (see pgDump), so PG_BIN may hold only the server binaries.
type Server struct {
	dsn        string
	version    string
	versionNum int    // server_version_num, e.g. 160014
	bin        string // directory with the server binaries, may be empty
	stop       func()
}

// StartServer returns a running server.
func StartServer(ctx context.Context) (*Server, error) {
	if dsn := os.Getenv("PG_DSN"); dsn != "" {
		bin, _ := findPGBin()
		s := &Server{dsn: dsn, bin: bin, stop: func() {}}
		return s, s.readVersion(ctx)
	}
	bin, err := findPGBin()
	if err != nil {
		return nil, err
	}
	tmp, err := os.MkdirTemp("", "pgschema-harness-")
	if err != nil {
		return nil, err
	}
	run := func(args ...string) error {
		var cmd *exec.Cmd
		if os.Geteuid() == 0 {
			// initdb refuses to run as root.
			cmd = exec.CommandContext(ctx, "runuser", append([]string{"-u", "postgres", "--"}, args...)...)
		} else {
			cmd = exec.CommandContext(ctx, args[0], args[1:]...)
		}
		out, err := cmd.CombinedOutput()
		if err != nil {
			return fmt.Errorf("%s: %w\n%s", strings.Join(args, " "), err, out)
		}
		return nil
	}
	if os.Geteuid() == 0 {
		u, err := user.Lookup("postgres")
		if err != nil {
			return nil, fmt.Errorf("running as root requires the postgres system user: %w", err)
		}
		if out, err := exec.Command("chown", u.Username, tmp).CombinedOutput(); err != nil {
			return nil, fmt.Errorf("chown: %w: %s", err, out)
		}
	}
	data := filepath.Join(tmp, "data")
	port := 20000 + rand.Intn(20000)
	if err := run(filepath.Join(bin, "initdb"), "-D", data, "-U", "postgres", "-A", "trust", "-E", "UTF8", "--no-locale", "--no-sync"); err != nil {
		return nil, err
	}
	opts := fmt.Sprintf("-k %s -p %d -c listen_addresses='' -c fsync=off -c synchronous_commit=off -c full_page_writes=off", tmp, port)
	if err := run(filepath.Join(bin, "pg_ctl"), "-D", data, "-o", opts, "-l", filepath.Join(tmp, "server.log"), "-w", "start"); err != nil {
		return nil, err
	}
	s := &Server{
		dsn: fmt.Sprintf("host=%s port=%d user=postgres dbname=postgres sslmode=disable", tmp, port),
		bin: bin,
		stop: func() {
			_ = run(filepath.Join(bin, "pg_ctl"), "-D", data, "-m", "immediate", "-w", "stop")
			_ = os.RemoveAll(tmp)
		},
	}
	return s, s.readVersion(ctx)
}

func findPGBin() (string, error) {
	if b := os.Getenv("PG_BIN"); b != "" {
		return b, nil
	}
	if p, err := exec.LookPath("pg_ctl"); err == nil {
		return filepath.Dir(p), nil
	}
	dirs, _ := filepath.Glob("/usr/lib/postgresql/*/bin")
	sort.Strings(dirs)
	if len(dirs) == 0 {
		return "", fmt.Errorf("PostgreSQL binaries not found: set PG_DSN or PG_BIN")
	}
	return dirs[len(dirs)-1], nil
}

func (s *Server) readVersion(ctx context.Context) error {
	conn, err := pgconn.Connect(ctx, s.dsn)
	if err != nil {
		return err
	}
	defer conn.Close(ctx)
	res, err := conn.Exec(ctx, "SHOW server_version; SHOW server_version_num").ReadAll()
	if err != nil {
		return err
	}
	s.version = string(res[0].Rows[0][0])
	s.versionNum, err = strconv.Atoi(string(res[1].Rows[0][0]))
	return err
}

// Version returns server_version.
func (s *Server) Version() string { return s.version }

// Major returns the major version of the server, e.g. 16.
func (s *Server) Major() int { return s.versionNum / 10000 }

// dropDatabase drops a database even if somebody is still connected to it.
func (s *Server) dropDatabase(ctx context.Context, admin *pgconn.PgConn, name string) error {
	if s.versionNum >= 130000 {
		_, err := admin.Exec(ctx, "DROP DATABASE IF EXISTS "+quoteIdent(name)+" WITH (FORCE)").ReadAll()
		return err
	}
	// DROP DATABASE ... WITH (FORCE) appeared in PostgreSQL 13. DROP DATABASE
	// cannot share a query message with another statement: they would run in
	// one implicit transaction.
	if _, err := admin.Exec(ctx, "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = "+quoteLiteral(name)).ReadAll(); err != nil {
		return err
	}
	_, err := admin.Exec(ctx, "DROP DATABASE IF EXISTS "+quoteIdent(name)).ReadAll()
	return err
}

// pgDump returns the pg_dump binary: PG_DUMP, the one next to the server
// binaries, PATH or the newest /usr/lib/postgresql/*/bin. pg_dump reads
// servers of its own and older major versions.
func (s *Server) pgDump() string {
	if p := os.Getenv("PG_DUMP"); p != "" {
		return p
	}
	if s.bin != "" {
		if p := filepath.Join(s.bin, "pg_dump"); fileExists(p) {
			return p
		}
	}
	if p, err := exec.LookPath("pg_dump"); err == nil {
		return p
	}
	found, _ := filepath.Glob("/usr/lib/postgresql/*/bin/pg_dump")
	major := func(p string) int {
		n, _ := strconv.Atoi(filepath.Base(filepath.Dir(filepath.Dir(p))))
		return n
	}
	sort.Slice(found, func(i, j int) bool { return major(found[i]) < major(found[j]) })
	if len(found) > 0 {
		return found[len(found)-1]
	}
	return "pg_dump"
}

func fileExists(p string) bool {
	st, err := os.Stat(p)
	return err == nil && !st.IsDir()
}

// Stop shuts the server down if it was started by the harness.
func (s *Server) Stop() { s.stop() }

// Database is a fresh database used by one case run.
type Database struct {
	srv  *Server
	name string
	Conn *pgconn.PgConn
}

// NewDatabase creates an empty database and connects to it.
func (s *Server) NewDatabase(ctx context.Context, name string) (*Database, error) {
	admin, err := pgconn.Connect(ctx, s.dsn)
	if err != nil {
		return nil, err
	}
	defer admin.Close(ctx)
	if err := s.dropDatabase(ctx, admin, name); err != nil {
		return nil, err
	}
	if _, err := admin.Exec(ctx, "CREATE DATABASE "+quoteIdent(name)+" TEMPLATE template0").ReadAll(); err != nil {
		return nil, err
	}
	cfg, err := pgconn.ParseConfig(s.dsn)
	if err != nil {
		return nil, err
	}
	cfg.Database = name
	cctx, cancel := context.WithTimeout(ctx, 30*time.Second)
	defer cancel()
	conn, err := pgconn.ConnectConfig(cctx, cfg)
	if err != nil {
		return nil, err
	}
	return &Database{srv: s, name: name, Conn: conn}, nil
}

// Exec runs sql with the simple query protocol, exactly like the postgres
// driver of golang-migrate does with a whole migration file: all statements
// of the file go in one Query message.
func (d *Database) Exec(ctx context.Context, sql string) error {
	_, err := d.Conn.Exec(ctx, sql).ReadAll()
	return err
}

// QueryStrings runs a query returning a single text column.
func (d *Database) QueryStrings(ctx context.Context, sql string) ([]string, error) {
	res, err := d.Conn.Exec(ctx, sql).ReadAll()
	if err != nil {
		return nil, err
	}
	var out []string
	for _, r := range res {
		for _, row := range r.Rows {
			out = append(out, string(row[0]))
		}
	}
	return out, nil
}

// DumpSchema returns pg_dump --schema-only output for one schema.
func (d *Database) DumpSchema(ctx context.Context, schema string) (string, error) {
	cfg, err := pgconn.ParseConfig(d.srv.dsn)
	if err != nil {
		return "", err
	}
	conn := fmt.Sprintf("host=%s port=%d user=%s dbname=%s", cfg.Host, cfg.Port, cfg.User, d.name)
	cmd := exec.CommandContext(ctx, d.srv.pgDump(), "--schema-only", "--no-owner", "--schema="+schema, "-d", conn)
	if cfg.Password != "" {
		cmd.Env = append(os.Environ(), "PGPASSWORD="+cfg.Password)
	}
	out, err := cmd.Output()
	if err != nil {
		if ee, ok := err.(*exec.ExitError); ok {
			return "", fmt.Errorf("pg_dump: %w: %s", err, ee.Stderr)
		}
		return "", fmt.Errorf("pg_dump: %w", err)
	}
	return string(out), nil
}

// Drop closes the connection and drops the database.
func (d *Database) Drop(ctx context.Context) {
	_ = d.Conn.Close(ctx)
	admin, err := pgconn.Connect(ctx, d.srv.dsn)
	if err != nil {
		return
	}
	defer admin.Close(ctx)
	_ = d.srv.dropDatabase(ctx, admin, d.name)
}

func quoteIdent(s string) string {
	return `"` + strings.ReplaceAll(s, `"`, `""`) + `"`
}

func quoteLiteral(s string) string {
	return `'` + strings.ReplaceAll(s, `'`, `''`) + `'`
}
