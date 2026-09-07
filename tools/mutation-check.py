#!/usr/bin/env python3
"""Mutation check: break one guard at a time and confirm a test goes red.

std-14 cl-3 and std-5 cl-6: a test that stays green with the guard removed is not
a regression guard. Every mutation below must produce a failing named test.
"""
import pathlib
import subprocess
import sys

SRC = pathlib.Path("Sources/TokenCounter")

MUTATIONS = [
    (
        "Claude drops its dedupe check",
        SRC / "Providers/ClaudeProvider.swift",
        "if hasKey && state.seen.contains(key) { return }",
        "if false && state.seen.contains(key) { return }",
        "testSameCallInTwoTranscriptsCountsOnce",
    ),
    (
        "Claude ignores the day boundary",
        SRC / "Providers/ClaudeProvider.swift",
        "                  date >= dayStart",
        "                  date >= Date.distantPast",
        "testMidnightBoundaryIsExclusiveOfYesterday",
    ),
    (
        "Ledger consumes a partial trailing line",
        SRC / "Providers/JSONLLedger.swift",
        "let complete = chunk[chunk.startIndex...lastNewline]",
        "let complete = chunk[chunk.startIndex...]",
        "testHalfWrittenTrailingLineIsPickedUpLater",
    ),
    (
        "Ledger stops skipping files untouched today",
        SRC / "Providers/JSONLLedger.swift",
        "} else if mtime < dayStart {",
        "} else if false {",
        "testFileNotTouchedTodayIsSkipped",
    ),
    (
        "Codex drops its monotonic guard",
        SRC / "Providers/CodexProvider.swift",
        "guard zip(cumulative, previous).allSatisfy({ $0 >= $1 }) else {",
        "guard true else {",
        "testPartialDropRebaselinesInsteadOfGoingNegative",
    ),
    (
        "Codex banks the cumulative total instead of the rise",
        SRC / "Providers/CodexProvider.swift",
        "let delta = zip(cumulative, previous).map(-)",
        "let delta = cumulative",
        "testOnlyTheRiseInTheCumulativeTotalIsBanked",
    ),
    (
        "Gemini stops splitting cached out of input",
        SRC / "Providers/GeminiProvider.swift",
        'state.counts.input     += max(0, intValue(tokens["input"]) - cached) + intValue(tokens["tool"])',
        'state.counts.input     += intValue(tokens["input"]) + intValue(tokens["tool"])',
        "testMappingPreservesGeminisOwnTotal",
    ),
    (
        "History stores providers that report no token data",
        SRC / "History.swift",
        "for (id, snapshot) in snapshots where snapshot.installed && snapshot.quality != .unavailable {",
        "for (id, snapshot) in snapshots where true {",
        "testProvidersWithNoTokenDataAreNotStored",
    ),
    (
        "History reports an unobserved day as observed",
        SRC / "History.swift",
        "return DailyRecord(day: key, date: date, counts: [:], recorded: false)",
        "return DailyRecord(day: key, date: date, counts: [:], recorded: true)",
        "testUnobservedDaysComeBackFlaggedRatherThanZero",
    ),
    (
        "History stops pruning",
        SRC / "History.swift",
        "guard stored.days.count > Self.retainedDays else { return }",
        "guard false else { return }",
        "testRetentionDropsTheOldestDays",
    ),
    (
        "Gemini drops its message-id dedupe",
        SRC / "Providers/GeminiProvider.swift",
        "if !key.isEmpty && state.seen.contains(key) { continue }",
        "if false && state.seen.contains(key) { continue }",
        "testRewrittenSessionCountsOnlyNewMessages",
    ),
]


def run_test(name):
    result = subprocess.run(
        ["swift", "test", "--filter", name],
        capture_output=True, text=True,
    )
    return result.returncode == 0, result.stdout + result.stderr


def main():
    failures = []
    for label, path, original, mutated, test in MUTATIONS:
        source = path.read_text()
        if original not in source:
            failures.append(f"{label}: anchor not found in {path}, mutation not applied")
            print(f"  SKIP  {label}: anchor missing")
            continue
        path.write_text(source.replace(original, mutated, 1))
        try:
            passed, output = run_test(test)
            if passed:
                failures.append(f"{label}: {test} still passed with the guard broken")
                print(f"  GREEN {label}  <-- {test} did not catch it")
            elif "error:" in output and "Compiling" in output and "failed" not in output.lower():
                failures.append(f"{label}: mutation did not compile, so nothing was proven")
                print(f"  BUILD {label}: mutation did not compile")
            else:
                print(f"  RED   {label}  ({test} caught it)")
        finally:
            path.write_text(source)

    print()
    if failures:
        print("MUTATION CHECK FAILED")
        for f in failures:
            print("  -", f)
        sys.exit(1)
    print(f"MUTATION CHECK PASSED: all {len(MUTATIONS)} broken guards were caught")


if __name__ == "__main__":
    main()
