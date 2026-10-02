#!/usr/bin/env python3
"""Converts the declarations of PostgreSQL's gram.y (tokens, types, precedence)
for the pgschema grammar.

Writes, into the directory given as the second argument:

  00_header.y   the Go header: package, imports, the %union and %start
  01_decls.y    the %token, %type and precedence declarations, ending with %%
  types.txt     for every symbol its C type and the Go type of its value

The tags of PostgreSQL's %union (about forty) are mapped to the six fields of
the Go semantic value:

  node     every node pointer, whatever its C type, as a ast.Node
  list     List *, as []ast.Node
  str      char *, const char *, and char (as a string of one character)
  ival     int and the enums, as int32
  boolean  bool
  loc      the location, which @N and @$ read

Run once to produce gram/00_header.y and gram/01_decls.y; they are then
edited like the rest of the grammar.

    gramdecls.py gram.y internal/parse/gram
"""
import os
import re
import sys

src = open(sys.argv[1]).read()
out = sys.argv[2]
os.makedirs(out, exist_ok=True)

# the %union: tag -> C type
union = re.search(r'%union\s*\{(.*?)\n\}', src, re.S).group(1)
ctype = {}
for line in union.split('\n'):
    line = re.sub(r'/\*.*?\*/', '', line).strip().rstrip(';')
    if not line or line.startswith('core_YYSTYPE'):
        continue
    m = re.match(r'(.+?)\s*\**\s*(\w+)$', line)
    decl, tag = line.rsplit(None, 1)
    stars = tag.count('*')
    tag = tag.lstrip('*')
    ptr = decl.endswith('*') or stars > 0
    base = decl.rstrip('*').strip()
    ctype[tag] = (base, ptr or stars > 0)

ENUMS = {'jtype', 'dbehavior', 'oncommit', 'objtype', 'fun_param_mode', 'setquantifier', 'mergematch'}
PRIVATE = {'privtarget': 'privTarget', 'importqual': 'importQual', 'selectlimit': 'selectLimit',
           'groupclause': 'groupClause', 'keyactions': 'keyActions', 'keyaction': 'keyAction'}


def physical(tag):
    if tag in ('str', 'keyword', 'chr'):
        return 'str'
    if tag == 'ival' or tag in ENUMS:
        return 'ival'
    if tag == 'boolean':
        return 'boolean'
    if tag == 'list':
        return 'list'
    return 'node'


def describe(tag):
    base, ptr = ctype[tag]
    phys = physical(tag)
    if tag in ('str', 'keyword'):
        return 'str (string)'
    if tag == 'chr':
        return 'str (one character)'
    if tag == 'ival':
        return 'ival (int32)'
    if tag in ENUMS:
        return 'ival (int32 holding %s)' % base
    if tag == 'boolean':
        return 'boolean (bool)'
    if tag == 'list':
        return 'list ([]Node)'
    if tag == 'node':
        return 'node (Node)'
    if tag in PRIVATE:
        return 'node (*%s)' % PRIVATE[tag]
    return 'node (*%s)' % base


start = src.index('%}') + 2
end = src.index('\n%%\n')
decl = src[start:end]
decl = re.sub(r'%union\s*\{.*?\n\}\n', '', decl, flags=re.S)
lines = []
types = {}
for line in decl.split('\n'):
    if re.match(r'%(pure-parser|expect|name-prefix|locations|parse-param|lex-param|define)', line):
        continue
    lines.append(line)
text = '\n'.join(lines)
# a %type or %token declaration runs until the next line that starts with %
for m in re.finditer(r'^%(type|token)\s*<(\w+)>([^%]*)', text, re.M):
    tag = m.group(2)
    body = re.sub(r'/\*.*?\*/', '', m.group(3), flags=re.S)
    for name in body.split():
        types[name] = tag
text = re.sub(r'<(\w+)>', lambda m: '<%s>' % physical(m.group(1)), text)

header = '''%{
// Code derived from PostgreSQL's src/backend/parser/gram.y (REL_17_STABLE).
//
// Portions Copyright (c) 1996-2024, PostgreSQL Global Development Group
// Portions Copyright (c) 1994, Regents of the University of California
//
// PostgreSQL License: see ../../LICENSE.PostgreSQL.

package parse

import . "github.com/4itosik/pg_migrate_research/pgschema/internal/ast"
%}

// The semantic value. node holds every node pointer of gram.y's %union
// whatever its type; use as[*T]($N) where the C code reads a field of $N.
// loc is the start of the symbol, what bison calls @N.
%union {
	loc     int32
	ival    int32
	boolean bool
	str     string
	node    Node
	list    []Node
}

%start parse_toplevel
'''
open(os.path.join(out, '00_header.y'), 'w').write(header)
open(os.path.join(out, '01_decls.y'), 'w').write(text.strip('\n') + '\n\n%%\n')
with open(os.path.join(out, 'types.txt'), 'w') as f:
    f.write('# symbol: field of the semantic value (Go type); C tag in brackets\n')
    for name in sorted(types):
        tag = types[name]
        f.write('%s: %s [%s]\n' % (name, describe(tag), tag))
print(len(types), 'symbols typed;', len(ctype), 'union tags')
