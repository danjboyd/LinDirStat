#!/usr/bin/env bash
# Builds and runs the tools-xctest suite.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/gnustep-env.sh
. "$(dirname "${BASH_SOURCE[0]}")/gnustep-env.sh"
# xctest from the GNUstep install, or from a tools-xctest checkout given by
# TOOLS_XCTEST_ROOT (the makefiles in Tests use it too).
xctest="${TOOLS_XCTEST_ROOT:+$TOOLS_XCTEST_ROOT/obj/}xctest"
xctest_libraries="${TOOLS_XCTEST_ROOT:+$TOOLS_XCTEST_ROOT/XCTest/obj:}"

gnustep_source_env

cd "$repo_root"
# The app first: the tests link the updater libraries it builds.
make -C Source >/dev/null
make -C Tests >/dev/null
# Tests write defaults (the xctest domain); a private GNUstep home keeps them
# out of the user's. GNUstep.sh unsets GNUSTEP_HOME, so it is set here.
test_home="$(mktemp -d "${TMPDIR:-/tmp}/lindirstat-tests-home.XXXXXX")"
trap 'rm -rf "$test_home"' EXIT
GNUSTEP_HOME="$test_home" LD_LIBRARY_PATH="$xctest_libraries${LD_LIBRARY_PATH:-}" \
  "$xctest" Tests/LinDirStatTests.bundle

# The command line end to end, against the app build.
scripts/test-command-line.sh

# The UI coordination tests, on a private Xvfb (skipped without one).
scripts/run-ui-tests.sh
