#!/usr/bin/env python3
"""Makes the skeleton of the pgschema grammar from PostgreSQL's gram.y.

The rules (with their comments) are copied as they are, but the C code of
every action is moved into a comment inside an empty Go action:

    CallStmt: CALL func_application
        { /*C
            CallStmt *n = makeNode(CallStmt);
            ...
        */ }

so that the whole grammar builds at once, accepts and rejects what
PostgreSQL's does, and every action waits to be translated to Go in place.
The number of "/*C" left in gram/*.y is the work that remains.

The rules are split into the fragment files gram/10_rules_NN.y at the line
numbers of gram.y given in CUTS.

    gramskel.py gram.y internal/parse/gram
"""
import os
import re
import sys

src = open(sys.argv[1]).read()
out = sys.argv[2]
lines = src.split('\n')

# symbol -> (physical field, enum name or None), from gramdecls.py's types.txt
types = {}
for l in open(os.path.join(out, 'types.txt')):
    m = re.match(r'(\w+): (\w+) \((.*?)\) \[(\w+)\]', l)
    if m:
        em = re.match(r'int32 holding (\w+)', m.group(3))
        types[m.group(1)] = (m.group(2), em.group(1) if em else None)

first = [i for i, l in enumerate(lines) if l.strip() == '%%'][0]
last = [i for i, l in enumerate(lines) if l.strip() == '%%'][1]

# 1-based line numbers of gram.y where a fragment starts
CUTS = [911, 2073, 3292, 5160, 7043, 8804, 10509, 12079, 13425, 14752, 16112, 17080]


def trivial(body, lhs, syms):
    """Go for an action that is one of a few trivial C statements, else None."""
    b = ' '.join(body.split())
    t = lambda i: types.get(syms[i - 1], ('', None)) if 0 < i <= len(syms) else ('', None)
    lt = types.get(lhs, ('', None))
    m = re.fullmatch(r'\$\$ = (NULL|NIL);', b)
    if m and lt[0] in ('node', 'list'):
        return '$$ = nil'
    if m and lt[0] == 'str':
        return '$$ = ""'
    m = re.fullmatch(r'\$\$ = (true|false);', b)
    if m and lt[0] == 'boolean':
        return '$$ = ' + m.group(1)
    m = re.fullmatch(r'\$\$ = (?:\((?:Node|List) \*\) ?)?\$(\d+);', b)
    if m and t(int(m.group(1)))[0] == lt[0] and lt[0]:
        return '$$ = $' + m.group(1)
    m = re.fullmatch(r'\$\$ = list_make1\(\$(\d+)\);', b)
    if m and t(int(m.group(1)))[0] == 'node' and lt[0] == 'list':
        return '$$ = []Node{$%s}' % m.group(1)
    m = re.fullmatch(r'\$\$ = lappend\(\$(\d+), \$(\d+)\);', b)
    if m and t(int(m.group(1)))[0] == 'list' and t(int(m.group(2)))[0] == 'node' and lt[0] == 'list':
        return '$$ = append($%s, $%s)' % m.groups()
    m = re.fullmatch(r'\$\$ = ([A-Z][A-Z0-9_]+);', b)
    if m and lt[1]:
        return '$$ = int32(%s)' % m.group(1)
    m = re.fullmatch(r'\$\$ = (\d+);', b)
    if m and lt[0] == 'ival' and not lt[1]:
        return '$$ = ' + m.group(1)
    m = re.fullmatch(r'\$\$ = pstrdup\(\$(\d+)\);', b)
    if m and t(int(m.group(1)))[0] == 'str' and lt[0] == 'str':
        return '$$ = $' + m.group(1)
    m = re.fullmatch(r'\$\$ = ("[^"\\]*");', b)
    if m and lt[0] == 'str':
        return '$$ = ' + m.group(1)
    m = re.fullmatch(r"\$\$ = '(.)';", b)
    if m and lt[0] == 'str':
        return '$$ = "%s"' % m.group(1)
    return None


def convert(text):
    res = []
    i, n = 0, len(text)
    lhs, syms = '', []
    atstart = True  # at the start of a line
    while i < n:
        c = text[i]
        if text.startswith('/*', i):
            j = text.index('*/', i) + 2
            res.append(text[i:j])
            i = j
        elif c in '"\'':
            j = i + 1
            while text[j] != c:
                j += 2 if text[j] == '\\' else 1
            if c == "'":
                syms.append("'")
            res.append(text[i:j + 1])
            i = j + 1
        elif c == '{':
            # the action: up to the matching brace, C strings and comments aware
            depth, j = 1, i + 1
            while depth:
                d = text[j]
                if text.startswith('/*', j):
                    j = text.index('*/', j) + 2
                    continue
                if d in '"\'':
                    k = j + 1
                    while text[k] != d:
                        k += 2 if text[k] == '\\' else 1
                    j = k + 1
                    continue
                if d == '{':
                    depth += 1
                elif d == '}':
                    depth -= 1
                j += 1
            body = text[i + 1:j - 1]
            go = trivial(body, lhs, syms)
            if go:
                res.append('{ ' + go + ' }')
            else:
                res.append('{ /*C' + body.replace('*/', '* /') + '*/ }')
            i = j
        elif c == '|':
            syms = []
            res.append(c)
            i += 1
        elif c == '%' and text.startswith('%prec', i):
            m = re.compile(r'%prec\s+\w+').match(text, i)
            res.append(m.group(0))
            i = m.end()
        elif c.isalpha() or c == '_':
            m = re.compile(r'[A-Za-z_][A-Za-z_0-9]*').match(text, i)
            word = m.group(0)
            rest = text[m.end():]
            if atstart and re.match(r'[ \t]*:', rest):
                lhs, syms = word, []
            else:
                syms.append(word)
            res.append(word)
            i = m.end()
        else:
            res.append(c)
            atstart = c == '\n' or (atstart and c in ' \t')
            i += 1
            continue
        atstart = False
    return ''.join(res)


# the rules start after the line "%%" that ends the declarations
bounds = [c for c in CUTS if c > first + 1] + [last + 1]
files = []
for k in range(len(bounds) - 1):
    a, b = bounds[k] - 1, bounds[k + 1] - 1
    if k == 0:
        a = first + 1
    files.append((a, b))


def snap(i):
    # a cut before blank lines moves to the first line with text
    while lines[i].strip() == '':
        i += 1
    return i


files = [(snap(a) if k else a, snap(b) if k < len(files) - 1 else b) for k, (a, b) in enumerate(files)]

# convert all rules at once (a cut must not fall inside an action), then cut.
# Markers mark the cuts, because the conversion changes the number of lines.
head = re.compile(r'^([A-Za-z_][A-Za-z_0-9]*[ \t]*:|/\*{10})')
for a, b in files[1:]:
    if not head.match(lines[a]):
        sys.exit('gram.y line %d is not the start of a rule: %r' % (a + 1, lines[a]))
cut_at = {a: k for k, (a, b) in enumerate(files) if k}
marked = []
for i in range(first + 1, last):
    if i in cut_at:
        marked.append('\x01CUT\x01')
    marked.append(lines[i])
pieces = convert('\n'.join(marked)).split('\x01CUT\x01\n')

os.makedirs(out, exist_ok=True)
for old in os.listdir(out):
    if old.startswith('10_rules_'):
        os.remove(os.path.join(out, old))
total = 0
for k, ((a, b), text) in enumerate(zip(files, pieces)):
    total += text.count('{ /*C')
    name = os.path.join(out, '10_rules_%02d.y' % (k + 1))
    with open(name, 'w') as f:
        f.write('/* gram.y lines %d-%d */\n' % (a + 1, b))
        f.write(text.rstrip('\n') + '\n\n')
    print(name, b - a, 'lines')
print(total, 'actions to port')
