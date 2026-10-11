// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "EventHorizon",
    platforms: [.macOS(.v14)],
    targets: [.executableTarget(name: "EventHorizon", path: "Sources")]
)
