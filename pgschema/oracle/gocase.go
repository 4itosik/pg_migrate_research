package oracle

// GoCamelCase converts a protobuf field name to the name protoc-gen-go gives
// the Go field: "table_elts" becomes "TableElts". The generator of the AST
// and the tree comparison both use it, so that a field of a libpg_query
// message is found in the library's struct by name.
func GoCamelCase(s string) string {
	var b []byte
	for i := 0; i < len(s); i++ {
		c := s[i]
		switch {
		case c == '.' && i+1 < len(s) && isLower(s[i+1]):
			// skip over '.' in ".{{lowercase}}"
		case c == '.':
			b = append(b, '_')
		case c == '_' && (i == 0 || s[i-1] == '.'):
			b = append(b, 'X')
		case c == '_' && i+1 < len(s) && isLower(s[i+1]):
			// skip over '_' in "_{{lowercase}}"
		case c >= '0' && c <= '9':
			b = append(b, c)
		default:
			if isLower(c) {
				c -= 'a' - 'A'
			}
			b = append(b, c)
			for ; i+1 < len(s) && isLower(s[i+1]); i++ {
				b = append(b, s[i+1])
			}
		}
	}
	return string(b)
}

func isLower(c byte) bool { return c >= 'a' && c <= 'z' }
