#!/usr/bin/python3
"""fold.py <sample> [thread-filter] [--by frame-regex ...]: a `sample` report's call tree as folded
stacks (self samples per full stack). With --by, the busy samples grouped by the first regex (in the order
given) that a frame of the stack matches, as a table: what share of the thread's work goes through what."""
import re, sys, collections
IDLE = ("mach_msg2_trap", "__psynch_cvwait", "__workq_kernreturn", "semaphore_wait_trap", "kevent", "__semwait_signal",
        "__ulock_wait", "start_wqthread", "thread_start", "__psynch_mutexwait", "swtch_pri", "__select",
        "semaphore_timedwait_trap", "__sigsuspend", "_pthread_wqthread", "???")
args = sys.argv[1:]
path = args.pop(0)
flt = args.pop(0) if args and not args[0].startswith("--") else None
by = args[args.index("--by") + 1:] if "--by" in args else []
node = re.compile(r"^([\s+!:|]*)(\d+) (.*)$")
stacks = collections.Counter()
thr = None; stack = []; in_tree = False
def clean(n):
    n = re.sub(r"\s+\(in .*", "", n); n = re.sub(r"\s+\+ \d+.*", "", n); return n[:140]
entries = []
for l in open(path).read().split("\n"):
    if l.startswith("Call graph:"): in_tree = True; continue
    if in_tree and (l.startswith("Total number") or l.startswith("Binary Images") or l.startswith("Sort by")): break
    if not in_tree: continue
    m = node.match(l)
    if not m: continue
    d = len(m.group(1)); c = int(m.group(2)); n = m.group(3)
    if d <= 4 and ("Thread_" in n or "DispatchQueue" in n):
        thr = n; stack = []; continue
    while stack and stack[-1][0] >= d: stack.pop()
    stack.append([d, c, clean(n), 0])
    if len(stack) > 1: stack[-2][3] += c
    entries.append((thr, [s[2] for s in stack], c, stack[-1]))
# self = count - children: recompute after full parse
selfmap = collections.Counter()
for thr_, names, c, ref in entries:
    s = ref[1] - ref[3]
    if s > 0 and (not flt or flt.lower() in (thr_ or "").lower()) and not any(names[-1].startswith(x) for x in IDLE):
        stacks[(thr_, tuple(names))] += s
if by:
    groups = collections.Counter(); total = 0
    for (t, names), s in stacks.items():
        total += s
        key = "(other)"
        # The first regex (in the order given) that any frame of the stack matches.
        for r in by:
            frame = next((f for f in names if re.search(r, f)), None)
            if frame: key = frame; break
        groups[key] += s
    print(f"total busy {total}")
    for k, v in groups.most_common(40): print(f"{v:7} {100*v/max(total,1):5.1f}%  {k}")
else:
    for (t, names), s in stacks.most_common(int(1e9)):
        print(f"{s} {';'.join(names)}")
