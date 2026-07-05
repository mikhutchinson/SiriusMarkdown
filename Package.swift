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
        ),
        .library(
            name: "SiriusMarkdownMath",
            targets: ["SiriusMarkdownMath"]
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
            dependencies: ["SiriusMarkdownCore"],
            resources: [
                .process("Resources")
            ]
        ),
        .target(
            name: "SiriusMarkdownPretextSupport",
            dependencies: ["SiriusMarkdownCore"],
            resources: [
                .process("Fixtures")
            ]
        ),
        // Vendored SwiftMath (MIT; see `Sources/SwiftMath/LICENSE` and
        // `NOTICE.md`). Inlined as a target rather than a `.package(path:)`
        // sub-package so a stable-version requirement on SiriusMarkdown does
        // not transitively depend on an unversioned (unstable) package, which
        // SwiftPM's resolver rejects. Compiled under Swift 5 language mode
        // because upstream SwiftMath is not Swift 6 strict-concurrency clean
        // (non-Sendable mutable globals). Linked only into SiriusMarkdownMath
        // on iOS/macOS/visionOS via the conditional dependency below.
        .target(
            name: "SwiftMath",
            dependencies: [],
            resources: [
                .copy("mathFonts.bundle")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
        .target(
            name: "SiriusMarkdownMath",
            dependencies: [
                "SiriusMarkdownSwiftUI",
                .target(
                    name: "SwiftMath",
                    condition: .when(platforms: [.iOS, .macOS, .visionOS])
                )
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
        ),
        .testTarget(
            name: "SiriusMarkdownMathTests",
            dependencies: [
                "SiriusMarkdownMath",
                "SiriusMarkdownSwiftUI",
                "SiriusMarkdownCore"
            ]
        )
    ]
)
