#!/usr/bin/env python3
"""Replaces the C action comments of a grammar fragment with Go code.

    gramapply.py FILE --list              number the remaining "{ /*C ... */ }" blocks
    gramapply.py FILE SPEC                replace the blocks named in SPEC

SPEC is a list of entries

    @@ <number> <text that the C code of block <number> must contain>
    <Go code, any number of lines>

The Go code is put between braces, indented like the block it replaces.
Numbers refer to the order of the blocks in FILE before the replacement, so one
SPEC replaces many blocks in one pass. A wrong key aborts without writing.
"""
import re
import sys

path = sys.argv[1]
text = open(path).read()
pat = re.compile(r'\{ /\*C(.*?)\*/ \}', re.S)
blocks = list(pat.finditer(text))

if sys.argv[2] == '--list':
    for i, m in enumerate(blocks):
        line = text.count('\n', 0, m.start()) + 1
        c = ' '.join(m.group(1).split())
        print('%3d  line %-5d %s' % (i, line, c[:110]))
    print(len(blocks), 'blocks')
    sys.exit(0)

spec = open(sys.argv[2]).read()
entries = re.split(r'^@@ ', spec, flags=re.M)[1:]
repl = {}
for e in entries:
    head, _, body = e.partition('\n')
    num, _, key = head.partition(' ')
    num = int(num)
    if num >= len(blocks):
        sys.exit('no block %d' % num)
    if key.strip() and key.strip() not in ' '.join(blocks[num].group(1).split()):
        sys.exit('block %d does not contain %r: %s' % (num, key, ' '.join(blocks[num].group(1).split())[:100]))
    repl[num] = body.rstrip('\n')

out, last = [], 0
for i, m in enumerate(blocks):
    if i not in repl:
        continue
    out.append(text[last:m.start()])
    ls = text.rfind('\n', 0, m.start()) + 1
    indent = re.match(r'[ \t]*', text[ls:m.start()]).group(0)
    body = repl[i]
    if '\n' not in body:
        out.append('{ %s }' % body.strip())
    else:
        lines = body.split('\n')
        out.append('{\n' + '\n'.join((indent + '\t' + l) if l.strip() else '' for l in lines) + '\n' + indent + '}')
    last = m.end()
out.append(text[last:])
open(path, 'w').write(''.join(out))
print('replaced %d of %d blocks; %d left' % (len(repl), len(blocks), len(blocks) - len(repl)))
