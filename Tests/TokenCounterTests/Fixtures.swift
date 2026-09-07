import Foundation
import XCTest

/// A throwaway directory tree, plus helpers for writing the transcript shapes the
/// providers read. Every test builds its own so nothing touches the real
/// ~/.claude, ~/.codex or ~/.gemini, and nothing shares scan state.
final class Fixture {
    let root: URL
    let dataDirectory: URL
    let stateDirectory: URL

    init(_ name: String = "fixture") {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("token-counter-tests")
            .appendingPathComponent("\(name)-\(UUID().uuidString)")
        dataDirectory = root.appendingPathComponent("data")
        stateDirectory = root.appendingPathComponent("state")
        for url in [dataDirectory, stateDirectory] {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    /// Writes `contents` to a path under the data directory, creating parents.
    @discardableResult
    func write(_ relativePath: String, _ contents: String) -> URL {
        let url = dataDirectory.appendingPathComponent(relativePath)
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? contents.data(using: .utf8)!.write(to: url)
        return url
    }

    /// Appends without rewriting, so byte-cursor behaviour is exercised honestly.
    func append(_ relativePath: String, _ contents: String) {
        let url = dataDirectory.appendingPathComponent(relativePath)
        guard let handle = try? FileHandle(forWritingTo: url) else {
            XCTFail("cannot append to \(relativePath)"); return
        }
        defer { try? handle.close() }
        try? handle.seekToEnd()
        try? handle.write(contentsOf: contents.data(using: .utf8)!)
    }

    func touch(_ relativePath: String, modified: Date) {
        let url = dataDirectory.appendingPathComponent(relativePath)
        try? FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
    }
}

// MARK: - Record builders

enum Rec {
    /// A Claude Code assistant turn carrying usage.
    static func claude(
        id: String,
        request: String,
        at timestamp: String,
        input: Int = 10,
        output: Int = 20,
        cacheWrite: Int = 30,
        cacheRead: Int = 40
    ) -> String {
        """
        {"type":"assistant","timestamp":"\(timestamp)","requestId":"\(request)","message":{"id":"\(id)","usage":{"input_tokens":\(input),"output_tokens":\(output),"cache_creation_input_tokens":\(cacheWrite),"cache_read_input_tokens":\(cacheRead)}}}
        """
    }

    /// A Codex token_count event. `total*` values are cumulative for the session.
    static func codex(
        at timestamp: String,
        totalInput: Int,
        totalCached: Int,
        totalOutput: Int
    ) -> String {
        """
        {"timestamp":"\(timestamp)","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":\(totalInput),"cached_input_tokens":\(totalCached),"output_tokens":\(totalOutput),"total_tokens":\(totalInput + totalOutput)}}}}
        """
    }

    /// A Gemini CLI session document.
    static func geminiSession(messages: [String]) -> String {
        """
        {"sessionId":"s1","projectHash":"p","startTime":"2026-09-07T00:00:00.000Z","messages":[\(messages.joined(separator: ","))]}
        """
    }

    static func geminiMessage(
        id: String,
        at timestamp: String,
        input: Int,
        cached: Int,
        output: Int,
        thoughts: Int,
        tool: Int
    ) -> String {
        """
        {"id":"\(id)","timestamp":"\(timestamp)","type":"gemini","tokens":{"input":\(input),"cached":\(cached),"output":\(output),"thoughts":\(thoughts),"tool":\(tool),"total":\(input + output + thoughts + tool)}}
        """
    }
}

// MARK: - Day helpers

enum TestDay {
    /// Local midnight for a date built from a UTC instant, mirroring how the app
    /// derives its own day boundary.
    static func start(_ date: Date) -> Date {
        Calendar.current.startOfDay(for: date)
    }

    static func key(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: date)
    }

    /// An ISO 8601 UTC stamp offset from a reference instant.
    static func iso(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        f.timeZone = TimeZone(identifier: "UTC")
        return f.string(from: date)
    }
}
