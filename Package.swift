// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Linkway",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "LinkwayCore", targets: ["LinkwayCore"]),
        .executable(name: "Linkway", targets: ["Linkway"]),
    ],
    targets: [
        .target(name: "LinkwayCore"),
        .executableTarget(name: "Linkway", dependencies: ["LinkwayCore"]),
        .testTarget(name: "LinkwayCoreTests", dependencies: ["LinkwayCore"]),
        .testTarget(name: "LinkwayTests", dependencies: ["Linkway"]),
    ],
    swiftLanguageModes: [.v6]
)
