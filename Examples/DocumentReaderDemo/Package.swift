// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "DocumentReaderDemo",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "DocumentReaderDemo",
            targets: ["DocumentReaderDemo"]
        )
    ],
    dependencies: [
        .package(path: "../.."),
        .package(path: "../DemoSupport")
    ],
    targets: [
        .executableTarget(
            name: "DocumentReaderDemo",
            dependencies: [
                .product(name: "SiriusMarkdown", package: "SiriusMarkdown"),
                .product(name: "SiriusMarkdownMath", package: "SiriusMarkdown"),
                .product(name: "DemoSupport", package: "DemoSupport")
            ]
        )
    ]
)
