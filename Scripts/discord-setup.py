#!/usr/bin/env python3
"""Builds the NotchIsland channels on a Discord server and writes the webhooks the app posts to.

    Scripts/discord-setup.py [--guild SERVER_ID]

Needs a bot on the server with Administrator (or Manage Channels + Manage Webhooks + Manage
Messages), its token in DISCORD_BOT_TOKEN or in Support/discord-bot-token.txt (git-ignored).
Safe to run again: existing channels, tags and webhooks are reused, nothing is deleted.

Writes Support/diagnostics-webhooks.json (git-ignored); Scripts/build.sh puts it into the app.

    NotchIsland
      🚨-alerts       one line per crash, anomaly, bug and request, linking to the details
      👤-users        forum: one post per Mac, every report of that Mac in it
      🐞-bugs         forum: one post per bug report, tagged new / confirmed / fixed …
      💡-features     forum: one post per feature request, tagged new / planned / done …
      📌-baseline     the reference measurements of the developer's Mac
      📖-how-to       where to find what (pinned)
"""
import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TOKEN_FILE = os.path.join(ROOT, "Support", "discord-bot-token.txt")
OUTPUT = os.path.join(ROOT, "Support", "diagnostics-webhooks.json")
API = "https://discord.com/api/v10"

CATEGORY = "NotchIsland"
TEXT, CATEGORY_TYPE, FORUM = 0, 4, 15

BUG_TAGS = [("new", "🆕"), ("needs info", "❓"), ("confirmed", "✅"), ("in progress", "🛠️"), ("fixed", "✔️"), ("won't fix", "🚫")]
FEATURE_TAGS = [("new", "🆕"), ("planned", "🗓️"), ("in progress", "🛠️"), ("done", "✔️"), ("declined", "🚫")]
USER_TAGS = [("watching", "👀"), ("ok", "✅")]

CHANNELS = [
    # key, name, type, topic, tags
    ("alerts", "🚨-alerts", TEXT,
     "Crashes, unusual energy use, new bug reports and requests. Each line links to the details. Watch this one.", None),
    ("users", "👤-users", FORUM,
     "One post per Mac (👤 name · install id). Every diagnostics report of that Mac is in it, with report.txt, log.txt and crash reports.",
     USER_TAGS),
    ("bugs", "🐞-bugs", FORUM,
     "One post per bug report. Change the tag as it moves: new → confirmed → in progress → fixed.", BUG_TAGS),
    ("features", "💡-features", FORUM,
     "One post per feature request. Tag: new → planned → in progress → done (or declined).", FEATURE_TAGS),
    ("baseline", "📌-baseline", TEXT,
     "The developer's Mac measured on the published version: the reference every report is compared with.", None),
    ("howto", "📖-how-to", TEXT, "How this server works.", None),
]

HOW_TO = """**📖 How the NotchIsland reports are organised**

🚨 **alerts** — the only channel to watch. One line for every crash, unusual behaviour (energy, CPU, wakeups, memory, Spotlight, errors — compared with the reference Mac), bug report and feature request, with a link to the details.

👤 **users** — one post per Mac: `👤 name · install id`. Every report of that Mac is in it: the summary card, the quick diagnosis, the comparison with the reference, and the files (`report.txt` = everything, `log.txt` = the app's log, `.ips` = crash reports). Search the forum by name.

🐞 **bugs** / 💡 **features** — one post per report, like an issue tracker. Change the tag as it progresses. The user's own post links to it too.

📌 **baseline** — your Mac's numbers for the published version. Refresh after every release:
`Scripts/publish-baseline.sh`, then commit and push `docs/diagnostics-baseline.json`. Thresholds can be tuned in that file's `rules` without a new release.

Colours: 🐞 red bug · 💡 green idea · 📊 blue report · 💥 orange crash · ⚡ purple unusual."""


def token():
    value = os.environ.get("DISCORD_BOT_TOKEN", "").strip()
    if not value and os.path.exists(TOKEN_FILE):
        with open(TOKEN_FILE) as handle:
            value = handle.read().strip()
    if not value:
        sys.exit(f"error: no bot token (set DISCORD_BOT_TOKEN or put it in {os.path.relpath(TOKEN_FILE, ROOT)})")
    return value


def call(method, path, body=None, retries=5):
    data = json.dumps(body).encode() if body is not None else None
    request = urllib.request.Request(API + path, data=data, method=method, headers={
        "Authorization": f"Bot {TOKEN}",
        "Content-Type": "application/json",
        "User-Agent": "DiscordBot (https://github.com/vdavid0814/notch-island-public, 1.0)",
    })
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            text = response.read().decode()
            return json.loads(text) if text else None
    except urllib.error.HTTPError as error:
        detail = error.read().decode()
        if error.code == 429 and retries > 0:
            wait = json.loads(detail).get("retry_after", 2)
            time.sleep(float(wait) + 0.5)
            return call(method, path, body, retries - 1)
        sys.exit(f"error: {method} {path} → {error.code} {detail}")


def pick_guild(requested):
    guilds = call("GET", "/users/@me/guilds")
    if requested:
        match = [g for g in guilds if g["id"] == requested]
        if not match:
            sys.exit(f"error: the bot is not on server {requested}")
        return match[0]
    if len(guilds) == 1:
        return guilds[0]
    names = "\n".join(f"  {g['id']}  {g['name']}" for g in guilds)
    sys.exit(f"error: the bot is on {len(guilds)} servers; pick one with --guild:\n{names}")


def ensure_channel(existing, guild_id, name, kind, parent=None, topic=None, tags=None):
    for channel in existing:
        if channel["name"] == name and channel["type"] == kind:
            print(f"  = {name}")
            return channel
    body = {"name": name, "type": kind}
    if parent:
        body["parent_id"] = parent
    if topic:
        body["topic"] = topic
    if tags:
        body["available_tags"] = [{"name": n, "emoji_name": e} for n, e in tags]
    channel = call("POST", f"/guilds/{guild_id}/channels", body)
    existing.append(channel)
    print(f"  + {name}")
    return channel


def ensure_tags(channel, tags):
    """Adds tags a forum made earlier is missing; returns name → id."""
    have = {t["name"]: t for t in channel.get("available_tags", [])}
    missing = [(n, e) for n, e in tags if n not in have]
    if missing:
        wanted = list(channel.get("available_tags", [])) + [{"name": n, "emoji_name": e} for n, e in missing]
        channel = call("PATCH", f"/channels/{channel['id']}", {"available_tags": wanted})
        have = {t["name"]: t for t in channel.get("available_tags", [])}
    return {name: tag["id"] for name, tag in have.items()}


def ensure_webhook(channel):
    for hook in call("GET", f"/channels/{channel['id']}/webhooks"):
        if hook.get("name") == "NotchIsland" and hook.get("token"):
            return f"https://discord.com/api/webhooks/{hook['id']}/{hook['token']}"
    hook = call("POST", f"/channels/{channel['id']}/webhooks", {"name": "NotchIsland"})
    return f"https://discord.com/api/webhooks/{hook['id']}/{hook['token']}"


def post_how_to(channel):
    for message in call("GET", f"/channels/{channel['id']}/messages?limit=20"):
        if message.get("content", "").startswith("**📖 How the NotchIsland reports"):
            call("PATCH", f"/channels/{channel['id']}/messages/{message['id']}", {"content": HOW_TO})
            print("  = how-to message updated")
            return
    message = call("POST", f"/channels/{channel['id']}/messages", {"content": HOW_TO})
    call("PUT", f"/channels/{channel['id']}/pins/{message['id']}")
    print("  + how-to message pinned")


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--guild", help="the server's id (needed only if the bot is on several)")
    args = parser.parse_args()

    guild = pick_guild(args.guild)
    print(f"==> server: {guild['name']} ({guild['id']})")
    existing = call("GET", f"/guilds/{guild['id']}/channels")
    category = ensure_channel(existing, guild["id"], CATEGORY, CATEGORY_TYPE)

    made = {}
    for key, name, kind, topic, tags in CHANNELS:
        made[key] = ensure_channel(existing, guild["id"], name, kind, category["id"], topic, tags)

    tag_ids = {key: ensure_tags(made[key], tags) for key, _, kind, _, tags in CHANNELS if tags}
    print("==> webhooks")
    config = {key: ensure_webhook(made[key]) for key in ("users", "bugs", "features", "alerts", "baseline")}
    config["guild"] = guild["id"]
    config["bugTag"] = tag_ids["bugs"].get("new")
    config["featureTag"] = tag_ids["features"].get("new")
    post_how_to(made["howto"])

    with open(OUTPUT, "w") as handle:
        json.dump(config, handle, indent=2)
    print(f"==> wrote {os.path.relpath(OUTPUT, ROOT)} — rebuild the app (Scripts/build.sh) to use it")


if __name__ == "__main__":
    TOKEN = token()
    main()
