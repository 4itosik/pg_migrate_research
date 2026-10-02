package pgschema

import "testing"

// The generated table is what the servers reported: a few facts that the rules
// rely on.
func TestContribObjects(t *testing.T) {
	has := func(list []string, name string) bool {
		for _, n := range list {
			if n == name {
				return true
			}
		}
		return false
	}
	if !has(contribObjects["pgcrypto"].funcs, "digest") || !has(contribObjects["pgcrypto"].funcs, "crypt") {
		t.Error("pgcrypto lacks digest or crypt")
	}
	if !has(contribObjects["uuid-ossp"].funcs, "uuid_generate_v4") {
		t.Error("uuid-ossp lacks uuid_generate_v4")
	}
	if !has(contribObjects["citext"].types, "citext") || !contribObjects["citext"].ops {
		t.Error("citext lacks its type or operators")
	}
	if contribObjects["pgcrypto"].ops {
		t.Error("pgcrypto has no operators")
	}
	for ext, objs := range contribObjects {
		for _, list := range [][]string{objs.funcs, objs.types, objs.rels} {
			if has(list, "gen_random_uuid") || has(list, "now") || has(list, "int4") {
				t.Errorf("%s lists a name of the core", ext)
			}
		}
	}
	if len(contribObjects) < 40 {
		t.Errorf("only %d extensions", len(contribObjects))
	}
}
