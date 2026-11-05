#!/usr/bin/env bash
# The first-run offer to add an AppImage to the applications (#157):
#
#   scripts/check-appimage-desktop-integration.sh APPIMAGE
#
# On its own Xvfb, under env -i with a fresh home and private XDG folders:
#
# 1. the first launch asks; Add writes the desktop entry (Exec this AppImage,
#    StartupWMClass, MimeType) and the hicolor icon;
# 2. the next launch doesn't ask;
# 3. a launch from another path doesn't ask, and the entry follows the move;
# 4. with someone else's entry for LinDirStat, a fresh home doesn't ask and
#    writes nothing.
set -euo pipefail
# Runs again inside a private-home bwrap sandbox (scripts/sandbox.sh).
. "$(dirname "${BASH_SOURCE[0]}")/sandbox.sh"
ld_sandbox "$@"
. "$(dirname "${BASH_SOURCE[0]}")/run-processes.sh"

appimage="$(realpath "$1")"
# Without a FUSE device (a container) the AppImage cannot mount itself; it
# then runs from a temporary extraction, as AppImages offer.
appimage_env=()
[ -e /dev/fuse ] || appimage_env=(APPIMAGE_EXTRACT_AND_RUN=1)
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fixture="$repo_root/Tests/Fixtures/basic-tree"

root="$(mktemp -d "${TMPDIR:-/tmp}/ldin.XXXXXX")"
# gnustep-base only uses a temporary folder that only its owner can use, and
# its socket paths must stay short.
gs_tmp="$(mktemp -d /tmp/ldin-tmp.XXXXXX)"
chmod 700 "$gs_tmp"
xvfb_pid=""
app_pid=""
home="$root/home"
data="$root/data"
stop_app() {
  [ -n "$app_pid" ] && kill -- "-$app_pid" 2>/dev/null || true
  sleep 1
  [ -n "$app_pid" ] && kill -KILL -- "-$app_pid" 2>/dev/null || true
  app_pid=""
  ld_stop_run_processes "$home"
}
cleanup() {
  local status=$?
  stop_app || status=1
  [ -n "$xvfb_pid" ] && kill "$xvfb_pid" 2>/dev/null || true
  rm -rf "$root" "$gs_tmp"
  exit "$status"
}
trap cleanup EXIT

exec 3< <(Xvfb -displayfd 4 -screen 0 1280x800x24 -nolisten tcp 4>&1 2>/dev/null)
xvfb_pid=$!
read -r -t 10 display_number <&3 || { echo "desktop-integration: Xvfb did not start" >&2; exit 1; }
export DISPLAY=":$display_number"

launch() { # AppImage
  mkdir -p "$home" "$data"
  setsid env -i \
    PATH=/usr/bin:/bin \
    DISPLAY="$DISPLAY" \
    HOME="$home" \
    GNUSTEP_HOME="$home" \
    XDG_DATA_HOME="$data" \
    XDG_DATA_DIRS="$root/no-system-data" \
    XDG_CONFIG_HOME="$root/config" \
    XDG_CACHE_HOME="$root/cache" \
    TMP="$gs_tmp" TEMP="$gs_tmp" TMPDIR="$gs_tmp" \
    DBUS_SESSION_BUS_ADDRESS=unix:path=/nonexistent \
    LANG=C.UTF-8 \
    LINDIRSTAT_SCAN_PATH="$fixture" \
    ${appimage_env[@]+"${appimage_env[@]}"} \
    "$1" > "$root/app.log" 2>&1 &
  app_pid=$!
}

fail() {
  echo "desktop-integration: FAILED for $appimage: $*" >&2
  xwininfo -root -tree >&2 2>/dev/null || true
  [ -f "$root/app.log" ] && { echo "  log:" >&2; sed 's/^/    /' "$root/app.log" >&2; }
  exit 1
}

# An NSAlert's window is titled "Alert"; GNUstep's alert panels " ".
alert_window() {
  xwininfo -root -tree 2>/dev/null | sed -n 's/^ *\(0x[0-9a-f]*\) "\(Alert\| \)": ("LinDirStat".*/\1/p' | head -1
}
wait_for_main() {
  for _ in $(seq 200); do
    xwininfo -root -tree 2>/dev/null | grep -q '"[^"]*basic-tree": ("LinDirStat"' && return 0
    kill -0 "$app_pid" 2>/dev/null || return 1
    sleep 0.1
  done
  return 1
}
# The offer comes half a second after the window; give it time to.
no_alert() {
  sleep 4
  [ -z "$(alert_window)" ]
}

entry="$data/applications/lindirstat.desktop"
icon="$data/icons/hicolor/256x256/apps/lindirstat.png"

# 1. The first launch asks.
launch "$appimage"
wait_for_main || fail "no main window"
alert=""
for _ in $(seq 100); do
  alert="$(alert_window)"
  [ -n "$alert" ] && break
  sleep 0.1
done
[ -n "$alert" ] || fail "the first launch did not ask"
sleep 1
# Click Add: the buttons sit at the bottom of the alert, and with no window
# manager a key press has no focus to go to. Slowly: GNUstep misses a press and
# release in the same instant after a jump of the pointer.
eval "$(xdotool getwindowgeometry --shell "$alert" | grep -E '^(X|Y|WIDTH|HEIGHT)=')"
xdotool mousemove "$((X + WIDTH / 2))" "$((Y + HEIGHT - 160))"
sleep 0.3
xdotool mousedown 1
sleep 0.15
xdotool mouseup 1
for _ in $(seq 50); do
  [ -f "$entry" ] && break
  sleep 0.1
done
[ -f "$entry" ] || fail "Add did not write $entry"
[ -s "$icon" ] || fail "Add did not write $icon"
grep -qxF "Exec=\"$appimage\" %F" "$entry" || fail "the entry's Exec is wrong: $(grep '^Exec=' "$entry")"
grep -qx 'StartupWMClass=LinDirStat' "$entry" || fail "the entry has no StartupWMClass"
grep -qx 'MimeType=inode/directory;' "$entry" || fail "the entry has no MimeType"
echo "desktop-integration: the first launch asks, and Add writes the entry and icon"
stop_app

# 2. It asks once.
launch "$appimage"
wait_for_main || fail "no main window on the second launch"
no_alert || fail "the second launch asked again"
echo "desktop-integration: the next launch doesn't ask"
stop_app

# 3. Moved: the entry follows without asking.
moved="$root/moved/LinDirStat.AppImage"
mkdir -p "$(dirname "$moved")"
cp "$appimage" "$moved"
launch "$moved"
wait_for_main || fail "no main window from the moved AppImage"
no_alert || fail "the moved AppImage asked"
grep -qxF "Exec=\"$moved\" %F" "$entry" || fail "the entry did not follow the move: $(grep '^Exec=' "$entry")"
echo "desktop-integration: the entry follows a moved AppImage"
stop_app

# 4. Someone else's entry: nothing to offer, nothing written.
rm -rf "$data" "$home"
mkdir -p "$data/applications"
printf '[Desktop Entry]\nType=Application\nName=LinDirStat\nExec=/somewhere/else %%F\nStartupWMClass=LinDirStat\n' > "$data/applications/integrated.desktop"
launch "$appimage"
wait_for_main || fail "no main window with an integrated entry"
no_alert || fail "it asked although another entry lists LinDirStat"
[ ! -e "$entry" ] || fail "it wrote an entry although another lists LinDirStat"
echo "desktop-integration: someone else's entry is respected"
