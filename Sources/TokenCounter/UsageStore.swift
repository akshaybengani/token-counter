import Foundation
import SwiftUI

/// One arc of the ring. In combined mode there is one per enabled provider, stacked
/// so the ring shows composition as well as total.
struct RingSegment: Identifiable, Equatable {
    let id: String
    var start: Double
    var end: Double
    var color: Color
}

@MainActor
final class UsageStore: ObservableObject {
    static let shared = UsageStore()

    @Published private(set) var snapshots: [ProviderID: ProviderSnapshot] = [:]
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var isScanning = false

    @Published var combinedTarget: Int { didSet { Prefs.shared.combinedTarget = combinedTarget } }
    @Published var providerTargets: [ProviderID: Int] { didSet { Prefs.shared.providerTargets = providerTargets } }
    @Published var enabled: Set<ProviderID> { didSet { Prefs.shared.enabledProviders = enabled } }
    @Published var mode: DisplayMode { didSet { Prefs.shared.displayMode = mode } }
    @Published var includeCacheReads: Bool { didSet { Prefs.shared.includeCacheReads = includeCacheReads } }
    @Published var showBreakdown: Bool { didSet { Prefs.shared.showBreakdown = showBreakdown } }
    @Published var refreshMinutes: Int {
        didSet {
            Prefs.shared.refreshMinutes = refreshMinutes
            startTimer()
        }
    }

    /// Survives midnight, so the chart has something to plot.
    let history = DailyHistory()

    /// Bumped whenever history is written, so the chart redraws.
    @Published private(set) var historyRevision = 0

    private let providers: [ProviderID: any UsageProvider] = [
        .claude: ClaudeProvider(),
        .codex: CodexProvider(),
        .cursor: CursorProvider(),
        .gemini: GeminiProvider(),
        .copilot: CopilotProvider(),
    ]
    private let queue = DispatchQueue(label: "com.akshaybengani.tokencounter.scan", qos: .utility)
    private var timer: Timer?

    private init() {
        combinedTarget = Prefs.shared.combinedTarget
        providerTargets = Prefs.shared.providerTargets
        enabled = Prefs.shared.enabledProviders
        mode = Prefs.shared.displayMode
        includeCacheReads = Prefs.shared.includeCacheReads
        showBreakdown = Prefs.shared.showBreakdown
        refreshMinutes = Prefs.shared.refreshMinutes
    }

    // MARK: - Reading the tallies

    /// Providers in a stable order, so the legend and the ring never reshuffle.
    var orderedProviders: [ProviderID] { ProviderID.allCases }

    var activeProviders: [ProviderID] { orderedProviders.filter { enabled.contains($0) } }

    /// Enabled providers that actually report token counts. A provider reporting
    /// `.unavailable` is shown in the panel but kept out of every total, so an absent
    /// figure never reads as zero usage.
    var countingProviders: [ProviderID] {
        activeProviders.filter { snapshot($0).quality != .unavailable }
    }

    func snapshot(_ id: ProviderID) -> ProviderSnapshot {
        snapshots[id] ?? ProviderSnapshot(id: id)
    }

    func counts(_ id: ProviderID) -> TokenCounts { snapshot(id).counts }

    func used(_ id: ProviderID) -> Int {
        counts(id).total(includeCacheReads: includeCacheReads)
    }

    func target(_ id: ProviderID) -> Int {
        providerTargets[id] ?? combinedTarget
    }

    func setTarget(_ value: Int, for id: ProviderID) {
        var next = providerTargets
        next[id] = max(1_000, value)
        providerTargets = next
    }

    func fraction(_ id: ProviderID) -> Double {
        min(1, max(0, rawFraction(id)))
    }

    func rawFraction(_ id: ProviderID) -> Double {
        Double(used(id)) / Double(max(1, target(id)))
    }

    // MARK: - Combined figures

    var combinedUsed: Int {
        countingProviders.reduce(0) { $0 + used($1) }
    }

    var combinedCounts: TokenCounts {
        countingProviders.reduce(TokenCounts()) { $0 + counts($1) }
    }

    var combinedRawFraction: Double {
        Double(combinedUsed) / Double(max(1, combinedTarget))
    }

    var combinedFraction: Double { min(1, max(0, combinedRawFraction)) }

    var combinedRemaining: Int { max(0, combinedTarget - combinedUsed) }

    /// The figure the panel headline and the menu bar show, which depends on the mode.
    var headlineUsed: Int { combinedUsed }
    var headlineTarget: Int { combinedTarget }
    var headlineRawFraction: Double { combinedRawFraction }

    var percentText: String { percentText(combinedRawFraction) }

    func percentText(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))%"
    }

    var level: UsageLevel { UsageLevel(fraction: combinedRawFraction) }

    /// True when any enabled provider reports a figure that is a floor rather than a
    /// total, which the panel marks so the number is not read as exact.
    var hasPartialData: Bool {
        activeProviders.contains { snapshot($0).installed && snapshot($0).quality == .partial && used($0) > 0 }
    }

    /// Stacked arcs across the enabled providers, sized against the combined target.
    var combinedSegments: [RingSegment] {
        var out: [RingSegment] = []
        var offset = 0
        let target = max(1, combinedTarget)
        for id in countingProviders {
            let value = used(id)
            guard value > 0 else { continue }
            let start = Double(offset) / Double(target)
            let end = Double(offset + value) / Double(target)
            guard start < 1 else { break }
            out.append(RingSegment(id: id.rawValue, start: start, end: min(1, end), color: id.tint))
            offset += value
        }
        return out
    }

    // MARK: - Refresh

    func start() {
        refresh()
        startTimer()
    }

    private func startTimer() {
        timer?.invalidate()
        let interval = TimeInterval(max(1, refreshMinutes) * 60)
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        t.tolerance = interval * 0.2
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func refresh(rebuilding: Bool = false) {
        guard !isScanning else { return }
        isScanning = true
        let providers = self.providers
        let history = self.history
        queue.async { [weak self] in
            let now = Date()
            let dayStart = Calendar.current.startOfDay(for: now)
            let dayKey = DateParse.dayKey(for: now)

            var results: [ProviderID: ProviderSnapshot] = [:]
            for (id, provider) in providers {
                if rebuilding { provider.reset() }
                results[id] = provider.scan(dayStart: dayStart, dayKey: dayKey)
            }

            // The day key here is the one the providers just counted against, so
            // the row written is always the row they measured.
            history.record(day: dayKey, snapshots: results)

            Task { @MainActor in
                guard let self else { return }
                self.snapshots = results
                self.lastUpdated = Date()
                self.isScanning = false
                self.historyRevision &+= 1
            }
        }
    }

    func rebuild() { refresh(rebuilding: true) }

    /// Daily totals for the chart, oldest first, measured the way the panel measures.
    func dailyTotals(days: Int) -> [(record: DailyRecord, total: Int)] {
        let active = Set(countingProviders)
        return history.records(days: days).map { record in
            (record, record.total(includeCacheReads: includeCacheReads, providers: active))
        }
    }

    func sourceDescription(_ id: ProviderID) -> String {
        providers[id]?.sourceDescription ?? ""
    }
}

enum UsageLevel {
    case low, medium, high, over

    init(fraction: Double) {
        if fraction >= 1 { self = .over }
        else if fraction >= 0.85 { self = .high }
        else if fraction >= 0.6 { self = .medium }
        else { self = .low }
    }

    var color: Color {
        switch self {
        case .low:    return Palette.low
        case .medium: return Palette.medium
        case .high:   return Palette.high
        case .over:   return Palette.over
        }
    }

    /// The far end of the arc's gradient.
    var trailing: Color {
        switch self {
        case .low:    return Palette.lowTrailing
        case .medium: return Palette.mediumTrailing
        case .high:   return Palette.highTrailing
        case .over:   return Palette.overTrailing
        }
    }
}
