package ast

import (
	"fmt"
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

// Diff describes the first difference between two trees that Equal would
// find, as "path: a, b", or returns "" when they are equal. It is for error
// messages.
func Diff(a, b Node) string {
	return diffValues("", reflect.ValueOf(a), reflect.ValueOf(b))
}

func diffValues(path string, a, b reflect.Value) string {
	if a.IsValid() != b.IsValid() {
		return path + ": one side is missing"
	}
	if !a.IsValid() {
		return ""
	}
	if a.Type() != b.Type() {
		return fmt.Sprintf("%s: %s, %s", path, a.Type(), b.Type())
	}
	switch a.Kind() {
	case reflect.Pointer, reflect.Interface:
		if a.IsNil() || b.IsNil() {
			if a.IsNil() == b.IsNil() {
				return ""
			}
			return path + ": one side is nil"
		}
		if a.Elem().Kind() == reflect.Struct {
			path += "(" + a.Elem().Type().Name() + ")"
		}
		return diffValues(path, a.Elem(), b.Elem())
	case reflect.Struct:
		for i := 0; i < a.NumField(); i++ {
			name := a.Type().Field(i).Name
			if isLocationField(name) {
				continue
			}
			if d := diffValues(path+"."+name, a.Field(i), b.Field(i)); d != "" {
				return d
			}
		}
		return ""
	case reflect.Slice:
		if a.Len() != b.Len() {
			return fmt.Sprintf("%s: %d elements, %d elements", path, a.Len(), b.Len())
		}
		for i := 0; i < a.Len(); i++ {
			if d := diffValues(fmt.Sprintf("%s[%d]", path, i), a.Index(i), b.Index(i)); d != "" {
				return d
			}
		}
		return ""
	}
	if a.Interface() != b.Interface() {
		return fmt.Sprintf("%s: %v, %v", path, a.Interface(), b.Interface())
	}
	return ""
}
