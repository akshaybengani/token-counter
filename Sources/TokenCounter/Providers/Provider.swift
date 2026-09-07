import Foundation
import SwiftUI

/// Token tallies in a shape every provider can map onto.
///
/// Providers differ in what they record. Claude Code reports cache writes and cache
/// reads separately; Codex reports a cached-input figure but no cache-write figure;
/// Cursor reports only input and output. A provider leaves at zero whatever it does
/// not measure, so a zero here means "not reported", not "none happened".
struct TokenCounts: Codable, Equatable {
    var input = 0
    var output = 0
    var cacheWrite = 0
    var cacheRead = 0
    var calls = 0

    /// Cache reads dwarf everything else, so counting them is opt-in.
    func total(includeCacheReads: Bool) -> Int {
        input + output + cacheWrite + (includeCacheReads ? cacheRead : 0)
    }

    static func + (a: TokenCounts, b: TokenCounts) -> TokenCounts {
        TokenCounts(
            input: a.input + b.input,
            output: a.output + b.output,
            cacheWrite: a.cacheWrite + b.cacheWrite,
            cacheRead: a.cacheRead + b.cacheRead,
            calls: a.calls + b.calls
        )
    }
}

enum ProviderID: String, Codable, CaseIterable, Identifiable {
    case claude
    case codex
    case cursor
    case gemini
    case copilot

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude: return "Claude Code"
        case .codex:  return "Codex"
        case .cursor: return "Cursor"
        case .gemini: return "Gemini CLI"
        case .copilot: return "Copilot"
        }
    }

    /// For the panel legend, where horizontal space is tight.
    var shortName: String {
        switch self {
        case .claude: return "Claude"
        case .codex:  return "Codex"
        case .cursor: return "Cursor"
        case .gemini: return "Gemini"
        case .copilot: return "Copilot"
        }
    }

    var tint: Color {
        switch self {
        case .claude: return Color(red: 0.93, green: 0.55, blue: 0.24)
        case .codex:  return Color(red: 0.30, green: 0.78, blue: 0.62)
        case .cursor: return Color(red: 0.45, green: 0.60, blue: 0.95)
        case .gemini: return Color(red: 0.68, green: 0.48, blue: 0.92)
        case .copilot: return Color(red: 0.55, green: 0.58, blue: 0.64)
        }
    }
}

/// How much to trust a provider's figure.
enum DataQuality: String, Codable {
    /// The tool records per-call token counts with timestamps.
    case measured
    /// The tool records token counts for only some calls, so the figure is a floor.
    case partial
    /// The tool is installed but records no token counts locally.
    case unavailable

    var marker: String {
        switch self {
        case .measured:    return ""
        case .partial:     return "≥"
        case .unavailable: return "?"
        }
    }
}

struct ProviderSnapshot: Equatable {
    var id: ProviderID
    var counts = TokenCounts()
    var quality: DataQuality = .measured
    /// False when the tool's data directory is absent, which reads as "not installed".
    var installed = true

    static func absent(_ id: ProviderID) -> ProviderSnapshot {
        ProviderSnapshot(id: id, counts: TokenCounts(), quality: .unavailable, installed: false)
    }
}

/// Providers are built on the main actor and then used only on the scan queue.
protocol UsageProvider: AnyObject, Sendable {
    var id: ProviderID { get }
    /// Where this provider reads from, shown in settings.
    var sourceDescription: String { get }
    /// Tally usage at or after `dayStart`. Called off the main thread.
    func scan(dayStart: Date, dayKey: String) -> ProviderSnapshot
    /// Discard incremental state so the next scan re-reads from the beginning.
    func reset()
}
