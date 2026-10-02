//go:build wasm2go

package pgqrewrite

import (
	"bytes"
	"fmt"
	"os"
	"path/filepath"
	"reflect"
	"sort"
	"strings"
	"testing"

	wz "github.com/wasilibs/go-pgquery/parser"

	"github.com/4itosik/pg_migrate_research/poc/pgquery/internal/libpgquery"
)

// TestWasm2goSameBytes checks that the wasm2go build of libpg_query returns
// the same bytes as go-pgquery for the corpus files and for every statement
// of REGRESS_DIR: parse tree, scanner tokens, PL/pgSQL tree of functions and
// DO blocks, and every field of the errors.
//
//	REGRESS_DIR=/path/to/src/test/regress/sql go test -tags wasm2go -run TestWasm2goSameBytes -v
func TestWasm2goSameBytes(t *testing.T) {
	var inputs []string
	corpus := os.Getenv("CORPUS_DIR")
	if corpus == "" {
		corpus = "../corpus"
	}
	files, _ := filepath.Glob(filepath.Join(corpus, "*", "*.sql"))
	sort.Strings(files)
	for _, f := range files {
		b, err := os.ReadFile(f)
		if err != nil {
			t.Fatal(err)
		}
		inputs = append(inputs, string(b))
	}
	if dir := os.Getenv("REGRESS_DIR"); dir != "" {
		files, _ := filepath.Glob(filepath.Join(dir, "*.sql"))
		sort.Strings(files)
		for _, f := range files {
			b, err := os.ReadFile(f)
			if err != nil {
				t.Fatal(err)
			}
			inputs = append(inputs, splitStatements(stripPsql(string(b)))...)
		}
	}

	var parsed, failed, plpgsql, diffs int
	check := func(what, sql string, a, b []byte, errA, errB error) {
		if bytes.Equal(a, b) && errFields(errA) == errFields(errB) {
			return
		}
		diffs++
		if diffs <= 10 {
			t.Errorf("%s differs for %q:\n go-pgquery: %d bytes, %s\n wasm2go:    %d bytes, %s",
				what, snippet(sql), len(a), errFields(errA), len(b), errFields(errB))
		}
	}
	for _, sql := range inputs {
		a, errA := wz.ParseToProtobuf(sql)
		b, errB := libpgquery.ParseToProtobuf(sql)
		check("parse", sql, a, b, errA, errB)
		if errA == nil {
			parsed++
		} else {
			failed++
		}
		a, errA = wz.ScanToProtobuf(sql)
		b, errB = libpgquery.ScanToProtobuf(sql)
		check("scan", sql, a, b, errA, errB)

		// libpg_query asserts on functions without a body string, so only
		// PL/pgSQL functions and DO blocks go to the PL/pgSQL parser, as in
		// the rewriter.
		u := strings.ToUpper(sql)
		if (strings.Contains(u, "PLPGSQL") && (strings.Contains(u, "FUNCTION") || strings.Contains(u, "PROCEDURE"))) ||
			strings.HasPrefix(u, "DO") {
			plpgsql++
			ja, errA := wz.ParsePlPgSqlToJSON(sql)
			jb, errB := libpgquery.ParsePlPgSqlToJSON(sql)
			check("PL/pgSQL", sql, []byte(ja), []byte(jb), errA, errB)
		}
	}
	t.Logf("inputs %d (parsed %d, errors %d), PL/pgSQL inputs %d, differences %d", len(inputs), parsed, failed, plpgsql, diffs)
}

// errFields formats every field of a libpg_query error of either backend.
func errFields(err error) string {
	if err == nil {
		return "ok"
	}
	v := reflect.ValueOf(err)
	if v.Kind() != reflect.Pointer || v.Elem().Kind() != reflect.Struct {
		return "error " + err.Error()
	}
	v = v.Elem()
	var parts []string
	for _, f := range []string{"Message", "Funcname", "Filename", "Lineno", "Cursorpos", "Context"} {
		parts = append(parts, fmt.Sprintf("%s=%v", f, v.FieldByName(f)))
	}
	return strings.Join(parts, " ")
}
