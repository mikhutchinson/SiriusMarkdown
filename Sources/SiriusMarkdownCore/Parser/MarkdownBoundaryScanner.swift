import Foundation

struct MarkdownBoundaryFence: Sendable, Hashable {
    var marker: Character
    var length: Int
}

struct MarkdownBoundaryHTMLBlock: Sendable, Hashable {
    var closingToken: String
}

public struct MarkdownBoundaryScanState: Sendable, Hashable {
    var lowerBound: Int
    var scannedUpperBound: Int
    var observedUpperBound: Int
    var candidateUpperBound: Int?
    var openFence: MarkdownBoundaryFence?
    var openMathFence: Bool
    var openDisplayMath: Bool
    var openHTMLBlock: MarkdownBoundaryHTMLBlock?
    var pendingReferenceLabels: Set<String>
    var definedReferenceLabels: Set<String>
    var unknownReferenceAmbiguity: Bool
    var consecutiveBlankLines: Int
    var lastNonBlankWasListLike: Bool

    public init(lowerBound: Int = 0) {
        self.lowerBound = lowerBound
        self.scannedUpperBound = lowerBound
        self.observedUpperBound = lowerBound
        self.candidateUpperBound = nil
        self.openFence = nil
        self.openMathFence = false
        self.openDisplayMath = false
        self.openHTMLBlock = nil
        self.pendingReferenceLabels = []
        self.definedReferenceLabels = []
        self.unknownReferenceAmbiguity = false
        self.consecutiveBlankLines = 0
        self.lastNonBlankWasListLike = false
    }

    public mutating func reset(lowerBound: Int) {
        self = MarkdownBoundaryScanState(lowerBound: lowerBound)
    }
}

public struct MarkdownBoundaryScanResult: Sendable, Hashable {
    public var safeUpperBound: Int?
    public var scannedByteCount: Int
    public var scannedLineCount: Int

    public init(safeUpperBound: Int?, scannedByteCount: Int, scannedLineCount: Int) {
        self.safeUpperBound = safeUpperBound
        self.scannedByteCount = scannedByteCount
        self.scannedLineCount = scannedLineCount
    }
}

public struct MarkdownBoundaryScanner: Sendable, Hashable {
    public init() {}

    public func safeSealUpperBound(in source: MarkdownSourceBuffer, after lowerBound: Int) -> Int? {
        var state = MarkdownBoundaryScanState(lowerBound: lowerBound)
        return scan(in: source, state: &state).safeUpperBound
    }

    public func scan(
        in source: MarkdownSourceBuffer,
        state: inout MarkdownBoundaryScanState
    ) -> MarkdownBoundaryScanResult {
        if state.scannedUpperBound < state.lowerBound ||
            state.scannedUpperBound > source.byteCount ||
            state.observedUpperBound < state.scannedUpperBound ||
            state.observedUpperBound > source.byteCount {
            state.reset(lowerBound: state.lowerBound)
        }

        if state.observedUpperBound < source.byteCount,
           !source.containsByte(10, in: state.observedUpperBound..<source.byteCount) {
            state.observedUpperBound = source.byteCount
            return MarkdownBoundaryScanResult(
                safeUpperBound: currentSafeUpperBound(in: state),
                scannedByteCount: 0,
                scannedLineCount: 0
            )
        }

        let lines = source.lines(in: state.scannedUpperBound..<source.byteCount)
        guard !lines.isEmpty else {
            state.observedUpperBound = source.byteCount
            return MarkdownBoundaryScanResult(
                safeUpperBound: currentSafeUpperBound(in: state),
                scannedByteCount: 0,
                scannedLineCount: 0
            )
        }

        var scannedByteCount = 0
        var scannedLineCount = 0

        for line in lines {
            guard line.includesTerminatingNewline else {
                break
            }

            let nextLineStart = line.includesTerminatingNewline
                ? line.byteRange.upperBound + 1
                : line.byteRange.upperBound
            let normalized = normalizedLineText(line.text)
            let trimmed = normalized.trimmingCharacters(in: .whitespaces)

            if let fence = state.openFence {
                if closesFence(normalized, fence: fence) {
                    state.openFence = nil
                }
            } else if let html = state.openHTMLBlock {
                if closesHTMLBlock(trimmed, html: html) {
                    state.openHTMLBlock = nil
                }
            } else if state.openMathFence {
                if trimmed == "$$" {
                    state.openMathFence = false
                }
            } else if state.openDisplayMath {
                if closesDisplayMath(trimmed) {
                    state.openDisplayMath = false
                }
            } else if let fence = opensFence(normalized) {
                state.openFence = fence
                state.lastNonBlankWasListLike = false
            } else if let html = opensHTMLBlock(trimmed) {
                state.openHTMLBlock = html
                state.lastNonBlankWasListLike = false
            } else if trimmed == "$$" {
                state.openMathFence = true
                state.lastNonBlankWasListLike = false
            } else if opensDisplayMath(trimmed) {
                state.openDisplayMath = true
                state.lastNonBlankWasListLike = false
            } else if trimmed.isEmpty {
                state.consecutiveBlankLines += 1
                state.unknownReferenceAmbiguity = false
                if !state.lastNonBlankWasListLike || state.consecutiveBlankLines >= 2 {
                    state.candidateUpperBound = min(nextLineStart, source.byteCount)
                }
            } else {
                scanReferenceLinks(in: normalized, state: &state)
                state.consecutiveBlankLines = 0
                state.lastNonBlankWasListLike = isListLike(trimmed)
            }

            scannedByteCount += max(0, nextLineStart - state.scannedUpperBound)
            scannedLineCount += 1
            state.scannedUpperBound = nextLineStart
        }
        state.observedUpperBound = source.byteCount

        return MarkdownBoundaryScanResult(
            safeUpperBound: currentSafeUpperBound(in: state),
            scannedByteCount: scannedByteCount,
            scannedLineCount: scannedLineCount
        )
    }

    private func currentSafeUpperBound(in state: MarkdownBoundaryScanState) -> Int? {
        if state.openFence != nil || state.openMathFence || state.openDisplayMath || state.openHTMLBlock != nil || state.unknownReferenceAmbiguity {
            return nil
        }

        if !state.pendingReferenceLabels.isSubset(of: state.definedReferenceLabels) {
            return nil
        }

        return state.candidateUpperBound.flatMap { $0 > state.lowerBound ? $0 : nil }
    }

    private func scanReferenceLinks(in line: String, state: inout MarkdownBoundaryScanState) {
        var cursor = line.startIndex
        while cursor < line.endIndex {
            guard line[cursor] == "[" else {
                cursor = line.index(after: cursor)
                continue
            }

            let opening = cursor
            guard let closing = closingBracket(in: line, after: opening) else {
                state.unknownReferenceAmbiguity = true
                return
            }

            let label = line[line.index(after: opening)..<closing]
            if isTaskCheckboxLabel(label) {
                cursor = line.index(after: closing)
                continue
            }

            let afterClosing = line.index(after: closing)
            if afterClosing < line.endIndex {
                switch line[afterClosing] {
                case "(":
                    cursor = line.index(after: afterClosing)
                    continue
                case ":" where line[..<opening].trimmingCharacters(in: .whitespaces).isEmpty:
                    if let normalized = normalizedReferenceLabel(label) {
                        state.definedReferenceLabels.insert(normalized)
                    }
                    return
                case "[":
                    guard let secondClosing = closingBracket(in: line, after: afterClosing) else {
                        state.unknownReferenceAmbiguity = true
                        return
                    }
                    let explicitLabel = line[line.index(after: afterClosing)..<secondClosing]
                    let referenceLabel = explicitLabel.isEmpty ? label : explicitLabel
                    if let normalized = normalizedReferenceLabel(referenceLabel) {
                        state.pendingReferenceLabels.insert(normalized)
                    }
                    cursor = line.index(after: secondClosing)
                default:
                    if let normalized = normalizedReferenceLabel(label) {
                        state.pendingReferenceLabels.insert(normalized)
                    }
                    cursor = afterClosing
                }
            } else if let normalized = normalizedReferenceLabel(label) {
                state.pendingReferenceLabels.insert(normalized)
                cursor = afterClosing
            } else {
                cursor = afterClosing
            }
        }
    }

    private func closingBracket(in line: String, after opening: String.Index) -> String.Index? {
        var cursor = line.index(after: opening)
        var escaped = false
        while cursor < line.endIndex {
            let character = line[cursor]
            if escaped {
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if character == "]" {
                return cursor
            }
            cursor = line.index(after: cursor)
        }
        return nil
    }

    private func isTaskCheckboxLabel(_ label: Substring) -> Bool {
        label == " " || label.lowercased() == "x"
    }

    private func normalizedReferenceLabel(_ label: Substring) -> String? {
        let normalized = label
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .lowercased()
        return normalized.isEmpty ? nil : normalized
    }

    private func opensFence(_ line: String) -> MarkdownBoundaryFence? {
        guard let content = lineAfterAllowedFenceIndent(line),
              content.hasPrefix("```") || content.hasPrefix("~~~")
        else {
            return nil
        }

        let marker = content.first ?? "`"
        let count = content.prefix { $0 == marker }.count
        guard count >= 3 else {
            return nil
        }

        return MarkdownBoundaryFence(marker: marker, length: count)
    }

    private func closesFence(_ line: String, fence: MarkdownBoundaryFence) -> Bool {
        guard let content = lineAfterAllowedFenceIndent(line) else {
            return false
        }

        let count = content.prefix { $0 == fence.marker }.count
        guard count >= fence.length else {
            return false
        }

        return content.dropFirst(count).allSatisfy(\.isWhitespace)
    }

    private func lineAfterAllowedFenceIndent(_ line: String) -> Substring? {
        var index = line.startIndex
        var leadingSpaces = 0

        while index < line.endIndex {
            switch line[index] {
            case " ":
                leadingSpaces += 1
                guard leadingSpaces <= 3 else {
                    return nil
                }
                index = line.index(after: index)
            case "\t":
                return nil
            default:
                return line[index...]
            }
        }

        return line[index...]
    }

    private func opensHTMLBlock(_ line: String) -> MarkdownBoundaryHTMLBlock? {
        let lowercased = line.lowercased()

        if lowercased.hasPrefix("<!--") && !lowercased.contains("-->") {
            return MarkdownBoundaryHTMLBlock(closingToken: "-->")
        }

        if lowercased.hasPrefix("<?") && !lowercased.contains("?>") {
            return MarkdownBoundaryHTMLBlock(closingToken: "?>")
        }

        if lowercased.hasPrefix("<![cdata[") && !lowercased.contains("]]>") {
            return MarkdownBoundaryHTMLBlock(closingToken: "]]>")
        }

        if opensHTMLDeclaration(lowercased) && !lowercased.contains(">") {
            return MarkdownBoundaryHTMLBlock(closingToken: ">")
        }

        for tag in htmlContainerTags {
            if startsHTMLTag(lowercased, tag: tag) && !lowercased.contains("</\(tag)>") {
                return MarkdownBoundaryHTMLBlock(closingToken: "</\(tag)>")
            }
        }

        return nil
    }

    private var htmlContainerTags: [String] {
        [
            "address", "article", "aside", "blockquote", "body", "caption", "center",
            "colgroup", "dd", "details", "dialog", "dir", "div", "dl", "dt",
            "fieldset", "figcaption", "figure", "footer", "form", "frame", "frameset",
            "h1", "h2", "h3", "h4", "h5", "h6", "head", "header", "html", "iframe",
            "legend", "li", "main", "menu", "menuitem", "nav", "noframes", "ol",
            "optgroup", "option", "p", "pre", "script", "section", "style", "summary",
            "table", "tbody", "td", "tfoot", "th", "thead", "title", "tr", "ul"
        ]
    }

    private func startsHTMLTag(_ line: String, tag: String) -> Bool {
        guard line.hasPrefix("<\(tag)") else {
            return false
        }

        let index = line.index(line.startIndex, offsetBy: tag.count + 1)
        guard index < line.endIndex else {
            return false
        }

        let next = line[index]
        return next == ">" || next == "/" || next.isWhitespace
    }

    private func opensHTMLDeclaration(_ line: String) -> Bool {
        guard line.hasPrefix("<!") && !line.hasPrefix("<!--") && !line.hasPrefix("<![cdata[") else {
            return false
        }

        let marker = line.index(line.startIndex, offsetBy: 2)
        guard marker < line.endIndex else {
            return false
        }

        return line[marker].isLetter
    }

    private func closesHTMLBlock(_ line: String, html: MarkdownBoundaryHTMLBlock) -> Bool {
        line.lowercased().contains(html.closingToken)
    }

    private func opensDisplayMath(_ line: String) -> Bool {
        guard let open = line.range(of: "\\[") else {
            return false
        }

        return !String(line[open.upperBound...]).contains("\\]")
    }

    private func closesDisplayMath(_ line: String) -> Bool {
        line.contains("\\]")
    }

    private func isListLike(_ line: String) -> Bool {
        if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ") ||
            line.hasPrefix("- [ ]") || line.hasPrefix("- [x]") ||
            line.hasPrefix("* [ ]") || line.hasPrefix("* [x]") {
            return true
        }

        var index = line.startIndex
        var sawDigit = false
        while index < line.endIndex, line[index].isNumber {
            sawDigit = true
            index = line.index(after: index)
        }

        guard sawDigit, index < line.endIndex else {
            return false
        }

        guard line[index] == "." || line[index] == ")" else {
            return false
        }

        let next = line.index(after: index)
        return next < line.endIndex && line[next] == " "
    }

    private func normalizedLineText(_ line: String) -> String {
        if line.last == "\r" {
            return String(line.dropLast())
        }
        return line
    }
}
