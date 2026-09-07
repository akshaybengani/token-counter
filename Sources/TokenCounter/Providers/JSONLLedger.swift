import Foundation
import SQLite3

/// Tells SQLite to copy a bound string. Swift's bridged C string is a temporary that
/// dies when the bind call returns, so the default SQLITE_STATIC would leave the
/// statement pointing at freed memory by the time it is stepped.
let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Where providers keep their incremental state.
///
/// `TOKEN_COUNTER_STATE_DIR` redirects it, which is how `tools/verify` scans from an
/// arbitrary cutoff without touching the running app's state. That matters because byte
/// cursors deliberately survive a day rollover: a tool that advanced the app's cursors
/// while writing a different day key would make the app skip records it had not counted.
enum StateStore {
    static var directory: URL {
        if let override = ProcessInfo.processInfo.environment["TOKEN_COUNTER_STATE_DIR"],
           !override.isEmpty {
            let url = URL(fileURLWithPath: override, isDirectory: true)
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }
        let url = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TokenCounter", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

/// Incremental state for a provider that reads append-only JSONL transcripts.
struct LedgerState: Codable {
    var dayKey = ""
    var counts = TokenCounts()
    /// path -> bytes already consumed
    var cursors: [String: UInt64] = [:]
    /// Dedupe keys for today, reset at midnight.
    var seen: Set<String> = []
    /// Per-file carry-over for providers that report cumulative totals (Codex).
    var runningTotals: [String: [Int]] = [:]
}

/// Walks a tree of JSONL files, remembering how far into each one it has read.
///
/// A refresh parses only bytes appended since the previous scan, which keeps a
/// five-minute poll cheap even when the transcripts run to hundreds of megabytes.
final class JSONLLedger: @unchecked Sendable {
    /// Called for every candidate line. Mutates `state.counts` when the record counts.
    typealias LineHandler = (Data.SubSequence, Date, String, inout LedgerState) -> Void

    let root: URL
    private let stateURL: URL
    private let needle: Data
    private let handler: LineHandler
    private var state = LedgerState()

    init(
        root: URL,
        stateName: String,
        needle: String,
        stateDirectory: URL? = nil,
        handler: @escaping LineHandler
    ) {
        self.root = root
        self.needle = Data(needle.utf8)
        self.handler = handler
        stateURL = (stateDirectory ?? StateStore.directory)
            .appendingPathComponent("\(stateName).json")
        load()
    }

    var rootExists: Bool {
        FileManager.default.fileExists(atPath: root.path)
    }

    func scan(dayStart: Date, dayKey: String) -> TokenCounts {
        // Local-midnight rollover. Byte cursors and running totals survive, because
        // they describe how far we have read, not what day it is.
        if state.dayKey != dayKey {
            state.dayKey = dayKey
            state.counts = TokenCounts()
            state.seen = []
        }

        var livePaths = Set<String>()

        for file in files() {
            let path = file.path
            livePaths.insert(path)

            let attrs = try? FileManager.default.attributesOfItem(atPath: path)
            let size = (attrs?[.size] as? NSNumber)?.uint64Value ?? 0
            let mtime = (attrs?[.modificationDate] as? Date) ?? .distantPast

            var offset: UInt64
            if let known = state.cursors[path] {
                offset = known
            } else if mtime < dayStart {
                // First sight of a file untouched today: it cannot hold today's records,
                // so skip its bytes and remember where the end is.
                state.cursors[path] = size
                continue
            } else {
                offset = 0
            }

            if size < offset { offset = 0 }   // truncated or rotated
            if size == offset { continue }

            guard let handle = try? FileHandle(forReadingFrom: file) else { continue }
            defer { try? handle.close() }
            do { try handle.seek(toOffset: offset) } catch { continue }
            guard let chunk = try? handle.readToEnd(), !chunk.isEmpty else { continue }

            // Stop at the last newline so a half-written trailing line is read next time.
            guard let lastNewline = chunk.lastIndex(of: 0x0A) else { continue }
            let complete = chunk[chunk.startIndex...lastNewline]

            for line in complete.split(separator: 0x0A, omittingEmptySubsequences: true) {
                guard line.range(of: needle) != nil else { continue }
                handler(line, dayStart, path, &state)
            }

            state.cursors[path] = offset + UInt64(complete.count)
        }

        // Forget files that have since been deleted.
        if state.cursors.count > livePaths.count {
            state.cursors = state.cursors.filter { livePaths.contains($0.key) }
            state.runningTotals = state.runningTotals.filter { livePaths.contains($0.key) }
        }

        save()
        return state.counts
    }

    private func files() -> [URL] {
        guard let e = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }
        var out: [URL] = []
        for case let url as URL in e where url.pathExtension == "jsonl" {
            out.append(url)
        }
        return out
    }

    func reset() {
        state = LedgerState()
        try? FileManager.default.removeItem(at: stateURL)
    }

    private func load() {
        guard let data = try? Data(contentsOf: stateURL),
              let decoded = try? JSONDecoder().decode(LedgerState.self, from: data)
        else { return }
        state = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: stateURL, options: .atomic)
    }
}

/// Shared date helpers. Transcript timestamps are UTC ISO 8601, with or without
/// fractional seconds depending on the tool.
enum DateParse {
    private static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func iso(_ s: String) -> Date? {
        fractional.date(from: s) ?? plain.date(from: s)
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    static func dayKey(for date: Date) -> String { dayFormatter.string(from: date) }
}

func intValue(_ any: Any?) -> Int { (any as? NSNumber)?.intValue ?? 0 }
