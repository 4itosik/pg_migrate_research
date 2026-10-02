package ast

import (
	"reflect"
	"strings"
)

// Equal reports whether two trees are the same except for the byte
// locations: the fields named Location, Loc, StmtLocation, StmtLen and those
// that end in Location are not compared. It is equal() of PostgreSQL, which
// ignores locations too, and the check that a rewritten migration parses to
// the tree it was meant to.
func Equal(a, b Node) bool {
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
			if isLocationField(a.Type().Field(i).Name) {
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

func isLocationField(name string) bool {
	return name == "Loc" || name == "StmtLen" || strings.HasSuffix(name, "Location")
}
