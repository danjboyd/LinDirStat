#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output_path="${1:-/tmp/lindirstat-gui-review.png}"
gnustep_makefiles="$HOME/.local/share/gnustep-cli/System/Library/Makefiles"

if [[ -f "$gnustep_makefiles/GNUstep.sh" ]]; then
  set +u
  # shellcheck disable=SC1091
  . "$gnustep_makefiles/GNUstep.sh"
  set -u
fi

cd "$repo_root"
make

# An explicit fixture: without a path the app scans its working directory's
# fixture, or the home folder, which a screenshot run must never walk.
LINDIRSTAT_SCAN_PATH="$repo_root/Tests/Fixtures/basic-tree" openapp Source/LinDirStat.app &
app_pid=$!
trap 'kill "$app_pid" >/dev/null 2>&1 || true' EXIT

sleep 2
window_id="$(xdotool search --name LinDirStat | while read -r candidate; do
  if xwininfo -id "$candidate" 2>/dev/null | grep -q 'IsViewable'; then
    echo "$candidate"
    break
  fi
done)"

if [[ -z "$window_id" ]]; then
  echo "Could not find a viewable LinDirStat window." >&2
  exit 1
fi

import -window "$window_id" "$output_path"
echo "$output_path"
