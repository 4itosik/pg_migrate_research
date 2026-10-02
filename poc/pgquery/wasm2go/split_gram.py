#!/usr/bin/env python3
"""Split the action switch of a bison-generated parser (libpg_query's
src_backend_parser_gram.c or src_pl_plpgsql_src_pl_gram.c) into K functions.

The Go compiler needs memory superlinear in function size, and after
wasm2go the grammar actions form one ~20k-line Go function. The actions use
only $$, @$, $n, @n, the scanner handle and parser globals (no YYABORT,
YYERROR, YYACCEPT, goto or return), so moving them into functions that get
pointers to yyval, yyloc and the stacks does not change behaviour.

    split_gram.py IN.c OUT.c K
"""
import re
import sys

src, dst, k = sys.argv[1], sys.argv[2], int(sys.argv[3])
lines = open(src).read().split('\n')
whole = '\n'.join(lines)
parser = re.search(r'^#define yyparse (\w+)$', whole, re.M).group(1)
pure = re.search(r'^yyparse \(core_yyscan_t yyscanner\)$', whole, re.M) is not None

red = next(i for i, l in enumerate(lines) if l.strip() == 'YY_REDUCE_PRINT (yyn);')
assert lines[red + 1].strip() == 'switch (yyn)' and lines[red + 2].strip() == '{'
start = red + 3
end = next(j for j in range(start, len(lines)) if lines[j].strip() == 'default: break;')
assert lines[end + 1].strip() == '}'
body = lines[start:end]

# Check the actions on code without comments and string literals.
code = '\n'.join(body)
code = re.sub(r'/\*.*?\*/', ' ', code, flags=re.S)
code = re.sub(r'"(\\.|[^"\\])*"', '""', code)
code = re.sub(r"'(\\.|[^'\\])*'", "''", code)
for bad in ('YYABORT', 'YYERROR', 'YYACCEPT', 'YYBACKUP', 'yyerrok', 'goto', 'return',
            'yystate', 'yyssp', 'yyss', 'yylen', 'yyresult', 'yyerrstatus'):
    assert not re.search(r'\b%s\b' % bad, code), bad
if pure:  # these are locals of a pure parser
    for bad in ('yychar', 'yylval', 'yylloc', 'yyclearin'):
        assert not re.search(r'\b%s\b' % bad, code), bad

case_re = re.compile(r'^\s*case (\d+):\s*$')
cases = [j for j, l in enumerate(body) if case_re.match(l)]
target = len(body) / k
chunks, cur = [], 0
for n, j in enumerate(cases):
    if n and j - cur >= target and len(chunks) < k - 1:
        chunks.append((cur, j))
        cur = j
chunks.append((cur, len(body)))

params = 'int yyn, YYSTYPE *yyvalp, YYLTYPE *yylocp, YYSTYPE *yyvsp, YYLTYPE *yylsp'
args = 'yyn, &yyval, &yyloc, yyvsp, yylsp'
if pure:
    params += ', core_yyscan_t yyscanner'
    args += ', yyscanner'
prefix = '%s_reduce_' % parser
funcs, dispatch = [], []
for c, (a, b) in enumerate(chunks):
    name = '%s%d' % (prefix, c)
    funcs += [
        'static void __attribute__((noinline))',
        '%s(%s)' % (name, params),
        '{',
        '#define yyval (*yyvalp)',
        '#define yyloc (*yylocp)',
    ] + (['#define yynerrs 0'] if pure else []) + [
        '#define __func__ "%s"' % parser,
        '  switch (yyn)',
        '    {',
    ] + body[a:b] + [
        '      default: break;',
        '    }',
        '#undef yyval',
        '#undef yyloc',
    ] + (['#undef yynerrs'] if pure else []) + [
        '#undef __func__',
        '}',
        '',
    ]
    call = '%s (%s);' % (name, args)
    if len(chunks) == 1:
        dispatch.append('  ' + call)
    elif c == 0:
        dispatch.append('  if (yyn < %s) %s' % (case_re.match(body[chunks[1][0]]).group(1), call))
    elif c < len(chunks) - 1:
        dispatch.append('  else if (yyn < %s) %s' % (case_re.match(body[chunks[c + 1][0]]).group(1), call))
    else:
        dispatch.append('  else %s' % call)

out = lines[:red + 1] + dispatch + lines[end + 2:]
ins = next(i for i, l in enumerate(out) if l.strip() == '| yyparse.  |') - 1
out = out[:ins] + ['/* Grammar actions, split out of yyparse by split_gram.py. */'] + funcs + out[ins:]
open(dst, 'w').write('\n'.join(out))
print('%s: %d actions in %d functions (%s*), %d..%d lines each' % (
    parser, len(cases), len(chunks), prefix, min(b - a for a, b in chunks), max(b - a for a, b in chunks)))
