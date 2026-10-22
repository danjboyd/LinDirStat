#!/usr/bin/env bash
# Alt+F4 under GNOME Shell must close a LinDirStat window, not kill the app:
#
#   scripts/check-appimage-alt-f4.sh APPIMAGE
#
# Runs GNOME Shell (X11) on its own Xvfb, with a private home, settings,
# runtime folder and session bus, and the AppImage under env -i on that
# display, scanning the test fixture. Then:
#
# 1. opens Preferences and presses Alt+F4 on it: Preferences must close and
#    the app keep running;
# 2. presses Alt+F4 on the main window: the app must quit the normal way
#    (closing its last window quits it), with exit status 0.
#
# Mutter asks a window to close with WM_DELETE_WINDOW, and kills the client
# when the window doesn't list it; with stock libs-back the windows the
# Adwaita theme decorates didn't (packaging/linux/libs-back, patch 0002), and
# Alt+F4 on Preferences quit the whole app ("X connection ... broken").
#
# Skips (exit 0) when gnome-shell or Xvfb is missing, unless
# LINDIRSTAT_ALT_F4_REQUIRED=1.
set -euo pipefail
# Runs again inside a private-home bwrap sandbox (scripts/sandbox.sh).
. "$(dirname "${BASH_SOURCE[0]}")/sandbox.sh"
ld_sandbox "$@"

appimage="$(realpath "$1")"
# Without a FUSE device (a container) the AppImage cannot mount itself; it
# then runs from a temporary extraction, as AppImages offer.
appimage_env=()
[ -e /dev/fuse ] || appimage_env=(APPIMAGE_EXTRACT_AND_RUN=1)
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fixture="$repo_root/Tests/Fixtures/basic-tree"

for tool in gnome-shell Xvfb dbus-run-session xdotool xprop xwininfo; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "alt-f4: SKIPPED ($tool is not installed)"
    [ "${LINDIRSTAT_ALT_F4_REQUIRED:-0}" = 1 ] && exit 1
    exit 0
  fi
done

root="$(mktemp -d "${TMPDIR:-/tmp}/ldaf.XXXXXX")"
# gnustep-base only uses a temporary folder that only its owner can use, and
# its socket paths must stay short.
gs_tmp="$(mktemp -d /tmp/ldaf-tmp.XXXXXX)"
chmod 700 "$root" "$gs_tmp"
mkdir -p "$root/home" "$root/run" "$root/xdg/data" "$root/xdg/cache" "$root/xdg/config/glib-2.0/settings"
chmod 700 "$root/run"
# No welcome tour over the windows.
printf "[org/gnome/shell]\nwelcome-dialog-last-shown-version='999'\n" > "$root/xdg/config/glib-2.0/settings/keyfile"
xvfb_pid=""
shell_pid=""
app_pid=""
cleanup() {
  [ -n "$app_pid" ] && kill -- "-$app_pid" 2>/dev/null || true
  [ -n "$shell_pid" ] && kill "$shell_pid" 2>/dev/null || true
  sleep 1
  [ -n "$app_pid" ] && kill -KILL -- "-$app_pid" 2>/dev/null || true
  [ -n "$xvfb_pid" ] && kill "$xvfb_pid" 2>/dev/null || true
  # The private session bus starts gvfs and the document portal, which mount
  # FUSE file systems in the runtime folder, and an accessibility bus.
  for mount in "$root/run/gvfs" "$root/run/doc"; do
    fusermount3 -u "$mount" 2>/dev/null || fusermount -u "$mount" 2>/dev/null || true
  done
  for pid in $(pgrep -u "$(id -u)" dbus-daemon 2>/dev/null); do
    if tr '\0' '\n' < "/proc/$pid/environ" 2>/dev/null | grep -qx "XDG_RUNTIME_DIR=$root/run"; then
      kill "$pid" 2>/dev/null || true
    fi
  done
  rm -rf "$root" "$gs_tmp" 2>/dev/null || true
}
trap cleanup EXIT

exec 3< <(Xvfb -displayfd 4 -screen 0 1600x1000x24 -nolisten tcp 4>&1 2>/dev/null)
xvfb_pid=$!
read -r -t 10 display_number <&3 || { echo "alt-f4: Xvfb did not start" >&2; exit 1; }
display=":$display_number"
export DISPLAY="$display"

session_env=(PATH=/usr/bin:/bin HOME="$root/home" XDG_RUNTIME_DIR="$root/run"
  XDG_CONFIG_HOME="$root/xdg/config" XDG_DATA_HOME="$root/xdg/data"
  XDG_CACHE_HOME="$root/xdg/cache" GSETTINGS_BACKEND=keyfile DISPLAY="$display")
env -i "${session_env[@]}" dbus-run-session -- gnome-shell --x11 --replace > "$root/shell.log" 2>&1 &
shell_pid=$!
for _ in $(seq 100); do
  xprop -root _NET_SUPPORTING_WM_CHECK 2>/dev/null | grep -q 'window id' && break
  sleep 0.1
done
xprop -root _NET_SUPPORTING_WM_CHECK 2>/dev/null | grep -q 'window id' || { echo "alt-f4: GNOME Shell did not start" >&2; cat "$root/shell.log" >&2; exit 1; }
sleep 3
# GNOME Shell starts in the overview.
xdotool key Escape
sleep 1

setsid env -i "${session_env[@]}" \
  GNUSTEP_HOME="$root/home" \
  TMP="$gs_tmp" TEMP="$gs_tmp" TMPDIR="$gs_tmp" \
  DBUS_SESSION_BUS_ADDRESS=unix:path=/nonexistent \
  LANG=C.UTF-8 \
  LINDIRSTAT_SCAN_PATH="$fixture" \
  ${appimage_env[@]+"${appimage_env[@]}"} \
  "$appimage" > "$root/app.log" 2>&1 &
app_pid=$!

# The private session bus GNOME Shell runs on (dbus-run-session's).
shell_bus() {
  local pid
  for pid in $(pgrep -u "$(id -u)" -x gnome-shell 2>/dev/null); do
    if tr '\0' '\n' < "/proc/$pid/environ" 2>/dev/null | grep -qx "XDG_RUNTIME_DIR=$root/run"; then
      tr '\0' '\n' < "/proc/$pid/environ" | sed -n 's/^DBUS_SESSION_BUS_ADDRESS=//p'
      return 0
    fi
  done
}
hide_overview() {
  local bus
  bus="$(shell_bus)"
  [ -n "$bus" ] || return 0
  DBUS_SESSION_BUS_ADDRESS="$bus" gdbus call --session --dest org.gnome.Shell \
    --object-path /org/gnome/Shell --method org.freedesktop.DBus.Properties.Set \
    org.gnome.Shell OverviewActive '<false>' >/dev/null 2>&1 || true
}

# The window GNOME Shell manages whose title matches, or nothing.
window_named() {
  local w
  for w in $(xprop -root _NET_CLIENT_LIST 2>/dev/null | grep -o '0x[0-9a-f]*'); do
    xprop -id "$w" WM_NAME 2>/dev/null | grep -qE "= \"$1\"\$" && { echo "$w"; return 0; }
  done
  return 0
}
wait_for_window() {
  local w=""
  for _ in $(seq 150); do
    w="$(window_named "$1")"
    [ -n "$w" ] && break
    sleep 0.1
  done
  echo "$w"
}
alt_f4() {
  xdotool windowactivate --sync "$1" 2>/dev/null || true
  sleep 0.5
  xdotool key alt+F4
}

fail() {
  if [ -n "${LINDIRSTAT_ALT_F4_DEBUG:-}" ]; then
    mkdir -p "$LINDIRSTAT_ALT_F4_DEBUG"
    import -window root "$LINDIRSTAT_ALT_F4_DEBUG/screen.png" 2>/dev/null || true
    xwininfo -root -tree > "$LINDIRSTAT_ALT_F4_DEBUG/windows.txt" 2>/dev/null || true
    xprop -root _NET_ACTIVE_WINDOW _NET_CLIENT_LIST > "$LINDIRSTAT_ALT_F4_DEBUG/root.txt" 2>/dev/null || true
    cp "$root/shell.log" "$root/app.log" "$LINDIRSTAT_ALT_F4_DEBUG/" 2>/dev/null || true
  fi
  echo "alt-f4: FAILED for $appimage: $*" >&2
  echo "  log:" >&2
  sed 's/^/    /' "$root/app.log" >&2
  exit 1
}

main="$(wait_for_window '.*basic-tree')"
[ -n "$main" ] || fail "no main window showing the fixture scan"
sleep 2

# GNOME Shell can bring the overview up again as it finishes starting; while
# it is up no window is active and keys go to its search field. Ctrl+, can
# also arrive before the window has the input focus: try again.
prefs=""
for _ in 1 2 3 4 5; do
  if xprop -root _NET_ACTIVE_WINDOW 2>/dev/null | grep -q '# 0x0$'; then
    # Synthetic keys and clicks don't always reach the overview; the
    # shell's own D-Bus property always closes it.
    hide_overview
    sleep 1
  fi
  xdotool windowactivate --sync "$main" 2>/dev/null || true
  sleep 1
  xdotool key ctrl+comma
  for _ in $(seq 30); do
    prefs="$(window_named 'Preferences')"
    [ -n "$prefs" ] && break
    sleep 0.1
  done
  [ -n "$prefs" ] && break
done
[ -n "$prefs" ] || fail "Preferences did not open"
protocols="$(xprop -id "$prefs" WM_PROTOCOLS 2>/dev/null || true)"
sleep 1
alt_f4 "$prefs"
sleep 3
kill -0 "$app_pid" 2>/dev/null || fail "Alt+F4 on Preferences ended the app (Preferences had $protocols)"
[ -z "$(window_named 'Preferences')" ] || fail "Alt+F4 did not close Preferences"
echo "alt-f4: Alt+F4 closed Preferences and the app kept running"

alt_f4 "$main"
for _ in $(seq 100); do
  kill -0 "$app_pid" 2>/dev/null || break
  sleep 0.1
done
kill -0 "$app_pid" 2>/dev/null && fail "Alt+F4 on the main window did not quit the app"
status=0
wait "$app_pid" || status=$?
app_pid=""
grep -q 'X connection' "$root/app.log" && fail "the app lost its X connection (killed by the window manager)"
[ "$status" -eq 0 ] || fail "the app exited with status $status"
echo "alt-f4: Alt+F4 on the main window quit the app normally"
