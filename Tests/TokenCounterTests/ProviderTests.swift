import XCTest
@testable import TokenCounter

/// These cover the cases the differential harness cannot reach, because it compares
/// against whatever the machine's live transcripts happen to contain.
final class ClaudeProviderTests: XCTestCase {

    /// A resumed session and a sub-agent sidechain both re-log turns that already
    /// happened, so the same call appears in more than one transcript. Counting
    /// records rather than calls roughly doubles the total.
    func testSameCallInTwoTranscriptsCountsOnce() {
        tagAc("akshay/personal/specs/spec-26/acs/ac-18")

        let f = Fixture("claude-dupe")
        let now = Date()
        let stamp = TestDay.iso(now)
        let record = Rec.claude(id: "msg_1", request: "req_1", at: stamp, input: 7, output: 11)

        f.write("projA/one.jsonl", record + "\n")
        f.write("projB/two.jsonl", record + "\n")

        let snapshot = ClaudeProvider(root: f.dataDirectory, stateDirectory: f.stateDirectory)
            .scan(dayStart: TestDay.start(now), dayKey: TestDay.key(now))

        XCTAssertEqual(snapshot.counts.calls, 1, "the same message id and request id is one call")
        XCTAssertEqual(snapshot.counts.input, 7)
        XCTAssertEqual(snapshot.counts.output, 11)
    }

    /// Two genuinely different calls must both count, so the dedupe key is not
    /// collapsing everything.
    func testDistinctCallsBothCount() {
        tagAc("akshay/personal/specs/spec-26/acs/ac-18")

        let f = Fixture("claude-distinct")
        let now = Date()
        f.write("proj/one.jsonl",
                Rec.claude(id: "a", request: "r1", at: TestDay.iso(now), input: 1, output: 2) + "\n" +
                Rec.claude(id: "b", request: "r2", at: TestDay.iso(now), input: 3, output: 4) + "\n")

        let snapshot = ClaudeProvider(root: f.dataDirectory, stateDirectory: f.stateDirectory)
            .scan(dayStart: TestDay.start(now), dayKey: TestDay.key(now))

        XCTAssertEqual(snapshot.counts.calls, 2)
        XCTAssertEqual(snapshot.counts.input, 4)
    }

    /// A transcript being written to right now ends mid-line. That fragment must be
    /// left for the next scan rather than parsed as truncated JSON or skipped.
    func testHalfWrittenTrailingLineIsPickedUpLater() {
        tagAc("akshay/personal/specs/spec-26/acs/ac-20")

        let f = Fixture("claude-partial")
        let now = Date()
        let complete = Rec.claude(id: "a", request: "r1", at: TestDay.iso(now), input: 5, output: 5)
        let fragment = Rec.claude(id: "b", request: "r2", at: TestDay.iso(now), input: 9, output: 9)
        let cut = String(fragment.prefix(fragment.count / 2))

        f.write("proj/live.jsonl", complete + "\n" + cut)

        let provider = ClaudeProvider(root: f.dataDirectory, stateDirectory: f.stateDirectory)
        let first = provider.scan(dayStart: TestDay.start(now), dayKey: TestDay.key(now))
        XCTAssertEqual(first.counts.calls, 1, "only the complete line counts on the first pass")

        // The writer finishes the line.
        f.append("proj/live.jsonl", String(fragment.dropFirst(cut.count)) + "\n")

        let second = provider.scan(dayStart: TestDay.start(now), dayKey: TestDay.key(now))
        XCTAssertEqual(second.counts.calls, 2, "the finished line is counted on the next pass")
        XCTAssertEqual(second.counts.input, 14)
    }

    /// The byte cursor must not re-count what it has already read.
    func testAppendedRecordsCountOnceAcrossScans() {
        tagAc("akshay/personal/specs/spec-26/acs/ac-19")

        let f = Fixture("claude-append")
        let now = Date()
        let provider = ClaudeProvider(root: f.dataDirectory, stateDirectory: f.stateDirectory)

        f.write("proj/a.jsonl", Rec.claude(id: "a", request: "r1", at: TestDay.iso(now), input: 2, output: 0) + "\n")
        _ = provider.scan(dayStart: TestDay.start(now), dayKey: TestDay.key(now))

        f.append("proj/a.jsonl", Rec.claude(id: "b", request: "r2", at: TestDay.iso(now), input: 3, output: 0) + "\n")
        let snapshot = provider.scan(dayStart: TestDay.start(now), dayKey: TestDay.key(now))

        XCTAssertEqual(snapshot.counts.calls, 2)
        XCTAssertEqual(snapshot.counts.input, 5, "the first record is not counted twice")
    }

    /// A record one second before local midnight belongs to yesterday; one second
    /// after belongs to today.
    func testMidnightBoundaryIsExclusiveOfYesterday() {
        tagAc("akshay/personal/specs/spec-26/acs/ac-17")

        let f = Fixture("claude-midnight")
        let now = Date()
        let midnight = TestDay.start(now)
        let before = midnight.addingTimeInterval(-1)
        let after = midnight.addingTimeInterval(1)

        f.write("proj/a.jsonl",
                Rec.claude(id: "old", request: "r1", at: TestDay.iso(before), input: 100, output: 0) + "\n" +
                Rec.claude(id: "new", request: "r2", at: TestDay.iso(after), input: 1, output: 0) + "\n")

        let snapshot = ClaudeProvider(root: f.dataDirectory, stateDirectory: f.stateDirectory)
            .scan(dayStart: midnight, dayKey: TestDay.key(now))

        XCTAssertEqual(snapshot.counts.calls, 1, "only the record at or after midnight counts")
        XCTAssertEqual(snapshot.counts.input, 1)
    }

    /// The rollover asymmetry that once cost a whole day's tally: on a new day the
    /// counts reset, but the byte cursors must survive, because anything past a
    /// cursor can only belong to the new day.
    func testDayRolloverResetsCountsButKeepsCursors() {
        tagAc("akshay/personal/specs/spec-26/acs/ac-18")

        let f = Fixture("claude-rollover")
        let now = Date()
        let provider = ClaudeProvider(root: f.dataDirectory, stateDirectory: f.stateDirectory)

        f.write("proj/a.jsonl", Rec.claude(id: "a", request: "r1", at: TestDay.iso(now), input: 50, output: 0) + "\n")
        let today = provider.scan(dayStart: TestDay.start(now), dayKey: TestDay.key(now))
        XCTAssertEqual(today.counts.input, 50)

        // Same files, a new day key, and nothing appended since.
        let tomorrow = now.addingTimeInterval(86_400)
        let next = provider.scan(dayStart: TestDay.start(tomorrow), dayKey: TestDay.key(tomorrow))

        XCTAssertEqual(next.counts.calls, 0, "yesterday's records do not carry into the new day")
        XCTAssertEqual(next.counts.input, 0)
    }

    /// A transcript replaced with a shorter one leaves the stored offset past its
    /// end. Reading from there would skip the new content silently, so the cursor
    /// has to restart from zero.
    func testFileThatShrankRestartsFromZero() {
        tagAc("akshay/personal/specs/spec-26/acs/ac-20")

        let f = Fixture("claude-truncated")
        let now = Date()
        let provider = ClaudeProvider(root: f.dataDirectory, stateDirectory: f.stateDirectory)

        // A long file, fully consumed, so the cursor sits at its end.
        var lines = ""
        for index in 0..<20 {
            lines += Rec.claude(id: "a\(index)", request: "r\(index)", at: TestDay.iso(now), input: 1, output: 0) + "\n"
        }
        f.write("proj/a.jsonl", lines)
        let first = provider.scan(dayStart: TestDay.start(now), dayKey: TestDay.key(now))
        XCTAssertEqual(first.counts.calls, 20)

        // Replaced by a shorter file: fewer bytes than the offset already recorded.
        f.write("proj/a.jsonl", Rec.claude(id: "fresh", request: "rf", at: TestDay.iso(now), input: 7, output: 0) + "\n")
        let second = provider.scan(dayStart: TestDay.start(now), dayKey: TestDay.key(now))

        XCTAssertEqual(second.counts.calls, 21, "the replaced file is read from the start, not skipped")
        XCTAssertEqual(second.counts.input, 20 + 7)
    }

    /// A file untouched today cannot hold today's records, so its bytes are skipped
    /// outright. This is what keeps a cold scan proportional to the day's writing.
    func testFileNotTouchedTodayIsSkipped() {
        tagAc("akshay/personal/specs/spec-26/acs/ac-19")

        let f = Fixture("claude-stale")
        let now = Date()
        f.write("proj/old.jsonl", Rec.claude(id: "a", request: "r1", at: TestDay.iso(now), input: 999, output: 0) + "\n")
        f.touch("proj/old.jsonl", modified: now.addingTimeInterval(-172_800))

        let snapshot = ClaudeProvider(root: f.dataDirectory, stateDirectory: f.stateDirectory)
            .scan(dayStart: TestDay.start(now), dayKey: TestDay.key(now))

        XCTAssertEqual(snapshot.counts.calls, 0, "an old file's bytes are never read")
    }

    func testMissingRootReportsNotInstalled() {
        tagAc("akshay/personal/specs/spec-26/acs/ac-12")

        let f = Fixture("claude-absent")
        let snapshot = ClaudeProvider(
            root: f.root.appendingPathComponent("nope"),
            stateDirectory: f.stateDirectory
        ).scan(dayStart: TestDay.start(Date()), dayKey: TestDay.key(Date()))

        XCTAssertFalse(snapshot.installed)
        XCTAssertEqual(snapshot.quality, .unavailable)
    }
}

final class CodexProviderTests: XCTestCase {

    /// Codex emits the same token_count twice per turn. Summing the per-turn field
    /// double counts, which is why each rise in the cumulative total is banked instead.
    func testRepeatedIdenticalEventsCountOnce() {
        tagAc("akshay/personal/specs/spec-26/acs/ac-18")

        let f = Fixture("codex-repeat")
        let now = Date()
        let stamp = TestDay.iso(now)
        f.write("2026/09/07/rollout-a.jsonl",
                Rec.codex(at: stamp, totalInput: 9603, totalCached: 7552, totalOutput: 302) + "\n" +
                Rec.codex(at: stamp, totalInput: 9603, totalCached: 7552, totalOutput: 302) + "\n")

        let snapshot = CodexProvider(root: f.dataDirectory, stateDirectory: f.stateDirectory)
            .scan(dayStart: TestDay.start(now), dayKey: TestDay.key(now))

        XCTAssertEqual(snapshot.counts.calls, 1, "the duplicate event adds nothing")
        XCTAssertEqual(snapshot.counts.cacheRead, 7552)
        XCTAssertEqual(snapshot.counts.input, 9603 - 7552, "cached input is split out of input")
        XCTAssertEqual(snapshot.counts.output, 302)
    }

    /// Only the increase is banked, so a rising cumulative total is not re-added.
    func testOnlyTheRiseInTheCumulativeTotalIsBanked() {
        tagAc("akshay/personal/specs/spec-26/acs/ac-18")

        let f = Fixture("codex-rise")
        let now = Date()
        let stamp = TestDay.iso(now)
        f.write("2026/09/07/rollout-a.jsonl",
                Rec.codex(at: stamp, totalInput: 100, totalCached: 0, totalOutput: 10) + "\n" +
                Rec.codex(at: stamp, totalInput: 250, totalCached: 0, totalOutput: 25) + "\n")

        let snapshot = CodexProvider(root: f.dataDirectory, stateDirectory: f.stateDirectory)
            .scan(dayStart: TestDay.start(now), dayKey: TestDay.key(now))

        XCTAssertEqual(snapshot.counts.input, 250, "the final cumulative figure, not 100 + 250")
        XCTAssertEqual(snapshot.counts.output, 25)
    }

    /// A cumulative figure that drops means the file was replaced, so the new reading
    /// becomes the baseline.
    ///
    /// The case that actually needs the guard is a *partial* drop: cached input falling
    /// while the others rise. A whole-figure drop is already absorbed by the positive
    /// delta check, but a partial one slips through it and produces a negative cache
    /// read and an inflated input, because the cached delta is subtracted from input.
    func testPartialDropRebaselinesInsteadOfGoingNegative() {
        tagAc("akshay/personal/specs/spec-26/acs/ac-18")

        let f = Fixture("codex-drop")
        let now = Date()
        let stamp = TestDay.iso(now)
        f.write("2026/09/07/rollout-a.jsonl",
                Rec.codex(at: stamp, totalInput: 100, totalCached: 90, totalOutput: 10) + "\n" +
                // Cached falls, input and output rise: the file was replaced mid-session.
                Rec.codex(at: stamp, totalInput: 200, totalCached: 50, totalOutput: 20) + "\n" +
                Rec.codex(at: stamp, totalInput: 260, totalCached: 60, totalOutput: 25) + "\n")

        let snapshot = CodexProvider(root: f.dataDirectory, stateDirectory: f.stateDirectory)
            .scan(dayStart: TestDay.start(now), dayKey: TestDay.key(now))
        let c = snapshot.counts

        XCTAssertGreaterThanOrEqual(c.cacheRead, 0, "a cached figure that fell must never bank negative")
        XCTAssertGreaterThanOrEqual(c.input, 0)
        XCTAssertEqual(c.input, 60, "10 from the first event, 50 from the rise after rebaselining")
        XCTAssertEqual(c.cacheRead, 100, "90 then 10, with the replaced reading skipped")
        XCTAssertEqual(c.output, 15)
    }

    /// A whole-figure drop must also contribute nothing negative.
    func testWholeFigureDropContributesNothingNegative() {
        tagAc("akshay/personal/specs/spec-26/acs/ac-18")

        let f = Fixture("codex-drop-all")
        let now = Date()
        let stamp = TestDay.iso(now)
        f.write("2026/09/07/rollout-a.jsonl",
                Rec.codex(at: stamp, totalInput: 500, totalCached: 0, totalOutput: 50) + "\n" +
                Rec.codex(at: stamp, totalInput: 20, totalCached: 0, totalOutput: 2) + "\n" +
                Rec.codex(at: stamp, totalInput: 60, totalCached: 0, totalOutput: 6) + "\n")

        let snapshot = CodexProvider(root: f.dataDirectory, stateDirectory: f.stateDirectory)
            .scan(dayStart: TestDay.start(now), dayKey: TestDay.key(now))

        XCTAssertEqual(snapshot.counts.input, 540, "500, then rebaseline at 20, then the 40 rise")
        XCTAssertGreaterThanOrEqual(snapshot.counts.output, 0)
    }

    /// A session that began yesterday must not dump its whole history into today on
    /// the first scan. Deltas are tracked throughout; only today's are banked.
    func testSessionStartedYesterdayOnlyBanksTodaysPortion() {
        tagAc("akshay/personal/specs/spec-26/acs/ac-17")
        tagAc("akshay/personal/specs/spec-26/acs/ac-18")

        let f = Fixture("codex-straddle")
        let now = Date()
        let midnight = TestDay.start(now)
        let yesterday = TestDay.iso(midnight.addingTimeInterval(-3600))
        let today = TestDay.iso(midnight.addingTimeInterval(3600))

        f.write("2026/09/07/rollout-a.jsonl",
                Rec.codex(at: yesterday, totalInput: 1000, totalCached: 0, totalOutput: 100) + "\n" +
                Rec.codex(at: today, totalInput: 1200, totalCached: 0, totalOutput: 130) + "\n")

        let snapshot = CodexProvider(root: f.dataDirectory, stateDirectory: f.stateDirectory)
            .scan(dayStart: midnight, dayKey: TestDay.key(now))

        XCTAssertEqual(snapshot.counts.input, 200, "only the rise that happened today")
        XCTAssertEqual(snapshot.counts.output, 30)
        XCTAssertEqual(snapshot.counts.calls, 1)
    }
}

final class GeminiProviderTests: XCTestCase {

    /// Gemini's total is input + output + thoughts + tool, with cached a slice of
    /// input. The mapping must preserve that total exactly.
    func testMappingPreservesGeminisOwnTotal() {
        tagAc("akshay/personal/specs/spec-26/acs/ac-22")

        let f = Fixture("gemini-total")
        let now = Date()
        let message = Rec.geminiMessage(
            id: "m1", at: TestDay.iso(now),
            input: 52945, cached: 52735, output: 761, thoughts: 1862, tool: 0)
        f.write("proj/chats/session-a.json", Rec.geminiSession(messages: [message]))

        let snapshot = GeminiProvider(root: f.dataDirectory, stateDirectory: f.stateDirectory)
            .scan(dayStart: TestDay.start(now), dayKey: TestDay.key(now))
        let c = snapshot.counts

        XCTAssertEqual(c.input, 52945 - 52735, "cached is a slice of input, not an addend")
        XCTAssertEqual(c.cacheRead, 52735)
        XCTAssertEqual(c.output, 761 + 1862, "thinking counts as output")
        XCTAssertEqual(c.input + c.output + c.cacheRead, 52945 + 761 + 1862,
                       "the mapping loses nothing against Gemini's own total")
    }

    /// A fully cached prompt must leave no negative input.
    func testFullyCachedPromptLeavesNoNegativeInput() {
        tagAc("akshay/personal/specs/spec-26/acs/ac-22")

        let f = Fixture("gemini-cached")
        let now = Date()
        let message = Rec.geminiMessage(
            id: "m1", at: TestDay.iso(now),
            input: 8000, cached: 8000, output: 5, thoughts: 0, tool: 0)
        f.write("proj/chats/session-a.json", Rec.geminiSession(messages: [message]))

        let snapshot = GeminiProvider(root: f.dataDirectory, stateDirectory: f.stateDirectory)
            .scan(dayStart: TestDay.start(now), dayKey: TestDay.key(now))

        XCTAssertEqual(snapshot.counts.input, 0)
        XCTAssertEqual(snapshot.counts.cacheRead, 8000)
    }

    /// Gemini rewrites the whole document as a session grows, so a re-read must count
    /// only the new messages. That is what the id dedupe is for.
    func testRewrittenSessionCountsOnlyNewMessages() {
        tagAc("akshay/personal/specs/spec-26/acs/ac-19")

        let f = Fixture("gemini-rewrite")
        let now = Date()
        let provider = GeminiProvider(root: f.dataDirectory, stateDirectory: f.stateDirectory)
        let first = Rec.geminiMessage(id: "m1", at: TestDay.iso(now), input: 100, cached: 0, output: 10, thoughts: 0, tool: 0)
        let second = Rec.geminiMessage(id: "m2", at: TestDay.iso(now), input: 200, cached: 0, output: 20, thoughts: 0, tool: 0)

        f.write("proj/chats/session-a.json", Rec.geminiSession(messages: [first]))
        let one = provider.scan(dayStart: TestDay.start(now), dayKey: TestDay.key(now))
        XCTAssertEqual(one.counts.calls, 1)

        // The whole document is rewritten with both messages, and its date moves.
        f.write("proj/chats/session-a.json", Rec.geminiSession(messages: [first, second]))
        f.touch("proj/chats/session-a.json", modified: Date())

        let two = provider.scan(dayStart: TestDay.start(now), dayKey: TestDay.key(now))
        XCTAssertEqual(two.counts.calls, 2, "the first message is not counted again")
        XCTAssertEqual(two.counts.input, 300)
    }

    /// Only files inside a `chats` directory named `session-*.json` are sessions.
    func testUnrelatedJSONIsIgnored() {
        let f = Fixture("gemini-noise")
        let now = Date()
        let message = Rec.geminiMessage(id: "m1", at: TestDay.iso(now), input: 500, cached: 0, output: 1, thoughts: 0, tool: 0)
        f.write("proj/settings.json", Rec.geminiSession(messages: [message]))
        f.write("proj/chats/notes.json", Rec.geminiSession(messages: [message]))

        let snapshot = GeminiProvider(root: f.dataDirectory, stateDirectory: f.stateDirectory)
            .scan(dayStart: TestDay.start(now), dayKey: TestDay.key(now))

        XCTAssertEqual(snapshot.counts.calls, 0)
    }
}

final class CopilotProviderTests: XCTestCase {

    /// Copilot records no token counts, and that is different from recording zero.
    /// The grade is what keeps it out of every total.
    func testReportsUnavailableRatherThanZero() {
        tagAc("akshay/personal/specs/spec-26/acs/ac-11")

        let snapshot = CopilotProvider().scan(dayStart: TestDay.start(Date()), dayKey: TestDay.key(Date()))
        if snapshot.installed {
            XCTAssertEqual(snapshot.quality, .unavailable)
            XCTAssertEqual(snapshot.counts.total(includeCacheReads: true), 0)
        } else {
            XCTAssertEqual(snapshot.quality, .unavailable)
        }
    }
}

final class TokenCountsTests: XCTestCase {

    func testCacheReadsAreExcludedUnlessAskedFor() {
        tagAc("akshay/personal/specs/spec-26/acs/ac-10")

        let c = TokenCounts(input: 1, output: 2, cacheWrite: 4, cacheRead: 8_000, calls: 1)
        XCTAssertEqual(c.total(includeCacheReads: false), 7)
        XCTAssertEqual(c.total(includeCacheReads: true), 8_007)
    }

    func testAdditionSumsEveryField() {
        let a = TokenCounts(input: 1, output: 2, cacheWrite: 3, cacheRead: 4, calls: 5)
        let b = TokenCounts(input: 10, output: 20, cacheWrite: 30, cacheRead: 40, calls: 50)
        XCTAssertEqual(a + b, TokenCounts(input: 11, output: 22, cacheWrite: 33, cacheRead: 44, calls: 55))
    }

    func testLevelBandsMatchTheDocumentedThresholds() {
        tagAc("akshay/personal/specs/spec-26/acs/ac-13")

        XCTAssertEqual(UsageLevel(fraction: 0.0), .low)
        XCTAssertEqual(UsageLevel(fraction: 0.59), .low)
        XCTAssertEqual(UsageLevel(fraction: 0.60), .medium)
        XCTAssertEqual(UsageLevel(fraction: 0.84), .medium)
        XCTAssertEqual(UsageLevel(fraction: 0.85), .high)
        XCTAssertEqual(UsageLevel(fraction: 0.99), .high)
        XCTAssertEqual(UsageLevel(fraction: 1.0), .over)
        XCTAssertEqual(UsageLevel(fraction: 3.0), .over)
    }
}
