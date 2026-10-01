package pgqrewrite

import (
	"fmt"
	"regexp"
	"sort"
	"strings"

	pg "github.com/pganalyze/pg_query_go/v6"
	pgquery "github.com/wasilibs/go-pgquery"
)

// tokens is the scanner output of a SQL text without comments.
type tokens struct {
	src  string
	list []*pg.ScanToken
}

func scanTokens(src string) (*tokens, error) {
	res, err := pgquery.Scan(src)
	if err != nil {
		return nil, err
	}
	t := &tokens{src: src}
	for _, tok := range res.Tokens {
		if tok.Token == pg.Token_SQL_COMMENT || tok.Token == pg.Token_C_COMMENT {
			continue
		}
		t.list = append(t.list, tok)
	}
	return t, nil
}

func (t *tokens) len() int { return len(t.list) }

// firstFrom returns the index of the first token starting at or after pos.
func (t *tokens) firstFrom(pos int) int {
	return sort.Search(len(t.list), func(i int) bool { return int(t.list[i].Start) >= pos })
}

// at returns the index of the token starting exactly at pos, or -1.
func (t *tokens) at(pos int) int {
	i := t.firstFrom(pos)
	if i < len(t.list) && int(t.list[i].Start) == pos {
		return i
	}
	return -1
}

func (t *tokens) text(i int) string {
	tok := t.list[i]
	return t.src[tok.Start:tok.End]
}

func (t *tokens) is(i int, tok pg.Token) bool {
	return i >= 0 && i < len(t.list) && t.list[i].Token == tok
}

// ident returns the normalized identifier for token i: unquoted identifiers
// and non-reserved keywords are lower-cased, quoted identifiers are
// unquoted. Reserved keywords and other tokens are not identifiers.
func (t *tokens) ident(i int) (string, bool) {
	if i < 0 || i >= len(t.list) {
		return "", false
	}
	tok := t.list[i]
	raw := t.src[tok.Start:tok.End]
	switch {
	case tok.Token == pg.Token_IDENT:
		if strings.HasPrefix(raw, `"`) {
			return strings.ReplaceAll(raw[1:len(raw)-1], `""`, `"`), true
		}
		return strings.ToLower(raw), true
	case tok.KeywordKind != pg.KeywordKind_NO_KEYWORD && tok.KeywordKind != pg.KeywordKind_RESERVED_KEYWORD:
		return strings.ToLower(raw), true
	}
	return "", false
}

// matchName reports whether the tokens starting at i spell the qualified
// name parts (p1 . p2 ...) and are not part of a longer qualified name.
func (t *tokens) matchName(i, end int, parts []string) bool {
	if i > 0 && t.is(i-1, pg.Token_ASCII_46) {
		return false
	}
	j := i
	for k, p := range parts {
		if k > 0 {
			if j >= end || !t.is(j, pg.Token_ASCII_46) {
				return false
			}
			j++
		}
		if j >= end {
			return false
		}
		if id, ok := t.ident(j); !ok || id != p {
			return false
		}
		j++
	}
	return !(j < end && t.is(j, pg.Token_ASCII_46))
}

// findName returns the index of the first token in [from, end) where the
// qualified name parts start, or -1.
func (t *tokens) findName(parts []string, from, end int) int {
	for i := from; i < end; i++ {
		if t.matchName(i, end, parts) {
			return i
		}
	}
	return -1
}

// findToken returns the index of the first token of one of the kinds in
// [from, end), or -1.
func (t *tokens) findToken(from, end int, kinds ...pg.Token) int {
	for i := from; i < end; i++ {
		for _, k := range kinds {
			if t.list[i].Token == k {
				return i
			}
		}
	}
	return -1
}

var simpleIdent = regexp.MustCompile(`^[a-z_][a-z0-9_$]*$`)

// quoteIdent quotes an identifier only when PostgreSQL requires it.
func quoteIdent(s string) string {
	if simpleIdent.MatchString(s) {
		if res, err := pgquery.Scan(s); err == nil && len(res.Tokens) == 1 &&
			res.Tokens[0].Token == pg.Token_IDENT {
			return s
		}
	}
	return `"` + strings.ReplaceAll(s, `"`, `""`) + `"`
}

func quoteLiteral(s string) string {
	return `'` + strings.ReplaceAll(s, `'`, `''`) + `'`
}

// dollarQuote quotes a function body with a tag that does not occur in it.
func dollarQuote(body string) string {
	tag := "$$"
	for i := 0; strings.Contains(body, tag); i++ {
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
			part, s = strings.ToLower(strings.TrimSpace(s[:i])), s[i:]
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

// strs returns the String values of a name list, or nil if the list holds
// anything else (A_Star, ...).
func strs(nodes []*pg.Node) []string {
	out := make([]string, 0, len(nodes))
	for _, n := range nodes {
		s := n.GetString_()
		if s == nil {
			return nil
		}
		out = append(out, s.Sval)
	}
	return out
}

// edit replaces src[start:end] with text; start == end is an insertion.
type edit struct {
	start, end int
	text       string
}

// applyEdits applies non-overlapping edits. Identical edits are merged.
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

func lineStarts(s string) []int {
	starts := []int{0}
	for i := 0; i < len(s); i++ {
		if s[i] == '\n' {
			starts = append(starts, i+1)
		}
	}
	return starts
}

func snippet(s string) string {
	s = strings.Join(strings.Fields(s), " ")
	if len(s) > 70 {
		s = s[:67] + "..."
	}
	return s
}
