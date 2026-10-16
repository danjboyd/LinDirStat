#!/usr/bin/env bash
# First launch of an AppImage as a new user on a machine without GNUstep:
#
#   scripts/check-appimage-first-launch.sh APPIMAGE
#
# Runs the AppImage under env -i with PATH=/usr/bin:/bin, a fresh HOME and
# GNUSTEP_HOME (no services cache, no defaults), private XDG and temporary
# folders, no session bus, on its own Xvfb. It passes when the main window
# shows a scan of the test fixture, and fails on a GNUstep alert panel (every
# alert's title is " "), on "Unable to find" or an exception in the log, or
# when the app exits. The build machine's PATH hid a missing make_services
# from the packager's smoke launch in 0.1.0.
set -euo pipefail

appimage="$(realpath "$1")"
# Without a FUSE device (a container) the AppImage cannot mount itself; it
# then runs from a temporary extraction, as AppImages offer.
appimage_env=()
[ -e /dev/fuse ] || appimage_env=(APPIMAGE_EXTRACT_AND_RUN=1)
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fixture="$repo_root/Tests/Fixtures/basic-tree"
wait_seconds="${LINDIRSTAT_FIRST_LAUNCH_WAIT:-15}"

root="$(mktemp -d "${TMPDIR:-/tmp}/ldfl.XXXXXX")"
# gnustep-base only uses a temporary folder that only its owner can use, and
# its socket paths must stay short.
gs_tmp="$(mktemp -d /tmp/ldfl-tmp.XXXXXX)"
chmod 700 "$gs_tmp"
mkdir -p "$root/home" "$root/xdg/data" "$root/xdg/config" "$root/xdg/cache"
xvfb_pid=""
app_pid=""
cleanup() {
  # setsid made the app its own process group: end all of it.
  [ -n "$app_pid" ] && kill -- "-$app_pid" 2>/dev/null || true
  sleep 1
  [ -n "$app_pid" ] && kill -KILL -- "-$app_pid" 2>/dev/null || true
  [ -n "$xvfb_pid" ] && kill "$xvfb_pid" 2>/dev/null || true
  rm -rf "$root" "$gs_tmp"
}
trap cleanup EXIT

exec 3< <(Xvfb -displayfd 4 -screen 0 1280x800x24 -nolisten tcp 4>&1 2>/dev/null)
xvfb_pid=$!
read -r -t 10 display_number <&3 || { echo "first-launch: Xvfb did not start" >&2; exit 1; }
display=":$display_number"

setsid env -i \
  PATH=/usr/bin:/bin \
  DISPLAY="$display" \
  HOME="$root/home" \
  GNUSTEP_HOME="$root/home" \
  XDG_DATA_HOME="$root/xdg/data" \
  XDG_CONFIG_HOME="$root/xdg/config" \
  XDG_CACHE_HOME="$root/xdg/cache" \
  TMP="$gs_tmp" TEMP="$gs_tmp" TMPDIR="$gs_tmp" \
  DBUS_SESSION_BUS_ADDRESS=unix:path=/nonexistent \
  LANG=C.UTF-8 \
  LINDIRSTAT_SCAN_PATH="$fixture" \
  ${appimage_env[@]+"${appimage_env[@]}"} \
  "$appimage" > "$root/app.log" 2>&1 &
app_pid=$!
sleep "$wait_seconds"

failures=()
kill -0 "$app_pid" 2>/dev/null || failures+=("the app exited during startup")
windows="$(DISPLAY="$display" xwininfo -root -tree 2>/dev/null || true)"
grep -q '^ *0x[0-9a-f]* " ": ("LinDirStat"' <<<"$windows" && failures+=("an alert panel is on screen")
grep -q '"[^"]*basic-tree": ("LinDirStat"' <<<"$windows" || failures+=("no main window showing the fixture scan")
grep -qiE 'Unable to find|exception' "$root/app.log" && failures+=("the log reports an error")
[ -f "$root/home/GNUstep/Library/Services/.GNUstepServices" ] || failures+=("no services cache was built")

if [ "${#failures[@]}" -gt 0 ]; then
  echo "first-launch: FAILED for $appimage:" >&2
  printf '  - %s\n' "${failures[@]}" >&2
  echo "  log:" >&2
  sed 's/^/    /' "$root/app.log" >&2
  exit 1
fi
echo "first-launch: $appimage starts cleanly for a new user without GNUstep"
