import Foundation
import XCTest
@testable import TokenCounter

/// Checks the README's privacy claims against the repository, so they cannot rot into
/// marketing. These read the source tree rather than the running app, which is the
/// right shape: the claim is about what the shipped code contains.
final class ClaimTests: XCTestCase {

    /// Walks up from this file to the package root.
    private var repositoryRoot: URL {
        var url = URL(fileURLWithPath: #filePath)
        while url.pathComponents.count > 1 {
            url = url.deletingLastPathComponent()
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("Package.swift").path) {
                return url
            }
        }
        XCTFail("cannot find the package root from \(#filePath)")
        return url
    }

    private func swiftFiles(under directory: URL) -> [URL] {
        guard let walker = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) else {
            return []
        }
        return walker.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }

    /// The app target contains no networking. The test target deliberately does, for
    /// AC emission, and never ships inside the app, so the check is scoped to Sources.
    func testTheAppTargetContainsNoNetworking() throws {
        tagAc("akshay/personal/specs/spec-26/acs/ac-5")

        let sources = swiftFiles(under: repositoryRoot.appendingPathComponent("Sources"))
        XCTAssertFalse(sources.isEmpty, "found no sources to check, so this would pass vacuously")

        let banned = ["URLSession", "import Network", "NSURLConnection", "CFSocket", "URLRequest"]
        for file in sources {
            let text = try String(contentsOf: file, encoding: .utf8)
            for needle in banned {
                XCTAssertFalse(
                    text.contains(needle),
                    "\(file.lastPathComponent) contains \(needle): the app is supposed to make no network calls"
                )
            }
        }
    }

    /// No message content is read: only token counts and timestamps.
    func testTheAppReadsNoMessageContent() throws {
        tagAc("akshay/personal/specs/spec-26/acs/ac-5")

        let providers = swiftFiles(under: repositoryRoot.appendingPathComponent("Sources/TokenCounter/Providers"))
        XCTAssertFalse(providers.isEmpty, "found no provider sources, so this would pass vacuously")

        // Keys that would mean reading what was actually said.
        let contentKeys = ["\"content\"", "\"text\"", "\"richText\"", "\"user_message\"", "\"assistant_response\""]
        for file in providers {
            let text = try String(contentsOf: file, encoding: .utf8)
            for key in contentKeys {
                XCTAssertFalse(text.contains(key),
                               "\(file.lastPathComponent) reads \(key), which is message content")
            }
        }
    }

    /// Zero third-party dependencies, which is part of what makes the privacy claims
    /// checkable at a glance.
    func testThePackageDeclaresNoDependencies() throws {
        tagAc("akshay/personal/specs/spec-26/acs/ac-5")

        let manifest = try String(contentsOf: repositoryRoot.appendingPathComponent("Package.swift"), encoding: .utf8)
        XCTAssertTrue(manifest.contains("targets:"), "read the wrong file")
        XCTAssertFalse(manifest.contains(".package("), "a third-party dependency was added")
    }
}
