package oracle

import (
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
)

// UpdateMetrics sets section of the JSON metrics report at path to v and
// keeps the other sections. Stage tests and cmd/metrics write the report
// piece by piece, one section per stage ("stage1.lexer", ...). A section
// name with dots is stored as nested objects.
func UpdateMetrics(path string, section []string, v any) error {
	report := map[string]any{}
	b, err := os.ReadFile(path)
	switch {
	case err == nil:
		if err := json.Unmarshal(b, &report); err != nil {
			return err
		}
	case !errors.Is(err, os.ErrNotExist):
		return err
	}
	if len(section) == 0 {
		return errors.New("empty section")
	}
	// Round-trip through JSON so that the report holds generic values.
	raw, err := json.Marshal(v)
	if err != nil {
		return err
	}
	var val any
	if err := json.Unmarshal(raw, &val); err != nil {
		return err
	}
	m := report
	for _, k := range section[:len(section)-1] {
		next, ok := m[k].(map[string]any)
		if !ok {
			next = map[string]any{}
			m[k] = next
		}
		m = next
	}
	m[section[len(section)-1]] = val
	out, err := json.MarshalIndent(report, "", "  ")
	if err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	return os.WriteFile(path, append(out, '\n'), 0o644)
}

// EnforceBudgets reports whether the budget tests fail when a budget of the
// task is exceeded: always in CI, elsewhere when ENFORCE_BUDGETS is set. On a
// loaded machine the figures are worse than the 4 cores the budgets are for,
// so a local run only logs them.
func EnforceBudgets() bool {
	return os.Getenv("CI") != "" || os.Getenv("ENFORCE_BUDGETS") != ""
}
