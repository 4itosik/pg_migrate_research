package harness

import "testing"

// TestBaseline proves that the corpus is valid PostgreSQL when the target
// schema is on search_path.
func TestBaseline(t *testing.T) {
	RunTest(t, TestOptions{Config: Config{Candidate: "baseline", Library: "original SQL, search_path = auth, public", Mode: ModeBaseline}, Strict: true})
}

// TestNoop proves that the checks catch unqualified names: without rewriting
// every case must fail when the target schema is not on search_path.
func TestNoop(t *testing.T) {
	rep := RunTest(t, TestOptions{Config: Config{Candidate: "noop", Library: "original SQL, search_path = trap, public", Mode: ModeNoop}})
	for _, r := range rep.Results {
		if r.Status == "pass" {
			t.Errorf("%s passes without rewriting: the case does not detect missing qualification", r.Case)
		}
	}
}
