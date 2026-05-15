#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

swift run --package-path Tools/RenderProbe SiriusMarkdownRenderProbe
swift test --parallel --num-workers 1
TEST_LIST_FILE="$(mktemp)"
trap 'rm -f "$TEST_LIST_FILE"; rm -rf "${CONSUMER_DIR:-}"' EXIT
swift test list > "$TEST_LIST_FILE"
TEST_COUNT="$(grep -Ec '^[A-Za-z0-9_]+Tests\.' "$TEST_LIST_FILE")"
MINIMUM_TEST_COUNT=223
if (( TEST_COUNT < MINIMUM_TEST_COUNT )); then
  echo "error: swift test list discovered $TEST_COUNT tests; expected at least $MINIMUM_TEST_COUNT" >&2
  exit 1
fi
for required_test in \
  "SiriusMarkdownCoreTests.scannerTreatsCRLFBlankLinesLikeLF()" \
  "SiriusMarkdownCoreTests.scannerTreatsCRLFFencesMathAndHTMLLikeLF()" \
  "SiriusMarkdownCoreTests.crlfStreamedParseMatchesStaticParse()" \
  "SiriusMarkdownCoreTests.defaultPolicyRejectsUnsafeLinkSchemes()" \
  "SiriusMarkdownSwiftUITests.documentSelectionDefaultsToEnabledWhileNativeSelectionStaysLeafCompatibilityKnob()" \
  "SiriusMarkdownSwiftUITests.MarkdownNativeTextSelectionAppKitTests/defaultDocumentSelectionResolvesWrappedLineDragToExactSourceOnMacOS()" \
  "SiriusMarkdownSwiftUITests.MarkdownNativeTextSelectionAppKitTests/defaultDocumentSelectionResolvesDragAndCmdCCopyAcrossBlockBoundariesOnMacOS()" \
  "SiriusMarkdownSwiftUITests.MarkdownSelectionControllerCopiesExactPartialAndNonContiguousSourceRanges()" \
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
  --fallback-bundle-version 0.4.15 \
  --output-path /tmp/SiriusMarkdown.doccarchive
