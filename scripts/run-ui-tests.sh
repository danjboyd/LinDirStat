#!/usr/bin/env bash
# Builds and runs the UI coordination tests (Tests/UI): the real
# AppController and window on a private Xvfb display.
#
#   scripts/run-ui-tests.sh            # skips (exit 0) when Xvfb is missing
#   LINDIRSTAT_UI_TESTS_REQUIRED=1 scripts/run-ui-tests.sh   # fails instead
#   scripts/run-ui-tests.sh -XCTest LDAppControllerUITests/testName   # one test
#   LINDIRSTAT_UI_TESTS_WRAPPER="gdb -batch -ex run -ex bt --args" scripts/run-ui-tests.sh
#
# Everything the tests touch is private and thrown away afterwards:
# GNUSTEP_HOME (the defaults; gnustep-base takes the home folder from the
# user database, so HOME alone does not isolate them, and GNUstep.sh unsets
# GNUSTEP_HOME, so it is exported after sourcing it), XDG_DATA_HOME (the
# trash), XDG_CONFIG_HOME, XDG_CACHE_HOME and TMPDIR (the trees the tests
# scan, trash and delete). The display is
# picked by Xvfb (-displayfd) unless LINDIRSTAT_UI_DISPLAY names one.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
gnustep_makefiles="$HOME/.local/share/gnustep-cli/System/Library/Makefiles"
export TOOLS_XCTEST_ROOT="${TOOLS_XCTEST_ROOT:-$HOME/git/Arlen/vendor/tools-xctest}"

if ! command -v Xvfb >/dev/null 2>&1; then
  echo "run-ui-tests: SKIPPED (Xvfb is not installed; the UI tests need a private display)"
  [ "${LINDIRSTAT_UI_TESTS_REQUIRED:-0}" = 1 ] && exit 1
  exit 0
fi

set +u
# shellcheck disable=SC1091
. "$gnustep_makefiles/GNUstep.sh"
set -u

cd "$repo_root"
make -C Tests/UI >/dev/null

root="$(mktemp -d "${TMPDIR:-/tmp}/lindirstat-ui.XXXXXX")"
xvfb_pid=""
cleanup() {
  if [ -n "$xvfb_pid" ]; then
    kill "$xvfb_pid" 2>/dev/null || true
    wait "$xvfb_pid" 2>/dev/null || true
  fi
  rm -rf "$root"
}
trap cleanup EXIT

mkdir -p "$root/home/GNUstep/Defaults" "$root/data" "$root/config" "$root/cache" "$root/tmp"
# gnustep-base only takes a TMPDIR that only its owner can write.
chmod 700 "$root/tmp"

if [ -n "${LINDIRSTAT_UI_DISPLAY:-}" ]; then
  display="$LINDIRSTAT_UI_DISPLAY"
  Xvfb "$display" -screen 0 1600x1000x24 -nolisten tcp >/dev/null 2>&1 &
  xvfb_pid=$!
  sleep 1
else
  exec 3>"$root/display"
  Xvfb -displayfd 3 -screen 0 1600x1000x24 -nolisten tcp >/dev/null 2>&1 &
  xvfb_pid=$!
  exec 3>&-
  for _ in $(seq 50); do
    [ -s "$root/display" ] && break
    sleep 0.1
  done
  display=":$(tr -d '[:space:]' < "$root/display")"
fi
if ! kill -0 "$xvfb_pid" 2>/dev/null || [ "$display" = ":" ]; then
  echo "run-ui-tests: Xvfb did not start" >&2
  exit 1
fi

# The gnustep-cli libraries (on LD_LIBRARY_PATH after GNUstep.sh) were
# built for another prefix; without their configuration file they do not
# find the GUI backend.
cli_prefix="$HOME/.local/share/gnustep-cli"
config=()
library_path="$TOOLS_XCTEST_ROOT/XCTest/obj:${LD_LIBRARY_PATH:-}"
if [ -f "$cli_prefix/etc/GNUstep/GNUstep.conf" ]; then
  config=(GNUSTEP_CONFIG_FILE="$cli_prefix/etc/GNUstep/GNUstep.conf")
fi

status=0
env "${config[@]}" GNUSTEP_HOME="$root/home" \
  DISPLAY="$display" \
  DBUS_SESSION_BUS_ADDRESS=unix:path=/nonexistent \
  XDG_DATA_HOME="$root/data" \
  XDG_CONFIG_HOME="$root/config" \
  XDG_CACHE_HOME="$root/cache" \
  TMPDIR="$root/tmp" \
  LINDIRSTAT_UI_TESTS=1 \
  LINDIRSTAT_UI_TESTS_ROOT="$root" \
  LD_LIBRARY_PATH="$library_path" \
  timeout 300 ${LINDIRSTAT_UI_TESTS_WRAPPER:-} "$TOOLS_XCTEST_ROOT/obj/xctest" "$@" Tests/UI/build/LinDirStatUITests.bundle || status=$?
exit "$status"
