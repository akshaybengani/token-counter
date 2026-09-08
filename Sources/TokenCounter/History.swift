import Foundation

/// One day's usage, as it was observed.
struct DailyRecord: Identifiable, Equatable {
    let day: String
    let date: Date
    /// Per provider. A provider absent from here reported nothing that day.
    let counts: [ProviderID: TokenCounts]
    /// False for a day the app never saw, which is different from a day that was
    /// quiet. A closed laptop leaves no record; an idle one records zero.
    let recorded: Bool

    var id: String { day }

    func total(includeCacheReads: Bool, providers: Set<ProviderID>) -> Int {
        counts
            .filter { providers.contains($0.key) }
            .values
            .reduce(0) { $0 + $1.total(includeCacheReads: includeCacheReads) }
    }
}

/// Remembers what each day cost, so the total survives midnight.
///
/// Today's row is rewritten on every refresh rather than being written once at
/// midnight. That is deliberate: a Mac asleep or shut down at midnight would miss a
/// single scheduled write and lose the day, whereas an upsert of the current day is
/// idempotent and always current. When the day changes, yesterday's row is already
/// complete and today's starts.
///
/// A day the app never ran is absent rather than zero, and the chart draws that
/// difference.
final class DailyHistory: @unchecked Sendable {
    /// Roughly a year, which is far more than the panel plots and still a small file.
    static let retainedDays = 400

    private struct Stored: Codable {
        /// day key -> provider raw value -> counts
        var days: [String: [String: TokenCounts]] = [:]
    }

    private let url: URL
    private var stored = Stored()

    init(stateDirectory: URL? = nil) {
        url = (stateDirectory ?? StateStore.directory).appendingPathComponent("history.json")
        if let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode(Stored.self, from: data) {
            stored = decoded
        }
    }

    /// Writes the given day's figures, replacing whatever was there.
    ///
    /// Providers that cannot report token counts are left out, so an absent provider
    /// never lands in the file as a zero it did not earn.
    func record(day: String, snapshots: [ProviderID: ProviderSnapshot]) {
        var row: [String: TokenCounts] = [:]
        for (id, snapshot) in snapshots where snapshot.installed && snapshot.quality != .unavailable {
            row[id.rawValue] = snapshot.counts
        }
        guard !row.isEmpty else { return }
        stored.days[day] = row
        prune()
        save()
    }

    /// The last `days` days ending on `endingOn`, oldest first, with unobserved days
    /// present but flagged.
    func records(days: Int, endingOn: Date = Date()) -> [DailyRecord] {
        let calendar = Calendar.current
        let end = calendar.startOfDay(for: endingOn)
        return (0..<max(1, days)).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: end) else { return nil }
            let key = DateParse.dayKey(for: date)
            guard let row = stored.days[key] else {
                return DailyRecord(day: key, date: date, counts: [:], recorded: false)
            }
            var counts: [ProviderID: TokenCounts] = [:]
            for (raw, value) in row {
                if let id = ProviderID(rawValue: raw) { counts[id] = value }
            }
            return DailyRecord(day: key, date: date, counts: counts, recorded: true)
        }
    }

    var recordedDayCount: Int { stored.days.count }

    func reset() {
        stored = Stored()
        try? FileManager.default.removeItem(at: url)
    }

    private func prune() {
        guard stored.days.count > Self.retainedDays else { return }
        let doomed = stored.days.keys.sorted().prefix(stored.days.count - Self.retainedDays)
        for key in doomed { stored.days.removeValue(forKey: key) }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(stored) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
