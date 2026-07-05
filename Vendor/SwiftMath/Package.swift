// swift-tools-version: 6.0
//
// Vendored SwiftMath (MIT, Copyright (c) 2023 Computer Inspirations / Mike
// Griebling; translated from an Objective-C implementation by Kostub Deshmukh).
// See `LICENSE` in this directory for full terms.
//
// This is a local in-tree fork. The upstream package's generated
// `Bundle.module` accessor (built from a `swift-tools-version: 5.7` manifest)
// only checks `Bundle.main.bundleURL`'s root and a build-time path, so it
// fatals in a signed macOS `.app` that ships `SwiftMath_SwiftMath.bundle`
// under `Contents/Resources` (the only layout codesign allows). The patched
// `MTFont.fontBundle` in this fork searches `Contents/Resources` via
// `Bundle.main.url(forResource:)` before falling back to `Bundle.module`,
// restoring native math glyphs in packaged apps without breaking the signed
// bundle layout.
//
// The package is pinned to Swift 5 language mode (`swiftLanguageVersions:
// [.v5]`) because upstream SwiftMath is not Swift 6 strict-concurrency clean
// (several non-Sendable mutable globals). This matches upstream behavior
// without rewriting its concurrency model.

import PackageDescription

let package = Package(
    name: "SwiftMath",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
        .visionOS(.v1)
    ],
    products: [
        .library(
            name: "SwiftMath",
            targets: ["SwiftMath"]
        )
    ],
    dependencies: [],
    targets: [
        .target(
            name: "SwiftMath",
            dependencies: [],
            resources: [
                .copy("mathFonts.bundle")
            ]
        )
    ],
    swiftLanguageVersions: [.v5]
)

