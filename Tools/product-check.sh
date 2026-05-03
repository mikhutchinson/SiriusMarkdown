#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

bash Tools/release-check.sh
swift test --filter MarkdownRenderSession
swift test --filter MarkdownSelection
SIRIUS_MARKDOWN_PRODUCT_CHECK=1 swift test --filter Product
SIRIUS_MARKDOWN_RENDER_PROBE_OUTPUT="${TMPDIR:-/tmp}/SiriusMarkdownProductProbe.png" \
SIRIUS_MARKDOWN_CODE_HIGHLIGHT_PROBE_OUTPUT="${TMPDIR:-/tmp}/SiriusMarkdownCodeHighlightProbe.png" \
SIRIUS_MARKDOWN_RESIZE_PROBE_OUTPUT="${TMPDIR:-/tmp}/SiriusMarkdownResizeProbe.png" \
  swift run --package-path Tools/RenderProbe SiriusMarkdownRenderProbe

echo "SiriusMarkdown product check passed."
