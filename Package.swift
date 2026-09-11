// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "SimChoreographer", platforms: [.macOS(.v13)], products: [
    .executable(name: "SimChoreographer", targets: ["Tapper"]),
    .executable(name: "simchoreographerctl", targets: ["tapperctl"]),
    .executable(name: "tapperctl", targets: ["tapperctl"])
], targets: [
    .target(name: "TapperCore"),
    .executableTarget(name: "Tapper", dependencies: ["TapperCore"]),
    .executableTarget(name: "tapperctl", dependencies: ["TapperCore"]),
    .testTarget(name: "TapperCoreTests", dependencies: ["TapperCore", "Tapper"])
])
