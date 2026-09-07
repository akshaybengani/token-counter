import Foundation

/// Reads Gemini CLI sessions in `~/.gemini/tmp/<project>/chats/session-*.json`.
///
/// Unlike the Claude Code and Codex transcripts, these are whole JSON documents that
/// get rewritten as a session grows, so a byte cursor is no use. Instead each file is
/// skipped while its modification date is unchanged, and messages are deduped by id so
/// re-reading a grown file counts only what is new.
///
/// A Gemini message reports `{input, output, cached, thoughts, tool, total}`, where
/// `total` is `input + output + thoughts + tool` and `cached` is the cached slice of
/// `input`. Mapping keeps that sum intact: the cached slice moves to cache reads,
/// thinking tokens join output, and tool tokens join input, because they arrive as
/// prompt context.
///
/// Gemini's Antigravity surfaces (`~/.gemini/antigravity`, `~/.gemini/antigravity-cli`)
/// store conversations as protobuf and SQLite blobs that carry no token figures, so
/// there is nothing to read there.
final class GeminiProvider: UsageProvider, @unchecked Sendable {
    let id = ProviderID.gemini
    var sourceDescription: String { "~/.gemini/tmp/*/chats/session-*.json" }

    private struct State: Codable {
        var dayKey = ""
        var counts = TokenCounts()
        var seen: Set<String> = []
        /// path -> modification time last parsed
        var mtimes: [String: Double] = [:]
    }

    private let root: URL
    private let stateURL: URL
    private var state = State()

    /// `root` and `stateDirectory` default to the real locations; tests pass fixtures.
    init(root: URL? = nil, stateDirectory: URL? = nil) {
        self.root = root ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".gemini/tmp")
        stateURL = (stateDirectory ?? StateStore.directory).appendingPathComponent("gemini-state.json")
        if let data = try? Data(contentsOf: stateURL),
           let decoded = try? JSONDecoder().decode(State.self, from: data) {
            state = decoded
        }
    }

    func scan(dayStart: Date, dayKey: String) -> ProviderSnapshot {
        guard FileManager.default.fileExists(atPath: root.path) else { return .absent(id) }

        if state.dayKey != dayKey {
            state.dayKey = dayKey
            state.counts = TokenCounts()
            state.seen = []
            // Modification dates are re-checked from scratch on a new day, so a file
            // last written yesterday is not mistaken for one already counted today.
            state.mtimes = [:]
        }

        var livePaths = Set<String>()

        for file in sessionFiles() {
            let path = file.path
            livePaths.insert(path)

            let attrs = try? FileManager.default.attributesOfItem(atPath: path)
            let mtime = ((attrs?[.modificationDate] as? Date) ?? .distantPast).timeIntervalSince1970

            // A file nobody wrote today cannot hold today's messages.
            if mtime < dayStart.timeIntervalSince1970 {
                state.mtimes[path] = mtime
                continue
            }
            if let seenAt = state.mtimes[path], seenAt == mtime { continue }
            state.mtimes[path] = mtime

            guard let data = try? Data(contentsOf: file),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let messages = obj["messages"] as? [[String: Any]]
            else { continue }

            for message in messages {
                guard let tokens = message["tokens"] as? [String: Any] else { continue }

                let key = message["id"] as? String ?? ""
                if !key.isEmpty && state.seen.contains(key) { continue }

                guard let ts = message["timestamp"] as? String,
                      let date = DateParse.iso(ts),
                      date >= dayStart
                else { continue }

                if !key.isEmpty { state.seen.insert(key) }

                let cached = intValue(tokens["cached"])
                state.counts.input     += max(0, intValue(tokens["input"]) - cached) + intValue(tokens["tool"])
                state.counts.output    += intValue(tokens["output"]) + intValue(tokens["thoughts"])
                state.counts.cacheRead += cached
                state.counts.calls     += 1
            }
        }

        if state.mtimes.count > livePaths.count {
            state.mtimes = state.mtimes.filter { livePaths.contains($0.key) }
        }

        save()
        return ProviderSnapshot(id: id, counts: state.counts, quality: .measured, installed: true)
    }

    private func sessionFiles() -> [URL] {
        guard let e = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }
        var out: [URL] = []
        for case let url as URL in e
        where url.pathExtension == "json"
            && url.lastPathComponent.hasPrefix("session-")
            && url.deletingLastPathComponent().lastPathComponent == "chats" {
            out.append(url)
        }
        return out
    }

    func reset() {
        state = State()
        try? FileManager.default.removeItem(at: stateURL)
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: stateURL, options: .atomic)
    }
}
