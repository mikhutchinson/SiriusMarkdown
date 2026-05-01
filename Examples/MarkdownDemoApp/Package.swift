// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MarkdownDemoApp",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "MarkdownDemoApp",
            targets: ["MarkdownDemoApp"]
        )
    ],
    dependencies: [
        .package(path: "../..")
    ],
    targets: [
        .executableTarget(
            name: "MarkdownDemoApp",
            dependencies: [
                .product(name: "SiriusMarkdown", package: "SiriusMarkdown")
            ]
        )
    ]
)
