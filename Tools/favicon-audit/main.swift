import Foundation
import SiriusMarkdownCore

private struct AuditInput: Sendable {
    var rank: Int
    var domain: String
}

private struct AuditResult: Codable, Sendable {
    var rank: Int
    var domain: String
    var outcome: String
    var iconURL: String?
    var mimeType: String?
    var byteCount: Int?
    var pixelWidth: Int?
    var pixelHeight: Int?
    var elapsedMilliseconds: Int
    var failures: [String]?
}

private struct AuditReport: Codable {
    var generatedAt: Date
    var sourcePath: String
    var total: Int
    var faviconCount: Int
    var genericFallbackCount: Int
    var results: [AuditResult]
}

private actor AuditProgress {
    private var completed = 0
    private var faviconCount = 0
    private let total: Int

    init(total: Int) {
        self.total = total
    }

    func record(_ result: AuditResult) {
        completed += 1
        if result.outcome == "favicon" { faviconCount += 1 }
        if completed.isMultiple(of: 10) || completed == total {
            print("audited \(completed)/\(total), favicons \(faviconCount), safe glyph fallbacks \(completed - faviconCount)")
        }
    }
}

@main
private struct SiriusMarkdownFaviconAudit {
    static func main() async throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments.contains("--help") || arguments.contains("-h") {
            print(usage)
            return
        }
        guard let inputPath = value(after: "--input", in: arguments) else {
            throw AuditError.usage(usage)
        }
        let reportPath = value(after: "--report", in: arguments)
        let concurrency = max(1, Int(value(after: "--concurrency", in: arguments) ?? "16") ?? 16)
        let limit = max(1, Int(value(after: "--limit", in: arguments) ?? "250") ?? 250)
        let inputs = try loadInputs(path: inputPath, limit: limit)
        guard !inputs.isEmpty else { throw AuditError.emptyInput }

        let resolver = DefaultMarkdownLinkMetadataResolver()
        let progress = AuditProgress(total: inputs.count)
        var results: [AuditResult] = []
        results.reserveCapacity(inputs.count)

        for batchStart in stride(from: 0, to: inputs.count, by: concurrency) {
            let batchEnd = min(inputs.count, batchStart + concurrency)
            let batch = inputs[batchStart..<batchEnd]
            let batchResults = await withTaskGroup(of: AuditResult.self, returning: [AuditResult].self) { group in
                for input in batch {
                    group.addTask {
                        let result = await audit(input, resolver: resolver)
                        await progress.record(result)
                        return result
                    }
                }
                var values: [AuditResult] = []
                for await result in group { values.append(result) }
                return values
            }
            results.append(contentsOf: batchResults)
        }

        results.sort { $0.rank < $1.rank }
        let faviconCount = results.count { $0.outcome == "favicon" }
        let report = AuditReport(
            generatedAt: Date(),
            sourcePath: inputPath,
            total: results.count,
            faviconCount: faviconCount,
            genericFallbackCount: results.count - faviconCount,
            results: results
        )
        let encoded = try JSONEncoder.auditEncoder.encode(report)
        if let reportPath {
            try encoded.write(to: URL(fileURLWithPath: reportPath), options: .atomic)
            print("report: \(reportPath)")
        }
        print("complete: \(faviconCount)/\(results.count) runtime favicons; \(results.count - faviconCount) safe native glyph fallbacks")
    }

    private static func audit(
        _ input: AuditInput,
        resolver: DefaultMarkdownLinkMetadataResolver
    ) async -> AuditResult {
        let start = ContinuousClock.now
        let destination = URL(string: "https://\(input.domain)/")!
        let resolution = await resolver.resolveMetadata(for: destination)
        let elapsed = start.duration(to: .now)
        let milliseconds = Int(elapsed.components.seconds * 1_000) + Int(elapsed.components.attoseconds / 1_000_000_000_000_000)
        switch resolution {
        case let .metadata(metadata):
            switch metadata.decoration {
            case let .favicon(icon):
                return AuditResult(
                    rank: input.rank,
                    domain: input.domain,
                    outcome: "favicon",
                    iconURL: icon.sourceURL.absoluteString,
                    mimeType: icon.mimeType,
                    byteCount: icon.data.count,
                    pixelWidth: icon.pixelWidth,
                    pixelHeight: icon.pixelHeight,
                    elapsedMilliseconds: milliseconds,
                    failures: nil
                )
            case .glyph:
                break
            }
        case .unavailable:
            break
        }
        return AuditResult(
            rank: input.rank,
            domain: input.domain,
            outcome: "generic-glyph",
            iconURL: nil,
            mimeType: nil,
            byteCount: nil,
            pixelWidth: nil,
            pixelHeight: nil,
            elapsedMilliseconds: milliseconds,
            failures: resolver.failureDescriptions(for: destination)
        )
    }

    private static func loadInputs(path: String, limit: Int) throws -> [AuditInput] {
        let content = try String(contentsOfFile: path, encoding: .utf8)
        return content.split(whereSeparator: \.isNewline).prefix(limit).enumerated().compactMap { index, line in
            let fields = line.split(separator: ",", maxSplits: 1).map(String.init)
            let rank: Int
            let domain: String
            if fields.count == 2, let parsedRank = Int(fields[0]) {
                rank = parsedRank
                domain = fields[1]
            } else {
                rank = index + 1
                domain = fields[0]
            }
            let trimmed = domain.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !trimmed.isEmpty else { return nil }
            return AuditInput(rank: rank, domain: trimmed)
        }
    }

    private static func value(after option: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: option), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }

    private static let usage = "Usage: swift run SiriusMarkdownFaviconAudit --input ranks.csv [--report report.json] [--concurrency 16] [--limit 250]"
}

private extension JSONEncoder {
    static var auditEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private enum AuditError: Error {
    case usage(String)
    case emptyInput
}
