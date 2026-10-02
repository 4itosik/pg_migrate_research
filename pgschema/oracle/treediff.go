package oracle

import (
	"fmt"
	"reflect"
	"strings"

	"github.com/4itosik/pg_migrate_research/pgschema/internal/ast"
	pg "github.com/pganalyze/pg_query_go/v6"
	"google.golang.org/protobuf/reflect/protoreflect"
)

// Diff is the first difference between a tree of the library and the
// libpg_query tree of the same statement.
type Diff struct {
	// Path locates the difference: "stmts[0].SelectStmt.targetList[1]...".
	Path string
	// Ours and Theirs describe the two sides at Path.
	Ours, Theirs string
}

func (d *Diff) String() string {
	return fmt.Sprintf("%s: ours %s, libpg_query %s", d.Path, d.Ours, d.Theirs)
}

// DiffStatements compares the statements the library parsed with a
// libpg_query result field by field: node types, scalars, enum values
// (libpg_query numbers them one higher), lists and the byte locations.
// Fields that libpg_query has no counterpart for, such as String.Loc, are
// not compared. It returns nil when the trees are equal.
func DiffStatements(ours []*ast.RawStmt, theirs *pg.ParseResult) *Diff {
	if len(ours) != len(theirs.Stmts) {
		return &Diff{Path: "stmts", Ours: fmt.Sprintf("%d statements", len(ours)), Theirs: fmt.Sprintf("%d statements", len(theirs.Stmts))}
	}
	for i, s := range theirs.Stmts {
		path := fmt.Sprintf("stmts[%d]", i)
		if ours[i] == nil {
			return &Diff{Path: path, Ours: "nil", Theirs: "RawStmt"}
		}
		if d := diffMessage(path, reflect.ValueOf(ours[i]).Elem(), s.ProtoReflect()); d != nil {
			return d
		}
	}
	return nil
}

// isNil reports whether a Node interface is nil or holds a nil pointer.
func isNil(n ast.Node) bool {
	if n == nil {
		return true
	}
	v := reflect.ValueOf(n)
	return v.Kind() == reflect.Pointer && v.IsNil()
}

func diffNode(path string, ours ast.Node, theirs protoreflect.Message) *Diff {
	var inner protoreflect.Message
	name := ""
	if theirs.IsValid() {
		od := theirs.Descriptor().Oneofs().ByName("node")
		if fd := theirs.WhichOneof(od); fd != nil {
			inner = theirs.Get(fd).Message()
			name = string(fd.Message().Name())
		}
	}
	switch {
	case inner == nil && isNil(ours):
		return nil
	case inner == nil:
		return &Diff{Path: path, Ours: reflect.TypeOf(ours).Elem().Name(), Theirs: "nothing"}
	case isNil(ours):
		return &Diff{Path: path, Ours: "nothing", Theirs: name}
	}
	if got := reflect.TypeOf(ours).Elem().Name(); got != name {
		return &Diff{Path: path, Ours: got, Theirs: name}
	}
	return diffMessage(path+"."+name, reflect.ValueOf(ours).Elem(), inner)
}

// diffMessage compares a node struct with the libpg_query message of the
// same type, field by field.
func diffMessage(path string, ours reflect.Value, theirs protoreflect.Message) *Diff {
	md := theirs.Descriptor()
	for i := 0; i < md.Fields().Len(); i++ {
		fd := md.Fields().Get(i)
		fpath := path + "." + string(fd.Name())
		if o := fd.ContainingOneof(); o != nil && !o.IsSynthetic() {
			// A_Const: ival, fval, boolval, sval and bsval are one field Val
			if d := diffConstValue(path, ours, theirs, o); d != nil {
				return d
			}
			continue
		}
		field := ours.FieldByName(GoCamelCase(string(fd.Name())))
		if !field.IsValid() {
			return &Diff{Path: fpath, Ours: "no such field", Theirs: "present"}
		}
		if d := diffField(fpath, field, theirs, fd); d != nil {
			return d
		}
	}
	return nil
}

func diffConstValue(path string, ours reflect.Value, theirs protoreflect.Message, o protoreflect.OneofDescriptor) *Diff {
	val := ours.FieldByName("Val")
	want := theirs.WhichOneof(o)
	got := val.Interface()
	gotNode, _ := got.(ast.Node)
	switch {
	case want == nil && isNil(gotNode):
		return nil
	case want == nil:
		return &Diff{Path: path + ".val", Ours: reflect.TypeOf(gotNode).Elem().Name(), Theirs: "nothing"}
	case isNil(gotNode):
		return &Diff{Path: path + ".val", Ours: "nothing", Theirs: string(want.Message().Name())}
	}
	if name := reflect.TypeOf(gotNode).Elem().Name(); name != string(want.Message().Name()) {
		return &Diff{Path: path + ".val", Ours: name, Theirs: string(want.Message().Name())}
	}
	return diffMessage(path+"."+string(want.Name()), reflect.ValueOf(gotNode).Elem(), theirs.Get(want).Message())
}

func diffField(path string, ours reflect.Value, theirs protoreflect.Message, fd protoreflect.FieldDescriptor) *Diff {
	switch {
	case fd.IsList():
		return diffList(path, ours, theirs.Get(fd).List(), fd)
	case fd.Message() != nil:
		return diffMessageField(path, ours, theirs, fd)
	}
	return diffScalarValue(path, ours, theirs.Get(fd), fd)
}

func diffMessageField(path string, ours reflect.Value, theirs protoreflect.Message, fd protoreflect.FieldDescriptor) *Diff {
	present := theirs.Has(fd)
	var msg protoreflect.Message
	if present {
		msg = theirs.Get(fd).Message()
	}
	if fd.Message().Name() == "Node" {
		n, _ := ours.Interface().(ast.Node)
		if present {
			return diffNode(path, n, msg)
		}
		return diffNode(path, n, (*pg.Node)(nil).ProtoReflect())
	}
	// a field of a specific node type: *RangeVar and the like
	switch {
	case !present && ours.IsNil():
		return nil
	case !present:
		return &Diff{Path: path, Ours: ours.Type().Elem().Name(), Theirs: "nothing"}
	case ours.IsNil():
		return &Diff{Path: path, Ours: "nothing", Theirs: string(fd.Message().Name())}
	}
	return diffMessage(path, ours.Elem(), msg)
}

func diffList(path string, ours reflect.Value, theirs protoreflect.List, fd protoreflect.FieldDescriptor) *Diff {
	if ours.Len() != theirs.Len() {
		return &Diff{Path: path, Ours: fmt.Sprintf("%d elements", ours.Len()), Theirs: fmt.Sprintf("%d elements", theirs.Len())}
	}
	for i := 0; i < theirs.Len(); i++ {
		epath := fmt.Sprintf("%s[%d]", path, i)
		el := ours.Index(i)
		switch {
		case fd.Message() == nil:
			if d := diffScalarValue(epath, el, theirs.Get(i), fd); d != nil {
				return d
			}
		case fd.Message().Name() == "Node":
			n, _ := el.Interface().(ast.Node)
			if d := diffNode(epath, n, theirs.Get(i).Message()); d != nil {
				return d
			}
		default:
			if el.IsNil() {
				return &Diff{Path: epath, Ours: "nothing", Theirs: string(fd.Message().Name())}
			}
			if d := diffMessage(epath, el.Elem(), theirs.Get(i).Message()); d != nil {
				return d
			}
		}
	}
	return nil
}

func diffScalarValue(path string, ours reflect.Value, v protoreflect.Value, fd protoreflect.FieldDescriptor) *Diff {
	var got, want string
	switch fd.Kind() {
	case protoreflect.BoolKind:
		got, want = fmt.Sprint(ours.Bool()), fmt.Sprint(v.Bool())
	case protoreflect.StringKind:
		got, want = fmt.Sprintf("%q", ours.String()), fmt.Sprintf("%q", v.String())
	case protoreflect.Int32Kind, protoreflect.Int64Kind:
		got, want = fmt.Sprint(ours.Int()), fmt.Sprint(v.Int())
	case protoreflect.Uint32Kind, protoreflect.Uint64Kind:
		got, want = fmt.Sprint(ours.Uint()), fmt.Sprint(v.Uint())
	case protoreflect.DoubleKind:
		got, want = fmt.Sprint(ours.Float()), fmt.Sprint(v.Float())
	case protoreflect.EnumKind:
		// libpg_query numbers enums one higher than PostgreSQL does
		got, want = fmt.Sprint(ours.Int()), fmt.Sprint(int64(v.Enum())-1)
		if got == want {
			return nil
		}
		name := func(n int64) string {
			if ev := fd.Enum().Values().ByNumber(protoreflect.EnumNumber(n + 1)); ev != nil {
				return string(ev.Name())
			}
			return fmt.Sprint(n)
		}
		return &Diff{Path: path, Ours: name(ours.Int()), Theirs: name(int64(v.Enum()) - 1)}
	default:
		return &Diff{Path: path, Ours: "?", Theirs: "unsupported kind " + fd.Kind().String()}
	}
	if got != want {
		return &Diff{Path: path, Ours: got, Theirs: want}
	}
	return nil
}

// PathNodes lists the node types on a Diff path, for grouping differences
// by the kind of node: "stmts[0].SelectStmt.targetList[1].ResTarget" gives
// "SelectStmt/ResTarget".
func (d *Diff) PathNodes() string {
	var nodes []string
	for _, part := range strings.Split(d.Path, ".") {
		if part != "" && part[0] >= 'A' && part[0] <= 'Z' {
			nodes = append(nodes, part)
		}
	}
	return strings.Join(nodes, "/")
}
