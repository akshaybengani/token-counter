import Foundation
import SQLite3

/// Reads Cursor's editor database at
/// `~/Library/Application Support/Cursor/User/globalStorage/state.vscdb`.
///
/// Cursor is the weakest of the three sources, and deliberately reported as `.partial`:
///
///  * Only some messages carry a non-zero `tokenCount`. On this machine 119 of 10,068
///    did, so the figure is a floor rather than a total.
///  * A message carries no timestamp of its own. The only date available is the
///    conversation's `createdAt`, so a conversation opened yesterday and continued today
///    counts against yesterday.
///  * Cursor reports input and output only, with no cache figures.
///
/// The Cursor CLI keeps its own transcripts under `~/.cursor/chats`, but those record no
/// token counts at all, so there is nothing to read there.
final class CursorProvider: UsageProvider, @unchecked Sendable {
    let id = ProviderID.cursor
    var sourceDescription: String { "~/Library/Application Support/Cursor/.../state.vscdb" }

    private struct Cache: Codable {
        var dayKey = ""
        var dbModified: Date = .distantPast
        var counts = TokenCounts()
    }

    private let dbURL: URL
    private let cacheURL: URL
    private var cache = Cache()

    /// `database` and `stateDirectory` default to the real locations; tests pass fixtures.
    init(database: URL? = nil, stateDirectory: URL? = nil) {
        dbURL = database ?? URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support/Cursor/User/globalStorage/state.vscdb")
        cacheURL = (stateDirectory ?? StateStore.directory).appendingPathComponent("cursor-state.json")
        if let data = try? Data(contentsOf: cacheURL),
           let decoded = try? JSONDecoder().decode(Cache.self, from: data) {
            cache = decoded
        }
    }

    func scan(dayStart: Date, dayKey: String) -> ProviderSnapshot {
        guard FileManager.default.fileExists(atPath: dbURL.path) else { return .absent(id) }

        let attrs = try? FileManager.default.attributesOfItem(atPath: dbURL.path)
        let modified = (attrs?[.modificationDate] as? Date) ?? .distantPast

        // The database runs to hundreds of megabytes, so re-read it only when Cursor
        // has actually written to it.
        if cache.dayKey == dayKey && cache.dbModified == modified {
            return ProviderSnapshot(id: id, counts: cache.counts, quality: .partial, installed: true)
        }

        let counts = tally(dayStart: dayStart)
        cache = Cache(dayKey: dayKey, dbModified: modified, counts: counts)
        if let data = try? JSONEncoder().encode(cache) {
            try? data.write(to: cacheURL, options: .atomic)
        }
        return ProviderSnapshot(id: id, counts: counts, quality: .partial, installed: true)
    }

    private func tally(dayStart: Date) -> TokenCounts {
        var counts = TokenCounts()
        var db: OpaquePointer?
        // Read-only, and never create: Cursor owns this file.
        guard sqlite3_open_v2(dbURL.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            return counts
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 3_000)

        // One prepared lookup reused for every bubble in today's conversations.
        var bubbleStmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT value FROM cursorDiskKV WHERE key = ?", -1, &bubbleStmt, nil) == SQLITE_OK else {
            return counts
        }
        defer { sqlite3_finalize(bubbleStmt) }

        var composerStmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT value FROM cursorDiskKV WHERE key LIKE 'composerData:%'", -1, &composerStmt, nil) == SQLITE_OK else {
            return counts
        }
        defer { sqlite3_finalize(composerStmt) }

        while sqlite3_step(composerStmt) == SQLITE_ROW {
            guard let raw = sqlite3_column_text(composerStmt, 0) else { continue }
            guard let obj = try? JSONSerialization.jsonObject(with: Data(String(cString: raw).utf8)) as? [String: Any],
                  let composerID = obj["composerID"] as? String ?? obj["composerId"] as? String,
                  let createdMS = obj["createdAt"] as? NSNumber
            else { continue }

            let created = Date(timeIntervalSince1970: createdMS.doubleValue / 1000)
            guard created >= dayStart else { continue }

            let headers = obj["fullConversationHeadersOnly"] as? [[String: Any]] ?? []
            for header in headers {
                guard let bubbleID = header["bubbleId"] as? String else { continue }
                let key = "bubbleId:\(composerID):\(bubbleID)"

                sqlite3_reset(bubbleStmt)
                sqlite3_clear_bindings(bubbleStmt)
                sqlite3_bind_text(bubbleStmt, 1, key, -1, SQLITE_TRANSIENT)
                guard sqlite3_step(bubbleStmt) == SQLITE_ROW,
                      let bubbleRaw = sqlite3_column_text(bubbleStmt, 0),
                      let bubble = try? JSONSerialization.jsonObject(with: Data(String(cString: bubbleRaw).utf8)) as? [String: Any],
                      let tokenCount = bubble["tokenCount"] as? [String: Any]
                else { continue }

                let input = intValue(tokenCount["inputTokens"])
                let output = intValue(tokenCount["outputTokens"])
                guard input > 0 || output > 0 else { continue }
                counts.input += input
                counts.output += output
                counts.calls += 1
            }
        }
        return counts
    }

    func reset() {
        cache = Cache()
        try? FileManager.default.removeItem(at: cacheURL)
    }
}
