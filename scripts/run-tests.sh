#!/usr/bin/env bash
# Builds and runs the tools-xctest suite.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
gnustep_makefiles="$HOME/.local/share/gnustep-cli/System/Library/Makefiles"
export TOOLS_XCTEST_ROOT="${TOOLS_XCTEST_ROOT:-$HOME/git/Arlen/vendor/tools-xctest}"

set +u
# shellcheck disable=SC1091
. "$gnustep_makefiles/GNUstep.sh"
set -u

cd "$repo_root"
make -C Tests >/dev/null
LD_LIBRARY_PATH="$TOOLS_XCTEST_ROOT/XCTest/obj:${LD_LIBRARY_PATH:-}" \
  "$TOOLS_XCTEST_ROOT/obj/xctest" Tests/LinDirStatTests.bundle
