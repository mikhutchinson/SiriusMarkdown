// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SiriusMarkdown",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
        .tvOS(.v16),
        .watchOS(.v9),
        .visionOS(.v1)
    ],
    products: [
        .library(
            name: "SiriusMarkdown",
            targets: ["SiriusMarkdown"]
        ),
        .library(
            name: "SiriusMarkdownCore",
            targets: ["SiriusMarkdownCore"]
        ),
        .library(
            name: "SiriusMarkdownSwiftUI",
            targets: ["SiriusMarkdownSwiftUI"]
        ),
        .library(
            name: "SiriusMarkdownPretextSupport",
            targets: ["SiriusMarkdownPretextSupport"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-markdown.git", from: "0.7.3")
    ],
    targets: [
        .target(
            name: "SiriusMarkdown",
            dependencies: [
                "SiriusMarkdownCore",
                "SiriusMarkdownSwiftUI"
            ]
        ),
        .target(
            name: "SiriusMarkdownCore",
            dependencies: [
                .product(name: "Markdown", package: "swift-markdown")
            ]
        ),
        .target(
            name: "SiriusMarkdownSwiftUI",
            dependencies: ["SiriusMarkdownCore"]
        ),
        .target(
            name: "SiriusMarkdownPretextSupport",
            dependencies: ["SiriusMarkdownCore"],
            resources: [
                .process("Fixtures")
            ]
        ),
        .testTarget(
            name: "SiriusMarkdownTests",
            dependencies: ["SiriusMarkdown"]
        ),
        .testTarget(
            name: "SiriusMarkdownCoreTests",
            dependencies: ["SiriusMarkdownCore"]
        ),
        .testTarget(
            name: "SiriusMarkdownSwiftUITests",
            dependencies: ["SiriusMarkdownSwiftUI"]
        ),
        .testTarget(
            name: "SiriusMarkdownPretextSupportTests",
            dependencies: ["SiriusMarkdownPretextSupport"]
        )
    ]
)
