// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ResearchPaperReader",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "ResearchPaperReader", targets: ["ResearchPaperReader"])
    ],
    targets: [
        .executableTarget(
            name: "ResearchPaperReader",
            path: "Sources/ResearchPaperReader"
        ),
        .testTarget(
            name: "ResearchPaperReaderTests",
            dependencies: ["ResearchPaperReader"]
        )
    ]
)
