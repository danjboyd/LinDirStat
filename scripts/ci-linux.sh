#!/usr/bin/env bash
# Linux CI (.github/workflows/linux.yml): sets up the build inputs on a clean
# Debian 13 machine, then builds the app and runs the unit, command-line and
# UI tests (scripts/run-tests.sh, with the UI tests required).
#
#   scripts/ci-linux.sh
#
# Inputs, all pinned here:
# - the gnustep-cli-new managed toolchain (its v0.1.0 bootstrap, checked
#   against its sha256), in ~/.local/share/gnustep-cli as run-tests.sh
#   expects; skipped when that install exists;
# - tools-xctest at its pin in packaging/release-inputs.json
#   (scripts/build-tools-xctest.sh), built in CI_WORK
#   (default ${RUNNER_TEMP:-/tmp}/lindirstat-ci).
# The bootstrap installs the toolchain's own prerequisites with --yes, so on
# a clean machine it needs root (the workflow's container) or sudo.
set -euo pipefail

bootstrap_url="https://github.com/danjboyd/gnustep-cli-new/releases/download/v0.1.0/gnustep-bootstrap.sh"
bootstrap_sha256="3bdfa7a29a6442ce1bb994b027bfcba78beec649ae820391f009ac9eeb40ba63"

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="${CI_WORK:-${RUNNER_TEMP:-/tmp}/lindirstat-ci}"
gnustep_root="$HOME/.local/share/gnustep-cli"
mkdir -p "$work"

step() { printf '\n== %s\n' "$*"; }

step "Pinned inputs"
"$repo_root/scripts/test-pinned-inputs.sh"

step "GNUstep toolchain"
if [ ! -f "$gnustep_root/System/Library/Makefiles/GNUstep.sh" ]; then
  curl -fsSL -o "$work/gnustep-bootstrap.sh" "$bootstrap_url"
  echo "$bootstrap_sha256  $work/gnustep-bootstrap.sh" | sha256sum -c -
  sh "$work/gnustep-bootstrap.sh" setup --user --yes
fi
set +u
# shellcheck disable=SC1091
. "$gnustep_root/System/Library/Makefiles/GNUstep.sh"
set -u
gnustep-config --variable=GNUSTEP_MAKEFILES

step "tools-xctest $("$repo_root/scripts/pinned-checkout.sh" --field tools-xctest tag)"
tools_xctest="$(TOOLS_XCTEST_BUILD_DIR="$work/tools-xctest" "$repo_root/scripts/build-tools-xctest.sh")"

step "Build and test"
cd "$repo_root"
TOOLS_XCTEST_ROOT="$tools_xctest" LINDIRSTAT_UI_TESTS_REQUIRED=1 scripts/run-tests.sh
