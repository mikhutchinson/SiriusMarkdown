import Foundation

enum MarkdownJavaScriptResourceLookup {
    private final class BundleToken: NSObject {}

    static func script(named name: String, subdirectory: String) -> String? {
        guard let url = resourceURL(named: name, extension: "js", subdirectory: subdirectory) else {
            return nil
        }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    private static func resourceURL(
        named name: String,
        extension pathExtension: String,
        subdirectory: String?
    ) -> URL? {
        for bundle in candidateBundles() {
            if let url = bundle.url(
                forResource: name,
                withExtension: pathExtension,
                subdirectory: subdirectory
            ) {
                return url
            }
            if let url = bundle.url(forResource: name, withExtension: pathExtension) {
                return url
            }
        }

        let filename = "\(name).\(pathExtension)"
        for directory in candidateResourceDirectories() {
            for url in candidateFileURLs(
                filename: filename,
                subdirectory: subdirectory,
                resourceDirectory: directory
            ) where FileManager.default.isReadableFile(atPath: url.path) {
                return url
            }
        }
        return nil
    }

    private static func candidateBundles() -> [Bundle] {
        var bundles: [Bundle] = []
        var seen = Set<URL>()

        func append(_ bundle: Bundle?) {
            guard let bundle else { return }
            let url = bundle.bundleURL.standardizedFileURL
            guard seen.insert(url).inserted else { return }
            bundles.append(bundle)
        }

        append(Bundle(for: BundleToken.self))

        for bundle in Bundle.allBundles {
            append(bundle)
        }
        for bundle in Bundle.allFrameworks {
            append(bundle)
        }
        append(.main)

        for directory in candidateResourceDirectories() {
            for bundleName in resourceBundleNames {
                append(Bundle(url: directory.appendingPathComponent("\(bundleName).bundle")))
            }
        }

        return bundles
    }

    private static func candidateResourceDirectories() -> [URL] {
        var directories: [URL] = []
        var seen = Set<URL>()

        func append(_ url: URL?) {
            guard let url else { return }
            let standardized = url.standardizedFileURL
            guard seen.insert(standardized).inserted else { return }
            directories.append(standardized)
        }

        let tokenBundle = Bundle(for: BundleToken.self)
        append(tokenBundle.resourceURL)
        append(tokenBundle.bundleURL.deletingLastPathComponent())

        for bundle in Bundle.allBundles + Bundle.allFrameworks {
            append(bundle.resourceURL)
            append(bundle.bundleURL)
            append(bundle.bundleURL.deletingLastPathComponent())
        }
        append(Bundle.main.resourceURL)
        append(Bundle.main.bundleURL.appendingPathComponent("Contents/Resources"))

        return directories
    }

    private static func candidateFileURLs(
        filename: String,
        subdirectory: String?,
        resourceDirectory: URL
    ) -> [URL] {
        var urls: [URL] = []

        func append(_ directory: URL) {
            if let subdirectory {
                urls.append(directory.appendingPathComponent(subdirectory).appendingPathComponent(filename))
            }
            urls.append(directory.appendingPathComponent(filename))
        }

        append(resourceDirectory)
        for bundleName in resourceBundleNames {
            append(resourceDirectory.appendingPathComponent("\(bundleName).bundle"))
        }
        return urls
    }

    private static let resourceBundleNames = [
        "SiriusMarkdown_SiriusMarkdownSwiftUI",
        "SiriusMarkdownSwiftUI_SiriusMarkdownSwiftUI"
    ]
}
