// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Linkway",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "LinkwayCore", targets: ["LinkwayCore"]),
    ],
    targets: [
        .target(name: "LinkwayCore"),
        .testTarget(name: "LinkwayCoreTests", dependencies: ["LinkwayCore"]),
    ],
    swiftLanguageModes: [.v6]
)
