#!/usr/bin/env bash
# Full-window GUI parity gate: see scripts/gui-parity-gate.py and
# docs/regression-gate.md. Runs on its own Xvfb display (GUI_PARITY_DISPLAY,
# default: the first free one from :90) with private GNUstep defaults.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
gnustep_makefiles="$HOME/.local/share/gnustep-cli/System/Library/Makefiles"

if [[ -f "$gnustep_makefiles/GNUstep.sh" ]]; then
  set +u
  # The app is started directly (not through openapp), so it needs every
  # GNUstep path in its environment to find its backend and the theme.
  export GNUSTEP_SH_EXPORT_ALL_VARIABLES=yes
  # shellcheck disable=SC1091
  . "$gnustep_makefiles/GNUstep.sh"
  unset GNUSTEP_SH_EXPORT_ALL_VARIABLES
  set -u
fi

cd "$repo_root"
make -C Source >/dev/null
make -C Tools >/dev/null

python3 scripts/gui-parity-gate.py "$@"
