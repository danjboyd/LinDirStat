#!/usr/bin/env bash
# "Open With LinDirStat" on a folder, as a file manager does it:
#
#   scripts/check-appimage-open-folder.sh APPIMAGE
#
# Checks that the AppImage's desktop entry offers LinDirStat for folders
# (MimeType inode/directory, an Exec line that takes the files, %F), then
# runs the AppImage the way that Exec line does, with the test fixture as its
# argument and no LINDIRSTAT_SCAN_PATH, under env -i with a fresh home on its
# own Xvfb. It passes when the main window shows a scan of that folder.
# WinDirStat puts a "WinDirStat" entry on folders in Explorer; this is the
# freedesktop.org equivalent (GNOME's Disk Usage Analyzer does the same).
set -euo pipefail

appimage="$(realpath "$1")"
# Without a FUSE device (a container) the AppImage cannot mount itself; it
# then runs from a temporary extraction, as AppImages offer.
appimage_env=()
[ -e /dev/fuse ] || appimage_env=(APPIMAGE_EXTRACT_AND_RUN=1)
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fixture="$repo_root/Tests/Fixtures/basic-tree"
wait_seconds="${LINDIRSTAT_OPEN_FOLDER_WAIT:-15}"

root="$(mktemp -d "${TMPDIR:-/tmp}/ldof.XXXXXX")"
# gnustep-base only uses a temporary folder that only its owner can use, and
# its socket paths must stay short.
gs_tmp="$(mktemp -d /tmp/ldof-tmp.XXXXXX)"
chmod 700 "$gs_tmp"
mkdir -p "$root/home" "$root/xdg/data" "$root/xdg/config" "$root/xdg/cache" "$root/extract"
xvfb_pid=""
app_pid=""
cleanup() {
  [ -n "$app_pid" ] && kill -- "-$app_pid" 2>/dev/null || true
  sleep 1
  [ -n "$app_pid" ] && kill -KILL -- "-$app_pid" 2>/dev/null || true
  [ -n "$xvfb_pid" ] && kill "$xvfb_pid" 2>/dev/null || true
  rm -rf "$root" "$gs_tmp"
}
trap cleanup EXIT

fail() {
  echo "open-folder: FAILED for $appimage: $*" >&2
  [ -f "$root/app.log" ] && { echo "  log:" >&2; sed 's/^/    /' "$root/app.log" >&2; }
  exit 1
}

(cd "$root/extract" && "$appimage" --appimage-extract '*.desktop' >/dev/null 2>&1) || fail "could not extract the desktop entry"
desktop="$(find "$root/extract/squashfs-root" -maxdepth 1 -name '*.desktop' | head -1)"
[ -n "$desktop" ] || fail "no desktop entry at the top of the AppImage"
grep -qE '^MimeType=(.*;)?inode/directory;' "$desktop" || fail "the desktop entry does not list inode/directory: $(grep '^MimeType=' "$desktop" || echo 'no MimeType')"
exec_line="$(sed -n 's/^Exec=//p' "$desktop" | head -1)"
grep -qE '(^| )%[FU]( |$)' <<<"$exec_line" || fail "the desktop entry's Exec does not take files: $exec_line"
echo "open-folder: the desktop entry offers LinDirStat for folders (Exec=$exec_line)"

exec 3< <(Xvfb -displayfd 4 -screen 0 1280x800x24 -nolisten tcp 4>&1 2>/dev/null)
xvfb_pid=$!
read -r -t 10 display_number <&3 || fail "Xvfb did not start"
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
  ${appimage_env[@]+"${appimage_env[@]}"} \
  "$appimage" "$fixture" > "$root/app.log" 2>&1 &
app_pid=$!

windows=""
for _ in $(seq "$((wait_seconds * 10))"); do
  windows="$(DISPLAY="$display" xwininfo -root -tree 2>/dev/null || true)"
  grep -q '"[^"]*basic-tree": ("LinDirStat"' <<<"$windows" && break
  kill -0 "$app_pid" 2>/dev/null || break
  sleep 0.1
done
kill -0 "$app_pid" 2>/dev/null || fail "the app exited"
grep -q '"[^"]*basic-tree": ("LinDirStat"' <<<"$windows" || fail "no main window showing a scan of $fixture"
grep -q '^ *0x[0-9a-f]* " ": ("LinDirStat"' <<<"$windows" && fail "an alert panel is on screen"
echo "open-folder: the AppImage opened with a folder argument scans that folder"
