#!/usr/bin/env bash
set -euo pipefail

# Builds each Example SwiftPM package in release configuration and lays out a macOS .app bundle
# under Examples/MacOSArtifacts so demos run as normal apps (not tied to launching terminal stdin).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXAMPLES="$(cd "${SCRIPT_DIR}/.." && pwd)"
ARTIFACTS="${EXAMPLES}/MacOSArtifacts"
DEFAULT_DEMOS=(
  MarkdownDemoApp
  StreamingTranscriptDemo
  DocumentReaderDemo
)

declare -a demos
if (($#)); then
  demos=("$@")
else
  demos=("${DEFAULT_DEMOS[@]}")
fi

mkdir -p "${ARTIFACTS}"

bundle_one() {
  local name="$1"
  local pkg="${EXAMPLES}/${name}"
  local plist="${pkg}/Support/Info.plist"
  local bin_root
  local app="${ARTIFACTS}/${name}.app"
  local contents="${app}/Contents"
  local macos="${contents}/MacOS"
  local resources="${contents}/Resources"
  local exe="${macos}/${name}"
  local icon="${pkg}/Support/${name}.icns"

  [[ -f "${plist}" ]] || {
    printf 'error: missing %s\n' "${plist}" >&2
    return 1
  }

  [[ -f "${icon}" ]] || {
    printf 'error: missing %s\n' "${icon}" >&2
    return 1
  }

  # Build and resolve path in two steps: `--show-bin-path` alone can print the
  # destination before the linked executable exists on a cold package build.
  swift build --package-path "${pkg}" -c release
  bin_root="$(swift build --package-path "${pkg}" -c release --show-bin-path)"
  local built="${bin_root}/${name}"

  [[ -f "${built}" ]] || {
    printf 'error: expected built product %s\n' "${built}" >&2
    return 1
  }

  rm -rf "${app}"
  mkdir -p "${macos}" "${resources}"

  cp "${built}" "${exe}"
  chmod +x "${exe}"

  cp "${plist}" "${contents}/Info.plist"
  cp "${icon}" "${resources}/${name}.icns"

  printf 'bundled %s -> %s\n' "${name}" "${app}"
}

for d in "${demos[@]}"; do
  bundle_one "${d}"
done

printf 'Done. Apps are in %s (double-click from Finder).\n' "${ARTIFACTS}"
