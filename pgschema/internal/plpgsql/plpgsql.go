// Package plpgsql extracts the embedded SQL from the body of a PL/pgSQL
// function, procedure or DO block. It does not compile the body: it follows
// the structure of PostgreSQL's PL/pgSQL grammar (src/pl/plpgsql/src/pl_gram.y,
// PostgreSQL 17) on the tokens of package lex, without a catalog and without
// the types of the variables.
//
// Parse takes the text of a body (the decoded string: the content of the
// $$...$$ literal) and returns:
//
//   - the blocks, DECLARE sections, EXCEPTION handlers, labels and statements
//     with their nesting (Body.Root);
//   - every embedded SQL fragment: its byte range in the body, its parse mode
//     (a statement, an expression or one of the three assignment modes, as in
//     PostgreSQL's RawParseMode) and the line libpg_query reports for it
//     (Body.Fragments);
//   - the declarations: the name of each variable and its type as written
//     (Body.Decls), including the parameters the caller passes in Options;
//   - the dynamic SQL: EXECUTE, RETURN QUERY EXECUTE, OPEN ... FOR EXECUTE and
//     FOR ... IN EXECUTE, with the position of the command expression and of
//     the format(...) calls in it (Body.Dynamic).
//
// All offsets are byte offsets in the body text. Lines are 1-based and count
// the newlines of the body, like plpgsql_location_to_lineno. A body that sits
// in a '...' or E'...' literal of the CREATE FUNCTION statement must be
// decoded first; offsets in the decoded body do not map back to the source
// text one to one, so a rewriter edits the decoded body and quotes it again.
//
// What the grammar decides with the table of variable names, this package
// decides by structure, as docs/adr/0003-plpgsql.md says:
//
//   - a statement is an assignment when it starts with a name (up to three
//     dotted names, then subscripts and field selections) and the next token
//     is := or =; the number of the leading dotted names selects
//     ModePLpgSQLAssign1..3: one, two, or three when the first is a label
//     (a block or loop label in scope, or Options.Name) and the others are a
//     record variable and its field (r.f.g is two names, a field of a field);
//   - FOR x IN c [(args)] LOOP is a cursor loop when c is a declared cursor,
//     or when a plain identifier (not a SQL keyword) stands where the query
//     would start;
//   - OPEN c [(args)] ; is a bound cursor, OPEN c [[NO] SCROLL] FOR ... an
//     unbound one;
//   - FETCH c INTO / MOVE c ; has no direction when a name is followed by INTO
//     or a semicolon.
//
// The embedded SQL is not parsed here. A caller parses each fragment with
// parse.ParseMode(f.SQL(body), f.Mode) and adds f.Start to the positions in
// the result: SQL keeps the offsets of the body.
//
// The parser is lenient: it reports a syntax error where the structure is
// broken, but it does not check what the compiler checks (variables that do
// not exist, RETURN in the wrong kind of function, labels). The expression of
// RETURN NEXT is reported also when it is a lone variable name, for which
// PL/pgSQL builds no expression.
//
// Portions Copyright (c) 1996-2024, PostgreSQL Global Development Group
// Portions Copyright (c) 1994, Regents of the University of California
//
// PostgreSQL License: see ../../LICENSE.PostgreSQL.
package plpgsql

import (
	"fmt"

	"github.com/4itosik/pg_migrate_research/pgschema/internal/parse"
)

// Mode is the parse mode of a fragment: what parse.ParseMode must be asked
// to parse. Statement fragments use parse.ModeDefault, expressions
// parse.ModePLpgSQLExpr, assignments parse.ModePLpgSQLAssign1 to 3.
type Mode = parse.Mode

// Range is a byte range of the body: body[Start:End].
type Range struct{ Start, End int }

// Name is a part of a qualified name with its position.
type Name struct {
	Text string // folded unless quoted, like the scanner returns it
	// Start and End delimit the token, the quotes of a quoted name included.
	Start, End int
}

// Options are the facts about the function that the body does not contain.
type Options struct {
	// Name is the name of the function, folded like an identifier. PL/pgSQL
	// takes it as a label of the outermost block, so name.param.field := value
	// is an assignment with three names (ModePLpgSQLAssign3), where
	// param.field.sub := value has two. Empty for a DO block.
	Name string
	// Params are the parameters of the function. They become declarations of
	// kind DeclParam in Body.Decls; their type offsets are relative to
	// Param.Type, not to the body.
	Params []Param
}

// Param is a function parameter: its name (empty when unnamed) and its type
// as written in the CREATE FUNCTION statement.
type Param struct {
	Name string
	Type string
}

// FragKind says where a fragment comes from.
type FragKind uint8

// The kinds of fragments.
const (
	// KindSQL is a SQL statement: a static statement (possibly with INTO), the
	// query of a cursor, of OPEN ... FOR, of RETURN QUERY or of FOR ... IN, a
	// CALL or a DO. Mode is parse.ModeDefault.
	KindSQL FragKind = iota
	// KindPerform is a PERFORM statement. PL/pgSQL parses it as a SELECT: SQL
	// returns the text with "SELECT " in place of the keyword.
	KindPerform
	// KindAssign is "target := expr", with mode ModePLpgSQLAssign1..3.
	KindAssign
	// KindExpr is an expression.
	KindExpr
	// KindCaseWhen is the expression list of WHEN in a CASE with a selector:
	// PL/pgSQL parses it as `"var" IN (list)`; the fragment is the list.
	KindCaseWhen
	// KindCursorArg is one argument of an OPEN or FOR over a bound cursor.
	// Name is the parameter name for the notation "name := value".
	KindCursorArg
	// KindCommand is the command expression of dynamic SQL.
	KindCommand
)

var kindNames = [...]string{"sql", "perform", "assign", "expr", "case-when", "cursor-arg", "command"}

func (k FragKind) String() string {
	if int(k) < len(kindNames) {
		return kindNames[k]
	}
	return fmt.Sprintf("FragKind(%d)", int(k))
}

// Fragment is a piece of SQL embedded in the body, as PL/pgSQL hands it to
// the SQL parser.
type Fragment struct {
	Kind FragKind
	Mode Mode
	// Start and End delimit the fragment: body[Start:End]. A statement does
	// not include its final semicolon and trailing white space; an expression
	// does not include the keyword or the semicolon that ends it.
	Start, End int
	// Line is the line libpg_query reports for the fragment: the line of the
	// statement that owns it (of ELSIF or WHEN for their conditions, of the
	// declaration for a default value or a cursor query).
	Line int
	// Into is the INTO clause of a static statement that PL/pgSQL replaces
	// with spaces: INTO, an optional STRICT, the targets, and the white space
	// and comments up to the next token. It is the zero Range when there is
	// none, and it is cut to the fragment.
	Into Range
	// Name is the parameter name of a cursor argument in named notation.
	Name string
}

// SQL returns the text that PL/pgSQL passes to the SQL parser, with the
// offsets of the body kept: position p of the result is body[Start+p]. The
// INTO clause is replaced with spaces; the PERFORM keyword with "SELECT "
// (PL/pgSQL writes "SELECT" and moves the rest one byte to the left, which
// moves every position; this keeps them).
func (f *Fragment) SQL(body string) string {
	b := []byte(body[f.Start:f.End])
	if f.Kind == KindPerform && len(b) >= 7 {
		copy(b, "SELECT ")
	}
	for i := max(f.Into.Start, f.Start); i < min(f.Into.End, f.End); i++ {
		b[i-f.Start] = ' '
	}
	return string(b)
}

// TypeKind says what a declared type is.
type TypeKind uint8

// The kinds of types.
const (
	// TypePlain is a type name as the SQL grammar writes it: int,
	// numeric(10,2), public.mytype, timestamp with time zone, mytype[].
	TypePlain TypeKind = iota
	// TypeColumn is name%TYPE: a variable or a table column.
	TypeColumn
	// TypeRow is name%ROWTYPE: a table or a composite type.
	TypeRow
	// TypeRecord is the pseudo-type record.
	TypeRecord
)

var typeKindNames = [...]string{"plain", "%type", "%rowtype", "record"}

func (k TypeKind) String() string {
	if int(k) < len(typeKindNames) {
		return typeKindNames[k]
	}
	return fmt.Sprintf("TypeKind(%d)", int(k))
}

// TypeRef is a declared type as written.
type TypeRef struct {
	Kind TypeKind
	// Start and End delimit the text of the type: the first token to the end
	// of the last one, before COLLATE, NOT NULL, the default or the end of the
	// declaration. For a parameter they are offsets in Param.Type.
	Start, End int
	// Names is the qualified name the type starts with: for a plain type the
	// name of a user type (empty for the types that are keywords, like int or
	// double precision), for %TYPE and %ROWTYPE the name before the percent
	// sign (one to three parts).
	Names []Name
}

// DeclKind says what a declaration declares.
type DeclKind uint8

// The kinds of declarations.
const (
	DeclVar       DeclKind = iota // name [CONSTANT] type [COLLATE c] [NOT NULL] [:= expr]
	DeclAlias                     // name ALIAS FOR name
	DeclCursor                    // name [[NO] SCROLL] CURSOR [(args)] FOR query
	DeclCursorArg                 // an argument of a cursor declaration
	DeclParam                     // a parameter of the function, from Options
)

var declKindNames = [...]string{"var", "alias", "cursor", "cursor-arg", "param"}

func (k DeclKind) String() string {
	if int(k) < len(declKindNames) {
		return declKindNames[k]
	}
	return fmt.Sprintf("DeclKind(%d)", int(k))
}

// Decl is a declared variable.
type Decl struct {
	Kind DeclKind
	// Name is the name folded like the scanner folds identifiers.
	Name string
	// NameStart and NameEnd delimit the name in the body (zero for a
	// parameter).
	NameStart, NameEnd int
	// Line is the line of the declaration.
	Line int
	// Const and NotNull are the CONSTANT and NOT NULL flags.
	Const, NotNull bool
	// Type is nil for an alias and for a cursor.
	Type *TypeRef
	// Value is the default value expression of a variable, or the query of a
	// cursor; nil when there is none.
	Value *Fragment
	// Args are the arguments of a cursor.
	Args []*Decl
	// Alias is the name the alias stands for, as written.
	Alias string
}

// DynamicKind says which statement runs dynamic SQL.
type DynamicKind uint8

// The kinds of dynamic SQL.
const (
	DynExecute     DynamicKind = iota // EXECUTE command [INTO ...] [USING ...]
	DynForExecute                     // FOR x IN EXECUTE command LOOP
	DynOpenExecute                    // OPEN c FOR EXECUTE command
	DynReturnQuery                    // RETURN QUERY EXECUTE command
)

var dynKindNames = [...]string{"execute", "for-execute", "open-execute", "return-query-execute"}

func (k DynamicKind) String() string {
	if int(k) < len(dynKindNames) {
		return dynKindNames[k]
	}
	return fmt.Sprintf("DynamicKind(%d)", int(k))
}

// Dynamic is a statement that runs SQL built at run time. A rewriter cannot
// qualify names in it and warns.
type Dynamic struct {
	Kind DynamicKind
	Line int
	// Command is the command expression; it is also in Body.Fragments.
	Command *Fragment
	// Format are the calls of format(...) (or pg_catalog.format(...)) in the
	// command expression: from the name to the closing parenthesis.
	Format []Range
}

// StmtKind is the kind of a statement. The values are the suffixes of the
// PLpgSQL_stmt_* node names of libpg_query.
type StmtKind string

// The kinds of statements. EXIT and CONTINUE are StmtExit; FETCH and MOVE are
// StmtFetch (Stmt.Move tells them apart). The statement NULL is not a
// statement: PL/pgSQL does not keep it either.
const (
	StmtBlock       StmtKind = "block"
	StmtAssign      StmtKind = "assign"
	StmtIf          StmtKind = "if"
	StmtCase        StmtKind = "case"
	StmtLoop        StmtKind = "loop"
	StmtWhile       StmtKind = "while"
	StmtForInt      StmtKind = "fori"    // FOR i IN a .. b LOOP
	StmtForQuery    StmtKind = "fors"    // FOR r IN query LOOP
	StmtForCursor   StmtKind = "forc"    // FOR r IN cursor [(args)] LOOP
	StmtForExecute  StmtKind = "dynfors" // FOR r IN EXECUTE command LOOP
	StmtForeach     StmtKind = "foreach_a"
	StmtExit        StmtKind = "exit"
	StmtReturn      StmtKind = "return"
	StmtReturnNext  StmtKind = "return_next"
	StmtReturnQuery StmtKind = "return_query"
	StmtRaise       StmtKind = "raise"
	StmtAssert      StmtKind = "assert"
	StmtExecSQL     StmtKind = "execsql"
	StmtDynExecute  StmtKind = "dynexecute"
	StmtGetDiag     StmtKind = "getdiag"
	StmtOpen        StmtKind = "open"
	StmtFetch       StmtKind = "fetch"
	StmtClose       StmtKind = "close"
	StmtPerform     StmtKind = "perform"
	StmtCall        StmtKind = "call" // CALL and DO
	StmtCommit      StmtKind = "commit"
	StmtRollback    StmtKind = "rollback"
)

// Stmt is a statement.
type Stmt struct {
	Kind StmtKind
	// Line is the line libpg_query reports for the statement: the line of its
	// first keyword (of BEGIN for a block, after the label; of FOR for a
	// loop).
	Line int
	// Start and End delimit the statement, from the label if there is one to
	// the semicolon.
	Start, End int
	// Label is the label of a block or a loop, or the target of EXIT and
	// CONTINUE.
	Label string
	// Move is set for MOVE (StmtFetch).
	Move bool
	// Vars are the names of the loop variables of FOR and FOREACH.
	Vars []string
	// Cursor is the cursor variable of OPEN, FETCH, MOVE and CLOSE, and of
	// FOR over a cursor.
	Cursor string
	// Block is the block of a StmtBlock.
	Block *Block
	// Body is the body of a loop.
	Body []*Stmt
	// Branches are the IF, ELSIF and ELSE branches of an IF, and the WHEN and
	// ELSE branches of a CASE.
	Branches []*Branch
	// Frags are the fragments the statement owns, in source order: not those
	// of its branches and of the statements inside it.
	Frags []*Fragment
}

// Branch is a branch of IF or CASE.
type Branch struct {
	// Line is the line of IF, ELSIF, WHEN or ELSE.
	Line int
	// Cond is the condition; nil for ELSE.
	Cond  *Fragment
	Stmts []*Stmt
}

// Block is a block: [<<label>>] [DECLARE ...] BEGIN ... [EXCEPTION ...] END.
type Block struct {
	Label string
	// Line is the line of BEGIN.
	Line       int
	Start, End int
	Decls      []*Decl
	Stmts      []*Stmt
	Handlers   []*Handler
}

// Handler is a WHEN clause of an EXCEPTION section.
type Handler struct {
	Line int
	// Conditions are the condition names; for SQLSTATE 'xxxxx' the five
	// characters.
	Conditions []string
	Stmts      []*Stmt
}

// Body is the result of Parse.
type Body struct {
	// Text is the body that was parsed.
	Text string
	// Root is the outermost block.
	Root *Block
	// Fragments are all embedded SQL fragments in source order.
	Fragments []*Fragment
	// Decls are all declarations: the parameters, then those of the DECLARE
	// sections and cursor arguments in source order.
	Decls []*Decl
	// Dynamic are the statements that run dynamic SQL, in source order.
	Dynamic []*Dynamic
}

// Error is a syntax error in the body.
type Error struct {
	Msg  string
	Pos  int // byte offset in the body
	Line int
}

func (e *Error) Error() string { return fmt.Sprintf("%s (line %d)", e.Msg, e.Line) }
