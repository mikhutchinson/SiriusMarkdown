#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

swift run --package-path Tools/RenderProbe SiriusMarkdownRenderProbe
swift test
swift test list | wc -l
swift build
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
  --fallback-bundle-version 0.4.14 \
  --output-path /tmp/SiriusMarkdown.doccarchive
