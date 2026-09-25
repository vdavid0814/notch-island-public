import re,sys
lines=open(sys.argv[1]).read().split('\n')
minc=int(sys.argv[2]) if len(sys.argv)>2 else 20
maxd=int(sys.argv[3]) if len(sys.argv)>3 else 60
start=[i for i,l in enumerate(lines) if re.match(r'\s{4}\d+ Thread_',l) and ('Main Thread' in l or 'main-thread' in l)][0]
end=[i for i,l in enumerate(lines) if re.match(r'\s{4}\d+ Thread_',l) and i>start][0]
for l in lines[start:end]:
    m=re.match(r'([\s+!:|]*)(\d+) (.*)',l)
    if not m: continue
    d=len(m.group(1)); n=int(m.group(2))
    if n>=minc and d<=maxd and not re.search(r'mach_msg|__CFRunLoopServiceMachPort|ReceiveNextEventCommon|BlockUntilNext|_DPSNextEvent|RunCurrentEventLoop|DPSBlock|NSApplication\(NSEventRouting\)|NSApplication run|NSApplicationMain|runApp|App.main|main  \(in|start  \(in',l):
        name=re.sub(r'\s+\[0x[0-9a-f]+\]','',m.group(3))
        name=re.sub(r'\s+\+ \d+','',name)[:115]
        print(f"{d:3d} {n:5d} {name}")
