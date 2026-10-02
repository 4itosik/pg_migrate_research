package pgschema

// Rewrite qualifies the names in the text of one migration with a schema: the
// text goes in, with the schema and the other settings in opts (opts.Schema is
// the name of the schema), and the text with the schema inserted comes out, or
// an error and no text. The warnings are the places that cannot be rewritten
// statically.
//
// It is New, Learn and Rewrite in one call, for a migration that stands on its
// own. Several files that depend on each other (a type created by one and used
// by another) go through one Rewriter: Learn every up file first, then Rewrite
// each file.
func Rewrite(sql string, opts Options) (string, []string, error) {
	r, err := New(opts)
	if err != nil {
		return "", nil, err
	}
	return r.Rewrite(sql)
}
