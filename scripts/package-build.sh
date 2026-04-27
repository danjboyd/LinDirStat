#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ -f "$HOME/.local/share/gnustep-cli/System/Library/Makefiles/GNUstep.sh" ]]; then
  set +u
  # shellcheck disable=SC1091
  . "$HOME/.local/share/gnustep-cli/System/Library/Makefiles/GNUstep.sh"
  set -u
fi

python3 "$HOME/git/gnustep/gnustep-cli-new/scripts/internal/build.py" --execute "$repo_root"
