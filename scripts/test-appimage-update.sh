#!/usr/bin/env bash
# End-to-end test of the in-app updater (docs/updates.md): an installed
# AppImage finds a newer one in a signed feed, downloads and checks it,
# replaces itself and starts again as the new version. Then the same with a
# payload signed by the wrong key, which must be refused, leaving the
# installed AppImage as it was.
#
#   scripts/test-appimage-update.sh OLD.AppImage NEW.AppImage NEW.update-feed.json
#
# OLD and NEW come from the packager (package -Backend appimage, NEW with
# -PackageVersion higher than OLD's). The feed is NEW's .update-feed.json;
# its download URL is pointed at the local NEW and it is signed with the
# update key (UPDATE_ED_PRIVATE_KEY, else the file UPDATE_ED_PRIVATE_KEY_FILE,
# default ~/.config/lindirstat/update-ed25519.key). The app finds the feed
# through GP_UPDATER_FEED_URL.
#
# Runs on a private Xvfb with a private GNUstep home, XDG folders and TMPDIR
# (where the updater keeps its state), and answers the update dialogs with
# xdotool; your LinDirStat settings must not change. Needs Xvfb, xdotool,
# xwininfo and openssl.
set -euo pipefail
# Runs again inside a private-home bwrap sandbox (scripts/sandbox.sh).
. "$(dirname "${BASH_SOURCE[0]}")/sandbox.sh"
ld_sandbox "$@"
# Without a fuse device (CI containers, the sandbox) AppImages run extracted.
[ -e /dev/fuse ] || export APPIMAGE_EXTRACT_AND_RUN=1

if [ $# -ne 3 ]; then
  sed -n '2,20p' "$0" >&2
  exit 2
fi
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
old_appimage="$(realpath "$1")"
new_appimage="$(realpath "$2")"
new_feed="$(realpath "$3")"
for tool in Xvfb xdotool xwininfo openssl; do
  command -v "$tool" >/dev/null || { echo "test-appimage-update: needs $tool" >&2; exit 1; }
done
if [ -z "${UPDATE_ED_PRIVATE_KEY:-}" ]; then
  UPDATE_ED_PRIVATE_KEY="$(cat "${UPDATE_ED_PRIVATE_KEY_FILE:-$HOME/.config/lindirstat/update-ed25519.key}")"
fi
public_key="$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["updates"]["publicEDKey"])' "$repo_root/package.manifest.json")"

work="$(mktemp -d "${TMPDIR:-/tmp}/lindirstat-update-test.XXXXXX")"
xvfb_pid=""
# The AppImage, the app and its GNUstep daemons, all run from $work.
app_pids() { pgrep -f "^$work/" || true; }
# Stops the app and unmounts its AppImage (the runtime unmounts when it
# exits; one that was killed may not), so nothing under $work is a mount.
stop_app() {
  local pids mount_point
  pids="$(app_pids)"
  if [ -n "$pids" ]; then
    kill $pids 2>/dev/null || true
    wait_for '[ -z "$(app_pids)" ]' 20 || kill -9 $(app_pids) 2>/dev/null || true
  fi
  for mount_point in $(findmnt -rn -o TARGET | grep "^$work/" || true); do
    fusermount3 -u "$mount_point" 2>/dev/null || fusermount -u "$mount_point" 2>/dev/null || true
  done
  ! findmnt -rn -o TARGET | grep -q "^$work/"
}

# Removes a folder under $work, never while an AppImage is mounted there.
remove_under_work() {
  if stop_app; then
    rm -rf "$@"
  else
    echo "test-appimage-update: an AppImage is still mounted under $work; not removing it" >&2
    return 1
  fi
}

cleanup() {
  remove_under_work "$work" || true
  [ -n "$xvfb_pid" ] && kill "$xvfb_pid" 2>/dev/null || true
}
trap cleanup EXIT

failures=0
fail() { echo "FAIL: $*" >&2; failures=$((failures + 1)); }

exec 3< <(Xvfb -displayfd 4 -screen 0 1280x800x24 -nolisten tcp 4>&1 2>/dev/null)
xvfb_pid=$!
read -r -t 10 display_number <&3 || { echo "test-appimage-update: Xvfb did not start" >&2; exit 1; }
export DISPLAY=":$display_number"

sha() { sha256sum "$1" | cut -d' ' -f1; }

# Waits up to $2 seconds for the condition command $1.
wait_for() {
  local deadline=$((SECONDS + $2))
  until eval "$1"; do
    [ "$SECONDS" -ge "$deadline" ] && return 1
    sleep 0.5
  done
}

# The update dialogs are NSAlerts, all titled "Alert". There is no window
# manager, so windows are listed with xwininfo; the newest is listed first.
alert_count() { xwininfo -root -tree | grep -c '"Alert"' || true; }
newest_alert() { xwininfo -root -tree | grep '"Alert"' | head -1; }
main_window_count() { xwininfo -root -tree | grep -c "\"$work/scan\"" || true; }

# Presses the default button of the newest alert: Return, then a click on
# the button if that did not close it ($1, $2: the button's centre from the
# alert's top-left corner under the Adwaita theme; negative x counts from
# the right edge).
answer_alert() {
  local line id geometry width x y before
  line="$(newest_alert)"
  id="$(awk '{print $1}' <<<"$line")"
  geometry="$(grep -o '[0-9]*x[0-9]*+[0-9]*+[0-9]*' <<<"$line" | head -1)"
  IFS='x+' read -r width _ x y <<<"$geometry"
  before="$(alert_count)"
  xdotool windowfocus --sync "$id" 2>/dev/null || true
  xdotool key Return
  if wait_for '[ "$(alert_count)" -lt "$before" ]' 3; then
    return
  fi
  local dx="$1"
  [ "$dx" -lt 0 ] && dx=$((width + dx))
  xdotool mousemove $((x + dx)) $((y + $2)) mousedown 1
  sleep 0.15
  xdotool mouseup 1
}

# The updater's state file $1: its status, or why it failed.
helper_status() { helper_field "$1" status; }
helper_field() {
  python3 - "$1" "$2" <<'PY' 2>/dev/null || true
import json, sys
state = json.load(open(sys.argv[1]))
if sys.argv[2] == "error":
    print((state.get("error") or {}).get("message", "") or state.get("message", ""))
else:
    print(state.get(sys.argv[2], ""))
PY
}

# One scenario: installs OLD, publishes a feed for NEW signed with the key
# in $2 (base64 seed), starts OLD and accepts the update.
run_scenario() {
  local name="$1" signing_key="$2"
  remove_under_work "$work/install" "$work/release" "$work/home" "$work/xdg" "$work/tmp" "$work/scan" || return
  mkdir -p "$work/install" "$work/release" "$work/home" "$work/xdg/data" "$work/xdg/config" "$work/xdg/cache" "$work/scan"
  # The updater keeps its state in GNUstep's temporary folder: TMP (not
  # TMPDIR), used only when no one else can write to it. TMPDIR is where
  # the AppImage runtime mounts the AppImage.
  mkdir -m 700 "$work/tmp"
  cp "$old_appimage" "$work/install/LinDirStat.AppImage"
  chmod +x "$work/install/LinDirStat.AppImage"
  cp "$new_appimage" "$work/release/"
  printf 'x\n' > "$work/scan/file.txt"

  python3 - "$new_feed" "$work/release" "$work/release/stable.json" <<'PY'
import json, os, pathlib, sys
feed = json.load(open(sys.argv[1], encoding="utf-8-sig"))
for release in feed["releases"]:
    for asset in release["assets"]:
        asset["url"] = pathlib.Path(sys.argv[2], asset["name"]).as_uri()
json.dump(feed, open(sys.argv[3], "w"), indent=2)
PY
  # The wrong-key scenario signs with a throwaway key on purpose, so the signer
  # must not check it against the manifest key that release-linux.sh exports.
  UPDATE_ED_PUBLIC_KEY="" UPDATE_ED_PRIVATE_KEY="$signing_key" python3 "$repo_root/scripts/sign-update-feed.py" \
    "$work/release/stable.json" "$work/release" >/dev/null

  local old_sha new_sha state_dir state
  old_sha="$(sha "$work/install/LinDirStat.AppImage")"
  new_sha="$(sha "$new_appimage")"
  state_dir="$work/tmp/gnustep-packager-updater/org.lindirstat.LinDirStat"

  GNUSTEP_HOME="$work/home" XDG_DATA_HOME="$work/xdg/data" XDG_CONFIG_HOME="$work/xdg/config" \
  XDG_CACHE_HOME="$work/xdg/cache" TMP="$work/tmp" TMPDIR="$work/tmp" DBUS_SESSION_BUS_ADDRESS=unix:path=/nonexistent \
  GP_UPDATER_FEED_URL="file://$work/release/stable.json" LINDIRSTAT_SCAN_PATH="$work/scan" \
    "$work/install/LinDirStat.AppImage" >"$work/app-$name.log" 2>&1 &
  disown

  # The automatic check runs startupDelaySeconds (15) after launch.
  if ! wait_for '[ "$(alert_count)" -ge 1 ]' 60; then
    fail "$name: no update offered"
    return
  fi
  answer_alert 187 126   # Install Update

  state="$state_dir/update-state.json"
  if [ "$name" = signed ]; then
    if ! wait_for '[ "$(helper_status "$state")" = readyToApply ] && [ "$(alert_count)" -ge 1 ]' 120; then
      fail "$name: the update was not prepared (helper: $(helper_status "$state"))"
      return
    fi
    answer_alert -104 146  # Restart and Install
    if ! wait_for '[ "$(sha "$work/install/LinDirStat.AppImage" 2>/dev/null)" = "$new_sha" ]' 120; then
      fail "$name: the installed AppImage was not replaced"
      return
    fi
    if ! wait_for '[ "$(helper_status "$state")" = completed ] && [ -n "$(app_pids)" ] && [ "$(main_window_count)" -ge 1 ]' 60; then
      fail "$name: the updated AppImage did not start again"
      return
    fi
    echo "test-appimage-update: $name: replaced by the new AppImage, which started again"
  else
    if ! wait_for '[ "$(helper_status "$state")" = failed ]' 120; then
      fail "$name: the helper did not refuse the payload (helper: $(helper_status "$state"))"
      return
    fi
    if [ "$(sha "$work/install/LinDirStat.AppImage")" != "$old_sha" ]; then
      fail "$name: the installed AppImage changed"
      return
    fi
    echo "test-appimage-update: $name: payload refused ($(helper_field "$state" error)), installed AppImage unchanged"
  fi
  stop_app || true
}

real_settings="$HOME/GNUstep/Defaults/LinDirStat.plist"
settings_before="$(stat -c %Y "$real_settings" 2>/dev/null || echo none)"

run_scenario signed "$UPDATE_ED_PRIVATE_KEY"
# Any other key: a payload the installed copy's public key does not verify.
other_key="$(openssl genpkey -algorithm ed25519 -outform DER | tail -c 32 | base64)"
run_scenario wrong-key "$other_key"

if [ "$(stat -c %Y "$real_settings" 2>/dev/null || echo none)" != "$settings_before" ]; then
  fail "$real_settings changed"
fi

if [ "$failures" -ne 0 ]; then
  echo "test-appimage-update: $failures failure(s); logs were in $work" >&2
  exit 1
fi
echo "test-appimage-update: PASSED"
