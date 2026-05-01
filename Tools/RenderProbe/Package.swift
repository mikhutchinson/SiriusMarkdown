// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SiriusMarkdownRenderProbe",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "SiriusMarkdownRenderProbe",
            targets: ["SiriusMarkdownRenderProbe"]
        )
    ],
    dependencies: [
        .package(path: "../..")
    ],
    targets: [
        .executableTarget(
            name: "SiriusMarkdownRenderProbe",
            dependencies: [
                .product(name: "SiriusMarkdown", package: "SiriusMarkdown")
            ]
        )
    ]
)
