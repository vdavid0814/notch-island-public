---
name: whats-new
description: Writes NotchIsland's What's New page and release notes, in the look and plain wording of the How NotchIsland Works info page. REQUIRED at every git commit, git push and release of NotchIsland, with no exception, even for a small commit or when the user doesn't mention What's New. Also whenever a version number changes (0.8.9, "release", "publish", "kiadás", "publikálás", "commit push"), and whenever the What's New page, ReleaseNotes.current or the README's "What's new" section is written or changed.
---

# What's New

**Use this at every commit and push, without exception** (asked for by the user). `Scripts/release-guard.py`,
a hook in `.claude/settings.json`, brings it up at each `git commit`, `git push` and `gh release create`, and
refuses them while the versions disagree. A commit that is not a release still gets a look here: what a user
would notice in it goes into `ReleaseNotes.current` now, so that the release has it. Don't get round the hook.

After an update, NotchIsland opens What's New in the notch. The user wants it to feel like the How
NotchIsland Works page (`Views/Expanded/AppInfoPage.swift`), whose build, style and wording they
like. Read that page's texts before writing: they are the model to match.

## Who reads it

Someone who knows nothing about how the app is built, glancing at the notch right after an update.
They want to know what changed for them. So the text says what they will notice, not what was done
to the code.

## How to word it

Short, sensible, easy to take in. Not over-explained, and not even medium length.

- A card's title gives away the point: 2–5 words, so a glance at the titles is enough.
- A card's small text adds a little detail: one or two sentences, up to about 20 words. It should
  fit in 3 lines of a card a third of the page wide (rows are a fixed height and do not scroll).
- Everyday words. Leave out the things only a developer knows: render server, allocator, cache,
  main thread, footprint, coalition, Accessibility calls, build numbers.
- Say what it does for the reader, in plain statements. No marketing: no "blazing", "powerful",
  "we're excited", no exclamation marks.
- American English, as the rest of the app. Contractions are fine.

Before and after, from the info page:

| Too technical or long | As wanted |
|---|---|
| Animations run on the render server | macOS draws the animations |
| The system tells the island when something changes. Only the clipboard is looked at, every 1 to 30 seconds, less often the longer you are away. | macOS tells it when something changes. Only the clipboard is checked regularly. |
| All day, with only Settings' General page kept ready. | What it normally uses, all day. |
| Freed memory the allocator holds on to and uses again. | Freed memory, kept for reuse. It doesn't keep growing. |

Only say what is true of this version. A number comes from a measurement in `docs/ENERGY-LOG.md` or
this release's work, and "down from" compares it with what the last release really had. If nothing
was measured, use no number. Do not call something fixed that could not be confirmed: say so to the
user, and leave the claim out or word it for what was checked.

## How it is built

The page draws itself from `ReleaseNotes.current` (`Sources/NotchIslandKit/System/ReleaseNotes.swift`).
It opens on **the highlights** (`WhatsNewHighlights`): seven tiles of pictures round a "What's New" title,
the summary line and **More Details**, which leads to the cards by topic, drawn through the same parts as
the info page (`InfoPageShell`, `InfoStat`, `InfoCardGrid`), with a back button to the highlights. So only
the data is written at a release; the page's look is not touched. Replace the whole of `current`:

```swift
static let current = ReleaseNotes(
    version: "0.8.8",           // must be the new version, or the page does not open after the update
    summary: String(localized: "…"),   // one line under the title: the release's biggest changes, ~15 words
    highlights: [               // exactly 7 tiles, in this order: left column top and bottom, the wide one over
                                // the title, the two under it, right column top and bottom
        Highlight(title: String(localized: "Memory at rest"), visual: .bars([
            .init(label: "0.8.6", value: "190 MB", amount: 190, tint: .gray),
            .init(label: "0.8.8", value: "48 MB", amount: 48, tint: .indigo)])),
    ],
    stats: [                    // Performance's three largest numbers, each with one short line
        Stat(title: String(localized: "Memory at rest"), symbol: "moon.fill", tint: .indigo, value: "≈ 48 MB",
             detail: String(localized: "It was about 190 MB.")),
    ],
    new: [                      // the "Features" tab, the biggest first; 4, 6, 8, 9, 12 or 15 + manyMore
        Item(symbol: "square.stack.3d.up.fill", tint: .blue, title: String(localized: "…"),
             detail: String(localized: "…")),
    ],
    performance: [ /* "Performance": cards under the numbers: memory, energy, smoothness */ ],
    fixed: [ /* "Fixes": what stopped going wrong, said as the problem the reader saw */ ],
    known: [ /* "Good to Know": what still doesn't work, or a price of a change */ ])
```

The tabs follow the GitHub notes: Features, Performance, Fixes, Good to Know.

### The highlights

The first thing the reader sees, so it says the release's biggest things in pictures, not words.

- **Seven tiles, always** (a test refuses another count), or none: then the page opens on the cards.
  The wide tile over the title suits a row of symbols; the two under it a number or a small diagram.
- **Each tile a picture of what it says**, drawn from true data, with a 1–4 word title (about 20 letters):
  - `.bars` — before and after, from `docs/ENERGY-LOG.md` (memory, energy). The last bar is this version.
  - `.gauge` — one large measured number in a ring (fps, a percentage), a short `note` such as "was 15–30".
  - `.bubbles` — glossy symbols in a row: several cards at once (the fixes, with their own symbols and tints).
  - `.flow` — small symbols going into one: many things kept as one (settings saved in one file).
  - `.orbit` — one symbol with its parts round it (a page and its topics).
  - `.iconStyles` — a symbol in Clear, Dark and Tinted: something that follows the Mac's icon style.
  A new kind of picture is added to `WhatsNewHighlights.swift` when none of these fits. Never a drawn
  mock-up of the island (`AGENTS.md`): show the island only in a real photograph.
- **The biggest things in the biggest places** (asked for): the left and right columns and the wide tile
  get what the reader cares about most, such as a new feature, a page redone, memory or energy measured; the
  two small tiles under the title the rest. A fix only gets a tile when it was what users ran into most.
- **Numbers only as measured on this Mac for this release** (asked for): from `docs/ENERGY-LOG.md` or a
  measurement made now on the release build (Activity Monitor, `footprint`), against the version named
  under the bar. Nothing estimated, nothing carried over without saying from when.
- **Say what was redone, not only what was added**: a Settings page or a part of the island made anew
  belongs among the highlights as much as a new feature (`git diff --stat <last-tag>..HEAD -- Sources/…/Views`).
- **Use the cards' own symbols and tints**, so a tile and its card are recognisably the same thing.
- The `summary` is one sentence of plain words, two lines at most under the title.

- **Each card has its own SF Symbol and colour**, chosen for its meaning, as on the info page. A
  feature that has a card there keeps that symbol and tint.
- **Between 4 and 15 cards on each tab, always in full rows (approved by the user).** Only 4, 6, 8, 9,
  12 or 16 cards: 2×2, 3×2, 4×2, 3×3, 4×3 or 4×4. 16 means 15 cards and `ReleaseNotes.manyMore` ("And many
  more…") last; that card is used nowhere else. Never a short row. Four rows are lower (132 pt instead of
  160, `ReleaseNotes.rowHeight(rows:)`), so there each card's text is three lines at most (~65 letters). The cards reach the window's sides, bottom and each
  other evenly, and the window is as high as that tab's rows, unfolding between tabs on Size's spring. All of
  that comes by itself from the count; a test refuses any other count.
- **Performance counts its three numbers as cards**, in rows of three: so 3 or 6 cards under them.
- **A title stays on one line:** in rows of four a card is narrow, so a title there is about 20 letters.
- Show several things rather than few. More features than fit a smaller grid? Take the next grid up. Short
  of a card for a full row? Split a merged change, or add a true detail from the log or the app's real limits.
  Never invent one: a tab with nothing true to say is left empty, and its tab does not appear.
- **Sort by what the reader cares about**, and merge small related changes into one card. Keep
  `known` items from earlier releases only while they still hold.
- An empty section's tab does not appear.

## At each release

1. List what changed since the last release: `git log <last-tag>..HEAD` (bodies too) and
   `DECISIONS.md`.
2. Write `ReleaseNotes.current` with the bump of `Support/Info.plist`.
3. Write the README's `## What's new in vX` section and the GitHub release notes from the same
   content and topics: the largest changes at the top, then each topic in detail. Add the link text at the README's
   download button.
4. Build (`Scripts/run.sh`), open `notchisland://whatsnew` (the highlights) and
   `notchisland://whatsnew/details?topic=new|performance|fixed|known`, and look at each with `screencapture`:
   every tile's picture whole and centred, and on the tabs
   every row full and even, no title cut off or on two lines, no scrolling, and readable on Liquid
  Glass and Fade (the page lies on the island's own surface).
5. Run `Scripts/test.sh --filter ReleaseNotesTests`, then go on with the release (see `AGENTS.md`).
