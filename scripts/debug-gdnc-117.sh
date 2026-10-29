#!/usr/bin/env bash
# Temporary CI diagnostic for #117: the published v0.1.5 AppImage launched as
# the packager's smoke launches it, with process snapshots every 0.5 s, then
# again under strace -f. Not for merging.
set -u
P=/tmp/probe; mkdir -p "$P"
echo "PID 1: $(cat /proc/1/cmdline | tr '\0' ' ')"
curl -fsSL -o "$P/app.AppImage" https://github.com/danjboyd/LinDirStat-releases/releases/download/v0.1.5/LinDirStat-0.1.5-x86_64.AppImage
chmod +x "$P/app.AppImage"
Xvfb :0 -screen 0 1280x800x24 -nolisten tcp >/dev/null 2>&1 &
sleep 1
launch() { # $1: run name, rest: command prefix
  local name=$1; shift
  local E="$P/$name-env"; mkdir -p "$E/home" "$E/runtime" "$E/tmp"
  env -i APPIMAGE_EXTRACT_AND_RUN=1 DBUS_SESSION_BUS_ADDRESS="unix:path=$E/runtime/no-session-bus" DISPLAY=:0 \
    GNUSTEP_HOME="$E/home" HOME="$E/home" LANG=C.UTF-8 PATH=/usr/bin:/bin TMPDIR="$E/tmp" \
    XDG_CACHE_HOME="$E/home/.cache" XDG_CONFIG_HOME="$E/home/.config" XDG_DATA_HOME="$E/home/.local/share" \
    XDG_RUNTIME_DIR="$E/runtime" XDG_STATE_HOME="$E/home/.local/state" LINDIRSTAT_SCAN_PATH=/usr/share/zoneinfo \
    "$@" "$P/app.AppImage" > "$P/$name.log" 2>&1 &
  local app=$!
  for i in $(seq 1 24); do
    sleep 0.5
    echo "-- $name t=$(awk "BEGIN{print $i/2}") $(date +%T.%N | cut -c1-12)"
    ps -eo pid,ppid,pgid,sid,etimes,stat,args | grep -E 'gdnc|gpbs|LinDirStat$|defunct' | grep -v grep | cut -c1-160
    find "$E/tmp" -path '*NSMessagePort*' -maxdepth 4 2>/dev/null | sed 's/^/   port: /'
  done
  kill $app 2>/dev/null; sleep 2
  pkill -TERM -x gdnc 2>/dev/null; pkill -TERM -x LinDirStat 2>/dev/null; sleep 1
  echo "--- $name app log"; cat "$P/$name.log"
}
launch plain
launch strace strace -f -tt -o "$P/strace.txt" -e trace=%process,%signal,%net,close,kill,tgkill,exit_group -e signal=all
echo "--- gdnc in strace"
for pid in $(grep -E 'execve\(".*gdnc"' "$P/strace.txt" | awk '{print $1}' | sort -u); do
  echo "=== gdnc pid $pid"; grep "^$pid " "$P/strace.txt" | grep -v -E 'rt_sigaction|rt_sigprocmask' | tail -40
done
echo "--- signals and exits"
grep -E -- '--- SIG|\+\+\+ (exited|killed)|kill\(|tgkill' "$P/strace.txt" | head -60
true
