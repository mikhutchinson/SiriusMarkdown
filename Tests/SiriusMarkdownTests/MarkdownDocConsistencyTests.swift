import Foundation
import Testing

// MARK: - Helpers

private func packageRootURL(filePath: String = #filePath) -> URL {
    URL(fileURLWithPath: filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

private func readFile(_ relativePath: String) throws -> String {
    try String(
        contentsOf: packageRootURL().appending(path: relativePath),
        encoding: .utf8
    )
}

private func swiftSourceFiles(under root: URL) throws -> [URL] {
    guard let enumerator = FileManager.default.enumerator(
        at: root,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles]
    ) else {
        return []
    }
    var files: [URL] = []
    for case let url as URL in enumerator {
        let attrs = try url.resourceValues(forKeys: [.isRegularFileKey])
        if attrs.isRegularFile == true, url.pathExtension == "swift" {
            files.append(url)
        }
    }
    return files
}

private func docFiles(under root: URL) throws -> [URL] {
    let docsDir = root.appending(path: "Docs")
    guard let enumerator = FileManager.default.enumerator(
        at: docsDir,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles]
    ) else {
        return []
    }
    var files: [URL] = []
    for case let url as URL in enumerator {
        let attrs = try url.resourceValues(forKeys: [.isRegularFileKey])
        if attrs.isRegularFile == true, url.pathExtension == "md" {
            files.append(url)
        }
    }
    return files
}

// MARK: - Version consistency (INV-D1)

@Test
func readmeInstallVersionMatchesChangelogLatest() throws {
    let readme = try readFile("README.md")
    let changelog = try readFile("changelog.md")

    let changelogFirstVersion = changelog
        .components(separatedBy: .newlines)
        .first { $0.hasPrefix("## ") && !$0.hasPrefix("## Unreleased") }
        ?? ""
    let version = changelogFirstVersion
        .replacingOccurrences(of: "## ", with: "")
        .components(separatedBy: " - ")
        .first ?? ""

    #expect(!version.isEmpty, "Changelog should have a version entry")
    #expect(
        readme.contains(".package(url: \"https://github.com/mikhutchinson/SiriusMarkdown.git\", from: \"\(version)\")"),
        "README install version should match changelog latest (\(version))"
    )
}

@Test
func runbookReleaseTagMatchesChangelogLatest() throws {
    let runbook = try readFile("runbook.md")
    let changelog = try readFile("changelog.md")

    let changelogFirstVersion = changelog
        .components(separatedBy: .newlines)
        .first { $0.hasPrefix("## ") && !$0.hasPrefix("## Unreleased") }
        ?? ""
    let version = changelogFirstVersion
        .replacingOccurrences(of: "## ", with: "")
        .components(separatedBy: " - ")
        .first ?? ""

    #expect(!version.isEmpty, "Changelog should have a version entry")
    #expect(
        runbook.contains("use `\(version)` as the tag"),
        "Runbook release tag should match changelog latest (\(version))"
    )
    #expect(
        runbook.contains("git tag -a \(version) -m \"SiriusMarkdown \(version)\""),
        "Runbook git tag command should reference \(version)"
    )
}

// MARK: - No stale workaround language (INV-D2)

@Test
func readmeDoesNotContainBugSweepNarrative() throws {
    let readme = try readFile("README.md")
    #expect(!readme.contains("bug sweep"), "README should not reference bug-sweep narrative")
    #expect(!readme.contains("bug-sweep"), "README should not reference bug-sweep narrative")
}

@Test
func noStaleHangHistoryInCodeComments() throws {
    let root = packageRootURL()
    let sources = try swiftSourceFiles(under: root.appending(path: "Sources"))
    for file in sources {
        let content = try String(contentsOf: file, encoding: .utf8)
        #expect(
            !content.contains("Regression history"),
            "\(file.lastPathComponent) should not contain stale 'Regression history' comment"
        )
        #expect(
            !content.contains("peg the main thread"),
            "\(file.lastPathComponent) should not contain stale 'peg the main thread' comment"
        )
        #expect(
            !content.contains("host-update hangs"),
            "\(file.lastPathComponent) should not contain stale 'host-update hangs' comment"
        )
    }
}

@Test
func readmeDoesNotReferenceStaleBaselineHeuristic() throws {
    let readme = try readFile("README.md")
    #expect(!readme.contains("0.32"), "README should not reference the old 0.32 baseline heuristic")
}

@Test
func readmeDoesNotReferenceStaleFixedRasterizationScale() throws {
    let readme = try readFile("README.md")
    #expect(!readme.contains("fixed 3.0"), "README should not reference fixed 3.0 rasterization scale")
    #expect(!readme.contains("fixed 3x"), "README should not reference fixed 3x rasterization scale")
}

@Test
func noStaleConservativeDefaultInCodeComments() throws {
    let root = packageRootURL()
    let sources = try swiftSourceFiles(under: root.appending(path: "Sources"))
    for file in sources {
        let content = try String(contentsOf: file, encoding: .utf8)
        #expect(
            !content.contains("conservative public-package default"),
            "\(file.lastPathComponent) should not contain stale 'conservative public-package default' language"
        )
    }
}

// MARK: - AGENTS.md alignment (INV-D4)

@Test
func docsDoNotClaimWebKitRendering() throws {
    let root = packageRootURL()
    let readme = try readFile("README.md")
    #expect(!readme.contains("renders with WebKit"), "README should not claim WebKit rendering")
    #expect(!readme.contains("WebKit rendering"), "README should not claim WebKit rendering")

    let docs = try docFiles(under: root)
    for file in docs {
        let content = try String(contentsOf: file, encoding: .utf8)
        #expect(
            !content.contains("renders with WebKit"),
            "\(file.lastPathComponent) should not claim WebKit rendering"
        )
        #expect(
            !content.contains("uses WebKit rendering"),
            "\(file.lastPathComponent) should not claim WebKit rendering"
        )
    }
}

@Test
func docsDoNotClaimSwiftUIBodyDoesExpensiveWork() throws {
    let readme = try readFile("README.md")
    #expect(
        !readme.contains("SwiftUI body must parse Markdown"),
        "README should not claim SwiftUI body parses Markdown"
    )
    #expect(
        !readme.contains("body must parse Markdown"),
        "README should not claim body parses Markdown"
    )
}

@Test
func publicDocsDoNotLinkIgnoredInternalPlans() throws {
    let root = packageRootURL()
    let topLevelDocs = ["README.md", "runbook.md", "changelog.md", "bugfix.md"]
    for path in topLevelDocs {
        let content = try readFile(path)
        #expect(!content.contains("](.plan/"), "\(path) should not link ignored internal plans")
    }

    for file in try docFiles(under: root) {
        let content = try String(contentsOf: file, encoding: .utf8)
        #expect(
            !content.contains("](.plan/"),
            "\(file.lastPathComponent) should not link ignored internal plans"
        )
    }
}

@Test
func releaseRunbookPublishesMatchingGitHubRelease() throws {
    let runbook = try readFile("runbook.md")
    let changelog = try readFile("changelog.md")
    let latestHeading = try #require(changelog.components(separatedBy: .newlines).first {
        $0.hasPrefix("## ") && !$0.hasPrefix("## Unreleased")
    })
    let version = latestHeading
        .replacingOccurrences(of: "## ", with: "")
        .components(separatedBy: " - ")
        .first ?? ""

    #expect(runbook.contains("gh release create \(version)"))
    #expect(runbook.contains("gh release view \(version)"))
    #expect(runbook.contains("--verify-tag"))
    #expect(runbook.contains("--latest"))
}

// MARK: - Historical preservation (INV-D3)

@Test
func changelogHistoricalEntriesPreserved() throws {
    let changelog = try readFile("changelog.md")
    #expect(changelog.contains("## 0.5.12"), "Changelog should preserve 0.5.12 entry")
    #expect(changelog.contains("## 0.5.13"), "Changelog should preserve 0.5.13 entry")
    #expect(changelog.contains("## 0.5.14"), "Changelog should preserve 0.5.14 entry")
}

@Test
func bugfixLogHistoricalEntriesPreserved() throws {
    let bugfix = try readFile("bugfix.md")
    #expect(bugfix.contains("## Fixed"), "Bugfix log should preserve 'Fixed' section")
    #expect(bugfix.contains("## Resolved in 0.6.9"), "Bugfix log should record the current release")
    #expect(bugfix.contains("## Resolved in 0.6.8"), "Bugfix log should preserve the 0.6.8 entry")
    #expect(bugfix.contains("## Resolved in 0.6.7"), "Bugfix log should preserve the 0.6.7 entry")
    #expect(bugfix.contains("## Resolved in 0.6.6"), "Bugfix log should preserve the 0.6.6 entry")
    #expect(bugfix.contains("## Resolved in 0.6.0"), "Bugfix log should have 'Resolved in 0.6.0' section")
}

// MARK: - Release-check consistency

@Test
func releaseCheckTestFloorMatchesCurrentCount() throws {
    let releaseCheck = try readFile("Tools/release-check.sh")
    #expect(
        releaseCheck.contains("MINIMUM_TEST_COUNT=850"),
        "release-check.sh test floor should be 850"
    )
}

@Test
func releaseCheckBundleVersionMatchesChangelogLatest() throws {
    let releaseCheck = try readFile("Tools/release-check.sh")
    let changelog = try readFile("changelog.md")

    let changelogFirstVersion = changelog
        .components(separatedBy: .newlines)
        .first { $0.hasPrefix("## ") && !$0.hasPrefix("## Unreleased") }
        ?? ""
    let version = changelogFirstVersion
        .replacingOccurrences(of: "## ", with: "")
        .components(separatedBy: " - ")
        .first ?? ""

    #expect(
        releaseCheck.contains("--fallback-bundle-version \(version)"),
        "release-check.sh fallback bundle version should match changelog latest (\(version))"
    )
}
