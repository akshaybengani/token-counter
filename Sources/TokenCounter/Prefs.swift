import Foundation

enum PrefKey {
    static let combinedTarget = "combinedTarget"
    static let providerTargets = "providerTargets"
    static let enabledProviders = "enabledProviders"
    static let displayMode = "displayMode"
    static let includeCacheReads = "includeCacheReads"
    static let refreshMinutes = "refreshMinutes"
    static let alwaysOnTop = "alwaysOnTop"
    static let panelVisible = "panelVisible"
    static let showBreakdown = "showBreakdown"
}

/// One ring for the enabled providers together, or one small ring for each.
enum DisplayMode: String, Codable, CaseIterable, Identifiable {
    case combined
    case separate

    var id: String { rawValue }

    var label: String {
        switch self {
        case .combined: return "Combined"
        case .separate: return "Per provider"
        }
    }
}

final class Prefs {
    static let shared = Prefs()
    private let d = UserDefaults.standard

    private init() {
        d.register(defaults: [
            PrefKey.combinedTarget: 10_000_000,
            PrefKey.enabledProviders: ProviderID.allCases.filter { $0 != .copilot }.map(\.rawValue),
            PrefKey.displayMode: DisplayMode.combined.rawValue,
            PrefKey.includeCacheReads: false,
            PrefKey.refreshMinutes: 5,
            PrefKey.alwaysOnTop: true,
            PrefKey.panelVisible: true,
            PrefKey.showBreakdown: true,
        ])
    }

    var combinedTarget: Int {
        get { max(1_000, d.integer(forKey: PrefKey.combinedTarget)) }
        set { d.set(newValue, forKey: PrefKey.combinedTarget) }
    }

    /// Per-provider targets, used in per-provider mode. Missing entries fall back to
    /// the combined target so a newly enabled provider starts somewhere sensible.
    var providerTargets: [ProviderID: Int] {
        get {
            let raw = d.dictionary(forKey: PrefKey.providerTargets) as? [String: Int] ?? [:]
            var out: [ProviderID: Int] = [:]
            for (k, v) in raw {
                if let id = ProviderID(rawValue: k) { out[id] = max(1_000, v) }
            }
            return out
        }
        set {
            var raw: [String: Int] = [:]
            for (k, v) in newValue { raw[k.rawValue] = v }
            d.set(raw, forKey: PrefKey.providerTargets)
        }
    }

    var enabledProviders: Set<ProviderID> {
        get {
            let raw = d.stringArray(forKey: PrefKey.enabledProviders) ?? []
            let ids = raw.compactMap(ProviderID.init(rawValue:))
            // Never leave the panel with nothing to show.
            return ids.isEmpty ? Set(ProviderID.allCases.filter { $0 != .copilot }) : Set(ids)
        }
        set { d.set(newValue.map(\.rawValue), forKey: PrefKey.enabledProviders) }
    }

    var displayMode: DisplayMode {
        get { DisplayMode(rawValue: d.string(forKey: PrefKey.displayMode) ?? "") ?? .combined }
        set { d.set(newValue.rawValue, forKey: PrefKey.displayMode) }
    }

    var includeCacheReads: Bool {
        get { d.bool(forKey: PrefKey.includeCacheReads) }
        set { d.set(newValue, forKey: PrefKey.includeCacheReads) }
    }
    var refreshMinutes: Int {
        get { max(1, d.integer(forKey: PrefKey.refreshMinutes)) }
        set { d.set(newValue, forKey: PrefKey.refreshMinutes) }
    }
    var alwaysOnTop: Bool {
        get { d.bool(forKey: PrefKey.alwaysOnTop) }
        set { d.set(newValue, forKey: PrefKey.alwaysOnTop) }
    }
    var panelVisible: Bool {
        get { d.bool(forKey: PrefKey.panelVisible) }
        set { d.set(newValue, forKey: PrefKey.panelVisible) }
    }
    var showBreakdown: Bool {
        get { d.bool(forKey: PrefKey.showBreakdown) }
        set { d.set(newValue, forKey: PrefKey.showBreakdown) }
    }
}

// MARK: - Formatting

enum Fmt {
    /// 7,991,234 becomes "7.99M". Space on the panel is tight, so figures are
    /// abbreviated there while settings shows them grouped in full.
    static func compact(_ n: Int) -> String {
        let v = Double(n)
        if v >= 1_000_000_000 { return String(format: "%.2fB", v / 1e9) }
        if v >= 1_000_000 { return String(format: "%.2fM", v / 1e6) }
        if v >= 10_000 { return String(format: "%.0fK", v / 1e3) }
        if v >= 1_000 { return String(format: "%.1fK", v / 1e3) }
        return "\(n)"
    }

    /// Targets read better without trailing zeros: 10,000,000 becomes "10M".
    static func compactTight(_ n: Int) -> String {
        let v = Double(n)
        if v >= 1_000_000_000 { return trim(v / 1e9) + "B" }
        if v >= 1_000_000 { return trim(v / 1e6) + "M" }
        if v >= 1_000 { return trim(v / 1e3) + "K" }
        return "\(n)"
    }

    private static func trim(_ v: Double) -> String {
        v == v.rounded() ? String(format: "%.0f", v) : String(format: "%.1f", v)
    }

    static func grouped(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    static func relative(_ date: Date?) -> String {
        guard let date else { return "Not set" }
        let s = Int(Date().timeIntervalSince(date))
        if s < 10 { return "just now" }
        if s < 60 { return "\(s)s ago" }
        if s < 3600 { return "\(s / 60)m ago" }
        return "\(s / 3600)h ago"
    }

    /// "1 call" or "24 calls", per the counted-noun rule.
    static func calls(_ n: Int) -> String {
        n == 1 ? "1 call" : "\(Fmt.grouped(n)) calls"
    }
}
