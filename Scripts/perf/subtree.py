#!/usr/bin/python3
"""subtree.py <sample> <needle> <min-count-of-node> [depth] [min]: the call tree under the first node matching needle with at least min-count samples."""
import re,sys
lines=open(sys.argv[1]).read().split('\n'); needle=sys.argv[2]; nmin=int(sys.argv[3]); maxd=int(sys.argv[4]) if len(sys.argv)>4 else 12; mn=int(sys.argv[5]) if len(sys.argv)>5 else 10
node=re.compile(r"^([\s+!:|]*)(\d+) (.*)$")
root=None; out=[]
for l in lines:
    m=node.match(l)
    if not m: continue
    d=len(m.group(1)); c=int(m.group(2)); n=m.group(3)
    if root is None:
        if needle in n and c>=nmin: root=d; print(c, re.sub(r"\s+\(in .*","",n)[:120])
        continue
    if d<=root: break
    lvl=(d-root)//2
    if lvl<=maxd and c>=mn: print('  '*lvl+str(c)+' '+re.sub(r"\s+\(in .*","",n)[:110])
