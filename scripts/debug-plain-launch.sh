#!/usr/bin/env bash
# Temporary CI diagnostic (debug-smoke-gdnc): a plain launch on Xvfb, with
# the helper processes and the app's log. Not for merging.
set -u
G="$HOME/.local/share/gnustep-cli"
set +u; export GNUSTEP_SH_EXPORT_ALL_VARIABLES=yes; . "$G/System/Library/Makefiles/GNUstep.sh"; set -u
W=$(mktemp -d /tmp/dbg.XXXXXX); mkdir -p "$W/home" "$W/tmp" "$W/run"
Xvfb :55 -screen 0 1600x1000x24 -nolisten tcp >/dev/null 2>&1 & X=$!
sleep 1
for mode in plain scan; do
  echo "===== $mode"
  extra=""; [ "$mode" = scan ] && extra="LINDIRSTAT_SCAN_PATH=/usr/share/zoneinfo"
  env -i $extra DISPLAY=:55 HOME="$W/home" GNUSTEP_HOME="$W/home" LANG=C.UTF-8 PATH="$PATH" TMPDIR="$W/tmp" XDG_RUNTIME_DIR="$W/run" \
    LD_LIBRARY_PATH="${LD_LIBRARY_PATH:-}" GNUSTEP_MAKEFILES="$GNUSTEP_MAKEFILES" \
    Source/LinDirStat.app/LinDirStat --GNU-Debug=NSDistributedNotificationCenter > "$W/$mode.log" 2>&1 & A=$!
  for i in 1 2 3 4 5 6 7 8 9; do sleep 1; echo "-- t=$i"; ps -eo pid,ppid,etimes,stat,args | grep -E "gdnc|gpbs|make_services|LinDirStat" | grep -v grep; ls "$W/tmp/NSMessagePort/names" 2>/dev/null | while read n; do echo "name: $(echo "$n" | base64 -d 2>/dev/null)"; done; done
  kill $A 2>/dev/null; sleep 1
  echo "--- app log ($mode)"; cat "$W/$mode.log"
  pkill -x gdnc 2>/dev/null; sleep 1
done
kill $X
