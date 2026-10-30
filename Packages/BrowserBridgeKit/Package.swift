// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BrowserBridgeKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "BrowserBridgeKit", targets: ["BrowserBridgeKit"]),
        .executable(name: "NextshotBrowserHost", targets: ["NextshotBrowserHost"]),
    ],
    dependencies: [.package(path: "../FeedbackKit")],
    targets: [
        .target(name: "BrowserBridgeKit", dependencies: ["FeedbackKit"]),
        .executableTarget(name: "NextshotBrowserHost", dependencies: ["BrowserBridgeKit"]),
    ]
)
