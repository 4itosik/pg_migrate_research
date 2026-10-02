package oracle

import (
	"fmt"
	"os"
	"path/filepath"
	"reflect"
	"regexp"
	"sort"
	"strings"

	pg "github.com/pganalyze/pg_query_go/v6"
)

// RegressFile is one file of the PostgreSQL regression suite split into
// statements. The dataset is described in ../../DATASET.md.
type RegressFile struct {
	Name string
	// Statements are the top-level statements of the file. It is nil when
	// the scanner rejected the file even after dropping the offending
	// lines.
	Statements []string
}

// LoadRegress reads and splits every *.sql file in dir.
func LoadRegress(dir string) ([]RegressFile, error) {
	paths, err := filepath.Glob(filepath.Join(dir, "*.sql"))
	if err != nil {
		return nil, err
	}
	if len(paths) == 0 {
		return nil, fmt.Errorf("no *.sql files in %s", dir)
	}
	sort.Strings(paths)
	files := make([]RegressFile, 0, len(paths))
	for _, p := range paths {
		b, err := os.ReadFile(p)
		if err != nil {
			return nil, err
		}
		files = append(files, RegressFile{Name: filepath.Base(p), Statements: SplitStatements(string(b))})
	}
	return files, nil
}

// Statement is a regression test statement that libpg_query accepts.
type Statement struct {
	File string
	SQL  string
	// Tree is the libpg_query parse tree.
	Tree *pg.ParseResult
}

// Accepted returns the statements of files that libpg_query parses, in file
// order, the same way as the research did.
func Accepted(files []RegressFile) []Statement {
	var out []Statement
	for _, f := range files {
		for _, s := range f.Statements {
			if tree, err := Parse(s); err == nil {
				out = append(out, Statement{File: f.Name, SQL: s, Tree: tree})
			}
		}
	}
	return out
}

// SplitStatements turns the text of a psql script into statements: psql
// meta-commands and COPY ... FROM stdin data are dropped, then the text is
// split on top-level semicolons with the PostgreSQL scanner, so semicolons in
// strings, comments and dollar quotes are ignored and BEGIN ATOMIC ... END
// bodies stay whole. A line with a token the scanner rejects is dropped,
// because the tests check such errors on purpose.
func SplitStatements(script string) []string {
	s, res, err := scanScript(stripPsql(script))
	if err != nil {
		return nil
	}
	var out []string
	start, depth, atomic := 0, 0, 0
	for _, tok := range res.Tokens {
		switch tok.Token {
		case pg.Token_ASCII_40:
			depth++
		case pg.Token_ASCII_41:
			depth--
		case pg.Token_ATOMIC:
			atomic++
		case pg.Token_CASE:
			if atomic > 0 {
				atomic++
			}
		case pg.Token_END_P:
			if atomic > 0 {
				atomic--
			}
		case pg.Token_ASCII_59:
			if depth == 0 && atomic == 0 {
				if stmt := strings.TrimSpace(s[start:tok.End]); stmt != ";" {
					out = append(out, stmt)
				}
				start = int(tok.End)
			}
		}
	}
	if rest := strings.TrimSpace(s[start:]); rest != "" {
		out = append(out, rest)
	}
	return out
}

var copyFromStdin = regexp.MustCompile(`(?i)\bfrom\s+stdin\b[^;]*;\s*$`)

// stripPsql blanks psql meta-commands and the inline data of COPY ... FROM
// stdin: neither is SQL, and the data can break the scanner.
func stripPsql(s string) string {
	lines := strings.Split(s, "\n")
	inCopy := false
	for i, l := range lines {
		t := strings.TrimSpace(l)
		switch {
		case inCopy:
			inCopy = t != `\.`
			lines[i] = ""
		case strings.HasPrefix(t, `\`):
			lines[i] = ""
		case copyFromStdin.MatchString(t):
			inCopy = true
		}
	}
	return strings.Join(lines, "\n")
}

// scanScript scans a whole script. When the scanner rejects a token, the
// line with the token is blanked and the scan is repeated.
func scanScript(s string) (string, *pg.ScanResult, error) {
	var err error
	for try := 0; try < 100; try++ {
		var res *pg.ScanResult
		if res, err = Scan(s); err == nil {
			return s, res, nil
		}
		v := reflect.ValueOf(err)
		if v.Kind() != reflect.Pointer || v.Elem().Kind() != reflect.Struct {
			break
		}
		f := v.Elem().FieldByName("Cursorpos")
		if !f.IsValid() || f.Int() <= 0 {
			break
		}
		// Cursorpos counts characters from 1.
		pos, n := len(s), int(f.Int())-1
		for i := range s {
			if n == 0 {
				pos = i
				break
			}
			n--
		}
		start := strings.LastIndexByte(s[:pos], '\n') + 1
		end := strings.IndexByte(s[pos:], '\n')
		if end < 0 {
			end = len(s)
		} else {
			end += pos
		}
		if start == end {
			break
		}
		s = s[:start] + s[end:]
	}
	return s, nil, err
}
