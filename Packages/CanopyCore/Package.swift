// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CanopyCore",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "CanopyCore", targets: ["CanopyCore"])
    ],
    targets: [
        .target(name: "CanopyCore"),
        .testTarget(name: "CanopyCoreTests", dependencies: ["CanopyCore"])
    ]
)

