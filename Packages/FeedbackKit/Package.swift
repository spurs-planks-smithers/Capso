// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "FeedbackKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "FeedbackKit", targets: ["FeedbackKit"]),
    ],
    targets: [
        .target(
            name: "FeedbackKit",
            dependencies: []
        ),
        .testTarget(
            name: "FeedbackKitTests",
            dependencies: ["FeedbackKit"]
        ),
    ]
)
