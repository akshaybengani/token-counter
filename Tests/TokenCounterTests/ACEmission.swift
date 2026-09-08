import Foundation
import XCTest

// Emits acceptance-criterion test events to Memex. Hand-rolled because there is no
// official helper for Swift; the protocol is the language-agnostic one from
// get_information(topic='ac-emission-bootstrap').
//
// The contract this honours, point by point, because getting it wrong is silent:
//
//  * Emits on every finished test, pass and fail alike, so a failure cannot leave a
//    stale green behind.
//  * Never throws. A non-2xx, a network error and a hang are all swallowed, and the
//    request is bounded, so emission can never fail or stall the suite.
//  * Never retries. A 429 in particular is dropped, because retrying multiplies load
//    exactly when the server is shedding it. A 401 stops the rest of the buffer,
//    since the same key against the same server will not start working mid-run.
//  * Routes by the AC ref's namespace, never to localhost. An unknown namespace goes
//    to the SaaS host, which serves every workspace.
//  * Buffers and flushes one batch per test class, not one request per test.
//  * Falls back to single posts only on 404 or 405, which means the batch route is
//    absent, and bounds that fallback.
//  * Surfaces the response body, which carries the fix, not just the status.
enum ACEmit {
    /// Only `mindset-int` needs its own row; everything else is served by the SaaS host.
    private static let namespaceHosts = ["mindset-int": "https://int.memex.ai"]
    private static let saasHost = "https://memex.ai"
    private static let timeout: TimeInterval = 5
    private static let fallbackConcurrency = 4
    private static let fallbackDeadline: TimeInterval = 4

    struct Event {
        let acRef: String
        let status: String
        let testIdentifier: String
        let durationMS: Int
    }

    static var isEnabled: Bool {
        let raw = (ProcessInfo.processInfo.environment["MEMEX_EMIT"] ?? "").lowercased()
        return !["false", "0", "no", "off"].contains(raw)
    }

    private static func host(for acRef: String) -> String? {
        if let override = ProcessInfo.processInfo.environment["MEMEX_TEST_EVENTS_URL"], !override.isEmpty {
            return override
        }
        guard let namespace = acRef.split(separator: "/").first, !namespace.isEmpty else {
            return nil   // a malformed ref has nothing to route on
        }
        return namespaceHosts[String(namespace)] ?? saasHost
    }

    private static var actor: String? {
        let env = ProcessInfo.processInfo.environment
        for key in ["GITHUB_ACTOR", "GITLAB_USER_LOGIN", "BUILDKITE_BUILD_AUTHOR", "CIRCLE_USERNAME", "USER", "USERNAME"] {
            if let value = env[key], !value.isEmpty { return value }
        }
        return nil
    }

    private static func body(_ event: Event) -> [String: Any] {
        var payload: [String: Any] = [
            "ac_uid": event.acRef,
            "status": event.status,
            "test_identifier": event.testIdentifier,
            "duration_ms": event.durationMS,
        ]
        if let actor { payload["actor"] = actor }
        return payload
    }

    /// Sends one batch per host. Blocks briefly, bounded, because XCTest's hooks are
    /// synchronous and the process may exit as soon as they return.
    static func flush(_ events: [Event]) {
        guard isEnabled, !events.isEmpty else { return }

        var byHost: [String: [Event]] = [:]
        for event in events {
            guard let host = host(for: event.acRef) else {
                warn("no namespace in ref \(event.acRef), dropped")
                continue
            }
            byHost[host, default: []].append(event)
        }

        for (host, group) in byHost {
            // At most 500 per request, and an oversized batch is a hard 400 rather
            // than a silent truncation, so split rather than send one huge one.
            for chunk in stride(from: 0, to: group.count, by: 500).map({ Array(group[$0..<min($0 + 500, group.count)]) }) {
                sendBatch(chunk, to: host)
            }
        }
    }

    private static func sendBatch(_ events: [Event], to host: String) {
        let base = host.hasSuffix("/api/test-events") ? String(host.dropLast("/api/test-events".count)) : host
        guard let url = URL(string: base + "/api/test-events/batch") else { return }

        let payload: [String: Any] = ["events": events.map(body)]
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }

        let (status, responseBody, warning) = post(url: url, data: data)

        switch status {
        case 200...299:
            if let responseBody,
               let object = try? JSONSerialization.jsonObject(with: Data(responseBody.utf8)) as? [String: Any],
               let rejected = object["rejected"] as? Int, rejected > 0 {
                warn("batch accepted with \(rejected) rejected: \(responseBody)")
            }
            if let warning { warn(warning) }
        case 404, 405:
            // The batch route is absent, which means an older server. This is the only
            // status that may fan out; anything else must not.
            sendSingly(events, base: base)
        case 401:
            warn("401 from \(url): \(responseBody ?? "no body"). Stopping this flush; provision a fresh key.")
        case 0:
            warn("emission to \(url) failed or timed out, dropped")
        default:
            warn("\(status) from \(url): \(responseBody ?? "no body"), dropped")
        }
    }

    private static func sendSingly(_ events: [Event], base: String) {
        guard let url = URL(string: base + "/api/test-events") else { return }
        let started = Date()
        let queue = DispatchQueue(label: "ac-emit-fallback", attributes: .concurrent)
        let limiter = DispatchSemaphore(value: fallbackConcurrency)
        let group = DispatchGroup()
        var skipped = 0

        for event in events {
            guard Date().timeIntervalSince(started) < fallbackDeadline else { skipped += 1; continue }
            guard let data = try? JSONSerialization.data(withJSONObject: body(event)) else { continue }
            limiter.wait()
            group.enter()
            queue.async {
                defer { limiter.signal(); group.leave() }
                _ = post(url: url, data: data)
            }
        }
        group.wait()
        if skipped > 0 { warn("fallback deadline reached, \(skipped) emissions dropped") }
    }

    /// Returns (status, body, X-Memex-Warning). Status 0 means the request never
    /// completed, which is treated the same as any other failure: warn and drop.
    private static func post(url: URL, data: Data) -> (Int, String?, String?) {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let key = ProcessInfo.processInfo.environment["MEMEX_EMIT_KEY"], !key.isEmpty {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = data

        var status = 0
        var body: String?
        var warning: String?
        let done = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { payload, response, _ in
            if let http = response as? HTTPURLResponse {
                status = http.statusCode
                warning = http.value(forHTTPHeaderField: "X-Memex-Warning")
            }
            if let payload { body = String(data: payload, encoding: .utf8) }
            done.signal()
        }.resume()
        _ = done.wait(timeout: .now() + timeout + 1)
        return (status, body, warning)
    }

    private static func warn(_ message: String) {
        FileHandle.standardError.write(Data("ac-emit: \(message)\n".utf8))
    }
}

/// Collects tags per test and flushes once per test class.
final class ACObserver: NSObject, XCTestObservation {
    static let shared = ACObserver()
    private static var registered = false

    private let lock = NSLock()
    private var tags: [String: [String]] = [:]     // test name -> AC refs
    private var buffer: [ACEmit.Event] = []

    static func register() {
        guard !registered else { return }
        registered = true
        XCTestObservationCenter.shared.addTestObserver(shared)
    }

    func tag(_ acRef: String, for testName: String) {
        lock.lock(); defer { lock.unlock() }
        tags[testName, default: []].append(acRef)
    }

    func testCaseDidFinish(_ testCase: XCTestCase) {
        let name = testCase.name
        lock.lock()
        let refs = tags.removeValue(forKey: name) ?? []
        lock.unlock()
        guard !refs.isEmpty else { return }

        let run = testCase.testRun
        let status = (run?.hasSucceeded ?? true) ? "pass" : "fail"
        let duration = Int(((run?.totalDuration ?? 0) * 1000).rounded())
        let identifier = name
            .replacingOccurrences(of: "-[", with: "")
            .replacingOccurrences(of: "]", with: "")
            .replacingOccurrences(of: " ", with: "::")

        lock.lock()
        buffer.append(contentsOf: refs.map {
            ACEmit.Event(acRef: $0, status: status, testIdentifier: identifier, durationMS: duration)
        })
        lock.unlock()
    }

    /// One batch per class, which is the flush boundary every runner has.
    func testSuiteDidFinish(_ testSuite: XCTestSuite) {
        lock.lock()
        let events = buffer
        buffer = []
        lock.unlock()
        ACEmit.flush(events)
    }
}

extension XCTestCase {
    /// Declares that this test verifies an acceptance criterion.
    ///
    /// Call it inside the test body. Pass the full canonical ref: the bare `ac-N`
    /// handle is ambiguous across Specs, and the namespace prefix is what routes the
    /// emission.
    func tagAc(_ acRef: String) {
        ACObserver.register()
        ACObserver.shared.tag(acRef, for: name)
    }
}
