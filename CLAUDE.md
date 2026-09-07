# CLAUDE.md

## Orient

Token Counter is a macOS menu bar app that draws today's token spend across five coding
agents as a ring against a daily target. It reads files those tools have already written
locally, makes no network calls, and has no dependencies.

The authoritative record of why anything here is the way it is lives in Memex, not in
this file: **`akshay/personal/specs/spec-26`**. Read it before changing behaviour. Its
eight resolved decisions are what settle the questions this codebase keeps raising.

The README is written for a stranger and carries the design argument. This file is for
an agent that has to work here.

## Standards that govern this repository

Rules live in the standards, not here. Fetch with `get_doc({ref})`.

| Handle | Applies to |
|---|---|
| `akshay/personal/standards/std-35` | The root README |
| `akshay/personal/standards/std-29` | Any colour on any dial (one shared theme-aware palette) |
| `akshay/personal/standards/std-30` | How the interface represents absence and confidence |
| `akshay/personal/standards/std-14` | Verifying anything the user sees, and mutation checks |
| `akshay/personal/standards/std-5` | Shipping a test with a behavioural change |
| `akshay/personal/standards/std-23`, `std-24` | All prose and interface copy |
| `akshay/personal/standards/std-27` | Colour and spacing tokens rather than literals |

Two drifts are already filed against these, so do not re-report them: std-29 cl-2 is
closed by t-1, std-5 by t-2. Check the Spec's task list before assuming something is
unaddressed.

## Tripwires

**Before you change a provider's counting rule.** Every provider records something
different, and a wrong rule produces a plausible number rather than a crash. Read the
provider's doc comment first: it states what that tool records and why the rule is
shaped that way. Then run `./tools/verify/run.sh 2025-01-01`, which compares all five
providers against an independent Python implementation. The two sides must agree.

**Before you add or weaken a test.** Run `python3 tools/mutation-check.py`. It breaks
each guard in turn and requires a named test to go red. A green suite proves nothing on
its own; that is the whole point of the script.

**Before you touch anything that scans.** The app and any tool share a state directory.
Byte cursors deliberately outlive a midnight rollover, so a tool that advances them
while writing a different day key makes the app skip records it never counted. Set
`TOKEN_COUNTER_STATE_DIR` to a temporary directory in anything that scans outside the
app. This has already broken once.

**Before you claim the interface works.** Screen Recording is not granted here, so
`screencapture` and `CGWindowListCreateImage` both fail and the panel cannot be driven.
Render `PanelView` through `ImageRenderer` and query the window server for geometry.
Do not report hover behaviour or the login item as verified: both are flagged for manual
sign-off under t-4.

**Before you add a dependency.** There are none, and the README's privacy claims are
checkable partly because of that. Adding one is a decision recorded on spec-26, not a
silent edit to `Package.swift`.

## Where things are

| Path | What it is |
|---|---|
| `Sources/TokenCounter/Providers/` | One file per provider, plus the shared ledger and protocol |
| `Sources/TokenCounter/Palette.swift` | Every colour in the app |
| `Sources/TokenCounter/UsageStore.swift` | Aggregation, targets, thresholds, refresh timer |
| `Tests/TokenCounterTests/` | Provider rules, with fixtures rather than your real transcripts |
| `tools/verify/` | Differential harness against an independent implementation |
| `tools/mutation-check.py` | Proves the tests can fail |
| `tools/icongen/` | Renders the app icon |

## Local how-to

```bash
./build.sh                          # icon, compile, sign, install to ~/Applications
swift test                          # provider rules
python3 tools/mutation-check.py     # prove the tests can fail
./tools/verify/run.sh 2025-01-01    # cross-check every provider against Python
```

Requires macOS 14 or later and a Swift 5.9 toolchain. The app is a menu bar accessory
with no Dock icon, so after `build.sh` look for the percentage in the menu bar.

Tests use fixtures under `Tests/`. Never point them at your own `~/.claude`, `~/.codex`
or `~/.gemini`: a test that reads live data passes or fails by accident.

## Closing

If a rule seems to be missing, it belongs in a standard in Memex, not in this file. If
this file and a standard disagree, the standard wins and this file is the thing to fix.
