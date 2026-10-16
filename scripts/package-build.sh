#!/usr/bin/env bash
# Builds the app (Source) and its tools (Tools) with GNUstep Make, against the
# gnustep-cli-new install, for the packager's build step.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

gnustep_root="${GNUSTEP_CLI_ROOT:-$HOME/.local/share/gnustep-cli}"
if [[ -f "$gnustep_root/System/Library/Makefiles/GNUstep.sh" ]]; then
  set +u
  # shellcheck disable=SC1091
  . "$gnustep_root/System/Library/Makefiles/GNUstep.sh"
  set -u
fi

# The aggregate GNUmakefile at the root; gnustep-cli-new's build command runs
# the same make, but from a checkout of gnustep-cli-new.
make -C "$repo_root"
