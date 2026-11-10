// swift-tools-version: 5.9
import PackageDescription

// The production asynchronous operation, without media binaries or networking.
let package = Package(
    name: "SubtitleSelectionSupport", platforms: [.macOS("15.0")],
    targets: [
        .target(name: "SubtitleSelectionSupport"),
        .testTarget(name: "SubtitleSelectionSupportTests", dependencies: ["SubtitleSelectionSupport"]),
    ])
