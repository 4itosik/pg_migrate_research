//go:build wasm2go

package pgparse

import (
	pg "github.com/pganalyze/pg_query_go/v6"
	"google.golang.org/protobuf/proto"

	"github.com/4itosik/pg_migrate_research/poc/pgquery/internal/libpgquery"
)

// Backend names the backend in reports.
const Backend = "go-pgquery-wasm2go"

// Library describes the backend in reports.
const Library = "libpg_query 17 from github.com/wasilibs/go-pgquery, translated to Go by wasm2go"

func Parse(sql string) (*pg.ParseResult, error) {
	b, err := libpgquery.ParseToProtobuf(sql)
	if err != nil {
		return nil, err
	}
	tree := &pg.ParseResult{}
	if err := proto.Unmarshal(b, tree); err != nil {
		return nil, err
	}
	return tree, nil
}

func Scan(sql string) (*pg.ScanResult, error) {
	b, err := libpgquery.ScanToProtobuf(sql)
	if err != nil {
		return nil, err
	}
	res := &pg.ScanResult{}
	if err := proto.Unmarshal(b, res); err != nil {
		return nil, err
	}
	return res, nil
}

func ParsePlPgSqlToJSON(sql string) (string, error) { return libpgquery.ParsePlPgSqlToJSON(sql) }
