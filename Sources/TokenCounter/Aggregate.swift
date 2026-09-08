import Foundation

/// The arithmetic behind the panel, as pure functions.
///
/// Kept out of `UsageStore` so it can be tested through a small interface rather than
/// by reaching into an observable object's private state. The store holds the state
/// and calls these; they hold nothing.
enum Aggregate {

    /// Enabled providers that actually report token counts.
    ///
    /// A provider grading `.unavailable` is deliberately dropped here, which is what
    /// keeps an absent figure out of every total instead of contributing a zero.
    static func countingProviders(
        order: [ProviderID],
        enabled: Set<ProviderID>,
        snapshots: [ProviderID: ProviderSnapshot]
    ) -> [ProviderID] {
        order.filter { id in
            guard enabled.contains(id) else { return false }
            return (snapshots[id]?.quality ?? .measured) != .unavailable
        }
    }

    static func used(
        _ id: ProviderID,
        snapshots: [ProviderID: ProviderSnapshot],
        includeCacheReads: Bool
    ) -> Int {
        (snapshots[id]?.counts ?? TokenCounts()).total(includeCacheReads: includeCacheReads)
    }

    static func combinedCounts(
        providers: [ProviderID],
        snapshots: [ProviderID: ProviderSnapshot]
    ) -> TokenCounts {
        providers.reduce(TokenCounts()) { $0 + (snapshots[$1]?.counts ?? TokenCounts()) }
    }

    static func combinedUsed(
        providers: [ProviderID],
        snapshots: [ProviderID: ProviderSnapshot],
        includeCacheReads: Bool
    ) -> Int {
        providers.reduce(0) { $0 + used($1, snapshots: snapshots, includeCacheReads: includeCacheReads) }
    }

    /// Stacked arcs across the given providers, sized against `target`.
    ///
    /// A provider that spent nothing contributes no arc at all, rather than a
    /// zero-length one, because a zero-length arc with a round cap leaves a dot.
    /// The union of the arcs spans the same extent as a single arc for the same
    /// total would, so hovering divides the reading rather than rescaling it.
    static func segments(
        providers: [ProviderID],
        snapshots: [ProviderID: ProviderSnapshot],
        includeCacheReads: Bool,
        target: Int,
        tint: (ProviderID) -> ProviderTint
    ) -> [ProviderSegment] {
        var out: [ProviderSegment] = []
        var offset = 0
        let target = max(1, target)
        for id in providers {
            let value = used(id, snapshots: snapshots, includeCacheReads: includeCacheReads)
            guard value > 0 else { continue }
            let start = Double(offset) / Double(target)
            guard start < 1 else { break }
            let end = min(1, Double(offset + value) / Double(target))
            out.append(ProviderSegment(id: id, start: start, end: end, tint: tint(id)))
            offset += value
        }
        return out
    }
}

/// A provider's arc, before it is given a colour by the view layer.
struct ProviderSegment: Equatable {
    let id: ProviderID
    let start: Double
    let end: Double
    let tint: ProviderTint
}

/// Indirection so the arithmetic does not depend on SwiftUI.
struct ProviderTint: Equatable {
    let id: String
}
