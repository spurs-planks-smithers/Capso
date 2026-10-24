// swift-tools-version: 6.0

import PackageDescription

// Fork: the only package that makes outbound requests, and only to
// api.typesafe.ai. See docs/superpowers/specs/2026-10-24-jev-base-design.md.
let package = Package(
    name: "JevKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "JevKit", targets: ["JevKit"]),
    ],
    dependencies: [
        .package(path: "../FeedbackKit"),
    ],
    targets: [
        .target(
            name: "JevKit",
            dependencies: ["FeedbackKit"]
        ),
        .testTarget(
            name: "JevKitTests",
            dependencies: ["JevKit", "FeedbackKit"]
        ),
    ]
)
