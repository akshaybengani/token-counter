// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TokenCounter",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "TokenCounter",
            path: "Sources/TokenCounter"
        )
    ]
)
