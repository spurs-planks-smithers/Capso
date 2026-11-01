// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "FeedbackKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "FeedbackKit", targets: ["FeedbackKit"]),
        .executable(name: "nextshot-prompt", targets: ["NextshotPromptCLI"]),
    ],
    targets: [
        .target(
            name: "FeedbackKit",
            dependencies: []
        ),
        .executableTarget(
            name: "NextshotPromptCLI",
            dependencies: ["FeedbackKit"]
        ),
        .testTarget(
            name: "FeedbackKitTests",
            dependencies: ["FeedbackKit"]
        ),
    ]
)
