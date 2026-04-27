#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
scan_path="${1:-$HOME}"
gnustep_makefiles="$HOME/.local/share/gnustep-cli/System/Library/Makefiles"

if [[ -f "$gnustep_makefiles/GNUstep.sh" ]]; then
  set +u
  # shellcheck disable=SC1091
  . "$gnustep_makefiles/GNUstep.sh"
  set -u
fi

cd "$repo_root"
make -C Source

Source/LinDirStat.app/LinDirStat "$scan_path"
