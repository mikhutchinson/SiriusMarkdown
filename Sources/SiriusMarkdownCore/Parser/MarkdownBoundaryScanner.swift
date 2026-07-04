import Foundation

struct MarkdownBoundaryFence: Sendable, Hashable {
    var marker: Character
    var length: Int
    var usesReferenceProjection: Bool
    var blockQuoteProjectionDepth: Int
    var opensAfterListProjection: Bool
}

struct MarkdownBoundaryHTMLBlock: Sendable, Hashable {
    var closingToken: String
    var usesReferenceProjection: Bool
    var blockQuoteProjectionDepth: Int
    var opensAfterListProjection: Bool
    var terminatesOnBlankLine: Bool
}

private struct MarkdownReferenceScanProjection: Sendable, Hashable {
    var line: String
    var allowsLeadingTaskCheckboxMarker: Bool
    var strippedListItemMarker: Bool
}

public struct MarkdownBoundaryScanState: Sendable, Hashable {
    var lowerBound: Int
    var scannedUpperBound: Int
    var observedUpperBound: Int
    var candidateUpperBound: Int?
    var openFence: MarkdownBoundaryFence?
    var openInlineCodeSpanLength: Int?
    var openMultilineReferenceLabel: String?
    var openMultilineReferenceLabelCanOpenDefinition: Bool
    var inlineCodeFallbackPendingReferenceLabels: Set<String>
    var inlineCodeFallbackUnknownReferenceAmbiguity: Bool
    var openReferenceDefinitionLabels: Set<String>
    var openReferenceDefinitionLabelsWithDestination: Set<String>
    var openReferenceDefinitionCurrentLabels: Set<String>
    var openReferenceDefinitionFallbackPendingReferenceLabels: Set<String>
    var openReferenceDefinitionOpensAfterListContinuation: Bool
    var openMathFence: Bool
    var openMathFenceUsesReferenceProjection: Bool
    var openMathFenceBlockQuoteProjectionDepth: Int
    var openMathFenceOpensAfterListProjection: Bool
    var openDisplayMath: Bool
    var openDisplayMathUsesReferenceProjection: Bool
    var openDisplayMathBlockQuoteProjectionDepth: Int
    var openDisplayMathOpensAfterListProjection: Bool
    var openMathEnvironment: Bool
    var openMathEnvironmentUsesReferenceProjection: Bool
    var openMathEnvironmentBlockQuoteProjectionDepth: Int
    var openMathEnvironmentOpensAfterListProjection: Bool
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
        self.openInlineCodeSpanLength = nil
        self.openMultilineReferenceLabel = nil
        self.openMultilineReferenceLabelCanOpenDefinition = false
        self.inlineCodeFallbackPendingReferenceLabels = []
        self.inlineCodeFallbackUnknownReferenceAmbiguity = false
        self.openReferenceDefinitionLabels = []
        self.openReferenceDefinitionLabelsWithDestination = []
        self.openReferenceDefinitionCurrentLabels = []
        self.openReferenceDefinitionFallbackPendingReferenceLabels = []
        self.openReferenceDefinitionOpensAfterListContinuation = false
        self.openMathFence = false
        self.openMathFenceUsesReferenceProjection = false
        self.openMathFenceBlockQuoteProjectionDepth = 0
        self.openMathFenceOpensAfterListProjection = false
        self.openDisplayMath = false
        self.openDisplayMathUsesReferenceProjection = false
        self.openDisplayMathBlockQuoteProjectionDepth = 0
        self.openDisplayMathOpensAfterListProjection = false
        self.openMathEnvironment = false
        self.openMathEnvironmentUsesReferenceProjection = false
        self.openMathEnvironmentBlockQuoteProjectionDepth = 0
        self.openMathEnvironmentOpensAfterListProjection = false
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
            let referenceProjection = referenceScanProjection(for: normalized)
            let referenceScanLine = referenceProjection.line
            let trimmed = normalized.trimmingCharacters(in: .whitespaces)
            let blockStartTrimmed = blockStartLineText(normalized)?.trimmingCharacters(in: .whitespaces)
            let referenceBlockStartTrimmed = blockStartLineText(referenceScanLine)?
                .trimmingCharacters(in: .whitespaces)
            let followsListLikeLine = state.lastNonBlankWasListLike
            let precedingBlankLineCount = state.consecutiveBlankLines
            let continuesListLikeLine = followsListLikeLine &&
                (
                    precedingBlankLineCount == 0 ||
                        isIndentedListContinuationLine(normalized)
                )

            if let fence = state.openFence {
                if closesFence(normalized, fence: fence) ||
                    fence.usesReferenceProjection &&
                    closesFence(projectedBlockQuoteLine(normalized, depth: fence.blockQuoteProjectionDepth), fence: fence) {
                    state.openFence = nil
                    state.lastNonBlankWasListLike = fence.opensAfterListProjection
                }
                state.consecutiveBlankLines = 0
            } else if let html = state.openHTMLBlock {
                if html.terminatesOnBlankLine && isHTMLTerminatingBlankLine(normalized, trimmed: trimmed, html: html) {
                    state.openHTMLBlock = nil
                    state.consecutiveBlankLines += 1
                    state.lastNonBlankWasListLike = html.opensAfterListProjection
                    state.unknownReferenceAmbiguity = false
                    if !state.lastNonBlankWasListLike || state.consecutiveBlankLines >= 2 {
                        state.candidateUpperBound = min(nextLineStart, source.byteCount)
                    }
                } else if !html.terminatesOnBlankLine && closesHTMLBlock(normalized, trimmed: trimmed, html: html) {
                    state.openHTMLBlock = nil
                    state.consecutiveBlankLines = 0
                    state.lastNonBlankWasListLike = html.opensAfterListProjection
                } else {
                    state.consecutiveBlankLines = 0
                }
            } else if state.openMathFence {
                if trimmed == "$$" ||
                    state.openMathFenceUsesReferenceProjection &&
                    projectedBlockQuoteLine(
                        normalized,
                        depth: state.openMathFenceBlockQuoteProjectionDepth
                    ).trimmingCharacters(in: .whitespaces) == "$$" {
                    state.openMathFence = false
                    state.openMathFenceUsesReferenceProjection = false
                    state.openMathFenceBlockQuoteProjectionDepth = 0
                    state.lastNonBlankWasListLike = state.openMathFenceOpensAfterListProjection
                    state.openMathFenceOpensAfterListProjection = false
                }
                state.consecutiveBlankLines = 0
            } else if state.openDisplayMath {
                if closesDisplayMath(trimmed) ||
                    state.openDisplayMathUsesReferenceProjection &&
                    closesDisplayMath(
                        projectedBlockQuoteLine(
                            normalized,
                            depth: state.openDisplayMathBlockQuoteProjectionDepth
                        ).trimmingCharacters(in: .whitespaces)
                    ) {
                    state.openDisplayMath = false
                    state.openDisplayMathUsesReferenceProjection = false
                    state.openDisplayMathBlockQuoteProjectionDepth = 0
                    state.lastNonBlankWasListLike = state.openDisplayMathOpensAfterListProjection
                    state.openDisplayMathOpensAfterListProjection = false
                }
                state.consecutiveBlankLines = 0
            } else if state.openMathEnvironment {
                let environmentLineToCheck = state.openMathEnvironmentUsesReferenceProjection
                    ? projectedBlockQuoteLine(
                        normalized,
                        depth: state.openMathEnvironmentBlockQuoteProjectionDepth
                    ).trimmingCharacters(in: .whitespaces)
                    : trimmed
                if closesMathEnvironment(environmentLineToCheck) {
                    state.openMathEnvironment = false
                    state.openMathEnvironmentUsesReferenceProjection = false
                    state.openMathEnvironmentBlockQuoteProjectionDepth = 0
                    state.lastNonBlankWasListLike = state.openMathEnvironmentOpensAfterListProjection
                    state.openMathEnvironmentOpensAfterListProjection = false
                }
                state.consecutiveBlankLines = 0
            } else if var fence = opensFence(normalized) {
                fence.opensAfterListProjection = continuesListLikeLine
                state.openFence = fence
                state.consecutiveBlankLines = 0
                state.lastNonBlankWasListLike = false
            } else if var fence = opensFence(referenceScanLine) {
                fence.usesReferenceProjection = true
                fence.blockQuoteProjectionDepth = leadingBlockQuoteProjectionDepth(in: normalized)
                fence.opensAfterListProjection =
                    referenceProjection.strippedListItemMarker ||
                    continuesListLikeLine
                state.openFence = fence
                state.consecutiveBlankLines = 0
                state.lastNonBlankWasListLike = false
            } else if let blockStartTrimmed,
                      var html = opensHTMLBlock(blockStartTrimmed) {
                html.opensAfterListProjection = continuesListLikeLine
                state.openHTMLBlock = html
                state.consecutiveBlankLines = 0
                state.lastNonBlankWasListLike = false
            } else if let referenceBlockStartTrimmed,
                      var html = opensHTMLBlock(referenceBlockStartTrimmed) {
                html.usesReferenceProjection = true
                html.blockQuoteProjectionDepth = leadingBlockQuoteProjectionDepth(in: normalized)
                html.opensAfterListProjection =
                    referenceProjection.strippedListItemMarker ||
                    continuesListLikeLine
                state.openHTMLBlock = html
                state.consecutiveBlankLines = 0
                state.lastNonBlankWasListLike = false
            } else if blockStartTrimmed == "$$" {
                state.openMathFence = true
                state.openMathFenceUsesReferenceProjection = false
                state.openMathFenceOpensAfterListProjection = continuesListLikeLine
                state.consecutiveBlankLines = 0
                state.lastNonBlankWasListLike = false
            } else if referenceBlockStartTrimmed == "$$" {
                state.openMathFence = true
                state.openMathFenceUsesReferenceProjection = true
                state.openMathFenceBlockQuoteProjectionDepth = leadingBlockQuoteProjectionDepth(in: normalized)
                state.openMathFenceOpensAfterListProjection =
                    referenceProjection.strippedListItemMarker ||
                    continuesListLikeLine
                state.consecutiveBlankLines = 0
                state.lastNonBlankWasListLike = false
            } else if let blockStartTrimmed,
                      opensDisplayMath(blockStartTrimmed) {
                state.openDisplayMath = true
                state.openDisplayMathUsesReferenceProjection = false
                state.openDisplayMathOpensAfterListProjection = continuesListLikeLine
                state.consecutiveBlankLines = 0
                state.lastNonBlankWasListLike = false
            } else if let referenceBlockStartTrimmed,
                      opensDisplayMath(referenceBlockStartTrimmed) {
                state.openDisplayMath = true
                state.openDisplayMathUsesReferenceProjection = true
                state.openDisplayMathBlockQuoteProjectionDepth = leadingBlockQuoteProjectionDepth(in: normalized)
                state.openDisplayMathOpensAfterListProjection =
                    referenceProjection.strippedListItemMarker ||
                    continuesListLikeLine
                state.consecutiveBlankLines = 0
                state.lastNonBlankWasListLike = false
            } else if opensMathEnvironment(blockStartTrimmed) {
                state.openMathEnvironment = true
                state.openMathEnvironmentUsesReferenceProjection = false
                state.openMathEnvironmentOpensAfterListProjection = continuesListLikeLine
                state.consecutiveBlankLines = 0
                state.lastNonBlankWasListLike = false
            } else if opensMathEnvironment(referenceBlockStartTrimmed) {
                state.openMathEnvironment = true
                state.openMathEnvironmentUsesReferenceProjection = true
                state.openMathEnvironmentBlockQuoteProjectionDepth = leadingBlockQuoteProjectionDepth(in: normalized)
                state.openMathEnvironmentOpensAfterListProjection =
                    referenceProjection.strippedListItemMarker ||
                    continuesListLikeLine
                state.consecutiveBlankLines = 0
                state.lastNonBlankWasListLike = false
            } else if trimmed.isEmpty {
                finalizeOpenReferenceDefinitionsIfNeeded(state: &state)
                promoteInlineCodeFallbackIfNeeded(state: &state)
                state.openMultilineReferenceLabel = nil
                state.openMultilineReferenceLabelCanOpenDefinition = false
                state.consecutiveBlankLines += 1
                state.unknownReferenceAmbiguity = false
                if !state.lastNonBlankWasListLike || state.consecutiveBlankLines >= 2 {
                    state.candidateUpperBound = min(nextLineStart, source.byteCount)
                }
            } else if !state.openReferenceDefinitionLabels.isEmpty {
                if let label = referenceDefinitionOpeningLabel(in: referenceScanLine) {
                    openReferenceDefinition(label: label, line: referenceScanLine, state: &state)
                } else if isReferenceDefinitionContinuationLine(referenceScanLine) {
                    if referenceDefinitionContinuationLineHasDestination(in: referenceScanLine) {
                        state.openReferenceDefinitionLabelsWithDestination.formUnion(
                            state.openReferenceDefinitionCurrentLabels
                        )
                    }
                }
                state.consecutiveBlankLines = 0
                state.lastNonBlankWasListLike = state.openReferenceDefinitionOpensAfterListContinuation
            } else {
                let isReferenceDefinitionLine = referenceDefinitionOpeningLabel(in: referenceScanLine) != nil
                scanReferenceLinks(
                    in: referenceScanLine,
                    allowsProjectedTaskCheckboxMarker: referenceProjection.allowsLeadingTaskCheckboxMarker,
                    state: &state
                )
                if isReferenceDefinitionLine &&
                    (referenceProjection.strippedListItemMarker || continuesListLikeLine) {
                    state.openReferenceDefinitionOpensAfterListContinuation = true
                }
                state.consecutiveBlankLines = 0
                state.lastNonBlankWasListLike =
                    isListLike(trimmed) ||
                    referenceProjection.strippedListItemMarker ||
                    continuesListLikeLine
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
        if state.openFence != nil ||
            state.openInlineCodeSpanLength != nil ||
            state.openMultilineReferenceLabel != nil ||
            state.openMathFence ||
            state.openDisplayMath ||
            state.openMathEnvironment ||
            state.openHTMLBlock != nil ||
            !state.openReferenceDefinitionLabels.isEmpty ||
            state.unknownReferenceAmbiguity {
            return nil
        }

        if !state.pendingReferenceLabels.isSubset(of: state.definedReferenceLabels) {
            return nil
        }

        return state.candidateUpperBound.flatMap { $0 > state.lowerBound ? $0 : nil }
    }

    private func scanReferenceLinks(
        in line: String,
        allowsProjectedTaskCheckboxMarker: Bool,
        state: inout MarkdownBoundaryScanState
    ) {
        var cursor = line.startIndex
        if state.openMultilineReferenceLabel != nil {
            guard let continuationCursor = consumeOpenMultilineReferenceLabel(in: line, state: &state) else {
                return
            }
            cursor = continuationCursor
        }

        while cursor < line.endIndex {
            if let delimiterLength = state.openInlineCodeSpanLength {
                guard let closing = closingBacktickRun(
                    length: delimiterLength,
                    in: line,
                    startingAt: cursor
                ) else {
                    collectInlineCodeFallbackReferences(
                        in: line[cursor...],
                        state: &state
                    )
                    return
                }
                state.openInlineCodeSpanLength = nil
                discardInlineCodeFallback(state: &state)
                cursor = closing.upperBound
                continue
            }

            if line[cursor] == "<",
               !isEscapedCharacter(at: cursor, in: line),
               let angleEnd = inlineAngleConstructEnd(in: line, openingAngle: cursor) {
                cursor = line.index(after: angleEnd)
                continue
            }

            if line[cursor] == "`", !isEscapedCharacter(at: cursor, in: line) {
                let opening = backtickRun(startingAt: cursor, in: line)
                guard let closing = closingBacktickRun(matching: opening, in: line) else {
                    state.openInlineCodeSpanLength = line.distance(
                        from: opening.lowerBound,
                        to: opening.upperBound
                    )
                    collectInlineCodeFallbackReferences(
                        in: line[opening.upperBound...],
                        state: &state
                    )
                    return
                }
                cursor = closing.upperBound
                continue
            }

            guard line[cursor] == "[" else {
                cursor = line.index(after: cursor)
                continue
            }
            guard !isEscapedCharacter(at: cursor, in: line) else {
                cursor = line.index(after: cursor)
                continue
            }

            let opening = cursor
            guard let closing = closingBracket(in: line, after: opening) else {
                state.openMultilineReferenceLabel = String(line[line.index(after: opening)...])
                state.openMultilineReferenceLabelCanOpenDefinition = isReferenceDefinitionOpening(opening, in: line)
                state.unknownReferenceAmbiguity = true
                return
            }

            let label = line[line.index(after: opening)..<closing]
            if isTaskCheckboxMarker(
                label,
                opening: opening,
                closing: closing,
                in: line,
                allowsProjectedLeadingMarker: allowsProjectedTaskCheckboxMarker
            ) {
                cursor = line.index(after: closing)
                continue
            }

            let afterClosing = line.index(after: closing)
            if afterClosing < line.endIndex {
                switch line[afterClosing] {
                case "(":
                    let labelContainsPendingReference = collectPendingReferenceCandidates(
                        in: label,
                        state: &state
                    )
                    if let destinationEnd = inlineLinkDestinationEnd(
                        in: line,
                        openingParen: afterClosing
                    ) {
                        cursor = line.index(after: destinationEnd)
                    } else if labelContainsPendingReference {
                        cursor = afterClosing
                    } else {
                        cursor = line.index(after: afterClosing)
                    }
                    continue
                case ":" where isReferenceDefinitionOpening(opening, in: line):
                    if let normalized = normalizedReferenceLabel(label) {
                        openReferenceDefinition(label: normalized, line: line, state: &state)
                    }
                    return
                case "[":
                    guard let secondClosing = closingBracket(in: line, after: afterClosing) else {
                        state.openMultilineReferenceLabel = String(line[line.index(after: afterClosing)...])
                        state.openMultilineReferenceLabelCanOpenDefinition = false
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

    private func consumeOpenMultilineReferenceLabel(
        in line: String,
        state: inout MarkdownBoundaryScanState
    ) -> String.Index? {
        guard let leadingLabel = state.openMultilineReferenceLabel else {
            return line.startIndex
        }
        let canOpenDefinition = state.openMultilineReferenceLabelCanOpenDefinition

        guard let closing = closingMultilineReferenceLabel(in: line) else {
            state.openMultilineReferenceLabel = leadingLabel + "\n" + line
            state.unknownReferenceAmbiguity = true
            return nil
        }

        let labelText = leadingLabel + "\n" + String(line[..<closing])
        state.openMultilineReferenceLabel = nil
        state.openMultilineReferenceLabelCanOpenDefinition = false
        state.unknownReferenceAmbiguity = false

        let afterClosing = line.index(after: closing)
        if afterClosing < line.endIndex {
            switch line[afterClosing] {
            case ":" where canOpenDefinition:
                if let normalized = normalizedReferenceLabel(labelText[...]) {
                    let afterColon = line.index(after: afterClosing)
                    openReferenceDefinition(
                        label: normalized,
                        line: "[\(labelText)]:\(line[afterColon...])",
                        state: &state
                    )
                }
                return line.endIndex
            case "(":
                let labelContainsPendingReference = collectPendingReferenceCandidates(
                    in: labelText[...],
                    state: &state
                )
                if let destinationEnd = inlineLinkDestinationEnd(
                    in: line,
                    openingParen: afterClosing
                ) {
                    return line.index(after: destinationEnd)
                }
                return labelContainsPendingReference
                    ? afterClosing
                    : line.index(after: afterClosing)
            case "[":
                guard let secondClosing = closingBracket(in: line, after: afterClosing) else {
                    state.unknownReferenceAmbiguity = true
                    return nil
                }
                let explicitLabel = line[line.index(after: afterClosing)..<secondClosing]
                if explicitLabel.isEmpty {
                    if let normalized = normalizedReferenceLabel(labelText[...]) {
                        state.pendingReferenceLabels.insert(normalized)
                    }
                } else if let normalized = normalizedReferenceLabel(explicitLabel) {
                    state.pendingReferenceLabels.insert(normalized)
                }
                return line.index(after: secondClosing)
            default:
                if let normalized = normalizedReferenceLabel(labelText[...]) {
                    state.pendingReferenceLabels.insert(normalized)
                }
                return afterClosing
            }
        }

        if let normalized = normalizedReferenceLabel(labelText[...]) {
            state.pendingReferenceLabels.insert(normalized)
        }
        return afterClosing
    }

    private func promoteInlineCodeFallbackIfNeeded(state: inout MarkdownBoundaryScanState) {
        guard state.openInlineCodeSpanLength != nil else {
            return
        }

        state.pendingReferenceLabels.formUnion(state.inlineCodeFallbackPendingReferenceLabels)
        state.unknownReferenceAmbiguity =
            state.unknownReferenceAmbiguity ||
            state.inlineCodeFallbackUnknownReferenceAmbiguity
        state.openInlineCodeSpanLength = nil
        discardInlineCodeFallback(state: &state)
    }

    private func discardInlineCodeFallback(state: inout MarkdownBoundaryScanState) {
        state.inlineCodeFallbackPendingReferenceLabels.removeAll()
        state.inlineCodeFallbackUnknownReferenceAmbiguity = false
    }

    private func finalizeOpenReferenceDefinitionsIfNeeded(state: inout MarkdownBoundaryScanState) {
        guard !state.openReferenceDefinitionLabels.isEmpty else {
            return
        }

        state.definedReferenceLabels.formUnion(state.openReferenceDefinitionLabelsWithDestination)
        state.pendingReferenceLabels.formUnion(
            state.openReferenceDefinitionFallbackPendingReferenceLabels
                .subtracting(state.openReferenceDefinitionLabelsWithDestination)
        )
        state.openReferenceDefinitionLabels.removeAll()
        state.openReferenceDefinitionLabelsWithDestination.removeAll()
        state.openReferenceDefinitionCurrentLabels.removeAll()
        state.openReferenceDefinitionFallbackPendingReferenceLabels.removeAll()
        state.openReferenceDefinitionOpensAfterListContinuation = false
    }

    private func openReferenceDefinition(
        label: String,
        line: String,
        state: inout MarkdownBoundaryScanState
    ) {
        state.openReferenceDefinitionLabels.insert(label)
        state.openReferenceDefinitionFallbackPendingReferenceLabels.insert(label)
        state.openReferenceDefinitionCurrentLabels = [label]
        if referenceDefinitionOpeningLineHasDestination(in: line) {
            state.openReferenceDefinitionLabelsWithDestination.insert(label)
        }
    }

    private func collectInlineCodeFallbackReferences(
        in text: Substring,
        state: inout MarkdownBoundaryScanState
    ) {
        let fallback = String(text)
        var cursor = fallback.startIndex
        while cursor < fallback.endIndex {
            guard fallback[cursor] == "[" else {
                cursor = fallback.index(after: cursor)
                continue
            }
            guard !isEscapedCharacter(at: cursor, in: fallback) else {
                cursor = fallback.index(after: cursor)
                continue
            }

            let opening = cursor
            guard let closing = closingBracket(in: fallback, after: opening) else {
                state.inlineCodeFallbackUnknownReferenceAmbiguity = true
                return
            }

            let label = fallback[fallback.index(after: opening)..<closing]
            let afterClosing = fallback.index(after: closing)
            if afterClosing < fallback.endIndex {
                switch fallback[afterClosing] {
                case "(":
                    cursor = fallback.index(after: afterClosing)
                    continue
                case "[":
                    guard let secondClosing = closingBracket(in: fallback, after: afterClosing) else {
                        state.inlineCodeFallbackUnknownReferenceAmbiguity = true
                        return
                    }
                    let explicitLabel = fallback[fallback.index(after: afterClosing)..<secondClosing]
                    let referenceLabel = explicitLabel.isEmpty ? label : explicitLabel
                    if let normalized = normalizedReferenceLabel(referenceLabel) {
                        state.inlineCodeFallbackPendingReferenceLabels.insert(normalized)
                    }
                    cursor = fallback.index(after: secondClosing)
                default:
                    if let normalized = normalizedReferenceLabel(label) {
                        state.inlineCodeFallbackPendingReferenceLabels.insert(normalized)
                    }
                    cursor = afterClosing
                }
            } else if let normalized = normalizedReferenceLabel(label) {
                state.inlineCodeFallbackPendingReferenceLabels.insert(normalized)
                cursor = afterClosing
            } else {
                cursor = afterClosing
            }
        }
    }

    @discardableResult
    private func collectPendingReferenceCandidates(
        in text: Substring,
        state: inout MarkdownBoundaryScanState
    ) -> Bool {
        let fallback = String(text)
        var cursor = fallback.startIndex
        var foundCandidate = false
        while cursor < fallback.endIndex {
            guard fallback[cursor] == "[" else {
                cursor = fallback.index(after: cursor)
                continue
            }
            guard !isEscapedCharacter(at: cursor, in: fallback) else {
                cursor = fallback.index(after: cursor)
                continue
            }

            let opening = cursor
            guard let closing = closingBracket(in: fallback, after: opening) else {
                state.unknownReferenceAmbiguity = true
                return true
            }

            let label = fallback[fallback.index(after: opening)..<closing]
            let afterClosing = fallback.index(after: closing)
            if afterClosing < fallback.endIndex {
                switch fallback[afterClosing] {
                case "(":
                    cursor = fallback.index(after: afterClosing)
                    continue
                case "[":
                    guard let secondClosing = closingBracket(in: fallback, after: afterClosing) else {
                        state.unknownReferenceAmbiguity = true
                        return true
                    }
                    let explicitLabel = fallback[fallback.index(after: afterClosing)..<secondClosing]
                    let referenceLabel = explicitLabel.isEmpty ? label : explicitLabel
                    if let normalized = normalizedReferenceLabel(referenceLabel) {
                        state.pendingReferenceLabels.insert(normalized)
                        foundCandidate = true
                    }
                    cursor = fallback.index(after: secondClosing)
                default:
                    if let normalized = normalizedReferenceLabel(label) {
                        state.pendingReferenceLabels.insert(normalized)
                        foundCandidate = true
                    }
                    cursor = afterClosing
                }
            } else if let normalized = normalizedReferenceLabel(label) {
                state.pendingReferenceLabels.insert(normalized)
                foundCandidate = true
                cursor = afterClosing
            } else {
                cursor = afterClosing
            }
        }

        return foundCandidate
    }

    private func isEscapedCharacter(at index: String.Index, in line: String) -> Bool {
        var cursor = index
        var backslashCount = 0
        while cursor > line.startIndex {
            let previous = line.index(before: cursor)
            guard line[previous] == "\\" else {
                break
            }
            backslashCount += 1
            cursor = previous
        }
        return backslashCount % 2 == 1
    }

    private func closingBacktickRun(
        matching opening: Range<String.Index>,
        in line: String
    ) -> Range<String.Index>? {
        let openingLength = line.distance(from: opening.lowerBound, to: opening.upperBound)
        var cursor = opening.upperBound

        while cursor < line.endIndex {
            guard line[cursor] == "`" else {
                cursor = line.index(after: cursor)
                continue
            }

            let candidate = backtickRun(startingAt: cursor, in: line)
            if line.distance(from: candidate.lowerBound, to: candidate.upperBound) == openingLength {
                return candidate
            }
            cursor = candidate.upperBound
        }

        return nil
    }

    private func closingBacktickRun(
        length: Int,
        in line: String,
        startingAt start: String.Index
    ) -> Range<String.Index>? {
        var cursor = start

        while cursor < line.endIndex {
            guard line[cursor] == "`" else {
                cursor = line.index(after: cursor)
                continue
            }

            let candidate = backtickRun(startingAt: cursor, in: line)
            if line.distance(from: candidate.lowerBound, to: candidate.upperBound) == length {
                return candidate
            }
            cursor = candidate.upperBound
        }

        return nil
    }

    private func inlineLinkDestinationEnd(
        in line: String,
        openingParen: String.Index
    ) -> String.Index? {
        var cursor = line.index(after: openingParen)
        var parenDepth = 1
        var destinationStarted = false
        var scanningAngleDestination = false
        var afterDestination = false
        var consumedTitle = false
        var scanningParentheticalTitle = false
        var titleQuote: Character?

        while cursor < line.endIndex {
            let character = line[cursor]

            if isEscapedCharacter(at: cursor, in: line) {
                if character.isWhitespace {
                    return nil
                }
                cursor = line.index(after: cursor)
                continue
            }

            if let quote = titleQuote {
                if character == quote {
                    titleQuote = nil
                    consumedTitle = true
                    afterDestination = true
                }
                cursor = line.index(after: cursor)
                continue
            }

            if scanningAngleDestination {
                if character == ">" {
                    scanningAngleDestination = false
                    afterDestination = true
                }
                cursor = line.index(after: cursor)
                continue
            }

            if scanningParentheticalTitle {
                if character == "(" {
                    parenDepth += 1
                } else if character == ")" {
                    parenDepth -= 1
                    if parenDepth == 1 {
                        scanningParentheticalTitle = false
                        consumedTitle = true
                    }
                }
                cursor = line.index(after: cursor)
                continue
            }

            if !destinationStarted {
                if character.isWhitespace {
                    cursor = line.index(after: cursor)
                    continue
                }

                destinationStarted = true
                if character == "<" {
                    scanningAngleDestination = true
                    cursor = line.index(after: cursor)
                    continue
                }
            }

            if afterDestination {
                if character.isWhitespace {
                    cursor = line.index(after: cursor)
                    continue
                }

                if consumedTitle {
                    guard character == ")" else {
                        return nil
                    }
                    parenDepth -= 1
                    return parenDepth == 0 ? cursor : nil
                }

                if character == "\"" || character == "'" {
                    titleQuote = character
                    cursor = line.index(after: cursor)
                    continue
                }

                if character == "(" {
                    scanningParentheticalTitle = true
                    parenDepth += 1
                    cursor = line.index(after: cursor)
                    continue
                }

                guard character == ")" else {
                    return nil
                }
                parenDepth -= 1
                return parenDepth == 0 ? cursor : nil
            }

            if character.isWhitespace {
                afterDestination = true
                cursor = line.index(after: cursor)
                continue
            }

            if character == "(" {
                parenDepth += 1
                cursor = line.index(after: cursor)
                continue
            }

            if character == ")" {
                parenDepth -= 1
                if parenDepth == 0 {
                    return cursor
                }
            }

            cursor = line.index(after: cursor)
        }

        return nil
    }

    private func inlineAngleConstructEnd(
        in line: String,
        openingAngle: String.Index
    ) -> String.Index? {
        let afterOpening = line.index(after: openingAngle)
        guard afterOpening < line.endIndex else {
            return nil
        }

        if let commentEnd = inlineHTMLCommentEnd(in: line, openingAngle: openingAngle) {
            return commentEnd
        }

        if startsAutolink(in: line, afterOpeningAngle: afterOpening) {
            return autolinkEnd(in: line, startingAt: afterOpening)
        }

        if let specialEnd = inlineHTMLSpecialFormEnd(in: line, afterOpeningAngle: afterOpening) {
            return specialEnd
        }

        guard startsInlineHTMLTag(in: line, afterOpeningAngle: afterOpening) else {
            return nil
        }

        return htmlTagEnd(in: line, startingAt: afterOpening)
    }

    private func inlineHTMLCommentEnd(
        in line: String,
        openingAngle: String.Index
    ) -> String.Index? {
        guard line[openingAngle...].hasPrefix("<!--") else {
            return nil
        }

        guard let closing = line[openingAngle...].range(of: "-->") else {
            return nil
        }

        return line.index(before: closing.upperBound)
    }

    private func startsAutolink(
        in line: String,
        afterOpeningAngle start: String.Index
    ) -> Bool {
        var cursor = start
        var sawSchemeColon = false
        var scheme = ""

        while cursor < line.endIndex {
            let character = line[cursor]
            if character == ":" {
                sawSchemeColon = true
                break
            }

            guard isSchemeContinuation(character) else {
                return false
            }

            scheme.append(character)
            cursor = line.index(after: cursor)
        }

        guard sawSchemeColon,
              let first = scheme.first,
              isASCIILetter(first),
              (2...32).contains(scheme.count)
        else {
            return false
        }

        return scheme.dropFirst().allSatisfy(isSchemeContinuation)
    }

    private func autolinkEnd(
        in line: String,
        startingAt start: String.Index
    ) -> String.Index? {
        var cursor = start
        while cursor < line.endIndex {
            let character = line[cursor]
            if character == ">" {
                return cursor
            }
            if character == "<" || character.isWhitespace {
                return nil
            }
            cursor = line.index(after: cursor)
        }
        return nil
    }

    private func inlineHTMLSpecialFormEnd(
        in line: String,
        afterOpeningAngle start: String.Index
    ) -> String.Index? {
        if line[start...].hasPrefix("?") {
            return inlineHTMLTerminatorEnd("?>", in: line, from: start)
        }

        guard startsInlineHTMLDeclaration(in: line, at: start) else {
            return nil
        }
        return inlineHTMLTerminatorEnd(">", in: line, from: start)
    }

    private func inlineHTMLTerminatorEnd(
        _ terminator: String,
        in line: String,
        from start: String.Index
    ) -> String.Index? {
        guard let range = line.range(of: terminator, range: start..<line.endIndex) else {
            return nil
        }

        return line.index(before: range.upperBound)
    }

    private func startsInlineHTMLDeclaration(
        in line: String,
        at start: String.Index
    ) -> Bool {
        guard line[start...].hasPrefix("!") else {
            return false
        }

        let marker = line.index(after: start)
        guard marker < line.endIndex else {
            return false
        }

        return line[marker].isLetter
    }

    private func startsInlineHTMLTag(
        in line: String,
        afterOpeningAngle start: String.Index
    ) -> Bool {
        var cursor = start
        if line[cursor] == "/" {
            cursor = line.index(after: cursor)
        }

        guard cursor < line.endIndex,
              isASCIILetter(line[cursor])
        else {
            return false
        }

        repeat {
            cursor = line.index(after: cursor)
        } while cursor < line.endIndex && isHTMLTagNameCharacter(line[cursor])

        guard cursor < line.endIndex else {
            return false
        }

        let terminator = line[cursor]
        return terminator == ">" || terminator == "/" || terminator.isWhitespace
    }

    private func htmlTagEnd(
        in line: String,
        startingAt start: String.Index
    ) -> String.Index? {
        var cursor = start
        var quote: Character?

        while cursor < line.endIndex {
            let character = line[cursor]

            if let activeQuote = quote {
                if character == activeQuote {
                    quote = nil
                }
                cursor = line.index(after: cursor)
                continue
            }

            if character == "\"" || character == "'" {
                quote = character
                cursor = line.index(after: cursor)
                continue
            }

            if character == "[" || character == "]" {
                return nil
            }

            if character == ">" {
                return cursor
            }

            cursor = line.index(after: cursor)
        }

        return nil
    }

    private func isHTMLTagNameCharacter(_ character: Character) -> Bool {
        isASCIILetter(character) ||
            isASCIIDigit(character) ||
            character == "-"
    }

    private func backtickRun(
        startingAt index: String.Index,
        in line: String
    ) -> Range<String.Index> {
        var cursor = index
        while cursor < line.endIndex, line[cursor] == "`" {
            cursor = line.index(after: cursor)
        }
        return index..<cursor
    }

    private func closingBracket(in line: String, after opening: String.Index) -> String.Index? {
        var cursor = line.index(after: opening)
        var depth = 1
        var escaped = false

        while cursor < line.endIndex {
            let character = line[cursor]
            if escaped {
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if character == "[" {
                depth += 1
            } else if character == "]" {
                depth -= 1
                if depth == 0 {
                    return cursor
                }
            }
            cursor = line.index(after: cursor)
        }

        return nil
    }

    private func closingMultilineReferenceLabel(in line: String) -> String.Index? {
        var cursor = line.startIndex
        var depth = 1
        var escaped = false

        while cursor < line.endIndex {
            let character = line[cursor]
            if escaped {
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if character == "[" {
                depth += 1
            } else if character == "]" {
                depth -= 1
                if depth == 0 {
                    return cursor
                }
            }
            cursor = line.index(after: cursor)
        }

        return nil
    }

    private func isTaskCheckboxMarker(
        _ label: Substring,
        opening: String.Index,
        closing: String.Index,
        in line: String,
        allowsProjectedLeadingMarker: Bool
    ) -> Bool {
        guard label == " " || label.lowercased() == "x" else {
            return false
        }

        let afterClosing = line.index(after: closing)
        guard afterClosing == line.endIndex ||
            line[afterClosing] == " " ||
            line[afterClosing] == "\t"
        else {
            return false
        }

        let prefix = line[..<opening]
        var cursor = prefix.startIndex
        var leadingSpaces = 0
        while cursor < prefix.endIndex, prefix[cursor] == " " {
            leadingSpaces += 1
            guard leadingSpaces <= 3 else {
                return false
            }
            cursor = prefix.index(after: cursor)
        }

        if allowsProjectedLeadingMarker, cursor == prefix.endIndex {
            return true
        }

        guard cursor < prefix.endIndex else {
            return false
        }

        switch prefix[cursor] {
        case "-", "*", "+":
            cursor = prefix.index(after: cursor)
        case let character where character.isNumber:
            repeat {
                cursor = prefix.index(after: cursor)
            } while cursor < prefix.endIndex && prefix[cursor].isNumber

            guard cursor < prefix.endIndex,
                  prefix[cursor] == "." || prefix[cursor] == ")"
            else {
                return false
            }
            cursor = prefix.index(after: cursor)
        default:
            return false
        }

        var hasMarkerWhitespace = false
        while cursor < prefix.endIndex {
            guard prefix[cursor] == " " else {
                return false
            }
            hasMarkerWhitespace = true
            cursor = prefix.index(after: cursor)
        }

        return hasMarkerWhitespace
    }

    private func isReferenceDefinitionOpening(_ opening: String.Index, in line: String) -> Bool {
        var cursor = line.startIndex
        var leadingSpaces = 0
        while cursor < opening {
            guard line[cursor] == " " else {
                return false
            }
            leadingSpaces += 1
            guard leadingSpaces <= 3 else {
                return false
            }
            cursor = line.index(after: cursor)
        }

        return true
    }

    private func referenceDefinitionOpeningLabel(in line: String) -> String? {
        var cursor = line.startIndex
        var leadingSpaces = 0
        while cursor < line.endIndex, line[cursor] == " " {
            leadingSpaces += 1
            guard leadingSpaces <= 3 else {
                return nil
            }
            cursor = line.index(after: cursor)
        }

        guard cursor < line.endIndex, line[cursor] == "[" else {
            return nil
        }

        let opening = cursor
        guard let closing = closingBracket(in: line, after: opening) else {
            return nil
        }

        let afterClosing = line.index(after: closing)
        guard afterClosing < line.endIndex, line[afterClosing] == ":" else {
            return nil
        }

        return normalizedReferenceLabel(line[line.index(after: opening)..<closing])
    }

    private func referenceDefinitionOpeningLineHasDestination(in line: String) -> Bool {
        var cursor = line.startIndex
        var leadingSpaces = 0
        while cursor < line.endIndex, line[cursor] == " " {
            leadingSpaces += 1
            guard leadingSpaces <= 3 else {
                return false
            }
            cursor = line.index(after: cursor)
        }

        guard cursor < line.endIndex, line[cursor] == "[",
              let closing = closingBracket(in: line, after: cursor)
        else {
            return false
        }

        let afterClosing = line.index(after: closing)
        guard afterClosing < line.endIndex, line[afterClosing] == ":" else {
            return false
        }

        return referenceDefinitionRemainderHasDestination(line[line.index(after: afterClosing)...])
    }

    private func isReferenceDefinitionContinuationLine(_ line: String) -> Bool {
        referenceDefinitionContinuationContentStart(in: line) != nil
    }

    private func referenceDefinitionContinuationLineHasDestination(in line: String) -> Bool {
        guard let cursor = referenceDefinitionContinuationContentStart(in: line) else {
            return false
        }

        return referenceDefinitionRemainderHasDestination(line[cursor...])
    }

    private func referenceDefinitionScanLine(_ line: String) -> String {
        referenceScanProjection(for: line).line
    }

    private func referenceScanProjection(for line: String) -> MarkdownReferenceScanProjection {
        var current = line
        var allowsLeadingTaskCheckboxMarker = false
        var strippedListItemMarker = false
        while true {
            if let stripped = stripLeadingBlockQuoteMarker(from: current) {
                current = stripped
                allowsLeadingTaskCheckboxMarker = false
                continue
            }
            if let stripped = stripLeadingListItemMarker(from: current) {
                current = stripped
                allowsLeadingTaskCheckboxMarker = true
                strippedListItemMarker = true
                continue
            }
            return MarkdownReferenceScanProjection(
                line: current,
                allowsLeadingTaskCheckboxMarker: allowsLeadingTaskCheckboxMarker,
                strippedListItemMarker: strippedListItemMarker
            )
        }
    }

    private func leadingBlockQuoteProjectionDepth(in line: String) -> Int {
        var current = line
        var depth = 0
        while true {
            if let stripped = stripLeadingBlockQuoteMarker(from: current) {
                depth += 1
                current = stripped
                continue
            }
            if let stripped = stripLeadingListItemMarker(from: current) {
                current = stripped
                continue
            }
            return depth
        }
    }

    private func projectedBlockQuoteLine(_ line: String, depth: Int) -> String {
        guard depth > 0 else {
            return line
        }

        var current = line
        for _ in 0..<depth {
            guard let stripped = stripLeadingBlockQuoteMarker(from: current) else {
                return current
            }
            current = stripped
        }
        return current
    }

    private func stripLeadingBlockQuoteMarker(from line: String) -> String? {
        var cursor = line.startIndex
        var leadingSpaces = 0
        while cursor < line.endIndex, line[cursor] == " ", leadingSpaces < 3 {
            leadingSpaces += 1
            cursor = line.index(after: cursor)
        }

        guard cursor < line.endIndex, line[cursor] == ">" else {
            return nil
        }

        cursor = line.index(after: cursor)
        if cursor < line.endIndex, line[cursor] == " " || line[cursor] == "\t" {
            cursor = line.index(after: cursor)
        }
        return String(line[cursor...])
    }

    private func stripLeadingListItemMarker(from line: String) -> String? {
        var cursor = line.startIndex
        var leadingSpaces = 0
        while cursor < line.endIndex, line[cursor] == " ", leadingSpaces < 3 {
            leadingSpaces += 1
            cursor = line.index(after: cursor)
        }

        guard cursor < line.endIndex else {
            return nil
        }

        if line[cursor] == "-" || line[cursor] == "+" || line[cursor] == "*" {
            let afterMarker = line.index(after: cursor)
            guard afterMarker < line.endIndex,
                  line[afterMarker] == " " || line[afterMarker] == "\t"
            else {
                return nil
            }
            return String(line[skipInlineSpaces(in: line[afterMarker...], from: afterMarker)...])
        }

        guard line[cursor].isNumber else {
            return nil
        }

        var digitCursor = cursor
        var digitCount = 0
        while digitCursor < line.endIndex, line[digitCursor].isNumber, digitCount < 9 {
            digitCount += 1
            digitCursor = line.index(after: digitCursor)
        }

        guard digitCount > 0,
              digitCursor < line.endIndex,
              line[digitCursor] == "." || line[digitCursor] == ")"
        else {
            return nil
        }

        let afterMarker = line.index(after: digitCursor)
        guard afterMarker < line.endIndex,
              line[afterMarker] == " " || line[afterMarker] == "\t"
        else {
            return nil
        }
        return String(line[skipInlineSpaces(in: line[afterMarker...], from: afterMarker)...])
    }

    private func referenceDefinitionContinuationContentStart(in line: String) -> String.Index? {
        var cursor = line.startIndex
        var sawIndent = false
        while cursor < line.endIndex,
              line[cursor] == " " || line[cursor] == "\t" {
            sawIndent = true
            cursor = line.index(after: cursor)
        }

        guard sawIndent, cursor < line.endIndex else {
            return nil
        }
        return cursor
    }

    private func referenceDefinitionRemainderHasDestination(_ remainder: Substring) -> Bool {
        var cursor = skipInlineSpaces(in: remainder, from: remainder.startIndex)
        guard cursor < remainder.endIndex else {
            return false
        }

        guard let destinationEnd = referenceDefinitionDestinationEnd(in: remainder, from: cursor) else {
            return false
        }

        cursor = skipInlineSpaces(in: remainder, from: destinationEnd)
        guard cursor < remainder.endIndex else {
            return true
        }

        guard let titleEnd = referenceDefinitionTitleEnd(in: remainder, from: cursor) else {
            return false
        }

        cursor = skipInlineSpaces(in: remainder, from: titleEnd)
        return cursor == remainder.endIndex
    }

    private func referenceDefinitionDestinationEnd(
        in remainder: Substring,
        from start: Substring.Index
    ) -> Substring.Index? {
        guard start < remainder.endIndex else {
            return nil
        }

        if remainder[start] == "<" {
            return angleReferenceDefinitionDestinationEnd(in: remainder, from: start)
        }

        var cursor = start
        var parenDepth = 0
        var sawContent = false

        while cursor < remainder.endIndex {
            let character = remainder[cursor]
            if character == " " || character == "\t" {
                break
            }
            if character == "<" || character.isNewline || isASCIIControl(character) {
                return nil
            }
            if character == "\\" {
                let next = remainder.index(after: cursor)
                guard next < remainder.endIndex,
                      !remainder[next].isNewline,
                      !isASCIIControl(remainder[next]),
                      remainder[next] != " ",
                      remainder[next] != "\t"
                else {
                    return nil
                }
                sawContent = true
                cursor = remainder.index(after: next)
                continue
            }
            if character == "(" {
                parenDepth += 1
            } else if character == ")" {
                guard parenDepth > 0 else {
                    return nil
                }
                parenDepth -= 1
            }
            sawContent = true
            cursor = remainder.index(after: cursor)
        }

        return sawContent && parenDepth == 0 ? cursor : nil
    }

    private func angleReferenceDefinitionDestinationEnd(
        in remainder: Substring,
        from start: Substring.Index
    ) -> Substring.Index? {
        var cursor = remainder.index(after: start)

        while cursor < remainder.endIndex {
            let character = remainder[cursor]
            if character == "\\" {
                let next = remainder.index(after: cursor)
                guard next < remainder.endIndex,
                      !remainder[next].isNewline
                else {
                    return nil
                }
                cursor = remainder.index(after: next)
                continue
            }
            if character == ">" {
                return remainder.index(after: cursor)
            }
            if character == "<" || character.isNewline {
                return nil
            }
            cursor = remainder.index(after: cursor)
        }

        return nil
    }

    private func referenceDefinitionTitleEnd(
        in remainder: Substring,
        from start: Substring.Index
    ) -> Substring.Index? {
        guard start < remainder.endIndex else {
            return nil
        }

        let opener = remainder[start]
        let closer: Character
        switch opener {
        case "\"", "'":
            closer = opener
        case "(":
            closer = ")"
        default:
            return nil
        }

        var cursor = remainder.index(after: start)
        while cursor < remainder.endIndex {
            if remainder[cursor] == "\\" {
                let next = remainder.index(after: cursor)
                guard next < remainder.endIndex else {
                    return nil
                }
                cursor = remainder.index(after: next)
                continue
            }

            if remainder[cursor] == closer {
                return remainder.index(after: cursor)
            }

            cursor = remainder.index(after: cursor)
        }

        return nil
    }

    private func skipInlineSpaces(
        in text: Substring,
        from start: Substring.Index
    ) -> Substring.Index {
        var cursor = start
        while cursor < text.endIndex,
              text[cursor] == " " || text[cursor] == "\t" {
            cursor = text.index(after: cursor)
        }
        return cursor
    }

    private func isASCIIControl(_ character: Character) -> Bool {
        guard character.unicodeScalars.count == 1,
              let scalar = character.unicodeScalars.first
        else {
            return false
        }

        return scalar.value < 0x20 || scalar.value == 0x7f
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
        if marker == "`", content.dropFirst(count).contains("`") {
            return nil
        }

        return MarkdownBoundaryFence(
            marker: marker,
            length: count,
            usesReferenceProjection: false,
            blockQuoteProjectionDepth: 0,
            opensAfterListProjection: false
        )
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

    private func blockStartLineText(_ line: String) -> String? {
        lineAfterAllowedFenceIndent(line).map(String.init)
    }

    private func opensHTMLBlock(_ line: String) -> MarkdownBoundaryHTMLBlock? {
        let lowercased = line.lowercased()

        if lowercased.hasPrefix("<!--") && !lowercased.contains("-->") {
            return MarkdownBoundaryHTMLBlock(
                closingToken: "-->",
                usesReferenceProjection: false,
                blockQuoteProjectionDepth: 0,
                opensAfterListProjection: false,
                terminatesOnBlankLine: false
            )
        }

        if lowercased.hasPrefix("<?") && !lowercased.contains("?>") {
            return MarkdownBoundaryHTMLBlock(
                closingToken: "?>",
                usesReferenceProjection: false,
                blockQuoteProjectionDepth: 0,
                opensAfterListProjection: false,
                terminatesOnBlankLine: false
            )
        }

        if lowercased.hasPrefix("<![cdata[") && !lowercased.contains("]]>") {
            return MarkdownBoundaryHTMLBlock(
                closingToken: "]]>",
                usesReferenceProjection: false,
                blockQuoteProjectionDepth: 0,
                opensAfterListProjection: false,
                terminatesOnBlankLine: false
            )
        }

        if opensHTMLDeclaration(lowercased) && !lowercased.contains(">") {
            return MarkdownBoundaryHTMLBlock(
                closingToken: ">",
                usesReferenceProjection: false,
                blockQuoteProjectionDepth: 0,
                opensAfterListProjection: false,
                terminatesOnBlankLine: false
            )
        }

        for tag in htmlRawTextTags {
            if startsHTMLTag(lowercased, tag: tag) && !lowercased.contains("</\(tag)>") {
                return MarkdownBoundaryHTMLBlock(
                    closingToken: "</\(tag)>",
                    usesReferenceProjection: false,
                    blockQuoteProjectionDepth: 0,
                    opensAfterListProjection: false,
                    terminatesOnBlankLine: false
                )
            }
        }

        for tag in htmlBlankLineTerminatedTags {
            if startsHTMLTag(lowercased, tag: tag) && !lowercased.contains("</\(tag)>") {
                return MarkdownBoundaryHTMLBlock(
                    closingToken: "</\(tag)>",
                    usesReferenceProjection: false,
                    blockQuoteProjectionDepth: 0,
                    opensAfterListProjection: false,
                    terminatesOnBlankLine: true
                )
            }
        }

        return nil
    }

    private var htmlRawTextTags: [String] {
        ["pre", "script", "style"]
    }

    private var htmlBlankLineTerminatedTags: [String] {
        [
            "address", "article", "aside", "blockquote", "body", "caption", "center",
            "colgroup", "dd", "details", "dialog", "dir", "div", "dl", "dt",
            "fieldset", "figcaption", "figure", "footer", "form", "frame", "frameset",
            "h1", "h2", "h3", "h4", "h5", "h6", "head", "header", "html", "iframe",
            "legend", "li", "main", "menu", "menuitem", "nav", "noframes", "ol",
            "optgroup", "option", "p", "section", "summary",
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

    private func closesHTMLBlock(
        _ normalizedLine: String,
        trimmed: String,
        html: MarkdownBoundaryHTMLBlock
    ) -> Bool {
        if html.usesReferenceProjection {
            let projectedLine = projectedBlockQuoteLine(normalizedLine, depth: html.blockQuoteProjectionDepth)
            if html.opensAfterListProjection,
               stripLeadingListItemMarker(from: projectedLine) != nil {
                return false
            }
            return closesHTMLBlock(trimmed, token: html.closingToken) ||
                closesHTMLBlock(
                    projectedLine.trimmingCharacters(in: .whitespaces),
                    token: html.closingToken
                )
        }

        return closesHTMLBlock(trimmed, token: html.closingToken)
    }

    private func isHTMLTerminatingBlankLine(
        _ normalizedLine: String,
        trimmed: String,
        html: MarkdownBoundaryHTMLBlock
    ) -> Bool {
        if trimmed.isEmpty {
            return true
        }

        guard html.usesReferenceProjection else {
            return false
        }

        let projectedLine = projectedBlockQuoteLine(normalizedLine, depth: html.blockQuoteProjectionDepth)
        if html.opensAfterListProjection,
           stripLeadingListItemMarker(from: projectedLine) != nil {
            return false
        }
        return projectedLine.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func closesHTMLBlock(_ line: String, token: String) -> Bool {
        line.lowercased().contains(token)
    }

    private func opensDisplayMath(_ line: String) -> Bool {
        line == "\\["
    }

    private func closesDisplayMath(_ line: String) -> Bool {
        line == "\\]"
    }

    private func opensMathEnvironment(_ line: String?) -> Bool {
        guard let line else { return false }
        return line.contains("\\begin{") && !line.contains("\\end{")
    }

    private func closesMathEnvironment(_ line: String) -> Bool {
        line.contains("\\end{")
    }

    private func isListLike(_ line: String) -> Bool {
        if let first = line.first,
           first == "-" || first == "*" || first == "+" {
            let next = line.index(after: line.startIndex)
            return next < line.endIndex && isListMarkerSpacing(line[next])
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
        return next < line.endIndex && isListMarkerSpacing(line[next])
    }

    private func isListMarkerSpacing(_ character: Character) -> Bool {
        character == " " || character == "\t"
    }

    private func isIndentedListContinuationLine(_ line: String) -> Bool {
        guard let first = line.first else {
            return false
        }

        return first == " " || first == "\t"
    }

    private func normalizedLineText(_ line: String) -> String {
        if line.last == "\r" {
            return String(line.dropLast())
        }
        return line
    }

    private func isSchemeContinuation(_ character: Character) -> Bool {
        isASCIILetter(character) ||
            isASCIIDigit(character) ||
            character == "+" ||
            character == "-" ||
            character == "."
    }

    private func isASCIILetter(_ character: Character) -> Bool {
        guard let value = asciiValue(of: character) else {
            return false
        }

        return (65...90).contains(value) || (97...122).contains(value)
    }

    private func isASCIIDigit(_ character: Character) -> Bool {
        guard let value = asciiValue(of: character) else {
            return false
        }

        return (48...57).contains(value)
    }

    private func asciiValue(of character: Character) -> UInt32? {
        guard character.unicodeScalars.count == 1,
              let value = character.unicodeScalars.first?.value,
              value <= 127
        else {
            return nil
        }

        return value
    }
}
