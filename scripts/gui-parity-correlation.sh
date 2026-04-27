#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output_dir="${GUI_PARITY_OUTPUT_DIR:-$repo_root/dist/validation/gui-parity}"
capture_path="${1:-$output_dir/lindirstat-gui-review.png}"
correlation_path="$output_dir/correlation.json"

mkdir -p "$output_dir"
cd "$repo_root"

./scripts/windirstat-parity-gate.sh

screenshot_arg="-"
if [[ -n "${DISPLAY:-}" ]] && command -v xdotool >/dev/null 2>&1 && command -v import >/dev/null 2>&1; then
  if ./scripts/capture-gui-review.sh "$capture_path"; then
    screenshot_arg="$capture_path"
  else
    echo "Skipping GUI screenshot correlation; capture command failed." >&2
  fi
else
  echo "Skipping GUI screenshot capture; DISPLAY, xdotool, or import is unavailable." >&2
fi

python3 scripts/gui-parity-correlation.py \
  "$repo_root/dist/validation/windirstat-parity/summary.json" \
  "$screenshot_arg" \
  "$correlation_path"
