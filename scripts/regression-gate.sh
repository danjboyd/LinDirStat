#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
packager_root="${GNUSTEP_PACKAGER:-$("$repo_root/scripts/pinned-checkout.sh" gnustep-packager "$repo_root/out/gnustep-packager")}"
packager="$packager_root/scripts/gnustep-packager.ps1"
xctest_root="${TOOLS_XCTEST_ROOT:-$("$repo_root/scripts/build-tools-xctest.sh")}"
gnustep_makefiles="$HOME/.local/share/gnustep-cli/System/Library/Makefiles"

if [[ -f "$gnustep_makefiles/GNUstep.sh" ]]; then
  set +u
  # shellcheck disable=SC1091
  . "$gnustep_makefiles/GNUstep.sh"
  set -u
fi

cd "$repo_root"

make
TOOLS_XCTEST_ROOT="$xctest_root" make -C Tests
# A private GNUstep home keeps the tests' defaults out of the user's (GNUstep.sh
# unsets GNUSTEP_HOME, so it is set here).
test_home="$(mktemp -d "${TMPDIR:-/tmp}/lindirstat-gate-home.XXXXXX")"
trap 'rm -rf "$test_home"' EXIT
GNUSTEP_HOME="$test_home" LD_LIBRARY_PATH="$xctest_root/XCTest/obj:${LD_LIBRARY_PATH:-}" "$xctest_root/obj/xctest" Tests/LinDirStatTests.bundle
scripts/test-command-line.sh
scripts/run-ui-tests.sh

./scripts/windirstat-parity-gate.sh
./scripts/gui-parity-gate.sh

pwsh "$packager" -Manifest package.manifest.json -Command manifest-check
pwsh "$packager" -Manifest package.manifest.json -Command build
pwsh "$packager" -Manifest package.manifest.json -Command stage
pwsh "$packager" -Manifest package.manifest.json -Command validate
