package harness

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
)

// CaseMeta is the content of case.json.
type CaseMeta struct {
	Title       string `json:"title"`
	Description string `json:"description"`
	// Expect is "pass" (default) or "limitation" for cases that no static
	// rewriter is expected to handle.
	Expect string `json:"expect"`
}

// Migration is a pair of golang-migrate files with the same version.
type Migration struct {
	Version  uint64
	Name     string
	UpFile   string
	DownFile string
	Up       string
	Down     string
}

// Case is one corpus directory.
type Case struct {
	Name       string
	Dir        string
	Meta       CaseMeta
	Setup      string
	Check      string
	Migrations []Migration
}

var migrationFileRe = regexp.MustCompile(`^(\d+)_(.+)\.(up|down)\.sql$`)

// LoadCorpus reads all case directories from dir.
func LoadCorpus(dir string) ([]Case, error) {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return nil, err
	}
	var cases []Case
	for _, e := range entries {
		if !e.IsDir() {
			continue
		}
		c, err := loadCase(filepath.Join(dir, e.Name()))
		if err != nil {
			return nil, fmt.Errorf("case %s: %w", e.Name(), err)
		}
		cases = append(cases, c)
	}
	sort.Slice(cases, func(i, j int) bool { return cases[i].Name < cases[j].Name })
	return cases, nil
}

func loadCase(dir string) (Case, error) {
	c := Case{Name: filepath.Base(dir), Dir: dir, Meta: CaseMeta{Expect: "pass"}}
	if b, err := os.ReadFile(filepath.Join(dir, "case.json")); err == nil {
		if err := json.Unmarshal(b, &c.Meta); err != nil {
			return c, err
		}
		if c.Meta.Expect == "" {
			c.Meta.Expect = "pass"
		}
	}
	if b, err := os.ReadFile(filepath.Join(dir, "setup.sql")); err == nil {
		c.Setup = string(b)
	}
	if b, err := os.ReadFile(filepath.Join(dir, "check.sql")); err == nil {
		c.Check = string(b)
	}
	entries, err := os.ReadDir(dir)
	if err != nil {
		return c, err
	}
	byVersion := map[uint64]*Migration{}
	for _, e := range entries {
		m := migrationFileRe.FindStringSubmatch(e.Name())
		if m == nil {
			continue
		}
		v, err := strconv.ParseUint(m[1], 10, 64)
		if err != nil {
			return c, err
		}
		b, err := os.ReadFile(filepath.Join(dir, e.Name()))
		if err != nil {
			return c, err
		}
		mig := byVersion[v]
		if mig == nil {
			mig = &Migration{Version: v, Name: m[2]}
			byVersion[v] = mig
		}
		if m[3] == "up" {
			mig.UpFile, mig.Up = e.Name(), string(b)
		} else {
			mig.DownFile, mig.Down = e.Name(), string(b)
		}
	}
	for _, m := range byVersion {
		c.Migrations = append(c.Migrations, *m)
	}
	sort.Slice(c.Migrations, func(i, j int) bool { return c.Migrations[i].Version < c.Migrations[j].Version })
	return c, nil
}
