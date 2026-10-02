package pgschema

import (
	"fmt"
	"sort"
	"strings"
)

// edit replaces src[start:end] with text; start == end is an insertion.
type edit struct {
	start, end int
	text       string
}

// applyEdits applies edits that do not overlap. Identical edits are merged.
func applyEdits(src string, edits []edit) (string, error) {
	if len(edits) == 0 {
		return src, nil
	}
	sorted := append([]edit(nil), edits...)
	sort.SliceStable(sorted, func(i, j int) bool {
		if sorted[i].start != sorted[j].start {
			return sorted[i].start < sorted[j].start
		}
		return sorted[i].end < sorted[j].end
	})
	var b strings.Builder
	pos := 0
	var prev *edit
	for i := range sorted {
		e := &sorted[i]
		if prev != nil && *prev == *e {
			continue
		}
		if e.start < pos || (prev != nil && e.start == prev.start && e.start == e.end && prev.start == prev.end) {
			return "", fmt.Errorf("conflicting edits at offset %d", e.start)
		}
		b.WriteString(src[pos:e.start])
		b.WriteString(e.text)
		pos = e.end
		prev = e
	}
	b.WriteString(src[pos:])
	return b.String(), nil
}

func shiftEdits(edits []edit, delta int) []edit {
	out := make([]edit, len(edits))
	for i, e := range edits {
		out[i] = edit{start: e.start + delta, end: e.end + delta, text: e.text}
	}
	return out
}

func quoteLiteral(s string) string {
	return `'` + strings.ReplaceAll(s, `'`, `''`) + `'`
}

// dollarQuote quotes a function body with a tag that closes the literal where
// the body ends: the tag must not occur in the body, nor appear earlier
// because the body ends with the start of it (a body that ends with $ and the
// tag $$ would close one character too early).
func dollarQuote(body string) string {
	tag := "$$"
	for i := 0; strings.Index(body+tag, tag) != len(body); i++ {
		tag = fmt.Sprintf("$body%d$", i)
	}
	return tag + body + tag
}

// splitQualifiedName parses an identifier chain as regclass input does:
// parts are separated by dots, unquoted parts are lower-cased.
func splitQualifiedName(s string) ([]string, bool) {
	s = strings.TrimSpace(s)
	var parts []string
	for {
		var part string
		if strings.HasPrefix(s, `"`) {
			var b strings.Builder
			i := 1
			for {
				if i >= len(s) {
					return nil, false
				}
				if s[i] == '"' {
					if i+1 < len(s) && s[i+1] == '"' {
						b.WriteByte('"')
						i += 2
						continue
					}
					i++
					break
				}
				b.WriteByte(s[i])
				i++
			}
			part, s = b.String(), strings.TrimSpace(s[i:])
		} else {
			i := strings.IndexAny(s, ".\"")
			if i < 0 {
				i = len(s)
			}
			part, s = asciiLower(strings.TrimSpace(s[:i])), s[i:]
			if part == "" {
				return nil, false
			}
		}
		parts = append(parts, part)
		if s == "" {
			return parts, true
		}
		if s[0] != '.' {
			return nil, false
		}
		s = strings.TrimSpace(s[1:])
	}
}

// asciiLower folds the ASCII letters of an unquoted identifier to lower case,
// as PostgreSQL does in UTF-8 (downcase_identifier): other letters stay.
func asciiLower(s string) string {
	return strings.Map(func(c rune) rune {
		if c >= 'A' && c <= 'Z' {
			return c + 'a' - 'A'
		}
		return c
	}, s)
}

// snippet shortens a statement for a message.
func snippet(s string) string {
	s = strings.Join(strings.Fields(s), " ")
	if len(s) > 70 {
		s = s[:67] + "..."
	}
	return s
}

func dedupe(in []Warning) []Warning {
	seen := map[Warning]bool{}
	var out []Warning
	for _, s := range in {
		if !seen[s] {
			seen[s] = true
			out = append(out, s)
		}
	}
	return out
}
