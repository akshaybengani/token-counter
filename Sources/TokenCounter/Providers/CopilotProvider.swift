import Foundation
import SQLite3

/// GitHub Copilot, which records no token counts anywhere on disk.
///
/// Every local store was checked:
///
///  * `~/.copilot/logs` holds process startup lines and nothing else.
///  * Copilot's session store, `session-store.db` in the `github.copilot-chat` extension
///    storage, has no token column in any table. Its `turns` table keeps the user
///    message, the assistant response, and a timestamp.
///  * VS Code's own `chatSessions` documents carry no usage figures.
///
/// So this provider reports `.unavailable` rather than a figure. It still counts the
/// turns in the session store, which tells you whether Copilot has been used at all,
/// and that count is deliberately kept out of every token total.
final class CopilotProvider: UsageProvider, @unchecked Sendable {
    let id = ProviderID.copilot
    var sourceDescription: String { "~/.copilot and the github.copilot-chat session store" }

    private let cliDirectory: URL
    private let sessionStore: URL

    init() {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        cliDirectory = home.appendingPathComponent(".copilot")
        sessionStore = home.appendingPathComponent(
            "Library/Application Support/Code/User/globalStorage/github.copilot-chat/session-store.db")
    }

    func scan(dayStart: Date, dayKey: String) -> ProviderSnapshot {
        let fm = FileManager.default
        let installed = fm.fileExists(atPath: cliDirectory.path)
            || fm.fileExists(atPath: sessionStore.path)
        guard installed else { return .absent(id) }

        var counts = TokenCounts()
        counts.calls = turnsToday(dayStart: dayStart)
        return ProviderSnapshot(id: id, counts: counts, quality: .unavailable, installed: true)
    }

    /// Counts turns recorded on or after `dayStart`. Returns 0 if the store cannot be
    /// read, which is the same answer as an empty store and is fine either way, since
    /// nothing here feeds a token total.
    private func turnsToday(dayStart: Date) -> Int {
        guard FileManager.default.fileExists(atPath: sessionStore.path) else { return 0 }

        var db: OpaquePointer?
        guard sqlite3_open_v2(sessionStore.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            return 0
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 2_000)

        var stmt: OpaquePointer?
        let sql = "SELECT count(*) FROM turns WHERE timestamp >= ?"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(stmt) }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(identifier: "UTC")
        sqlite3_bind_text(stmt, 1, formatter.string(from: dayStart), -1, SQLITE_TRANSIENT)

        guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int(stmt, 0))
    }

    func reset() {}
}
