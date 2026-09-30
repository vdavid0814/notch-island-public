#!/usr/bin/python3
"""ab.py <out.tsv> <label=NotchIsland.app> [<label=app> …] -- [anim.py scenario …]

Back-to-back comparison of builds with anim.py: A B A B … (ROUNDS rounds, default 2). Each turn
quits NotchIsland, launches that build, waits SETTLE s (default 35: past the liquid card's
prewarm), runs the scenarios through that build (NI_APP) and appends one row per scenario to
out.tsv: label, round, battery %, scenario, worst 1 s, worst 5 s, CPU ms. Then prints the medians.

Measuring copies must not send diagnostics: strip NIDiagnosticsConfig / NIDiagnosticsWebhookURL
from their Info.plist and sign them again (the script refuses a build that still has them).
Scenario order matters (the first opening after a launch costs more), so compare only runs made
with the same list."""
import collections, os, re, statistics, subprocess, sys, time

ANIM = os.path.join(os.path.dirname(os.path.abspath(__file__)), "anim.py")
out = sys.argv[1]
args = sys.argv[2:]
split = args.index("--") if "--" in args else len(args)
apps = [a.split("=", 1) for a in args[:split]]
scenarios = args[split + 1:]
rounds = int(os.environ.get("ROUNDS", "2"))
settle = float(os.environ.get("SETTLE", "35"))


def battery():
    m = re.search(r"(\d+)%", subprocess.run(["pmset", "-g", "batt"], capture_output=True, text=True).stdout)
    return m.group(1) if m else "?"


def launch(app):
    info = subprocess.run(["plutil", "-p", app + "/Contents/Info.plist"], capture_output=True, text=True).stdout
    assert "NIDiagnostics" not in info, f"{app} still sends diagnostics"
    subprocess.run(["pkill", "-x", "NotchIsland"]); time.sleep(2)
    subprocess.run(["open", "-g", "-a", app]); time.sleep(settle)


with open(out, "a") as f:
    for r in range(rounds):
        for label, app in apps:
            launch(app)
            # Every command goes to this build: without NI_APP, LaunchServices may start another one.
            res = subprocess.run(["python3", ANIM] + scenarios, capture_output=True, text=True,
                                 env=dict(os.environ, NI_APP=app)).stdout
            b = battery()
            for line in res.splitlines():
                m = re.match(r"(\S+)\s+worst 1 s\s+([\d.]+)\s+worst 5 s \(Activity Monitor\)\s+([\d.]+)\s+CPU\s+(\d+) ms", line)
                if m:
                    f.write("\t".join([label, str(r), b, *m.groups()]) + "\n"); f.flush()

rows = [line.rstrip("\n").split("\t") for line in open(out) if line.strip()]
labels = list(dict.fromkeys(row[0] for row in rows))
names = list(dict.fromkeys(row[3] for row in rows))
runs = collections.defaultdict(list)
for label, _, _, name, _, w5, cpu in rows:
    runs[(name, label)].append((float(w5), int(cpu)))
print("battery %:", sorted({row[2] for row in rows}))
print(f"{'scenario':16}" + "".join(f"{label + ' w5':>14}{label + ' ms':>12}" for label in labels))
for name in names:
    cells = ""
    for label in labels:
        v = runs[(name, label)]
        cells += f"{statistics.median(x[0] for x in v):14.1f}{statistics.median(x[1] for x in v):12.0f}" if v else " " * 26
    print(f"{name:16}{cells}")
