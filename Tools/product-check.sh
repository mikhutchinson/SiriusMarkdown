#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

bash Tools/release-check.sh
swift test --filter MarkdownRenderSession
swift test --filter MarkdownSelection
SIRIUS_MARKDOWN_PRODUCT_CHECK=1 swift test --filter Product
if [[ "${SIRIUS_MARKDOWN_RUN_VISUAL_PROBES:-0}" == "1" ]]; then
  SIRIUS_MARKDOWN_RENDER_PROBE_OUTPUT="${TMPDIR:-/tmp}/SiriusMarkdownProductProbe.png" \
  SIRIUS_MARKDOWN_CODE_HIGHLIGHT_PROBE_OUTPUT="${TMPDIR:-/tmp}/SiriusMarkdownCodeHighlightProbe.png" \
  SIRIUS_MARKDOWN_RESIZE_PROBE_OUTPUT="${TMPDIR:-/tmp}/SiriusMarkdownResizeProbe.png" \
  SIRIUS_MARKDOWN_SELECTION_STRESS_PROBE_OUTPUT="${TMPDIR:-/tmp}/SiriusMarkdownSelectionStressProbe.png" \
    swift run --package-path Tools/RenderProbe SiriusMarkdownRenderProbe
else
  echo "Skipping RenderProbe visual checks. Set SIRIUS_MARKDOWN_RUN_VISUAL_PROBES=1 to run them."
fi

echo "SiriusMarkdown product check passed."
