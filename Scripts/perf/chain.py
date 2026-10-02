#!/usr/bin/python3
"""chain.py <sample> <needle> [min]: for each call-tree node containing needle with >= min samples, its ancestors (outermost last)."""
import re,sys
lines=open(sys.argv[1]).read().split('\n'); needle=sys.argv[2]; mn=int(sys.argv[3]) if len(sys.argv)>3 else 20
node=re.compile(r"^([\s+!:|]*)(\d+) (.*)$")
stack=[]
def short(n): return re.sub(r"\s+\(in .*","",n)[:80]
for l in lines:
    m=node.match(l)
    if not m: continue
    d=len(m.group(1)); c=int(m.group(2)); n=m.group(3)
    while stack and stack[-1][0]>=d: stack.pop()
    stack.append((d,c,n))
    if needle in n and c>=mn:
        keys=('layout','Layout','display','Hosting','updateConstraints','(in NotchIsland)','Transaction','Window','viewDid','addSubview')
        chain=[str(x[1])+' '+short(x[2]) for x in stack[:-1] if any(k in x[2] for k in keys)]
        print(c, short(n)); print('    ' + '\n    '.join(chain[::-1][:12])); print()
