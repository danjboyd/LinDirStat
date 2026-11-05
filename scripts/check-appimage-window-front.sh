#!/usr/bin/env bash
# The main window must come up over other apps' windows under GNOME Shell:
#
#   scripts/check-appimage-window-front.sh APPIMAGE
#
# Runs GNOME Shell (X11) on its own Xvfb, as check-appimage-alt-f4.sh does,
# with another app's window focused and filling the screen. Then:
#
# 1. starts the AppImage with a folder: its main window must end up on top;
# 2. starts it with nothing to scan and closes Select Target with Escape: the
#    main window must end up on top. (OK needs a folder or a drive, and which
#    drives there are depends on the machine. Both take the same way out.)
#
# libs-back writes _NET_WM_USER_TIME 0 on a window mapped before any input, so
# Mutter stacks it below the focused window, and focusing it later doesn't
# raise it: the app looked as if it had quit (#155). Under GNOME on Wayland
# the app runs under XWayland, with the same Mutter rule.
#
# Skips (exit 0) when gnome-shell, Xvfb or xterm is missing, unless
# LINDIRSTAT_WINDOW_FRONT_REQUIRED=1.
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

for tool in gnome-shell Xvfb dbus-run-session xdotool xprop xterm gdbus; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "window-front: SKIPPED ($tool is not installed)"
    [ "${LINDIRSTAT_WINDOW_FRONT_REQUIRED:-0}" = 1 ] && exit 1
    exit 0
  fi
done

root="$(mktemp -d "${TMPDIR:-/tmp}/ldwf.XXXXXX")"
# gnustep-base only uses a temporary folder that only its owner can use, and
# its socket paths must stay short.
gs_tmp="$(mktemp -d /tmp/ldwf-tmp.XXXXXX)"
chmod 700 "$root" "$gs_tmp"
mkdir -p "$root/home" "$root/run" "$root/xdg/data" "$root/xdg/cache" "$root/xdg/config/glib-2.0/settings"
chmod 700 "$root/run"
# No welcome tour over the windows.
printf "[org/gnome/shell]\nwelcome-dialog-last-shown-version='999'\n" > "$root/xdg/config/glib-2.0/settings/keyfile"
xvfb_pid=""
shell_pid=""
other_pid=""
app_pid=""
stop_app() {
  [ -n "$app_pid" ] && kill -- "-$app_pid" 2>/dev/null || true
  sleep 1
  [ -n "$app_pid" ] && kill -KILL -- "-$app_pid" 2>/dev/null || true
  app_pid=""
  ld_stop_run_processes "$root/home"
}
cleanup() {
  local status=$?
  stop_app || status=1
  [ -n "$other_pid" ] && kill "$other_pid" 2>/dev/null || true
  [ -n "$shell_pid" ] && kill "$shell_pid" 2>/dev/null || true
  sleep 1
  [ -n "$xvfb_pid" ] && kill "$xvfb_pid" 2>/dev/null || true
  # The private session bus starts gvfs and the document portal, which mount
  # FUSE file systems in the runtime folder, and an accessibility bus.
  for mount in "$root/run/gvfs" "$root/run/doc"; do
    fusermount3 -u "$mount" 2>/dev/null || fusermount -u "$mount" 2>/dev/null || true
  done
  for pid in $(pgrep -u "$(id -u)" dbus-daemon 2>/dev/null); do
    if tr '\0' '\n' 2>/dev/null < "/proc/$pid/environ" | grep -qx "XDG_RUNTIME_DIR=$root/run"; then
      kill "$pid" 2>/dev/null || true
    fi
  done
  rm -rf "$root" "$gs_tmp" 2>/dev/null || true
  exit "$status"
}
trap cleanup EXIT

exec 3< <(Xvfb -displayfd 4 -screen 0 1600x1000x24 -nolisten tcp 4>&1 2>/dev/null)
xvfb_pid=$!
read -r -t 10 display_number <&3 || { echo "window-front: Xvfb did not start" >&2; exit 1; }
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
xprop -root _NET_SUPPORTING_WM_CHECK 2>/dev/null | grep -q 'window id' || { echo "window-front: GNOME Shell did not start" >&2; cat "$root/shell.log" >&2; exit 1; }
sleep 3
# GNOME Shell starts in the overview.
xdotool key Escape
sleep 1

# Synthetic keys and clicks don't always reach the overview; the shell's own
# D-Bus property always closes it.
hide_overview() {
  local pid bus
  for pid in $(pgrep -u "$(id -u)" -x gnome-shell 2>/dev/null); do
    if tr '\0' '\n' 2>/dev/null < "/proc/$pid/environ" | grep -qx "XDG_RUNTIME_DIR=$root/run"; then
      bus="$(tr '\0' '\n' 2>/dev/null < "/proc/$pid/environ" | sed -n 's/^DBUS_SESSION_BUS_ADDRESS=//p')"
      [ -n "$bus" ] && DBUS_SESSION_BUS_ADDRESS="$bus" gdbus call --session --dest org.gnome.Shell \
        --object-path /org/gnome/Shell --method org.freedesktop.DBus.Properties.Set \
        org.gnome.Shell OverviewActive '<false>' >/dev/null 2>&1 || true
    fi
  done
}

env -i "${session_env[@]}" xterm -geometry 200x60+0+0 -T OtherWindow >/dev/null 2>&1 &
other_pid=$!
other=""
for _ in $(seq 100); do
  other="$(xdotool search --name '^OtherWindow$' 2>/dev/null | tail -1 || true)"
  [ -n "$other" ] && break
  sleep 0.1
done
[ -n "$other" ] || { echo "window-front: the other window did not open" >&2; exit 1; }
sleep 2
hide_overview
sleep 1

focus_other() {
  xdotool windowactivate --sync "$other" 2>/dev/null || true
  sleep 1
}

launch() { # app arguments
  setsid env -i "${session_env[@]}" \
    GNUSTEP_HOME="$root/home" \
    TMP="$gs_tmp" TEMP="$gs_tmp" TMPDIR="$gs_tmp" \
    DBUS_SESSION_BUS_ADDRESS=unix:path=/nonexistent \
    LANG=C.UTF-8 \
    LINDIRSTAT_DESKTOP_PROMPT=off \
    ${appimage_env[@]+"${appimage_env[@]}"} \
    "$appimage" "$@" > "$root/app.log" 2>&1 &
  app_pid=$!
}

fail() {
  echo "window-front: FAILED for $appimage: $*" >&2
  xprop -root _NET_ACTIVE_WINDOW _NET_CLIENT_LIST_STACKING >&2 || true
  echo "  log:" >&2
  sed 's/^/    /' "$root/app.log" >&2
  exit 1
}

# The window on top of the stack, by its title.
top_title() {
  local top
  top="$(xprop -root _NET_CLIENT_LIST_STACKING 2>/dev/null | grep -o '0x[0-9a-f]*' | tail -1)"
  [ -n "$top" ] && xprop -id "$top" WM_NAME 2>/dev/null | sed -n 's/^WM_NAME([A-Z0-9_]*) = "\(.*\)"$/\1/p'
}

# Waits for the top window's title to match $1; ERE.
wait_for_top() {
  for _ in $(seq 150); do
    top_title | grep -qE "$1" && return 0
    kill -0 "$app_pid" 2>/dev/null || return 1
    sleep 0.1
  done
  return 1
}

# 1. A folder on the command line.
focus_other
launch "$fixture"
wait_for_top 'basic-tree' || fail "started with a folder, the main window is not on top (top: $(top_title))"
echo "window-front: started with a folder, the main window comes up on top"
stop_app || exit 1

# 2. Nothing to scan: Select Target first.
focus_other
launch
wait_for_top '^Select Target$' || fail "Select Target is not on top (top: $(top_title))"
panel="$(xdotool search --name '^Select Target$' 2>/dev/null | tail -1)"
sleep 2
xdotool windowactivate --sync "$panel" 2>/dev/null || true
sleep 0.5
xdotool key Escape
wait_for_top '^LinDirStat$' || fail "after Select Target closed, the main window is not on top (top: $(top_title))"
echo "window-front: after Select Target closed, the main window is on top"
