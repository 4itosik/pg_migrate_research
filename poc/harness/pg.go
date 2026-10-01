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
	"strings"
	"time"

	"github.com/jackc/pgx/v5/pgconn"
)

// Server is a PostgreSQL server used for validation.
//
// If PG_DSN is set it is used as is (the role must be allowed to create
// databases and roles). Otherwise a throwaway cluster is created with initdb
// from PG_BIN, PATH or /usr/lib/postgresql/*/bin.
type Server struct {
	dsn     string
	version string
	stop    func()
}

// StartServer returns a running server.
func StartServer(ctx context.Context) (*Server, error) {
	if dsn := os.Getenv("PG_DSN"); dsn != "" {
		s := &Server{dsn: dsn, stop: func() {}}
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
	res, err := conn.Exec(ctx, "SHOW server_version").ReadAll()
	if err != nil {
		return err
	}
	s.version = string(res[0].Rows[0][0])
	return nil
}

// Version returns server_version.
func (s *Server) Version() string { return s.version }

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
	quoted := quoteIdent(name)
	if _, err := admin.Exec(ctx, "DROP DATABASE IF EXISTS "+quoted+" WITH (FORCE)").ReadAll(); err != nil {
		return nil, err
	}
	if _, err := admin.Exec(ctx, "CREATE DATABASE "+quoted+" TEMPLATE template0").ReadAll(); err != nil {
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

// Drop closes the connection and drops the database.
func (d *Database) Drop(ctx context.Context) {
	_ = d.Conn.Close(ctx)
	admin, err := pgconn.Connect(ctx, d.srv.dsn)
	if err != nil {
		return
	}
	defer admin.Close(ctx)
	_, _ = admin.Exec(ctx, "DROP DATABASE IF EXISTS "+quoteIdent(d.name)+" WITH (FORCE)").ReadAll()
}

func quoteIdent(s string) string {
	return `"` + strings.ReplaceAll(s, `"`, `""`) + `"`
}

func quoteLiteral(s string) string {
	return `'` + strings.ReplaceAll(s, `'`, `''`) + `'`
}
