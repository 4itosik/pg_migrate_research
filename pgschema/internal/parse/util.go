// Package parse is the parser of PostgreSQL: a port of the grammar of
// src/backend/parser/gram.y (PostgreSQL 17) to goyacc, producing the parse
// tree of package ast with the byte locations PostgreSQL records.
//
// The grammar is in gram/*.y; gram.y is assembled from those files and
// gram_gen.go is generated from it (see generate.go). The action code is
// written by hand against the helper functions in this package, which are
// ports of the C helpers at the end of gram.y and of makefuncs.c.
//
// Portions Copyright (c) 1996-2024, PostgreSQL Global Development Group
// Portions Copyright (c) 1994, Regents of the University of California
//
// PostgreSQL License: see ../../LICENSE.PostgreSQL.
package parse

import (
	"reflect"
	"strings"

	. "github.com/4itosik/pg_migrate_research/pgschema/internal/ast"
)

// as asserts n to the node type T. It returns the zero value, a nil pointer,
// when n is nil or of another type. The grammar keeps every node, whatever
// its C type, in one Node field of the semantic value, and uses as where the
// C code reads a field of a specific node type.
func as[T any](n Node) T {
	t, _ := n.(T)
	return t
}

// nn returns n as a Node, or a nil Node when n is a nil pointer. Use it
// when a value that may be nil goes into a Node field: a nil *RangeVar in a
// Node is not a nil Node.
func nn[T Node](n T) Node {
	var zero T
	if any(n) == any(zero) {
		return nil
	}
	return n
}

// listNode is (Node *) list: PostgreSQL stores a List in a Node pointer as
// a List node, and an empty list as a null pointer.
func listNode(l []Node) Node {
	if len(l) == 0 {
		return nil
	}
	return &List{Items: l}
}

// asList is (List *) node: the items of a List node.
func asList(n Node) []Node {
	if l, ok := n.(*List); ok {
		return l.Items
	}
	return nil
}

// strVal is strVal(node) for a String node.
func strVal(n Node) string {
	if s, ok := n.(*String); ok {
		return s.Sval
	}
	return ""
}

// intVal is intVal(node) for an Integer node.
func intVal(n Node) int32 {
	if i, ok := n.(*Integer); ok {
		return i.Ival
	}
	return 0
}

// nameListToString is NameListToString: the dotted name of a list of String
// nodes, with "*" for A_Star.
func nameListToString(names []Node) string {
	var b strings.Builder
	for i, n := range names {
		if i > 0 {
			b.WriteByte('.')
		}
		switch v := n.(type) {
		case *String:
			b.WriteString(v.Sval)
		case *A_Star:
			b.WriteByte('*')
		}
	}
	return b.String()
}

// exprLocation is a simplified exprLocation of nodeFuncs.c, used only for
// the cursor position of errors: the Location field of the node, or of the
// first element of a list, -1 when there is none.
func exprLocation(n Node) int32 {
	if isNilNode(n) {
		return -1
	}
	if l, ok := n.(*List); ok {
		if len(l.Items) == 0 {
			return -1
		}
		return exprLocation(l.Items[0])
	}
	v := reflect.ValueOf(n).Elem()
	if f := v.FieldByName("Location"); f.IsValid() && f.Kind() == reflect.Int32 {
		return int32(f.Int())
	}
	return -1
}

func isNilNode(n Node) bool {
	if n == nil {
		return true
	}
	v := reflect.ValueOf(n)
	return v.Kind() == reflect.Pointer && v.IsNil()
}

// nodesEqual is equal() for the nodes the grammar compares: structural
// equality, ignoring the locations.
func nodesEqual(a, b Node) bool {
	return valuesEqual(reflect.ValueOf(a), reflect.ValueOf(b))
}

func valuesEqual(a, b reflect.Value) bool {
	if a.IsValid() != b.IsValid() {
		return false
	}
	if !a.IsValid() {
		return true
	}
	if a.Type() != b.Type() {
		return false
	}
	switch a.Kind() {
	case reflect.Pointer, reflect.Interface:
		if a.IsNil() || b.IsNil() {
			return a.IsNil() == b.IsNil()
		}
		return valuesEqual(a.Elem(), b.Elem())
	case reflect.Struct:
		for i := 0; i < a.NumField(); i++ {
			if name := a.Type().Field(i).Name; name == "Location" || name == "Loc" {
				continue
			}
			if !valuesEqual(a.Field(i), b.Field(i)) {
				return false
			}
		}
		return true
	case reflect.Slice:
		if a.Len() != b.Len() {
			return false
		}
		for i := 0; i < a.Len(); i++ {
			if !valuesEqual(a.Index(i), b.Index(i)) {
				return false
			}
		}
		return true
	}
	return a.Interface() == b.Interface()
}
