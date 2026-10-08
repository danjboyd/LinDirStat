#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
scan_path="${1:-$HOME}"
width="${2:-1200}"
height="${3:-360}"
output_dir="${4:-$repo_root/dist/validation/home-treemap}"
gnustep_makefiles="$HOME/.local/share/gnustep-cli/System/Library/Makefiles"

if [[ -f "$gnustep_makefiles/GNUstep.sh" ]]; then
  set +u
  # shellcheck disable=SC1091
  . "$gnustep_makefiles/GNUstep.sh"
  set -u
fi

mkdir -p "$output_dir"
cd "$repo_root"

make -C Tools
rects_path="$output_dir/treemap-rects.json"
ppm_path="$output_dir/treemap.ppm"
summary_path="$output_dir/summary.json"

LINDIRSTAT_TREEMAP_HEIGHT="$height" Tools/obj/windirstat-parity-exporter --path "$scan_path" "$width" --ppm "$ppm_path" > "$rects_path"

python3 - "$rects_path" "$summary_path" "$scan_path" "$width" "$height" <<'PY'
import json
import sys
from pathlib import Path

rects_path = Path(sys.argv[1])
summary_path = Path(sys.argv[2])
scan_path = sys.argv[3]
width = int(sys.argv[4])
height = int(sys.argv[5])
items = json.loads(rects_path.read_text())
total = sum(item["size"] for item in items)
largest = sorted(items, key=lambda item: item["size"], reverse=True)[:25]
summary = {
    "scan_path": scan_path,
    "viewport": [width, height],
    "leaf_count": len(items),
    "leaf_size_total": total,
    "largest_items": largest,
}
summary_path.write_text(json.dumps(summary, indent=2))
PY

echo "$ppm_path"
echo "$summary_path"
