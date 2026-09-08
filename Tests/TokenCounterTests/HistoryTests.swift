import XCTest
@testable import TokenCounter

final class DailyHistoryTests: XCTestCase {

    private func snapshot(_ id: ProviderID, input: Int, output: Int = 0, cacheRead: Int = 0,
                          quality: DataQuality = .measured, installed: Bool = true) -> ProviderSnapshot {
        ProviderSnapshot(
            id: id,
            counts: TokenCounts(input: input, output: output, cacheWrite: 0, cacheRead: cacheRead, calls: 1),
            quality: quality,
            installed: installed
        )
    }

    /// Today's row is rewritten on every scan, so a refresh must replace rather than
    /// accumulate. This is the property that lets the app write continuously instead
    /// of relying on a single write at midnight it might be asleep for.
    func testRecordingTheSameDayTwiceReplacesRatherThanAdds() {
        tagAc("akshay/personal/specs/spec-26/acs/ac-23")

        let f = Fixture("history-upsert")
        let history = DailyHistory(stateDirectory: f.stateDirectory)

        history.record(day: "2026-09-07", snapshots: [.claude: snapshot(.claude, input: 100)])
        history.record(day: "2026-09-07", snapshots: [.claude: snapshot(.claude, input: 250)])

        let row = history.records(days: 1, endingOn: day("2026-09-07")).first
        XCTAssertEqual(row?.counts[.claude]?.input, 250, "the later scan replaces the earlier one")
        XCTAssertEqual(history.recordedDayCount, 1)
    }

    /// Crossing midnight leaves yesterday intact and starts a new row.
    func testCrossingMidnightKeepsYesterdayAndStartsToday() {
        tagAc("akshay/personal/specs/spec-26/acs/ac-23")

        let f = Fixture("history-midnight")
        let history = DailyHistory(stateDirectory: f.stateDirectory)

        history.record(day: "2026-09-06", snapshots: [.claude: snapshot(.claude, input: 900)])
        history.record(day: "2026-09-07", snapshots: [.claude: snapshot(.claude, input: 5)])

        let rows = history.records(days: 2, endingOn: day("2026-09-07"))
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].day, "2026-09-06")
        XCTAssertEqual(rows[0].counts[.claude]?.input, 900, "yesterday is untouched")
        XCTAssertEqual(rows[1].day, "2026-09-07")
        XCTAssertEqual(rows[1].counts[.claude]?.input, 5)
    }

    /// A day the app never ran is not the same as a quiet day, and the chart draws
    /// the difference.
    func testUnobservedDaysComeBackFlaggedRatherThanZero() {
        tagAc("akshay/personal/specs/spec-26/acs/ac-24")

        let f = Fixture("history-gap")
        let history = DailyHistory(stateDirectory: f.stateDirectory)

        history.record(day: "2026-09-05", snapshots: [.claude: snapshot(.claude, input: 10)])
        history.record(day: "2026-09-07", snapshots: [.claude: snapshot(.claude, input: 20)])

        let rows = history.records(days: 3, endingOn: day("2026-09-07"))
        XCTAssertEqual(rows.map(\.day), ["2026-09-05", "2026-09-06", "2026-09-07"])
        XCTAssertTrue(rows[0].recorded)
        XCTAssertFalse(rows[1].recorded, "the middle day was never observed")
        XCTAssertTrue(rows[2].recorded)
        XCTAssertEqual(rows[1].total(includeCacheReads: true, providers: [.claude]), 0)
    }

    /// A provider that cannot report token counts must not be stored as a zero it
    /// did not earn.
    func testProvidersWithNoTokenDataAreNotStored() {
        tagAc("akshay/personal/specs/spec-26/acs/ac-24")

        let f = Fixture("history-unavailable")
        let history = DailyHistory(stateDirectory: f.stateDirectory)

        history.record(day: "2026-09-07", snapshots: [
            .claude: snapshot(.claude, input: 7),
            .copilot: snapshot(.copilot, input: 0, quality: .unavailable),
            .cursor: snapshot(.cursor, input: 0, quality: .partial, installed: false),
        ])

        let row = history.records(days: 1, endingOn: day("2026-09-07")).first
        XCTAssertNotNil(row?.counts[.claude])
        XCTAssertNil(row?.counts[.copilot], "a provider with no token data is left out")
        XCTAssertNil(row?.counts[.cursor], "an uninstalled provider is left out")
    }

    /// The total honours the cache-read setting and the provider selection, the same
    /// way the panel does.
    func testTotalHonoursCacheReadsAndProviderSelection() {
        tagAc("akshay/personal/specs/spec-26/acs/ac-10")

        let f = Fixture("history-total")
        let history = DailyHistory(stateDirectory: f.stateDirectory)

        history.record(day: "2026-09-07", snapshots: [
            .claude: snapshot(.claude, input: 10, output: 5, cacheRead: 1_000),
            .codex: snapshot(.codex, input: 3, output: 2),
        ])
        let row = history.records(days: 1, endingOn: day("2026-09-07")).first!

        XCTAssertEqual(row.total(includeCacheReads: false, providers: [.claude, .codex]), 20)
        XCTAssertEqual(row.total(includeCacheReads: true, providers: [.claude, .codex]), 1_020)
        XCTAssertEqual(row.total(includeCacheReads: false, providers: [.codex]), 5,
                       "a deselected provider is excluded")
    }

    /// History survives a relaunch, which is the whole point of writing it down.
    func testHistoryPersistsAcrossInstances() {
        tagAc("akshay/personal/specs/spec-26/acs/ac-23")

        let f = Fixture("history-persist")
        DailyHistory(stateDirectory: f.stateDirectory)
            .record(day: "2026-09-07", snapshots: [.claude: snapshot(.claude, input: 42)])

        let reopened = DailyHistory(stateDirectory: f.stateDirectory)
        XCTAssertEqual(
            reopened.records(days: 1, endingOn: day("2026-09-07")).first?.counts[.claude]?.input,
            42
        )
    }

    /// The file stays bounded, oldest days going first.
    func testRetentionDropsTheOldestDays() {
        let f = Fixture("history-prune")
        let history = DailyHistory(stateDirectory: f.stateDirectory)
        let calendar = Calendar.current
        let start = day("2024-01-01")

        for offset in 0..<(DailyHistory.retainedDays + 25) {
            let date = calendar.date(byAdding: .day, value: offset, to: start)!
            history.record(day: DateParse.dayKey(for: date),
                           snapshots: [.claude: snapshot(.claude, input: 1)])
        }

        XCTAssertEqual(history.recordedDayCount, DailyHistory.retainedDays)
        XCTAssertFalse(
            history.records(days: 1, endingOn: start).first?.recorded ?? true,
            "the oldest day was pruned"
        )
    }

    private func day(_ key: String) -> Date {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.date(from: key)!
    }
}
