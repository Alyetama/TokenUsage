// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TokenUsage",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "TokenUsage",
            path: "Sources/TokenUsage",
            linkerSettings: [
                // Read the local coding-agent SQLite stores (opencode, MiniMax).
                .linkedLibrary("sqlite3")
            ]
        )
    ],
    // Build with the Swift 6 toolchain but in the Swift 5 language mode so the
    // AppKit / background-scanning code stays free of strict-concurrency noise.
    swiftLanguageModes: [.v5]
)
