// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "HomewardCore",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .library(
            name: "HomewardCore",
            targets: ["HomewardCore"]
        ),
    ],
    targets: [
        .target(
            name: "HomewardCore"
        ),
        .testTarget(
            name: "HomewardCoreTests",
            dependencies: ["HomewardCore"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
