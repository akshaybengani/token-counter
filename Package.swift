// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TokenCounter",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "TokenCounter",
            path: "Sources/TokenCounter"
        ),
        // Tests cover the provider rules, which is where a wrong answer looks
        // plausible rather than broken. The interface is checked separately, by
        // rendering it (see tools/verify and the QA report on spec-26).
        .testTarget(
            name: "TokenCounterTests",
            dependencies: ["TokenCounter"],
            path: "Tests/TokenCounterTests"
        ),
    ]
)
