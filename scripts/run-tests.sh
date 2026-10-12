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
# The app first: the tests link the updater libraries it builds.
make -C Source >/dev/null
make -C Tests >/dev/null
# Tests write defaults (the xctest domain); a private GNUstep home keeps them
# out of the user's. GNUstep.sh unsets GNUSTEP_HOME, so it is set here.
test_home="$(mktemp -d "${TMPDIR:-/tmp}/lindirstat-tests-home.XXXXXX")"
trap 'rm -rf "$test_home"' EXIT
GNUSTEP_HOME="$test_home" LD_LIBRARY_PATH="$TOOLS_XCTEST_ROOT/XCTest/obj:${LD_LIBRARY_PATH:-}" \
  "$TOOLS_XCTEST_ROOT/obj/xctest" Tests/LinDirStatTests.bundle

# The command line end to end, against the app build.
scripts/test-command-line.sh

# The UI coordination tests, on a private Xvfb (skipped without one).
scripts/run-ui-tests.sh
