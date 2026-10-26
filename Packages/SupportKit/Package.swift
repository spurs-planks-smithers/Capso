// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SupportKit",
    platforms: [.macOS(.v15)],
    products: [.library(name: "SupportKit", targets: ["SupportKit"])],
    dependencies: [.package(path: "../FeedbackKit")],
    targets: [
        .target(name: "SupportKit", dependencies: ["FeedbackKit"]),
        .testTarget(name: "SupportKitTests", dependencies: ["SupportKit", "FeedbackKit"]),
    ]
)
