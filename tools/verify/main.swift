import Foundation

// Cross-checks the real provider implementations against the Python reference by
// scanning from an arbitrary cutoff instead of local midnight.
let iso = ISO8601DateFormatter()
iso.formatOptions = [.withFullDate]
iso.timeZone = TimeZone.current
guard let cutoff = iso.date(from: CommandLine.arguments[1]) else {
    print("bad date"); exit(1)
}
let key = "verify-" + CommandLine.arguments[1]
print("cutoff:", cutoff)

let providers: [any UsageProvider] = [ClaudeProvider(), CodexProvider(), CursorProvider()]
for p in providers {
    p.reset()
    let snap = p.scan(dayStart: cutoff, dayKey: key)
    let c = snap.counts
    print("\(p.id.rawValue.uppercased())  input=\(c.input) output=\(c.output) cacheWrite=\(c.cacheWrite) cacheRead=\(c.cacheRead) calls=\(c.calls)")
}
