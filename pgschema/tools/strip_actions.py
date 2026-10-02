#!/usr/bin/env python3
"""Turns PostgreSQL's gram.y into a goyacc grammar without actions.

Used by probe-goyacc.sh to measure what goyacc makes of the real grammar
(ADR 0001): bison-only directives are dropped, all type tags become <v>, the
C code is removed, and every alternative gets an empty action so that goyacc
does not check types of default actions.

    strip_actions.py gram.y > gram_noact.y
"""
import re
import sys

src = open(sys.argv[1]).read()
decl_start = src.index('%}') + 2
head_end = src.index('\n%%\n')
decl = src[decl_start:head_end]
rules = src[head_end + 4:src.index('\n%%\n', head_end + 4)]

decl = re.sub(r'%union\s*\{.*?\n\}\n', '%union {\n\tv int\n}\n', decl, flags=re.S)
out = []
for line in decl.split('\n'):
    if re.match(r'%(pure-parser|expect|name-prefix|locations|parse-param|lex-param|define)', line):
        continue
    out.append(re.sub(r'<[a-z_A-Z]+>', '<v>', line))
decl = '\n'.join(out)


def strip_actions(s):
    res = []
    i, n, depth, has = 0, len(s), 0, False
    while i < n:
        c = s[i]
        if s.startswith('/*', i):
            j = s.index('*/', i) + 2
            if depth == 0:
                res.append(s[i:j])
            i = j
        elif s.startswith('//', i):
            j = s.find('\n', i)
            if depth == 0:
                res.append(s[i:j])
            i = j
        elif c in '"\'':
            j = i + 1
            while s[j] != c:
                j += 2 if s[j] == '\\' else 1
            if depth == 0:
                res.append(s[i:j + 1])
            i = j + 1
        elif c == '{':
            depth += 1
            i += 1
        elif c == '}':
            depth -= 1
            if depth == 0:
                res.append(' {} ')
                has = True
            i += 1
        elif depth == 0 and c in '|;':
            if not has:
                res.append(' {} ')
            res.append(c)
            has = False
            i += 1
        else:
            if depth == 0:
                res.append(c)
            i += 1
    return ''.join(res)


print('%{\npackage gp\n%}')
print(decl)
print('%%')
print(strip_actions(rules))
