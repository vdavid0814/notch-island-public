#!/usr/bin/python3 -I
"""Claude Code's PreToolUse hook on Bash (.claude/settings.json): What's New can't be left out.

At `git commit`, `git push` and `gh release create` it brings up the `whats-new` skill, and refuses
them while the version in Support/Info.plist, ReleaseNotes.current and the README differ, or a release
is tagged otherwise. Asked for: the skill must be used every time, in no situation left out.
"""
import json, os, plistlib, re, sys

command = json.load(sys.stdin).get("tool_input", {}).get("command", "")
releases = re.search(r"\bgh\s+release\s+create\b", command)
if not (releases or re.search(r"\bgit\s+(?:-\S+\s+(?:\S+\s+)?)*(?:commit|push)\b", command)):
    sys.exit(0)

root = os.environ.get("CLAUDE_PROJECT_DIR") or os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
with open(os.path.join(root, "Support/Info.plist"), "rb") as file:
    version = plistlib.load(file)["CFBundleShortVersionString"]
with open(os.path.join(root, "Sources/NotchIslandKit/System/ReleaseNotes.swift")) as file:
    notes = re.search(r'static let current = ReleaseNotes\(\s*version: "([^"]+)"', file.read())
with open(os.path.join(root, "README.md")) as file:
    readme = file.read()

problems = []
if not notes or notes.group(1) != version:
    problems.append(f"ReleaseNotes.current is for {notes.group(1) if notes else '?'}, the app is {version}")
if f"## What's new in v{version}" not in readme:
    problems.append(f"the README has no \"What's new in v{version}\"")
if f"Download NotchIsland v{version} " not in readme:
    problems.append(f"the README's download link does not say v{version}")
tag = re.search(r"\bgh\s+release\s+create\s+(\S+)", command)
if releases and tag and tag.group(1) != f"v{version}":
    problems.append(f"the release is tagged {tag.group(1)}, the app is v{version}")

reminder = ("Use the whats-new skill (.claude/skills/whats-new/SKILL.md) now, before this goes out: every commit and "
            "push must have What's New checked. Anything a user would notice in this change belongs in "
            "ReleaseNotes.current, by its rules.")
if problems:
    output = {"permissionDecision": "deny",
              "permissionDecisionReason": "What's New is not ready: " + "; ".join(problems) + ". " + reminder}
else:
    output = {"additionalContext": reminder}
print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse", **output}}))
