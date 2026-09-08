import XCTest
@testable import TokenCounter

/// The arithmetic the panel and the chart both read from.
final class AggregateTests: XCTestCase {

    private func snap(_ id: ProviderID, input: Int = 0, output: Int = 0, cacheWrite: Int = 0,
                      cacheRead: Int = 0, quality: DataQuality = .measured,
                      installed: Bool = true) -> ProviderSnapshot {
        ProviderSnapshot(
            id: id,
            counts: TokenCounts(input: input, output: output, cacheWrite: cacheWrite, cacheRead: cacheRead, calls: 1),
            quality: quality,
            installed: installed
        )
    }

    private let order = ProviderID.allCases

    /// The headline formula, and that the setting adds cache reads without touching
    /// any collected figure.
    func testHeadlineTotalIsInputOutputAndCacheWritesUntilCacheReadsAreEnabled() {
        tagAc("akshay/personal/specs/spec-26/acs/ac-10")

        let snapshots: [ProviderID: ProviderSnapshot] = [
            .claude: snap(.claude, input: 10, output: 20, cacheWrite: 30, cacheRead: 4_000),
            .codex: snap(.codex, input: 1, output: 2, cacheWrite: 3, cacheRead: 500),
        ]
        let providers = Aggregate.countingProviders(order: order, enabled: [.claude, .codex], snapshots: snapshots)

        XCTAssertEqual(
            Aggregate.combinedUsed(providers: providers, snapshots: snapshots, includeCacheReads: false),
            66, "input + output + cache writes"
        )
        XCTAssertEqual(
            Aggregate.combinedUsed(providers: providers, snapshots: snapshots, includeCacheReads: true),
            4_566, "the same total plus cache reads"
        )
        // The collected figures are untouched by the setting.
        XCTAssertEqual(Aggregate.combinedCounts(providers: providers, snapshots: snapshots).cacheRead, 4_500)
    }

    /// A provider that reports nothing must contribute nothing, rather than a zero
    /// that would read as an idle provider.
    func testProviderWithNoTokenDataIsExcludedFromEveryTotal() {
        tagAc("akshay/personal/specs/spec-26/acs/ac-11")

        let snapshots: [ProviderID: ProviderSnapshot] = [
            .claude: snap(.claude, input: 100),
            .copilot: snap(.copilot, quality: .unavailable),
        ]
        let providers = Aggregate.countingProviders(
            order: order, enabled: [.claude, .copilot], snapshots: snapshots)

        XCTAssertEqual(providers, [.claude], "an unavailable provider is not a counting provider")
        XCTAssertFalse(providers.contains(.copilot))
        XCTAssertEqual(Aggregate.combinedUsed(providers: providers, snapshots: snapshots, includeCacheReads: true), 100)
    }

    /// A deselected provider drops out of the total even though it reported.
    func testDeselectedProviderIsExcluded() {
        tagAc("akshay/personal/specs/spec-26/acs/ac-10")

        let snapshots: [ProviderID: ProviderSnapshot] = [
            .claude: snap(.claude, input: 100),
            .codex: snap(.codex, input: 5),
        ]
        let providers = Aggregate.countingProviders(order: order, enabled: [.codex], snapshots: snapshots)
        XCTAssertEqual(providers, [.codex])
        XCTAssertEqual(Aggregate.combinedUsed(providers: providers, snapshots: snapshots, includeCacheReads: false), 5)
    }

    /// The hover split must divide the reading, not rescale it: the arcs together have
    /// to reach exactly as far as one arc for the same total would.
    func testSegmentsSpanTheSameExtentAsASingleArc() {
        tagAc("akshay/personal/specs/spec-26/acs/ac-14")

        let snapshots: [ProviderID: ProviderSnapshot] = [
            .claude: snap(.claude, input: 3_000_000),
            .codex: snap(.codex, input: 1_000_000),
        ]
        let target = 10_000_000
        let providers = Aggregate.countingProviders(order: order, enabled: [.claude, .codex], snapshots: snapshots)
        let segments = Aggregate.segments(
            providers: providers, snapshots: snapshots, includeCacheReads: false,
            target: target, tint: { ProviderTint(id: $0.rawValue) })

        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(segments.first?.start ?? -1, 0, accuracy: 0.0001, "the first arc starts at the top")
        // Contiguous: each arc begins where the previous ended.
        XCTAssertEqual(segments[1].start, segments[0].end, accuracy: 0.0001)

        let singleArc = Double(4_000_000) / Double(target)
        XCTAssertEqual(segments.last?.end ?? -1, singleArc, accuracy: 0.0001,
                       "the union reaches the same extent as one arc for 4M of 10M")
    }

    /// A provider that spent nothing draws no arc, because a zero-length arc with a
    /// round cap leaves a dot on the dial.
    func testProviderThatSpentNothingDrawsNoArc() {
        tagAc("akshay/personal/specs/spec-26/acs/ac-14")

        let snapshots: [ProviderID: ProviderSnapshot] = [
            .claude: snap(.claude, input: 500),
            .codex: snap(.codex, input: 0),
            .gemini: snap(.gemini, input: 0),
        ]
        let providers = Aggregate.countingProviders(
            order: order, enabled: [.claude, .codex, .gemini], snapshots: snapshots)
        let segments = Aggregate.segments(
            providers: providers, snapshots: snapshots, includeCacheReads: false,
            target: 1_000, tint: { ProviderTint(id: $0.rawValue) })

        XCTAssertEqual(segments.map(\.id), [.claude], "only the provider that spent anything gets an arc")
    }

    /// Past the target the arcs stop at the rim rather than wrapping around it.
    func testSegmentsAreClampedAtTheRim() {
        tagAc("akshay/personal/specs/spec-26/acs/ac-14")

        let snapshots: [ProviderID: ProviderSnapshot] = [
            .claude: snap(.claude, input: 8_000),
            .codex: snap(.codex, input: 8_000),
        ]
        let providers = Aggregate.countingProviders(order: order, enabled: [.claude, .codex], snapshots: snapshots)
        let segments = Aggregate.segments(
            providers: providers, snapshots: snapshots, includeCacheReads: false,
            target: 10_000, tint: { ProviderTint(id: $0.rawValue) })

        for segment in segments {
            XCTAssertLessThanOrEqual(segment.end, 1.0, "no arc runs past the rim")
            XCTAssertLessThan(segment.start, 1.0)
        }
    }
}
