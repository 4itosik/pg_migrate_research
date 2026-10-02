// Copyright 2009 The Go Authors. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

/*
This is a copy of goyacc modified for the pgschema parser. Changes:

  - @N and @$ in actions are the locations of the N-th symbol and of the
    result: yyDollar[N].loc and yyVAL.loc. The %union must have a field
    "loc int32". The location of a rule is the one of its first symbol (the
    default copy of $1 does that), and -1 for an empty rule, like
    YYLLOC_DEFAULT in PostgreSQL's gram.y.
  - Every action is a function of its own, yyActN(yylex, yyDollar, yyVAL),
    and the parser calls it through the table yyActions, instead of one
    switch with all the actions in yyParse. With -recv "p *parser" the
    first parameter of the functions is that one instead of the lexer; the
    lexer given to yyParse must then be of that type.

Goyacc is a version of yacc for Go.
It is written in Go and generates parsers written in Go.

Usage:

	goyacc args...

It is largely transliterated from the Inferno version written in Limbo
which in turn was largely transliterated from the Plan 9 version
written in C and documented at

	https://9p.io/magic/man2html/1/yacc

Adepts of the original yacc will have no trouble adapting to this
form of the tool.

The directory $GOPATH/src/golang.org/x/tools/cmd/goyacc/testdata/expr
is a yacc program for a very simple expression parser. See expr.y and
main.go in that directory for examples of how to write and build
goyacc programs.

The generated parser is reentrant. The parsing function yyParse expects
to be given an argument that conforms to the following interface:

	type yyLexer interface {
		Lex(lval *yySymType) int
		Error(e string)
	}

Lex should return the token identifier, and place other token
information in lval (which replaces the usual yylval).
Error is equivalent to yyerror in the original yacc.

Code inside the grammar actions may refer to the variable yylex,
which holds the yyLexer passed to yyParse.

Clients that need to understand more about the parser state can
create the parser separately from invoking it. The function yyNewParser
returns a yyParser conforming to the following interface:

	type yyParser interface {
		Parse(yyLex) int
		Lookahead() int
	}

Parse runs the parser; the top-level call yyParse(yylex) is equivalent
to yyNewParser().Parse(yylex).

Lookahead can be called during grammar actions to read (but not consume)
the value of the current lookahead token, as returned by yylex.Lex.
If there is no current lookahead token (because the parser has not called Lex
or has consumed the token returned by the most recent call to Lex),
Lookahead returns -1. Calling Lookahead is equivalent to reading
yychar from within in a grammar action.

Multiple grammars compiled into a single program should be placed in
distinct packages.  If that is impossible, the "-p prefix" flag to
goyacc sets the prefix, by default yy, that begins the names of
symbols, including types, the parser, and the lexer, generated and
referenced by yacc's generated code.  Setting it to distinct values
allows multiple grammars to be placed in a single package.
*/
package main
