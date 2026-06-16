#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

swift package clean
swift package --package-path Tools/RenderProbe clean
swift run --package-path Tools/RenderProbe SiriusMarkdownRenderProbe
swift test --no-parallel
TEST_LIST_FILE="$(mktemp)"
trap 'rm -f "$TEST_LIST_FILE"; rm -rf "${CONSUMER_DIR:-}"' EXIT
swift test list > "$TEST_LIST_FILE"
TEST_COUNT="$(grep -Ec '^[A-Za-z0-9_]+Tests\.' "$TEST_LIST_FILE")"
MINIMUM_TEST_COUNT=518
if (( TEST_COUNT < MINIMUM_TEST_COUNT )); then
  echo "error: swift test list discovered $TEST_COUNT tests; expected at least $MINIMUM_TEST_COUNT" >&2
  exit 1
fi
for required_test in \
  "SiriusMarkdownCoreTests.blankLineGapExactReturnsNilNearestReturnsFollowingBlock()" \
  "SiriusMarkdownCoreTests.activeTailAppendKeepsRevealTargetStable()" \
  "SiriusMarkdownCoreTests.lookupMapsMultilineParagraphHeadingListCodeAndTable()" \
  "SiriusMarkdownSwiftUITests.preparedSnapshotForwardsSourceLookupWithoutPreparingAgain()" \
  "SiriusMarkdownSwiftUITests.renderSessionLookupUpdatesAfterAppendAndReset()" \
  "SiriusMarkdownSwiftUITests.renderSessionCoalescesAppendBurstBeforePreparing()" \
  "SiriusMarkdownSwiftUITests.renderSessionReusesPreparedLongTranscriptBeyondCacheCapacity()" \
  "SiriusMarkdownSwiftUITests.renderSessionCoalescingPreservesHostBoundaryOrdering()" \
  "SiriusMarkdownSwiftUITests.preparedTableCurrencyAmountsRemainText()" \
  "SiriusMarkdownSwiftUITests.wideCodeBlockHostedFittingWidthStaysWithinHostColumn()" \
  "SiriusMarkdownSwiftUITests.selectionControllerSelectSourceLineHighlightsResolvedBlock()" \
  "SiriusMarkdownSwiftUITests.selectionControllerSelectSourceRangeUsesNearestFallbackInGap()" \
  "SiriusMarkdownCoreTests.firstBlockIDFallsBackToNearestBlockByByteOffsetWhenLineRangeIsEmpty()" \
  "SiriusMarkdownCoreTests.scannerDoesNotCloseTopLevelCodeFenceWithContainerLookingContent()" \
  "SiriusMarkdownCoreTests.scannerDoesNotCloseTopLevelDollarMathFenceWithContainerLookingContent()" \
  "SiriusMarkdownCoreTests.scannerDoesNotCloseContainerCodeFenceWithNestedContainerLookingContent()" \
  "SiriusMarkdownCoreTests.scannerDoesNotCloseContainerDollarMathFenceWithNestedContainerLookingContent()" \
  "SiriusMarkdownCoreTests.scannerDoesNotSealOpenBlockQuoteCodeFence()" \
  "SiriusMarkdownCoreTests.scannerDoesNotSealOpenListCodeFence()" \
  "SiriusMarkdownCoreTests.scannerSealsClosedContainerCodeFences()" \
  "SiriusMarkdownCoreTests.scannerSealsBacktickFenceLineWithBacktickInfoAsParagraph()" \
  "SiriusMarkdownCoreTests.scannerTreatsCRLFBlankLinesLikeLF()" \
  "SiriusMarkdownCoreTests.scannerTreatsCRLFFencesMathAndHTMLLikeLF()" \
  "SiriusMarkdownCoreTests.scannerDoesNotCloseListProjectedHTMLBlockWithNestedListLookingContent()" \
  "SiriusMarkdownCoreTests.crlfStreamedParseMatchesStaticParse()" \
  "SiriusMarkdownCoreTests.streamedTabDelimitedLooseListsMatchOneShotParse()" \
  "SiriusMarkdownCoreTests.streamedLooseListsWithContinuationLinesMatchOneShotParse()" \
  "SiriusMarkdownCoreTests.streamedListContainedBlocksWaitForIndentedContinuationAfterBlankLine()" \
  "SiriusMarkdownCoreTests.streamedTopLevelFencesIgnoreContainerLookingContentClosers()" \
  "SiriusMarkdownCoreTests.streamedContainerFencesIgnoreNestedContainerLookingContentClosers()" \
  "SiriusMarkdownCoreTests.streamedContainerHTMLBlocksMatchOneShotWithNestedContainerLookingClosers()" \
  "SiriusMarkdownCoreTests.streamedContainerCodeFenceWaitsForClosingFenceAfterBlankLine()" \
  "SiriusMarkdownCoreTests.backtickFenceLineWithBacktickInfoSealsAsNormalParagraph()" \
  "SiriusMarkdownCoreTests.scannerDoesNotSealOpenDisplayMathBracketFence()" \
  "SiriusMarkdownCoreTests.scannerDoesNotSealOpenBlockQuoteDisplayMathBracketFence()" \
  "SiriusMarkdownCoreTests.scannerDoesNotSealOpenListDisplayMathBracketFence()" \
  "SiriusMarkdownCoreTests.scannerDoesNotSealOpenContainerDollarMathFence()" \
  "SiriusMarkdownCoreTests.scannerSealsClosedContainerDisplayMathFences()" \
  "SiriusMarkdownCoreTests.scannerDoesNotCloseBracketDisplayMathFenceWithContainerLookingContent()" \
  "SiriusMarkdownCoreTests.streamedBracketDisplayMathFencesIgnoreContainerLookingContentClosers()" \
  "SiriusMarkdownCoreTests.scannerSealsEscapedDisplayMathDelimiterInProse()" \
  "SiriusMarkdownCoreTests.escapedDisplayMathDelimiterInProseSealsAsNormalParagraph()" \
  "SiriusMarkdownCoreTests.scannerSealsLineStartingWithNonDelimiterBracketDisplayMathText()" \
  "SiriusMarkdownCoreTests.lineStartingWithNonDelimiterBracketDisplayMathTextSealsAsNormalParagraph()" \
  "SiriusMarkdownCoreTests.scannerSealsFourSpaceIndentedMathOpenersAsCodeBlocks()" \
  "SiriusMarkdownCoreTests.fourSpaceIndentedMathOpenersSealAsCodeBlocks()" \
  "SiriusMarkdownCoreTests.streamedContainerDisplayMathWaitsForClosingFenceAfterBlankLine()" \
  "SiriusMarkdownCoreTests.copiedStreamsDoNotShareBoundaryScanState()" \
  "SiriusMarkdownCoreTests.defaultPolicyRejectsUnsafeLinkSchemes()" \
  "SiriusMarkdownCoreTests.defaultPolicyRejectsControlCharacterLinkDestinations()" \
  "SiriusMarkdownCoreTests.defaultPolicyRejectsMalformedAbsoluteLinkDestinations()" \
  "SiriusMarkdownCoreTests.defaultPolicyRejectsAmbiguousHTTPDestinations()" \
  "SiriusMarkdownCoreTests.defaultPolicyRejectsPercentEncodedHTTPDelimiterSmuggling()" \
  "SiriusMarkdownCoreTests.defaultPolicyRejectsAmbiguousMailtoDestinations()" \
  "SiriusMarkdownCoreTests.defaultPolicyRejectsEncodedMailtoQuerySeparators()" \
  "SiriusMarkdownCoreTests.defaultPolicyRejectsAmbiguousRelativeDestinations()" \
  "SiriusMarkdownCoreTests.defaultPolicyRejectsRelativeBackslashDestinations()" \
  "SiriusMarkdownCoreTests.defaultPolicyRejectsPercentEncodedAbsoluteRelativeDestinations()" \
  "SiriusMarkdownCoreTests.defaultPolicyRejectsHTMLEntityEncodedAbsoluteRelativeDestinations()" \
  "SiriusMarkdownCoreTests.scannerKeepsReferenceLinkCandidatesMutableUntilFinish()" \
  "SiriusMarkdownCoreTests.scannerSealsCheckedTaskListMarkerAfterSecondBlankLine()" \
  "SiriusMarkdownCoreTests.scannerKeepsProjectedNonTaskXReferenceMutableUntilDefinition()" \
  "SiriusMarkdownCoreTests.scannerSealsLiteralUnmatchedBracketAfterParagraphBoundary()" \
  "SiriusMarkdownCoreTests.scannerRecoversLiteralUnmatchedBracketAcrossIncrementalScans()" \
  "SiriusMarkdownCoreTests.scannerKeepsShortcutReferenceLabelNamedXMutableUntilDefinition()" \
  "SiriusMarkdownCoreTests.scannerSealsEscapedReferenceLabelInProse()" \
  "SiriusMarkdownCoreTests.scannerSealsReferenceLikeTextInsideInlineCodeSpan()" \
  "SiriusMarkdownCoreTests.scannerSealsReferenceLikeTextInsideMultilineInlineCodeSpan()" \
  "SiriusMarkdownCoreTests.scannerDoesNotCarryOpenInlineCodeSpanAcrossBlankLine()" \
  "SiriusMarkdownCoreTests.scannerKeepsReferenceAfterUnclosedInlineCodeOpenerMutableUntilDefinition()" \
  "SiriusMarkdownCoreTests.scannerKeepsNestedBracketInlineLinkLabelMutableUntilReferencesAreKnown()" \
  "SiriusMarkdownCoreTests.scannerSealsReferenceLikeTextInsideInlineLinkDestinationAndTitle()" \
  "SiriusMarkdownCoreTests.scannerSealsReferenceLikeTextInsideInlineAngleConstructs()" \
  "SiriusMarkdownCoreTests.scannerSealsReferenceLikeTextInsideInlineHTMLSpecialForms()" \
  "SiriusMarkdownCoreTests.scannerKeepsReferenceLikeTextInsideInlineCDATAConstructMutable()" \
  "SiriusMarkdownCoreTests.scannerKeepsReferenceLikeTextInsideMalformedInlineAngleConstructMutable()" \
  "SiriusMarkdownCoreTests.scannerKeepsReferenceLikeTextInsidePlainAngleProseMutable()" \
  "SiriusMarkdownCoreTests.scannerKeepsReferenceLikeTextInsideInvalidAutolinkSchemeMutable()" \
  "SiriusMarkdownCoreTests.scannerKeepsReferenceLikeTextInsideMalformedInlineLinkMutable()" \
  "SiriusMarkdownCoreTests.scannerKeepsMultilineShortcutAndCollapsedReferenceLabelsMutable()" \
  "SiriusMarkdownCoreTests.scannerKeepsReferenceAfterEscapedBacktickMutableUntilDefinition()" \
  "SiriusMarkdownCoreTests.scannerSealsReferenceCandidateAfterMatchingDefinitionArrives()" \
  "SiriusMarkdownCoreTests.scannerKeepsReferenceDefinitionOpenUntilContinuationBlank()" \
  "SiriusMarkdownCoreTests.scannerAcceptsTabIndentedReferenceDefinitionContinuation()" \
  "SiriusMarkdownCoreTests.scannerAcceptsContainerReferenceDefinitions()" \
  "SiriusMarkdownCoreTests.scannerAcceptsMultilineReferenceDefinitionLabels()" \
  "SiriusMarkdownCoreTests.scannerDoesNotTreatFourSpaceIndentedReferenceLikeDefinition()" \
  "SiriusMarkdownCoreTests.scannerSealsBlankLineTerminatedHTMLBlocksOnBlankLine()" \
  "SiriusMarkdownCoreTests.scannerDoesNotCloseBlankLineTerminatedHTMLBlocksOnClosingTag()" \
  "SiriusMarkdownCoreTests.blankLineTerminatedHTMLBlocksSealLikeOneShot()" \
  "SiriusMarkdownCoreTests.blankLineTerminatedHTMLBlocksDoNotLeakDefinitionsAfterClosingTags()" \
  "SiriusMarkdownCoreTests.scannerSealsFourSpaceIndentedHTMLOpenersAsCodeBlocks()" \
  "SiriusMarkdownCoreTests.fourSpaceIndentedHTMLOpenersSealAsCodeBlocks()" \
  "SiriusMarkdownCoreTests.streamedReferenceDefinitionsResolveLaterReferencesLikeWholeDocument()" \
  "SiriusMarkdownCoreTests.hostBoundaryPreservesMultilineReferenceDefinitionLabelsForLaterTail()" \
  "SiriusMarkdownCoreTests.streamedReferenceDefinitionsIgnoreFencedCodeDefinitionsLikeWholeDocument()" \
  "SiriusMarkdownCoreTests.streamedReferenceDefinitionsIgnoreHTMLDefinitionsLikeWholeDocument()" \
  "SiriusMarkdownCoreTests.containerHTMLBlocksDoNotLeakDefinitionsIntoReferencePrefix()" \
  "SiriusMarkdownCoreTests.streamedReferenceDefinitionsIgnoreMathDefinitionsLikeWholeDocument()" \
  "SiriusMarkdownCoreTests.streamedReferenceDefinitionsIgnoreContainerDisplayMathDefinitionsLikeWholeDocument()" \
  "SiriusMarkdownCoreTests.streamedReferenceDefinitionsIgnoreContainerParagraphTextDefinitionsLikeWholeDocument()" \
  "SiriusMarkdownCoreTests.streamedReferenceCandidatesSealAfterMatchingDefinitionArrives()" \
  "SiriusMarkdownCoreTests.streamedReferenceDefinitionDestinationContinuationResolvesLikeWholeDocument()" \
  "SiriusMarkdownCoreTests.streamedReferenceDefinitionTitleContinuationResolvesLikeWholeDocument()" \
  "SiriusMarkdownCoreTests.sealedReferenceDefinitionContinuationResolvesLaterReferences()" \
  "SiriusMarkdownCoreTests.hostBoundaryPreservesSealedReferenceDefinitionsForLaterTail()" \
  "SiriusMarkdownCoreTests.streamedShortcutReferenceLabelNamedXResolvesLikeWholeDocument()" \
  "SiriusMarkdownCoreTests.streamedReferenceAfterEscapedBacktickResolvesLikeWholeDocument()" \
  "SiriusMarkdownCoreTests.streamedReferenceAfterBlankLineInsideUnclosedCodeSpanResolvesLikeWholeDocument()" \
  "SiriusMarkdownCoreTests.streamedReferenceAfterUnclosedInlineCodeOpenerResolvesLikeWholeDocument()" \
  "SiriusMarkdownCoreTests.streamedReferenceInsideInvalidAutolinkSchemeResolvesLikeWholeDocument()" \
  "SiriusMarkdownCoreTests.streamedMultilineShortcutReferenceLabelResolvesLikeWholeDocument()" \
  "SiriusMarkdownCoreTests.streamedMultilineCollapsedReferenceLabelResolvesLikeWholeDocument()" \
  "SiriusMarkdownCoreTests.streamedMultilineExplicitReferenceLabelResolvesLikeWholeDocument()" \
  "SiriusMarkdownCoreTests.streamedReferenceIgnoresFourSpaceIndentedCodeDefinitionLikeWholeDocument()" \
  "SiriusMarkdownCoreTests.streamedMalformedReferenceDefinitionDoesNotMaskLaterValidDefinition()" \
  "SiriusMarkdownCoreTests.streamedNoDestinationReferenceDefinitionDoesNotBorrowSiblingDefinitionDestination()" \
  "SiriusMarkdownCoreTests.escapedReferenceLabelInProseSealsAsNormalParagraph()" \
  "SiriusMarkdownCoreTests.inlineCodeReferenceSyntaxSealsAsNormalParagraph()" \
  "SiriusMarkdownCoreTests.multilineInlineCodeReferenceSyntaxSealsAsNormalParagraph()" \
  "SiriusMarkdownCoreTests.nestedBracketInlineLinkLabelStaysMutableUntilReferencesAreKnown()" \
  "SiriusMarkdownCoreTests.checkedTaskListItemSealsAfterSecondBlankLineWithoutReferenceDefinition()" \
  "SiriusMarkdownCoreTests.inlineLinkDestinationReferenceSyntaxSealsAsNormalParagraph()" \
  "SiriusMarkdownCoreTests.inlineAngleReferenceSyntaxSealsAsNormalParagraph()" \
  "SiriusMarkdownCoreTests.inlineHTMLSpecialFormReferenceSyntaxSealsAsNormalParagraph()" \
  "SiriusMarkdownCoreTests.inlineCDATAReferenceSyntaxResolvesLikeWholeDocument()" \
  "SiriusMarkdownCoreTests.scannerGeneratedInlineReferenceCasesDoNotSealBeforeOneShotReferenceResolution()" \
  "SiriusMarkdownCoreTests.scannerGeneratedInlineReferenceContextMatrixDoesNotSealBeforeOneShotReferenceResolution()" \
  "SiriusMarkdownCoreTests.streamedGeneratedReferenceDefinitionCasesMatchOneShotResolution()" \
  "SiriusMarkdownCoreTests.hostBoundaryGeneratedReferenceDefinitionCasesMatchOneShotLaterReference()" \
  "SiriusMarkdownCoreTests.streamedFollowingLineBlockConstructsMatchOneShotAcrossChunking()" \
  "SiriusMarkdownCoreTests.streamedContainerReferenceDefinitionsAfterContainerTextMatchOneShotAcrossChunking()" \
  "SiriusMarkdownCoreTests.streamedStructuredBlockReferenceCandidatesMatchOneShotAcrossChunking()" \
  "SiriusMarkdownCoreTests.streamedGeneratedReferenceDocumentsMatchOneShotAcrossChunkSizes()" \
  "SiriusMarkdownCoreTests.streamedGeneratedReferenceDefinitionDestinationTitleEdgesMatchOneShotAcrossChunkSizes()" \
  "SiriusMarkdownCoreTests.streamedReferenceLinksResolveLikeWholeDocument()" \
  "SiriusMarkdownCoreTests.parserClassifiesOrderedTaskListFromASTCheckboxes()" \
  "SiriusMarkdownCoreTests.parserClassifiesNestedOrderedTaskListMetadataFromASTCheckboxes()" \
  "SiriusMarkdownCoreTests.parserPreservesNestedInlinePresentationAndLinks()" \
  "SiriusMarkdownCoreTests.parserPreservesLinkDestinationAcrossInlineBreaks()" \
  "SiriusMarkdownCoreTests.parserPreservesLinkedImagePresentationAndLinkDestination()" \
  "SiriusMarkdownCoreTests.parserDoesNotDropStructuredChildrenInsideBlockQuotesAndListItems()" \
  "SiriusMarkdownCoreTests.escapedParenInlineMathIsDetectedInPlainTextNodes()" \
  "SiriusMarkdownCoreTests.escapedBackslashBeforeParenDoesNotStartInlineMath()" \
  "SiriusMarkdownCoreTests.escapedBackslashBeforeDollarStillAllowsDollarMath()" \
  "SiriusMarkdownCoreTests.currencyRangesDoNotBecomeInlineMath()" \
  "SiriusMarkdownCoreTests.tableCurrencyAmountsDoNotBecomeInlineMath()" \
  "SiriusMarkdownCoreTests.dollarMathMayStartWithANumber()" \
  "SiriusMarkdownCoreTests.currencyLikeDollarRunsDoNotBecomeInlineMath()" \
  "SiriusMarkdownCoreTests.compactISOCurrencyCodesDoNotBecomeInlineMath()" \
  "SiriusMarkdownCoreTests.numericLeadingDollarMathParsesWhenFormulaLike()" \
  "SiriusMarkdownCoreTests.inlineMathKeepsPresentationAndLinkContext()" \
  "SiriusMarkdownCoreTests.styledAndLinkedCurrencyDoesNotBecomeInlineMath()" \
  "SiriusMarkdownCoreTests.codeSpansDoNotParseLatexOrDollarDelimiters()" \
  "SiriusMarkdownCoreTests.inlineSourceRangesRemainByteAccurateAfterMultibytePrefixes()" \
  "SiriusMarkdownCoreTests.tailInlineSourceRangesRemainByteAccurateAfterSealedReferencePrefix()" \
  "SiriusMarkdownCoreTests.paragraphEmbeddedDisplayMathPreservesReferenceLinkSemantics()" \
  "SiriusMarkdownCoreTests.displayMathInsideBlockQuoteProducesMathRun()" \
  "SiriusMarkdownCoreTests.displayMathInsideBlockQuotePreservesRawTexSource()" \
  "SiriusMarkdownCoreTests.displayMathInsideListItemProducesMathRun()" \
  "SiriusMarkdownCoreTests.linkedLiteralDisplayMathDelimiterDoesNotCoalesceAcrossFollowingLines()" \
  "SiriusMarkdownCoreTests.degradedBareDisplayBracketsWithLatexContentParseAsMathBlock()" \
  "SiriusMarkdownCoreTests.singleLineDollarDisplayMathBetweenProseSplitsIntoMathBlock()" \
  "SiriusMarkdownCoreTests.singleLineBracketDisplayMathBetweenProseSplitsIntoMathBlock()" \
  "SiriusMarkdownCoreTests.bareTexCommandsInProseBecomeMathRuns()" \
  "SiriusMarkdownCoreTests.adjacentBareTexCommandsStayTogetherWithoutEatingProse()" \
  "SiriusMarkdownCoreTests.bareTexRecoveryDoesNotRewritePathsUnknownCommandsOrEscapedMarkdown()" \
  "SiriusMarkdownMathTests.paragraphEmbeddedDisplayMathPreparesTypesetImage()" \
  "SiriusMarkdownMathTests.degradedBareDisplayBracketMathPreparesTypesetImage()" \
  "SiriusMarkdownSwiftUITests.documentSelectionDefaultsToEnabledWhileNativeSelectionStaysLeafCompatibilityKnob()" \
  "SiriusMarkdownSwiftUITests.renderSessionResetSuppressesStaleQueuedAppendPublication()" \
  "SiriusMarkdownSwiftUITests.MarkdownNativeTextSelectionAppKitTests/defaultDocumentSelectionResolvesWrappedLineDragToExactSourceOnMacOS()" \
  "SiriusMarkdownSwiftUITests.MarkdownNativeTextSelectionAppKitTests/defaultDocumentSelectionResolvesDragAndCmdCCopyAcrossBlockBoundariesOnMacOS()" \
  "SiriusMarkdownSwiftUITests.MarkdownNativeTextSelectionAppKitTests/defaultDocumentSelectionReceivesTextLeafFragmentForImageBackedInlineMath()" \
  "SiriusMarkdownSwiftUITests.MarkdownSelectionPerformanceTests/enabledDocumentSelectionHostLayoutStormDoesNotRebuildLineSelectionGeometryAfterWarmup()" \
  "SiriusMarkdownSwiftUITests.MarkdownSelectionPerformanceTests/sameRectRepeatedSelectionPreferenceResolutionDoesNotRebuildLineSelectionGeometry()" \
  "SiriusMarkdownSwiftUITests.MarkdownSelectionControllerCopiesExactPartialAndNonContiguousSourceRanges()" \
  "SiriusMarkdownSwiftUITests.MarkdownSelectionControllerPlainTextFallbackRespectsSelectedSourceRanges()" \
  "SiriusMarkdownSwiftUITests.MarkdownSelectionControllerKeepsRangeIntentAcrossSnapshotUpdates()" \
  "SiriusMarkdownSwiftUITests.MarkdownSelectionControllerSelectAllTracksAppendedDocument()" \
  "SiriusMarkdownSwiftUITests.selectionSourceRunSnapsAtomicRunsToSourceBoundaries()" \
  "SiriusMarkdownSwiftUITests.defaultJavaScriptResourceLoadingUsesNonTrappingLookup()" \
  "SiriusMarkdownSwiftUITests.preparedImageSelectionSourceRunIsAtomic()" \
  "SiriusMarkdownSwiftUITests.deniedPreparedImagesDoNotInvokeResolver()" \
  "SiriusMarkdownSwiftUITests.preparedImagePolicyEvaluatesOncePerSourceBackedRun()" \
  "SiriusMarkdownSwiftUITests.deniedPreparedImageCacheDoesNotRequireResolverIdentity()" \
  "SiriusMarkdownSwiftUITests.imageOnlyInlineCacheDoesNotRequireLinkPolicyIdentity()" \
  "SiriusMarkdownSwiftUITests.sourcelessImageInlineCacheDoesNotRequireImagePolicyIdentity()" \
  "SiriusMarkdownSwiftUITests.preparedInlineLinksUsePolicyNormalizedDestinations()" \
  "SiriusMarkdownSwiftUITests.deniedInlineMathCacheDoesNotRequireRendererIdentity()" \
  "SiriusMarkdownSwiftUITests.bareTexInlineMathPreparationUsesConfiguredImageRenderer()" \
  "SiriusMarkdownSwiftUITests.ProductDefaultCodeHighlighterHandlesLongSwiftStringLiteralsWithoutCrashing()" \
  "SiriusMarkdownSwiftUITests.ProductDefaultSwiftCodeHighlighterKeepsNestedInterpolationStringsColored()" \
  "SiriusMarkdownSwiftUITests.ProductDefaultSwiftCodeHighlighterRecognizesModernSwiftKeywords()" \
  "SiriusMarkdownSwiftUITests.imageBackedInlineMathPreparationDoesNotCallRenderedFallback()" \
  "SiriusMarkdownSwiftUITests.imageBackedInlineMathTextUsesConfiguredLinkAction()" \
  "SiriusMarkdownSwiftUITests.MarkdownNativeTextSelectionAppKitTests/defaultDocumentSelectionEmitsPreciseCodeBlockTextFragmentsOnMacOS()" \
  "SiriusMarkdownSwiftUITests.MarkdownNativeTextSelectionAppKitTests/defaultDocumentSelectionEmitsPreciseTextMathBlockFragmentsOnMacOS()" \
  "SiriusMarkdownSwiftUITests.MarkdownNativeTextSelectionAppKitTests/defaultDocumentSelectionEmitsPreciseAllowedHTMLBlockFragmentsOnMacOS()" \
  "SiriusMarkdownCoreTests.sourceBufferDecodesMultiChunkUnicodeSliceAsSingleUTF8Stream()" \
  "SiriusMarkdownCoreTests.sourceBufferDecodesLinesAcrossChunkBoundariesWithoutLineCopies()" \
  "SiriusMarkdownSwiftUITests.unpreparedSnapshotStillEnforcesBlockPoliciesWithoutPreparing()" \
  "SiriusMarkdownSwiftUITests.blockRenderPlanEvaluatesMathAndHTMLPoliciesOnce()"
do
  if ! grep -Fxq "$required_test" "$TEST_LIST_FILE"; then
    echo "error: required test is missing from swift test list: $required_test" >&2
    exit 1
  fi
done
echo "swift test list discovered $TEST_COUNT tests"
swift build
CONSUMER_DIR="$(mktemp -d)"
mkdir -p "$CONSUMER_DIR/Sources/SiriusMarkdownConsumer"
cat > "$CONSUMER_DIR/Package.swift" <<EOF
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SiriusMarkdownConsumer",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(path: "$ROOT_DIR")
    ],
    targets: [
        .executableTarget(
            name: "SiriusMarkdownConsumer",
            dependencies: [
                .product(name: "SiriusMarkdown", package: "SiriusMarkdown")
            ]
        )
    ]
)
EOF
cat > "$CONSUMER_DIR/Sources/SiriusMarkdownConsumer/main.swift" <<'EOF'
import SiriusMarkdown

var stream = MarkdownStream()
stream.append("# Consumer\n\nPackage resolution works.\n")
stream.finish()
let configuration = MarkdownRendererConfiguration.document
let prepared = configuration.prepare(snapshot: stream.snapshot())
precondition(prepared.snapshot.blocks.count == 2)
EOF
swift package --package-path "$CONSUMER_DIR" resolve
swift build --package-path "$CONSUMER_DIR"
bash Examples/scripts/bundle-macos-demos.sh
npm --prefix Tools/pretext-golden ci
npm --prefix Tools/pretext-golden test
swift package dump-symbol-graph
SYMBOL_GRAPH_DIR="$(find .build -type d -name symbolgraph -print -quit)"
if [[ -z "$SYMBOL_GRAPH_DIR" ]]; then
  echo "error: symbol graph directory was not generated" >&2
  exit 1
fi
rm -rf /tmp/SiriusMarkdown.doccarchive
xcrun docc convert Docs/SiriusMarkdown.docc \
  --additional-symbol-graph-dir "$SYMBOL_GRAPH_DIR" \
  --fallback-display-name SiriusMarkdown \
  --fallback-bundle-identifier com.sirius.markdown \
  --fallback-bundle-version 0.5.10 \
  --output-path /tmp/SiriusMarkdown.doccarchive
