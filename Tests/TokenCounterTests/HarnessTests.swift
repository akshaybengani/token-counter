import Foundation
import XCTest
@testable import TokenCounter

/// Asserts the differential harness's verdict.
///
/// The harness itself lives in `tools/verify` and runs the providers against an
/// independent Python implementation of the same rules. It writes a machine-readable
/// verdict, and this test reads it, which keeps AC emission in one place instead of
/// giving the shell a second emitter to maintain.
///
/// When the verdict is missing or stale the test SKIPS rather than passes. That
/// matters: a skipped test is never tagged, so the acceptance criterion stays
/// untested rather than going falsely green off a verdict nobody produced.
final class HarnessTests: XCTestCase {

    private struct Verdict: Decodable {
        let ok: Bool
        let cutoff: String
        let providers_compared: [String]
        let comparisons: Int
        let failures: [Failure]

        struct Failure: Decodable {
            let provider: String
            let field: String
            let detail: String
        }
    }

    /// A verdict older than this describes a tree that has since moved on.
    private let freshness: TimeInterval = 6 * 60 * 60

    private var repositoryRoot: URL {
        var url = URL(fileURLWithPath: #filePath)
        while url.pathComponents.count > 1 {
            url = url.deletingLastPathComponent()
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("Package.swift").path) {
                return url
            }
        }
        return url
    }

    func testEveryProviderAgreesWithTheIndependentImplementation() throws {
        let path = repositoryRoot.appendingPathComponent(".build/verify-result.json")

        guard let data = try? Data(contentsOf: path) else {
            throw XCTSkip("no harness verdict at .build/verify-result.json. Run ./tools/verify/run.sh <cutoff> first.")
        }
        let modified = (try? FileManager.default.attributesOfItem(atPath: path.path)[.modificationDate] as? Date) ?? nil
        if let modified, Date().timeIntervalSince(modified) > freshness {
            throw XCTSkip("the harness verdict is stale (\(Int(Date().timeIntervalSince(modified) / 3600))h old). Re-run ./tools/verify/run.sh.")
        }

        let verdict = try JSONDecoder().decode(Verdict.self, from: data)

        // Only tagged once the verdict is real and fresh, so a skip cannot verify
        // these criteria by accident.
        tagAc("akshay/personal/specs/spec-26/acs/ac-21")
        tagAc("akshay/personal/specs/spec-26/acs/ac-6")

        XCTAssertFalse(verdict.providers_compared.isEmpty,
                       "the harness compared no providers, so agreement would be vacuous")
        XCTAssertGreaterThanOrEqual(verdict.comparisons, 12,
                                    "only \(verdict.comparisons) figures were compared, which is too few to mean much")

        for failure in verdict.failures {
            XCTFail("\(failure.provider).\(failure.field) disagrees: \(failure.detail)")
        }
        XCTAssertTrue(verdict.ok,
                      "the providers and the reference implementation disagree at cutoff \(verdict.cutoff)")
    }
}
