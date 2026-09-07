import Foundation

/// Reads Claude Code transcripts in `~/.claude/projects/**/*.jsonl`.
///
/// Every assistant turn carries a `message.usage` object with four figures. Records
/// repeat across transcripts, because a resumed session and a sub-agent sidechain both
/// re-log turns, so each is deduped on `message.id` plus `requestId`.
final class ClaudeProvider: UsageProvider {
    let id = ProviderID.claude
    var sourceDescription: String { "~/.claude/projects/**/*.jsonl" }

    private let ledger: JSONLLedger

    /// `root` and `stateDirectory` default to the real locations; tests pass fixtures.
    init(root: URL? = nil, stateDirectory: URL? = nil) {
        let root = root ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude/projects")
        ledger = JSONLLedger(root: root, stateName: "claude-state", needle: "\"usage\"", stateDirectory: stateDirectory) { line, dayStart, _, state in
            guard let obj = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  let message = obj["message"] as? [String: Any],
                  let usage = message["usage"] as? [String: Any]
            else { return }

            let key = (message["id"] as? String ?? "") + "|" + (obj["requestId"] as? String ?? "")
            let hasKey = key != "|"
            if hasKey && state.seen.contains(key) { return }

            guard let ts = obj["timestamp"] as? String,
                  let date = DateParse.iso(ts),
                  date >= dayStart
            else { return }

            if hasKey { state.seen.insert(key) }

            state.counts.input      += intValue(usage["input_tokens"])
            state.counts.output     += intValue(usage["output_tokens"])
            state.counts.cacheWrite += intValue(usage["cache_creation_input_tokens"])
            state.counts.cacheRead  += intValue(usage["cache_read_input_tokens"])
            state.counts.calls      += 1
        }
    }

    func scan(dayStart: Date, dayKey: String) -> ProviderSnapshot {
        guard ledger.rootExists else { return .absent(id) }
        let counts = ledger.scan(dayStart: dayStart, dayKey: dayKey)
        return ProviderSnapshot(id: id, counts: counts, quality: .measured, installed: true)
    }

    func reset() { ledger.reset() }
}
