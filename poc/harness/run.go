package harness

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"time"
)

// Mode selects what the harness executes.
type Mode string

const (
	// ModeRewrite executes rewritten SQL with search_path = trap, public:
	// the target schema is not on the path, as behind pgbouncer.
	ModeRewrite Mode = "rewrite"
	// ModeBaseline executes the original SQL with search_path = <schema>, public.
	// It proves that the corpus itself is valid.
	ModeBaseline Mode = "baseline"
	// ModeNoop executes the original SQL with search_path = trap, public.
	// It proves that the checks detect missing qualification.
	ModeNoop Mode = "noop"
)

// Config describes one harness run.
type Config struct {
	Candidate string
	Library   string
	Mode      Mode
	Factory   Factory
	Schema    string
	// OutputDir receives the rewritten files as <case>/<file>.
	OutputDir string
	// SchemaDir holds normalized pg_dump --schema-only outputs of the
	// baseline run. The baseline writes them, other runs compare against
	// them, so a rewrite that silently changes the resulting schema fails.
	SchemaDir string
}

// CaseResult is the outcome of one case.
type CaseResult struct {
	Case      string   `json:"case"`
	Title     string   `json:"title"`
	Expect    string   `json:"expect"`
	Status    string   `json:"status"`
	Stage     string   `json:"stage,omitempty"`
	Error     string   `json:"error,omitempty"`
	Warnings  []string `json:"warnings,omitempty"`
	RewriteMS float64  `json:"rewrite_ms,omitempty"`
}

// Report is the outcome of a run over the corpus.
type Report struct {
	Candidate string       `json:"candidate"`
	Library   string       `json:"library"`
	Mode      Mode         `json:"mode"`
	Server    string       `json:"server_version"`
	Results   []CaseResult `json:"results"`
}

// Passed returns the number of passed cases.
func (r Report) Passed() int { return r.count("pass") }

// Skipped returns the number of cases skipped on this server version.
func (r Report) Skipped() int { return r.count("skip") }

func (r Report) count(status string) int {
	n := 0
	for _, c := range r.Results {
		if c.Status == status {
			n++
		}
	}
	return n
}

// Run executes all cases.
func Run(ctx context.Context, srv *Server, cases []Case, cfg Config) Report {
	if cfg.Schema == "" {
		cfg.Schema = "auth"
	}
	rep := Report{Candidate: cfg.Candidate, Library: cfg.Library, Mode: cfg.Mode, Server: srv.Version()}
	for _, c := range cases {
		rep.Results = append(rep.Results, runCase(ctx, srv, c, cfg))
	}
	return rep
}

func runCase(ctx context.Context, srv *Server, c Case, cfg Config) (res CaseResult) {
	res = CaseResult{Case: c.Name, Title: c.Meta.Title, Expect: c.Meta.Expect, Status: "pass"}
	fail := func(stage string, err error) CaseResult {
		res.Status, res.Stage, res.Error = "fail", stage, err.Error()
		return res
	}
	if c.Meta.MinServerVersion > srv.Major() {
		res.Status, res.Stage = "skip", "version"
		res.Error = fmt.Sprintf("needs PostgreSQL %d or newer", c.Meta.MinServerVersion)
		return res
	}
	ups := make([]string, len(c.Migrations))
	downs := make([]string, len(c.Migrations))
	for i, m := range c.Migrations {
		ups[i], downs[i] = m.Up, m.Down
	}

	searchPath := "trap, public"
	switch cfg.Mode {
	case ModeBaseline:
		searchPath = quoteIdent(cfg.Schema) + ", public"
	case ModeRewrite:
		rw, err := cfg.Factory(cfg.Schema)
		if err != nil {
			return fail("rewrite", err)
		}
		start := time.Now()
		for _, m := range c.Migrations {
			if m.Up == "" {
				continue
			}
			if err := rw.Learn(m.Up); err != nil {
				return fail("learn "+m.UpFile, err)
			}
		}
		rewrite := func(file, sql string) (string, error) {
			if sql == "" {
				return "", nil
			}
			r, err := rw.Rewrite(sql)
			if err != nil {
				return "", err
			}
			for _, w := range r.Warnings {
				res.Warnings = append(res.Warnings, file+": "+w)
			}
			if cfg.OutputDir != "" {
				dir := filepath.Join(cfg.OutputDir, c.Name)
				if err := os.MkdirAll(dir, 0o755); err != nil {
					return "", err
				}
				if err := os.WriteFile(filepath.Join(dir, file), []byte(r.SQL), 0o644); err != nil {
					return "", err
				}
			}
			return r.SQL, nil
		}
		for i, m := range c.Migrations {
			if ups[i], err = rewrite(m.UpFile, m.Up); err != nil {
				return fail("rewrite "+m.UpFile, err)
			}
			if downs[i], err = rewrite(m.DownFile, m.Down); err != nil {
				return fail("rewrite "+m.DownFile, err)
			}
		}
		res.RewriteMS = float64(time.Since(start).Microseconds()) / 1000
	}

	db, err := srv.NewDatabase(ctx, dbName(cfg.Candidate, c.Name))
	if err != nil {
		return fail("setup", err)
	}
	defer db.Drop(ctx)
	if err := db.Exec(ctx, fmt.Sprintf("CREATE SCHEMA %s; CREATE SCHEMA trap", quoteIdent(cfg.Schema))); err != nil {
		return fail("setup", err)
	}
	if c.Setup != "" {
		if err := db.Exec(ctx, c.Setup); err != nil {
			return fail("setup", err)
		}
	}
	for i, m := range c.Migrations {
		if ups[i] == "" {
			continue
		}
		if err := db.Exec(ctx, "SET search_path TO "+searchPath); err != nil {
			return fail("setup", err)
		}
		if err := db.Exec(ctx, ups[i]); err != nil {
			return fail("up "+m.UpFile, err)
		}
	}
	if cfg.SchemaDir != "" && cfg.Mode != ModeNoop {
		dump, err := db.DumpSchema(ctx, cfg.Schema)
		if err != nil {
			return fail("schema", err)
		}
		dump = normalizeDump(dump, cfg.Schema)
		path := filepath.Join(cfg.SchemaDir, c.Name+".sql")
		if cfg.Mode == ModeBaseline {
			if err := os.MkdirAll(cfg.SchemaDir, 0o755); err != nil {
				return fail("schema", err)
			}
			if err := os.WriteFile(path, []byte(dump), 0o644); err != nil {
				return fail("schema", err)
			}
		} else if want, err := os.ReadFile(path); err == nil {
			if d := diffLines(string(want), dump); d != "" {
				return fail("schema", fmt.Errorf("schema differs from the baseline:\n%s", d))
			}
		}
	}
	if c.Check != "" {
		if err := db.Exec(ctx, "SET search_path TO "+searchPath); err != nil {
			return fail("setup", err)
		}
		if err := db.Exec(ctx, c.Check); err != nil {
			return fail("check", err)
		}
	}
	leaks, err := db.QueryStrings(ctx, objectsQuery("trap", "public"))
	if err != nil {
		return fail("leak", err)
	}
	if len(leaks) > 0 {
		return fail("leak", fmt.Errorf("objects created outside of %s: %s", cfg.Schema, strings.Join(leaks, ", ")))
	}
	for i := len(c.Migrations) - 1; i >= 0; i-- {
		if downs[i] == "" {
			continue
		}
		if err := db.Exec(ctx, "SET search_path TO "+searchPath); err != nil {
			return fail("setup", err)
		}
		if err := db.Exec(ctx, downs[i]); err != nil {
			return fail("down "+c.Migrations[i].DownFile, err)
		}
	}
	left, err := db.QueryStrings(ctx, objectsQuery(cfg.Schema))
	if err != nil {
		return fail("down", err)
	}
	if len(left) > 0 {
		return fail("down", fmt.Errorf("objects left in %s after down migrations: %s", cfg.Schema, strings.Join(left, ", ")))
	}
	return res
}

// objectsQuery lists user objects (not owned by extensions) in the schemas.
func objectsQuery(schemas ...string) string {
	lits := make([]string, len(schemas))
	for i, s := range schemas {
		lits[i] = quoteLiteral(s)
	}
	return `
WITH ext AS (SELECT classid, objid FROM pg_depend WHERE deptype = 'e'),
ns AS (SELECT oid, nspname FROM pg_namespace WHERE nspname IN (` + strings.Join(lits, ", ") + `))
SELECT format('%s %s.%s', kind, nsp, name) FROM (
    SELECT 'relation' AS kind, ns.nspname AS nsp, c.relname::text AS name
    FROM pg_class c JOIN ns ON ns.oid = c.relnamespace
    WHERE NOT EXISTS (SELECT 1 FROM ext WHERE ext.classid = 'pg_class'::regclass AND ext.objid = c.oid)
    UNION ALL
    SELECT 'type', ns.nspname, t.typname::text
    FROM pg_type t JOIN ns ON ns.oid = t.typnamespace
    WHERE t.typrelid = 0 AND t.typcategory <> 'A'
      AND NOT EXISTS (SELECT 1 FROM ext WHERE ext.classid = 'pg_type'::regclass AND ext.objid = t.oid)
    UNION ALL
    SELECT 'function', ns.nspname, p.proname::text
    FROM pg_proc p JOIN ns ON ns.oid = p.pronamespace
    WHERE NOT EXISTS (SELECT 1 FROM ext WHERE ext.classid = 'pg_proc'::regclass AND ext.objid = p.oid)
    UNION ALL
    SELECT 'statistics', ns.nspname, s.stxname::text
    FROM pg_statistic_ext s JOIN ns ON ns.oid = s.stxnamespace
) x ORDER BY 1`
}

var (
	nonIdent   = regexp.MustCompile(`[^a-z0-9_]+`)
	dollarBody = regexp.MustCompile(`(?s)AS \$([A-Za-z_]*)\$.*?\$([A-Za-z_]*)\$`)
	dumpNoise  = regexp.MustCompile(`^(--.*|SET .*|SELECT pg_catalog\.set_config.*|\\(un)?restrict .*)$`)
)

// normalizeDump makes dumps of the baseline and of a rewrite comparable:
// comments and settings go away, function bodies (whose text legitimately
// differs: qualified names, deparser formatting) are replaced by a marker,
// and the target schema qualifier is removed.
func normalizeDump(dump, schema string) string {
	dump = dollarBody.ReplaceAllString(dump, "AS $$BODY$$")
	var lines []string
	for _, l := range strings.Split(dump, "\n") {
		if strings.TrimSpace(l) == "" || dumpNoise.MatchString(l) {
			continue
		}
		lines = append(lines, l)
	}
	out := strings.Join(lines, "\n") + "\n"
	out = strings.ReplaceAll(out, quoteIdent(schema)+".", "")
	return strings.ReplaceAll(out, schema+".", "")
}

// diffLines returns the first difference between two texts with context.
func diffLines(want, got string) string {
	if want == got {
		return ""
	}
	a, b := strings.Split(want, "\n"), strings.Split(got, "\n")
	i := 0
	for i < len(a) && i < len(b) && a[i] == b[i] {
		i++
	}
	ctx := func(l []string) string {
		lo, hi := i-1, i+2
		if lo < 0 {
			lo = 0
		}
		if hi > len(l) {
			hi = len(l)
		}
		if lo >= hi {
			return "(end)"
		}
		return strings.Join(l[lo:hi], "\n")
	}
	return fmt.Sprintf("--- baseline\n%s\n+++ rewritten\n%s", ctx(a), ctx(b))
}

func dbName(candidate, c string) string {
	n := nonIdent.ReplaceAllString(strings.ToLower("h_"+candidate+"_"+c), "_")
	if len(n) > 63 {
		n = n[:63]
	}
	return n
}

// WriteReport stores the report as JSON.
func WriteReport(path string, r Report) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	b, err := json.MarshalIndent(r, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(path, append(b, '\n'), 0o644)
}

// ReadReport loads a report written by WriteReport.
func ReadReport(path string) (Report, error) {
	var r Report
	b, err := os.ReadFile(path)
	if err != nil {
		return r, err
	}
	return r, json.Unmarshal(b, &r)
}
