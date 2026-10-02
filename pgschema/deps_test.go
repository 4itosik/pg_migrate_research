package pgschema_test

import (
	"os/exec"
	"strings"
	"testing"
)

// TestDependencies keeps the module on the standard library: the runtime of
// the library has no third-party imports, no cgo, no WebAssembly and no
// libpg_query. The oracle in ./oracle is a separate module and is not part
// of this one.
func TestDependencies(t *testing.T) {
	out, err := exec.Command("go", "list", "-deps", "-test",
		"-f", "{{if not .Standard}}{{with .Module}}{{.Path}}{{else}}no-module:{{.ImportPath}}{{end}}{{end}}",
		"./...").Output()
	if err != nil {
		t.Fatalf("go list: %v", err)
	}
	for _, mod := range strings.Fields(string(out)) {
		if mod != "github.com/4itosik/pg_migrate_research/pgschema" {
			t.Errorf("dependency outside the module and the standard library: %s", mod)
		}
	}
}
