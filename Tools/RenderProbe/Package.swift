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
        // Keep the dependency identity stable in isolated worktrees whose
        // directory basename is not literally `SiriusMarkdown`.
        .package(name: "SiriusMarkdown", path: "../..")
    ],
    targets: [
        .executableTarget(
            name: "SiriusMarkdownRenderProbe",
            dependencies: [
                .product(name: "SiriusMarkdown", package: "SiriusMarkdown"),
                .product(name: "SiriusMarkdownMath", package: "SiriusMarkdown")
            ]
        )
    ]
)
