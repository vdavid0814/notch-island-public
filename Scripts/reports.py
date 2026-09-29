#!/usr/bin/env python3
"""Downloads the diagnostics reports from the Discord server and reads them locally.

    Scripts/reports.py sync              # new reports → Support/reports/ (git-ignored)
    Scripts/reports.py list              # every install: who, version, last report, findings
    Scripts/reports.py show NAME [-n N]  # the Nth newest report of NAME (default 1), compared with
                                         # the one before it and with the reference Mac
    Scripts/reports.py section NAME TITLE [-n N]   # one section of a report, in full
    Scripts/reports.py path NAME [-n N]  # the folder of a report (report.txt, report.json, log.txt…)
    Scripts/reports.py grep PATTERN      # search every downloaded report and log

NAME matches any part of a folder name ("Anonymous", "919f32ab", "David"). The bot token comes
from DISCORD_BOT_TOKEN, Support/discord-bot-token.txt or ~/.discord_bot_token and is never printed.
Only reads from Discord: it never posts, edits or deletes anything.
"""
import argparse
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "Support" / "reports"
STATE = OUT / ".state.json"
API = "https://discord.com/api/v10"
# Discord's CDN answers Python's default User-Agent with 403.
BROWSER = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko)"
# Sections that change on every report: left out of "what changed since the previous report".
VOLATILE = {"Energy", "Event trail (this run)", "Log", "Top energy users", "Battery", "Compared with the reference",
            "History", "Windows", "Island internals", "Differs from the reference Mac"}
VOLATILE_KEYS = {"PID", "Running for", "Launched", "Uptime", "Disk free", "Memory footprint", "CPU time",
                 "Clipboard items", "Revision", "Written"}


# MARK: Discord

def token():
    """The first token Discord accepts (an old one left in a file after a reset is skipped)."""
    global TOKEN
    candidates = [("DISCORD_BOT_TOKEN", os.environ.get("DISCORD_BOT_TOKEN")),
                  ("~/.discord_bot_token", Path.home() / ".discord_bot_token"),
                  ("Support/discord-bot-token.txt", ROOT / "Support" / "discord-bot-token.txt")]
    rejected = []
    for name, candidate in candidates:
        if isinstance(candidate, Path):
            candidate = candidate.read_text().strip() if candidate.exists() else None
        if not candidate:
            continue
        TOKEN = candidate.strip()
        try:
            api("/users/@me")
            return TOKEN
        except urllib.error.HTTPError as error:
            if error.code != 401:
                raise
            rejected.append(name)
    sys.exit("error: no working bot token" + (f" (rejected: {', '.join(rejected)})" if rejected else
             " (DISCORD_BOT_TOKEN, ~/.discord_bot_token or Support/discord-bot-token.txt)"))


def api(path, **params):
    url = f"{API}{path}" + (f"?{urllib.parse.urlencode(params)}" if params else "")
    for _ in range(5):
        request = urllib.request.Request(url, headers={
            "Authorization": f"Bot {TOKEN}", "User-Agent": "DiscordBot (notchisland-reports, 1.0)"})
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                return json.load(response)
        except urllib.error.HTTPError as error:
            if error.code == 429:
                time.sleep(float(json.load(error).get("retry_after", 1)) + 0.2)
                continue
            if error.code in (403, 404):
                return None
            raise
    raise RuntimeError(f"rate limited: {path}")


def download(url, destination):
    request = urllib.request.Request(url, headers={"User-Agent": BROWSER})
    with urllib.request.urlopen(request, timeout=60) as response:
        destination.write_bytes(response.read())


def guild_id():
    config = ROOT / "Support" / "diagnostics-webhooks.json"
    if config.exists():
        guild = json.loads(config.read_text()).get("guild")
        if guild:
            return str(guild)
    guilds = api("/users/@me/guilds") or []
    if not guilds:
        sys.exit("error: the bot is on no server")
    return guilds[0]["id"]


def channels(guild):
    found = {}
    for channel in api(f"/guilds/{guild}/channels") or []:
        for kind in ("users", "bugs", "features", "alerts", "baseline"):
            if channel["name"].endswith(kind):
                found[kind] = channel
    return found


def threads(guild, forum):
    active = [t for t in (api(f"/guilds/{guild}/threads/active") or {}).get("threads", []) if t.get("parent_id") == forum]
    archived, before = [], None
    while True:
        params = {"limit": 100}
        if before:
            params["before"] = before
        page = api(f"/channels/{forum}/threads/archived/public", **params) or {}
        archived += page.get("threads", [])
        if not page.get("has_more") or not page.get("threads"):
            break
        before = page["threads"][-1]["thread_metadata"]["archive_timestamp"]
    return {t["id"]: t for t in active + archived}.values()


def messages(channel, after):
    """Every message after `after` (a message id), oldest first."""
    collected = []
    while True:
        page = api(f"/channels/{channel}/messages", limit=100, after=after or "0") or []
        if not page:
            break
        page.sort(key=lambda m: int(m["id"]))
        collected += page
        after = page[-1]["id"]
        if len(page) < 100:
            break
    return collected


def slug(text):
    text = re.sub(r"^[^\w]+", "", text)  # the emoji in front
    text = re.sub(r"[·—/:\\]+", "-", text)
    text = re.sub(r"\s+", "", text)
    return re.sub(r"-+", "-", text).strip("-") or "unnamed"


def kind_of(message):
    title = " ".join([message.get("content") or ""] + [e.get("title") or "" for e in message.get("embeds", [])])
    for word, kind in (("Crash", "crash"), ("unusual", "anomaly"), ("Unusual", "anomaly"), ("Bug", "bug"), ("🐞", "bug"),
                       ("Feature", "feature"), ("💡", "feature"), ("Reference", "baseline"), ("Diagnostics", "report")):
        if word in title:
            return kind
    return "message"


def save(message, folder, thread_name, guild):
    stamp = message["timestamp"][:19].replace(":", "").replace("T", "-")
    target = folder / f"{stamp}-{kind_of(message)}-{message['id'][-6:]}"
    target.mkdir(parents=True, exist_ok=True)
    record = {key: message.get(key) for key in ("id", "timestamp", "content", "embeds")}
    record["thread"] = thread_name
    record["link"] = f"https://discord.com/channels/{guild}/{message['channel_id']}/{message['id']}"
    record["attachments"] = [a["filename"] for a in message.get("attachments", [])]
    (target / "message.json").write_text(json.dumps(record, indent=2, ensure_ascii=False))
    for attachment in message.get("attachments", []):
        destination = target / attachment["filename"]
        if not destination.exists():
            try:
                download(attachment["url"], destination)
            except Exception as error:  # a file that failed is fetched again on the next sync
                print(f"    ! {attachment['filename']}: {error}", file=sys.stderr)
    return target


def sync(full=False):
    OUT.mkdir(parents=True, exist_ok=True)
    state = {} if full or not STATE.exists() else json.loads(STATE.read_text())
    guild = guild_id()
    found = channels(guild)
    new = []
    for kind in ("users", "bugs", "features"):
        forum = found.get(kind)
        if not forum:
            continue
        for thread in threads(guild, forum["id"]):
            folder = OUT / (slug(thread["name"]) if kind == "users" else f"{kind}/{slug(thread['name'])}")
            for message in messages(thread["id"], state.get(thread["id"])):
                if message.get("attachments") or message.get("embeds"):
                    new.append(save(message, folder, thread["name"], guild))
                state[thread["id"]] = message["id"]
    alerts = found.get("alerts")
    if alerts:
        log = OUT / "alerts.jsonl"
        with log.open("a") as handle:
            for message in messages(alerts["id"], state.get(alerts["id"])):
                handle.write(json.dumps({"timestamp": message["timestamp"], "embeds": message.get("embeds", [])},
                                        ensure_ascii=False) + "\n")
                state[alerts["id"]] = message["id"]
    STATE.write_text(json.dumps(state, indent=2))
    print(f"==> {len(new)} new message(s) in {OUT.relative_to(ROOT)}")
    for path in new:
        print(f"    {path.relative_to(OUT)}")


# MARK: Reading

def parse_text(text):
    """report.txt → (findings, sections): the reports sent before report.json existed."""
    findings, sections, current, last = [], [], None, None
    for line in text.splitlines():
        heading = re.match(r"^== (.+) ==$", line)
        if heading:
            current = {"title": heading.group(1), "entries": []}
            sections.append(current)
            last = None
            continue
        if current is None:
            if line.strip().startswith("⚠︎"):
                findings.append(line.strip()[2:].strip())
            continue
        if not line.strip():
            continue
        entry = re.match(r"^(\S.*?)\s* : (.*)$", line)
        if entry and not line.startswith(" "):
            last = {"key": entry.group(1).strip(), "value": entry.group(2)}
            current["entries"].append(last)
        elif last is not None:
            last["value"] += "\n" + line.strip()
    return findings, sections


def load(folder):
    """One downloaded report: meta, findings, metrics, sections."""
    message = json.loads((folder / "message.json").read_text())
    report = {"folder": folder, "message": message, "meta": {}, "findings": [], "metrics": {}, "comparisons": [], "sections": []}
    if (folder / "report.json").exists():
        document = json.loads((folder / "report.json").read_text())
        report.update({key: document.get(key, report[key]) for key in ("meta", "findings", "metrics", "comparisons", "sections")})
    elif (folder / "report.txt").exists():
        report["findings"], report["sections"] = parse_text((folder / "report.txt").read_text(errors="replace"))
    fields = {f["name"]: f["value"] for e in message.get("embeds", []) for f in e.get("fields", [])}
    report["fields"] = fields
    report["version"] = report["meta"].get("version") or value(report, "App", "Version") or fields.get("Version", "?")
    if not report["findings"] and "🔎 Quick diagnosis" in fields:
        report["findings"] = [line.lstrip("⚠️ ").strip() for line in fields["🔎 Quick diagnosis"].splitlines() if line.strip()]
    return report


def value(report, title, key):
    for section in report["sections"]:
        if section["title"] == title:
            for entry in section["entries"]:
                if entry["key"] == key:
                    return entry["value"]
    return None


def flat(report):
    """Every setting and state line, timings left out (they differ on every report)."""
    timing = re.compile(r"\s*\(?(query |in )?\d+ ms\)?")
    return {f"{s['title']} › {e['key']}": timing.sub("", e["value"]) for s in report["sections"] if s["title"] not in VOLATILE
            for e in s["entries"] if e["key"] not in VOLATILE_KEYS}


def installs():
    if not OUT.exists():
        return []
    return sorted([p for p in OUT.iterdir() if p.is_dir() and p.name not in ("bugs", "features")]
                  + [p for kind in ("bugs", "features") if (OUT / kind).exists() for p in (OUT / kind).iterdir() if p.is_dir()])


def reports(folder):
    return sorted([p for p in folder.iterdir() if (p / "message.json").exists()], reverse=True)


def pick(query, n):
    matches = [f for f in installs() if query.lower() in str(f.relative_to(OUT)).lower()]
    if not matches:
        sys.exit(f"error: nothing matches “{query}” (run sync first?)")
    if len(matches) > 1:
        exact = [f for f in matches if f.name.lower().startswith(query.lower())]
        matches = exact or matches
    folder = matches[0]
    found = reports(folder)
    if len(found) < n:
        sys.exit(f"error: {folder.name} has {len(found)} report(s)")
    return found[n - 1], (found[n] if len(found) > n else None)


def list_installs():
    rows = []
    for folder in installs():
        found = reports(folder)
        if not found:
            continue
        latest = load(found[0])
        rows.append((str(folder.relative_to(OUT)), len(found), latest["message"]["timestamp"][:16].replace("T", " "),
                     latest["version"], len(latest["findings"])))
    width = max([len(r[0]) for r in rows] + [7])
    print(f"{'install':{width}}  reports  last (UTC)        version      findings")
    for name, count, last, version, findings in rows:
        print(f"{name:{width}}  {count:7}  {last}  {version:11}  {findings}")


def show(query, n):
    path, previous_path = pick(query, n)
    report = load(path)
    message = report["message"]
    print(f"== {path.relative_to(OUT)} ==")
    print(f"{message['timestamp'][:19].replace('T', ' ')} UTC · v{report['version']} · {kind_of(message)} · {message['link']}")
    depth = value(report, "App", "Report depth")
    if depth:
        print(f"  depth: {depth.split(' (')[0]}")
    for name in ("macOS", "Mac", "Chip", "Runs from", "Accessibility", "Energy", "Latest on GitHub"):
        if name in report["fields"]:
            print(f"  {name}: {report['fields'][name]}")
    print("\nFindings:" if report["findings"] else "\nFindings: none")
    for finding in report["findings"]:
        print(f"  ⚠ {finding}")
    if report["comparisons"]:
        print("\nAgainst the reference:")
        for c in report["comparisons"]:
            reference = f" (ref {c['reference']:.2f})" if c.get("reference") is not None else ""
            print(f"  {'⚠' if c['unusual'] else ' '} {c['title']}: {c['value']:.2f}{reference}")
    elif any(k.startswith("📈") for k in report["fields"]):
        print("\nAgainst the reference:")
        for k, v in report["fields"].items():
            if k.startswith("📈"):
                print("  " + v.replace("\n", "\n  "))
    causes = value(report, "Likely causes", "Causes")
    if causes and causes != "nothing stands out":
        print("\nLikely causes:")
        print("  " + causes.replace("\n", "\n  "))
    crash = next((sec for sec in report["sections"] if sec["title"] == "Crash analysis"), None)
    if crash:
        print("\nCrash analysis:")
        for entry in crash["entries"]:
            print(f"  {entry['key']}:\n    " + entry["value"].replace("\n", "\n    "))
    own = value(report, "Errors by source", "NotchIsland's own")
    if own:
        print(f"\nNotchIsland's own errors: {own}")
    flow = value(report, "User flow", "Flow")
    if flow:
        print("\nUser flow (last 15 steps):")
        print("  " + "\n  ".join(flow.splitlines()[-15:]))
    differences = value(report, "Differs from the reference Mac", "Settings")
    if differences:
        print(f"\nSet up differently from the reference Mac ({value(report, 'Differs from the reference Mac', 'Differences')}):")
        print("  " + differences.replace("\n", "\n  "))
    if previous_path:
        previous = load(previous_path)
        print(f"\nChanged since the report before ({previous['message']['timestamp'][:16].replace('T', ' ')} UTC, v{previous['version']}):")
        if report["metrics"] and previous["metrics"]:
            for key in sorted(set(report["metrics"]) | set(previous["metrics"])):
                a, b = previous["metrics"].get(key), report["metrics"].get(key)
                if a != b and a is not None and b is not None and abs(b - a) > max(abs(a) * 0.25, 0.05):
                    print(f"  {key}: {a:.2f} → {b:.2f}")
        now, before = flat(report), flat(previous)
        changed = [k for k in sorted(set(now) | set(before)) if now.get(k) != before.get(k)]
        for key in changed[:80]:
            old, new = (before.get(key) or "—").replace("\n", " ⏎ "), (now.get(key) or "—").replace("\n", " ⏎ ")
            print(f"  {key}: {old[:160]} → {new[:160]}")
        if len(changed) > 80:
            print(f"  … {len(changed) - 80} more")
        if not changed:
            print("  no setting changed")
    files = sorted(p.name for p in path.iterdir() if p.name != "message.json")
    print(f"\nFiles: {', '.join(files)}\nFolder: {path}")


def section(query, title, n):
    path, _ = pick(query, n)
    report = load(path)
    for s in report["sections"]:
        if title.lower() in s["title"].lower():
            print(f"== {s['title']} ==")
            for entry in s["entries"]:
                print(f"{entry['key']} : " + entry["value"].replace("\n", "\n    "))
            print()
            return
    sys.exit(f"error: no section “{title}”; there are: " + ", ".join(s["title"] for s in report["sections"]))


def grep(pattern):
    expression = re.compile(pattern, re.IGNORECASE)
    for file in sorted(OUT.rglob("*")):
        if file.suffix not in (".txt", ".json", ".ips", ".crash") or file.name == ".state.json":
            continue
        for number, line in enumerate(file.read_text(errors="replace").splitlines(), 1):
            if expression.search(line):
                print(f"{file.relative_to(OUT)}:{number}: {line.strip()[:240]}")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("sync").add_argument("--full", action="store_true", help="download everything again")
    commands.add_parser("list")
    for name in ("show", "path"):
        command = commands.add_parser(name)
        command.add_argument("name")
        command.add_argument("-n", type=int, default=1)
    command = commands.add_parser("section")
    command.add_argument("name")
    command.add_argument("title")
    command.add_argument("-n", type=int, default=1)
    commands.add_parser("grep").add_argument("pattern")
    args = parser.parse_args()
    if args.command == "sync":
        token()
        sync(args.full)
    elif args.command == "list":
        list_installs()
    elif args.command == "show":
        show(args.name, args.n)
    elif args.command == "path":
        print(pick(args.name, args.n)[0])
    elif args.command == "section":
        section(args.name, args.title, args.n)
    elif args.command == "grep":
        grep(args.pattern)


TOKEN = None
if __name__ == "__main__":
    main()
