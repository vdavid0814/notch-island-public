#!/usr/bin/python3
"""Overnight soak: every island animation and opening, sampled four times a second, then a rest to
see whether memory comes back.

    night.py cycle <label> [rest-seconds]   one test cycle: every scenario, then a rest (default 300 s)
    night.py rest <label> <seconds>         a rest only (the hourly 10-minute leak check)
    night.py only <label> <scenario>...     just the named scenarios (no rest)

Per scenario: CPU % (rusage, 0.25 s and 1 s windows), GPU % (IOKit accumulatedGPUTime), physical
footprint (Activity Monitor's "Memory"), idle wakeups and Energy Impact (top's POWER, the same
number as Activity Monitor's column, computed by the kernel once a second). The MediaRemote
adapter (a perl child) is sampled alongside. Rows go to night/<label>.jsonl, one line per
scenario to night/summary.tsv, the footprint after each rest to night/memory.tsv.
`NI_APP` picks the app bundle.
"""
import json, os, subprocess, sys, threading, time, statistics
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from bench import APP, rusage, gpu_ns

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "night")
os.makedirs(OUT, exist_ok=True)
PERIOD = 0.25


def app_pid():
    out = subprocess.run(["pgrep", "-x", "NotchIsland"], capture_output=True, text=True).stdout.split()
    return int(out[0]) if out else None


def adapter_pid():
    out = subprocess.run(["pgrep", "-f", "mediaremote-adapter.pl .*stream"], capture_output=True, text=True).stdout.split()
    return int(out[0]) if out else None


def url(u):
    subprocess.run(["open", "-g", "-a", APP, "notchisland://" + u])


def music(verb):
    """play / pause / next, through the island's own media commands (Music's scripting can hang on an Automation prompt)"""
    url("media/" + verb)


class Sampler:
    """Samples the app (and the adapter) every PERIOD seconds, top's POWER every second."""

    def __init__(self, pid):
        self.pid, self.apid = pid, adapter_pid()
        self.rows, self.power, self.apower = [], {}, {}
        self.stop = False
        threading.Thread(target=self._top, daemon=True).start()
        threading.Thread(target=self._loop, daemon=True).start()

    def _top(self):
        args = ["top", "-l", "0", "-s", "1", "-stats", "pid,power", "-pid", str(self.pid)]
        if self.apid:
            args += ["-pid", str(self.apid)]
        self.top = subprocess.Popen(args, stdout=subprocess.PIPE, text=True)
        first = True
        for line in self.top.stdout:
            parts = line.split()
            if len(parts) == 2 and parts[0].isdigit():
                try:
                    v = float(parts[1])
                except ValueError:
                    continue
                if int(parts[0]) == self.pid:
                    # top's first sample covers the process's whole life; skip it.
                    if first:
                        first = False
                        continue
                    self.power[time.time()] = v
                else:
                    self.apower[time.time()] = v
            if self.stop:
                break

    def _loop(self):
        prev = rusage(self.pid); prev_g = gpu_ns(self.pid); prev_t = time.time()
        aprev = rusage(self.apid) if self.apid else None
        while not self.stop:
            time.sleep(PERIOD)
            now = time.time(); r = rusage(self.pid)
            if r is None:
                break
            g = gpu_ns(self.pid); dt = now - prev_t
            row = {"t": now, "cpu": (r[0] - prev[0]) / 1e9 / dt * 100, "gpu": (g - prev_g) / 1e9 / dt * 100,
                   "mb": r[1], "wake": (r[2] - prev[2]) / dt}
            if aprev:
                a = rusage(self.apid)
                if a:
                    row["acpu"] = (a[0] - aprev[0]) / 1e9 / dt * 100
                    aprev = a
            self.rows.append(row)
            prev, prev_g, prev_t = r, g, now

    def close(self):
        self.stop = True
        try:
            self.top.terminate()
        except Exception:
            pass

    def window(self, t0, t1):
        rows = [r for r in self.rows if t0 < r["t"] <= t1]
        pw = [v for t, v in self.power.items() if t0 + 1 < t <= t1 + 0.5]
        apw = [v for t, v in self.apower.items() if t0 + 1 < t <= t1 + 0.5]
        return rows, pw, apw


def stats(name, rows, pw, apw, t0, t1):
    if not rows:
        return None
    cpu = [r["cpu"] for r in rows]
    # 1-second windows (4 samples), as Activity Monitor at its fastest.
    cpu1 = [statistics.mean(cpu[i:i + 4]) for i in range(0, max(len(cpu) - 3, 1))]
    gpu = [r["gpu"] for r in rows]
    gpu1 = [statistics.mean(gpu[i:i + 4]) for i in range(0, max(len(gpu) - 3, 1))]
    mb = [r["mb"] for r in rows]
    acpu = [r.get("acpu", 0) for r in rows]
    return {
        "name": name, "t0": t0, "s": round(t1 - t0, 1),
        "cpu": round(statistics.mean(cpu), 2), "cpu_max1": round(max(cpu1), 1), "cpu_max025": round(max(cpu), 1),
        "cpu_ms": round(sum(r["cpu"] / 100 * PERIOD for r in rows) * 1000),
        "gpu": round(statistics.mean(gpu), 2), "gpu_max1": round(max(gpu1), 1),
        "e": round(statistics.mean(pw), 2) if pw else None, "e_max": max(pw) if pw else None,
        "mb_min": round(min(mb), 1), "mb_max": round(max(mb), 1), "mb_end": round(mb[-1], 1),
        "wake": round(statistics.mean(r["wake"] for r in rows), 1),
        "adapter_cpu": round(statistics.mean(acpu), 2), "adapter_e": round(statistics.mean(apw), 2) if apw else None,
    }


# Each scenario: steps of (notchisland:// route or a callable, seconds to wait after it).
def repeat(steps, n):
    return [s for _ in range(n) for s in steps]


SCENARIOS = [
    ("rest+music", lambda: [(lambda: music("play"), 0), ("close", 30)]),
    ("open-home", lambda: repeat([("open?page=home", 2.5), ("close", 3.5)], 5)),
    ("open-timer", lambda: repeat([("open?page=timer", 2.5), ("close", 3.5)], 3)),
    ("open-shelf", lambda: repeat([("open?page=shelf", 2.5), ("close", 3.5)], 3)),
    ("hover", lambda: repeat([("demo/hover?inside=1", 2.5), ("demo/hover?inside=0", 3.5)], 4)),
    ("siri", lambda: repeat([("siri", 2.5), ("close", 3.5)], 3)),
    ("siri-apps", lambda: repeat([("demo/siriapps", 2.5), ("close", 3.5)], 2)),
    ("siri-clipboard", lambda: repeat([("demo/siriclipboard", 2.5), ("close", 3.5)], 2)),
    ("volume", lambda: [("demo/volume?level=0.3", 0.6), ("demo/volume?level=0.5", 0.6),
                        ("demo/volume?level=0.7", 4), ("demo/brightness?level=0.4", 0.6),
                        ("demo/brightness?level=0.8", 4), ("demo/reset", 2)]),
    ("battery", lambda: [("demo/charging", 4), ("demo/unplug", 4), ("demo/low", 4), ("demo/reset", 3)]),
    ("airpods", lambda: [("demo/airpods", 5), ("close", 3)]),
    ("timer-done", lambda: [("demo/timerdone", 9), ("demo/reset", 3)]),
    ("drop", lambda: [("demo/drop", 6), ("demo/reset", 3)]),
    ("track-change", lambda: [(lambda: music("next"), 6)]),
    ("settings", lambda: [("settings/general", 5), ("settings/widgets", 5), ("settings/activities", 5),
                          ("settings/siri", 5), ("settings/about", 5), ("close", 1)]),
    ("after-settings", lambda: [(lambda: None, 20)]),
    ("rest-paused", lambda: [(lambda: music("pause"), 0), ("close", 40)]),
    ("open-home-paused", lambda: repeat([("open?page=home", 2.5), ("close", 3.5)], 3)),
    ("rest+music-again", lambda: [(lambda: music("play"), 0), ("close", 30)]),
]


def run(sampler, name, steps):
    t0 = time.time()
    for action, wait in steps:
        if callable(action):
            action()
        else:
            url(action)
        time.sleep(wait)
    time.sleep(0.5)
    t1 = time.time()
    return stats(name, *sampler.window(t0, t1), t0, t1)


def line(s):
    e = "-" if s["e"] is None else f"{s['e']:.1f}"
    em = "-" if s["e_max"] is None else f"{s['e_max']:.1f}"
    return (f"{s['name']:18} {s['s']:5.0f}s cpu {s['cpu']:5.2f} max1s {s['cpu_max1']:5.1f}  gpu {s['gpu']:5.2f} max1s {s['gpu_max1']:5.1f}"
            f"  E {e:>5} max {em:>5}  MB {s['mb_min']:5.1f}-{s['mb_max']:5.1f} end {s['mb_end']:5.1f}  wake {s['wake']:5.1f}"
            f"  adapter {s['adapter_cpu']:4.2f}%")


def record(label, results, pid):
    stamp = time.strftime("%H:%M:%S")
    with open(os.path.join(OUT, label + ".jsonl"), "a") as f:
        for s in results:
            f.write(json.dumps(s) + "\n")
    path = os.path.join(OUT, "summary.tsv")
    new = not os.path.exists(path)
    with open(path, "a") as f:
        if new:
            f.write("time\tlabel\tpid\tname\tseconds\tcpu\tcpu_max1\tgpu\tgpu_max1\te\te_max\tmb_min\tmb_max\tmb_end\twake\tadapter_cpu\n")
        for s in results:
            f.write("\t".join(str(x) for x in [stamp, label, pid, s["name"], s["s"], s["cpu"], s["cpu_max1"], s["gpu"],
                                                s["gpu_max1"], s["e"], s["e_max"], s["mb_min"], s["mb_max"], s["mb_end"],
                                                s["wake"], s["adapter_cpu"]]) + "\n")


def rest(sampler, label, seconds, pid):
    """A long rest, reported per minute so a slow climb shows."""
    url("close")
    results = []
    for minute in range(int(seconds // 60)):
        t0 = time.time(); time.sleep(60); t1 = time.time()
        s = stats(f"rest-{minute + 1}m", *sampler.window(t0, t1), t0, t1)
        if s:
            results.append(s); print(line(s), flush=True)
    if results:
        path = os.path.join(OUT, "memory.tsv")
        new = not os.path.exists(path)
        with open(path, "a") as f:
            if new:
                f.write("time\tlabel\tpid\trest_s\tmb_first_min\tmb_last_min\tmb_end\tcpu\te\n")
            f.write(f"{time.strftime('%H:%M:%S')}\t{label}\t{pid}\t{seconds}\t{results[0]['mb_end']}\t"
                    f"{results[-1]['mb_min']}\t{results[-1]['mb_end']}\t"
                    f"{statistics.mean(r['cpu'] for r in results):.2f}\t"
                    f"{statistics.mean(r['e'] for r in results if r['e'] is not None):.2f}\n")
    return results


def main():
    mode, label = sys.argv[1], sys.argv[2]
    pid = app_pid()
    assert pid, "NotchIsland is not running"
    sampler = Sampler(pid)
    time.sleep(1.5)
    results = []
    print(f"== {label} pid {pid} {time.strftime('%H:%M:%S')}", flush=True)
    try:
        if mode in ("cycle", "only"):
            names = sys.argv[3:] if mode == "only" else None
            for name, steps in SCENARIOS:
                if names and name not in names:
                    continue
                s = run(sampler, name, steps())
                if s:
                    results.append(s); print(line(s), flush=True)
            url("close")
            if mode == "cycle":
                music("play")
                results += rest(sampler, label, int(sys.argv[3]) if len(sys.argv) > 3 else 300, pid)
        elif mode == "rest":
            results += rest(sampler, label, int(sys.argv[3]), pid)
    finally:
        sampler.close()
        record(label, results, pid)


if __name__ == "__main__":
    main()
