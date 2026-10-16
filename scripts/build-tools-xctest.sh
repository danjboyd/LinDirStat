#!/usr/bin/env bash
# Builds tools-xctest, the unit test runner, from its pin in
# packaging/release-inputs.json (scripts/pinned-checkout.sh), against the
# gnustep-cli-new install.
#
#   scripts/build-tools-xctest.sh   # prints the built checkout's path
#
# Inputs (environment): GNUSTEP_CLI_ROOT (~/.local/share/gnustep-cli) and
# TOOLS_XCTEST_BUILD_DIR, where the checkout lives (out/tools-xctest). A
# checkout already built at the pin is reused. run-tests.sh and
# run-ui-tests.sh call this unless TOOLS_XCTEST_ROOT names a checkout.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
gnustep_root="${GNUSTEP_CLI_ROOT:-$HOME/.local/share/gnustep-cli}"
build_dir="${TOOLS_XCTEST_BUILD_DIR:-$repo_root/out/tools-xctest}"

die() { printf 'build-tools-xctest: %s\n' "$*" >&2; exit 1; }

if [[ -x "$build_dir/obj/xctest" ]] &&
   "$repo_root/scripts/pinned-checkout.sh" --verify tools-xctest "$build_dir" 2>/dev/null; then
  printf '%s\n' "$build_dir"
  exit 0
fi

[[ -f "$gnustep_root/System/Library/Makefiles/GNUstep.sh" ]] || die "no gnustep-cli-new install at $gnustep_root (set GNUSTEP_CLI_ROOT)"
"$repo_root/scripts/pinned-checkout.sh" tools-xctest "$build_dir" >/dev/null

(
  cd "$build_dir"
  set +u
  # shellcheck disable=SC1091
  . "$gnustep_root/System/Library/Makefiles/GNUstep.sh"
  set -u
  make > "$build_dir/make.out" 2>&1 || { tail -20 "$build_dir/make.out" >&2; exit 1; }
) || die "the build failed (log in $build_dir/make.out)"

[[ -x "$build_dir/obj/xctest" ]] || die "no xctest at $build_dir/obj/xctest"
printf '%s\n' "$build_dir"
