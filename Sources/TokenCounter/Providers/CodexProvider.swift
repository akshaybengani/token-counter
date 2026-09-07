import Foundation

/// Reads Codex rollouts in `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`.
///
/// Codex logs a `token_count` event carrying `total_token_usage`, which is cumulative
/// for the session, and `last_token_usage`, the most recent turn. It emits the same
/// pair twice per turn, so `last_token_usage` cannot be summed. Instead this tracks the
/// cumulative figure per session file and banks each increase, which is immune to the
/// repeats and to a scan landing mid-session.
///
/// `input_tokens` here is inclusive of `cached_input_tokens`, so the cached part is
/// split out to line up with the cache-read figure the other providers report.
final class CodexProvider: UsageProvider {
    let id = ProviderID.codex
    var sourceDescription: String { "~/.codex/sessions/**/rollout-*.jsonl" }

    private let ledger: JSONLLedger

    init() {
        let root = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".codex/sessions")
        ledger = JSONLLedger(root: root, stateName: "codex-state", needle: "\"token_count\"") { line, dayStart, path, state in
            guard let obj = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  let payload = obj["payload"] as? [String: Any],
                  payload["type"] as? String == "token_count",
                  let info = payload["info"] as? [String: Any],
                  let total = info["total_token_usage"] as? [String: Any]
            else { return }

            let cumulative = [
                intValue(total["input_tokens"]),
                intValue(total["cached_input_tokens"]),
                intValue(total["output_tokens"]),
            ]

            let previous = state.runningTotals[path] ?? [0, 0, 0]
            // Cumulative figures only ever rise. A drop means the file was replaced,
            // so treat the new reading as the baseline rather than banking a negative.
            guard zip(cumulative, previous).allSatisfy({ $0 >= $1 }) else {
                state.runningTotals[path] = cumulative
                return
            }

            let delta = zip(cumulative, previous).map(-)
            state.runningTotals[path] = cumulative
            guard delta.contains(where: { $0 > 0 }) else { return }

            // Deltas are always tracked so the baseline stays right, but only today's
            // turns are banked. That keeps a session started yesterday from dumping its
            // whole history into today on the first scan.
            guard let ts = obj["timestamp"] as? String,
                  let date = DateParse.iso(ts),
                  date >= dayStart
            else { return }

            let cachedInput = delta[1]
            state.counts.input     += max(0, delta[0] - cachedInput)
            state.counts.cacheRead += cachedInput
            state.counts.output    += delta[2]
            state.counts.calls     += 1
        }
    }

    func scan(dayStart: Date, dayKey: String) -> ProviderSnapshot {
        guard ledger.rootExists else { return .absent(id) }
        let counts = ledger.scan(dayStart: dayStart, dayKey: dayKey)
        return ProviderSnapshot(id: id, counts: counts, quality: .measured, installed: true)
    }

    func reset() { ledger.reset() }
}
