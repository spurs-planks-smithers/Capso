// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "StartupKit",
    platforms: [.macOS(.v15)],
    products: [.library(name: "StartupKit", targets: ["StartupKit"])],
    targets: [.target(name: "StartupKit")]
)
