// swift-tools-version: 6.1
import PackageDescription

// The production asynchronous operation, without media binaries or networking.
let package = Package(
    name: "SubtitleSelectionSupport", platforms: [.macOS("15.0")],
    targets: [
        .target(name: "SubtitleSelectionSupport"),
        .testTarget(name: "SubtitleSelectionSupportTests", dependencies: ["SubtitleSelectionSupport"]),
    ], swiftLanguageModes: [.v6])
