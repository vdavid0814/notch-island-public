#!/usr/bin/python3
"""selftime.py <sample report> [N] [thread-filter] [incl-filter]: busy samples per thread and the
hottest functions by self time (idle waits left out), plus inclusive time of frames matching
incl-filter (a module name, e.g. NotchIslandKit)."""
import re, sys, collections
IDLE = ("mach_msg2_trap", "__psynch_cvwait", "__workq_kernreturn", "semaphore_wait_trap", "kevent", "__semwait_signal",
        "__ulock_wait", "start_wqthread", "thread_start", "__psynch_mutexwait", "swtch_pri", "__select",
        "semaphore_timedwait_trap", "__sigsuspend", "_pthread_wqthread", "???")
lines = open(sys.argv[1]).read().split("\n")
N = int(sys.argv[2]) if len(sys.argv) > 2 else 40
flt = sys.argv[3] if len(sys.argv) > 3 and sys.argv[3] != "-" else None
inclmod = sys.argv[4] if len(sys.argv) > 4 else None
node = re.compile(r"^([\s+!:|]*)(\d+) (.*)$")
threads = collections.Counter(); selfc = collections.Counter(); incl = collections.Counter()
in_tree = False; thr = None
stack = []  # [depth, count, name, childsum]
def close(entry):
    d, c, name, kids, path = entry
    s = c - kids
    fn = re.sub(r"\s+\(in .*", "", name); fn = re.sub(r"\s+\+ \d+.*", "", fn)
    m = re.search(r"\(in ([^)]+)\)", name); mod = m.group(1) if m else "?"
    if s > 0 and not any(fn.startswith(x) for x in IDLE) and thr is not None and (not flt or flt in thr):
        threads[thr] += s; selfc[(mod, fn[:120])] += s
        seen = set()
        for (pm, pf) in path + [(mod, fn[:120])]:
            if inclmod and inclmod in pm and (pm, pf) not in seen:
                seen.add((pm, pf)); incl[(pm, pf)] += s
for l in lines:
    if l.startswith("Call graph:"): in_tree = True; continue
    if in_tree and (l.startswith("Total number") or l.startswith("Binary Images") or l.startswith("Sort by")):
        while stack: close(stack.pop())
        in_tree = False
    if not in_tree: continue
    m = node.match(l)
    if not m: continue
    depth = len(m.group(1)); cnt = int(m.group(2)); name = m.group(3)
    while stack and stack[-1][0] >= depth: close(stack.pop())
    if "Thread_" in name and not stack:
        thr = name[:80]
        stack.append([depth, cnt, "THREAD", cnt, []])  # thread node itself: no self time
        continue
    if stack: stack[-1][3] += cnt
    path = []
    if stack:
        p = stack[-1]
        path = p[4] + ([] if p[2] == "THREAD" else [(re.search(r"\(in ([^)]+)\)", p[2]).group(1) if "(in " in p[2] else "?",
                                                      re.sub(r"\s+\+ \d+.*", "", re.sub(r"\s+\(in .*", "", p[2]))[:120])])
    stack.append([depth, cnt, name, 0, path])
while stack: close(stack.pop())
print("busy samples (ms) per thread:")
for t, v in threads.most_common(15): print(f"{v:7} {t}")
print("total busy", sum(threads.values()))
print("\nself time:")
for (m, f), v in selfc.most_common(N): print(f"{v:7} {m:22} {f}")
if inclmod:
    print("\ninclusive:")
    for (m, f), v in incl.most_common(N): print(f"{v:7} {m:22} {f}")
