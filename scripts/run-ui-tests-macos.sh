#!/usr/bin/env bash
# Runs the UI coordination tests (Tests/UI) on macOS: the real AppController
# and window, against Apple's AppKit. Built by `make -C macos ui-test`, which
# calls this script.
#
#   scripts/run-ui-tests-macos.sh BUNDLE                       # every test
#   scripts/run-ui-tests-macos.sh BUNDLE LDAppControllerUITests/testName
#
# macOS gives no way to move a process's defaults (CFFIXED_USER_HOME does
# not reach cfprefsd), so the tests write to their host's domain, the xctest
# tool's: never LinDirStat's. This script saves that domain first and puts it
# back afterwards. TMPDIR, where the tests build the trees they scan and
# delete, is a private folder thrown away at the end. The test that moves
# files to the trash is Linux only: the macOS trash is the user's.
set -euo pipefail

bundle="${1:?usage: run-ui-tests-macos.sh BUNDLE [Class/test]}"
shift
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
domain=com.apple.dt.xctest.tool

root="$(mktemp -d "${TMPDIR:-/tmp}/lindirstat-ui.XXXXXX")"
root="$(cd "$root" && pwd -P)"
mkdir -p "$root/tmp"
chmod 700 "$root/tmp"

saved=""
if defaults export "$domain" "$root/defaults.plist" 2>/dev/null; then
  saved="$root/defaults.plist"
fi
cleanup() {
  if [ -n "$saved" ]; then
    defaults import "$domain" "$saved"
  else
    defaults delete "$domain" >/dev/null 2>&1 || true
  fi
  rm -rf "$root"
}
trap cleanup EXIT

only=()
if [ $# -gt 0 ]; then
  only=(-XCTest "$1")
fi

cd "$repo_root"
status=0
env TMPDIR="$root/tmp/" \
  LINDIRSTAT_UI_TESTS=1 \
  LINDIRSTAT_UI_TESTS_ROOT="$root" \
  LINDIRSTAT_UI_TESTS_DEFAULTS_DOMAIN="$domain" \
  xcrun xctest ${only[@]+"${only[@]}"} "$bundle" || status=$?
exit "$status"
