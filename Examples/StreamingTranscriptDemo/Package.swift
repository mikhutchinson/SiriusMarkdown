// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "StreamingTranscriptDemo",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "StreamingTranscriptDemo",
            targets: ["StreamingTranscriptDemo"]
        )
    ],
    dependencies: [
        .package(path: "../.."),
        .package(path: "../DemoSupport")
    ],
    targets: [
        .executableTarget(
            name: "StreamingTranscriptDemo",
            dependencies: [
                .product(name: "SiriusMarkdown", package: "SiriusMarkdown"),
                .product(name: "SiriusMarkdownMath", package: "SiriusMarkdown"),
                .product(name: "DemoSupport", package: "DemoSupport")
            ]
        )
    ]
)
