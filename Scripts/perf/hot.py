import re,collections,sys
lines=open(sys.argv[1]).read().split('\n')
n=int(sys.argv[2]) if len(sys.argv)>2 else 45
start=[i for i,l in enumerate(lines) if re.match(r'\s{4}\d+ Thread_',l) and ('Main Thread' in l or 'main-thread' in l)][0]
end=[i for i,l in enumerate(lines) if re.match(r'\s{4}\d+ Thread_',l) and i>start][0]
c=collections.Counter()
for l in lines[start:end]:
    m=re.match(r'[\s+!:|]*(\d+) (.*?)\s+\(in (NotchIslandKit|NotchIsland|SwiftUI|SwiftUICore|AppKit|QuartzCore)\)',l)
    if m:
        name=re.sub(r'<.*?>','',m.group(2))[:100]
        c[(m.group(3),name)]=max(c[(m.group(3),name)],int(m.group(1)))
total=int(re.match(r'\s+(\d+)',lines[start]).group(1))
print("main thread samples:",total)
for (mod,k),v in c.most_common(n):
    print(v,mod,k)
