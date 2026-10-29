#!/usr/bin/env bash
# Temporary CI diagnostic for #117: the published v0.1.5 AppImage launched as
# the packager's smoke launches it (from a shell, and through PowerShell's
# Start-Process as the smoke does), with process snapshots every 0.5 s, then
# under strace -f. Not for merging.
set -u
P=/tmp/probe; mkdir -p "$P"
echo "PID 1: $(cat /proc/1/cmdline | tr '\0' ' ')"
pin=scripts/pinned-checkout.sh
curl -fsSL -o "$P/pwsh.tar.gz" "$("$pin" --field powershell url)"
mkdir -p "$P/pwsh" && tar -xzf "$P/pwsh.tar.gz" -C "$P/pwsh" && chmod +x "$P/pwsh/pwsh"
curl -fsSL -o "$P/app.AppImage" https://github.com/danjboyd/LinDirStat-releases/releases/download/v0.1.5/LinDirStat-0.1.5-x86_64.AppImage
chmod +x "$P/app.AppImage"
Xvfb :0 -screen 0 1280x800x24 -nolisten tcp >/dev/null 2>&1 &
sleep 1

envargs() { # $1: env folder
  local E=$1
  echo "-i APPIMAGE_EXTRACT_AND_RUN=1 DBUS_SESSION_BUS_ADDRESS=unix:path=$E/runtime/no-session-bus DISPLAY=:0 GNUSTEP_HOME=$E/home HOME=$E/home LANG=C.UTF-8 PATH=/usr/bin:/bin TMPDIR=$E/tmp XDG_CACHE_HOME=$E/home/.cache XDG_CONFIG_HOME=$E/home/.config XDG_DATA_HOME=$E/home/.local/share XDG_RUNTIME_DIR=$E/runtime XDG_STATE_HOME=$E/home/.local/state $P/app.AppImage"
}
snapshots() { # $1: run name
  for i in $(seq 1 24); do
    sleep 0.5
    echo "-- $1 t=$(awk "BEGIN{print $i/2}") $(date +%T.%N | cut -c1-12)"
    ps -eo pid,ppid,pgid,sid,etimes,stat,args | grep -E 'gdnc|LinDirStat$|defunct|pwsh' | grep -v -e grep -e dpkg | cut -c1-150
  done
}
# Stops the app first, so its gdnc connection is not broken by the cleanup.
finish() { # $1: run name
  echo "-- $1 stopping $(date +%T.%N | cut -c1-12)"
  pkill -TERM -x LinDirStat; sleep 2; pkill -TERM -x gdnc; sleep 1
  echo "--- $1 app log"; cat "$P/$1.out" "$P/$1.err" 2>/dev/null
}
launch_shell() { # $1: run name, rest: command prefix
  local name=$1; shift; local E="$P/$name-env"; mkdir -p "$E/home" "$E/runtime" "$E/tmp"
  echo "-- $name launch $(date +%T.%N | cut -c1-12)"
  "$@" env $(envargs "$E") > "$P/$name.out" 2> "$P/$name.err" &
  snapshots "$name"; finish "$name"
}
launch_pwsh() { # $1: run name, rest: command prefix
  local name=$1; shift; local E="$P/$name-env"; mkdir -p "$E/home" "$E/runtime" "$E/tmp"
  echo "-- $name launch $(date +%T.%N | cut -c1-12)"
  "$@" "$P/pwsh/pwsh" -NoLogo -NoProfile -Command "\$p = Start-Process -FilePath env -ArgumentList '$(envargs "$E")' -PassThru -RedirectStandardOutput '$P/$name.out' -RedirectStandardError '$P/$name.err'; Start-Sleep -Seconds 14" &
  snapshots "$name"; finish "$name"; wait
}
trace=(strace -f -tt -e trace=%process,%signal,%net,close,kill,tgkill,exit_group -e signal=all)
launch_shell shell
launch_pwsh pwsh
launch_pwsh pwsh-strace "${trace[@]}" -o "$P/strace.txt"
echo "--- gdnc in strace"
for pid in $(grep -E 'execve\(".*gdnc"' "$P/strace.txt" | awk '{print $1}' | sort -u); do
  echo "=== gdnc pid $pid"; grep "^$pid " "$P/strace.txt" | grep -v -E 'rt_sigaction|rt_sigprocmask' | tail -40
done
echo "--- signals, kills and exits"
grep -E -- '--- SIG|\+\+\+ (exited|killed)|kill\(' "$P/strace.txt" | grep -v SIGCHLD | head -80
true
