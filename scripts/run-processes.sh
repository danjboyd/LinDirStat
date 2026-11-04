# Sourced by the check-appimage checks and package-linux.sh. A launched app
# starts gdnc as a daemon in its own session, so ending the app's process
# group leaves it running (#147). A run's processes are the ones with that
# run's private GNUSTEP_HOME in their environment; nothing else matches, so
# other users' daemons, the system's and your own session's are left alone.

# The processes this user can see with GNUSTEP_HOME=$1, one PID a line.
ld_run_processes() {
  # grep also fails on no match and on processes it cannot read.
  { grep -lszxF "GNUSTEP_HOME=$1" /proc/[0-9]*/environ || true; } | cut -d/ -f3
}

# Ends the processes with GNUSTEP_HOME=$1: TERM, then KILL after 3 seconds.
# Fails, naming them, if any is still there.
ld_stop_run_processes() {
  local pids _
  pids="$(ld_run_processes "$1")"
  [ -n "$pids" ] || return 0
  kill $pids 2>/dev/null || true
  for _ in $(seq 30); do
    pids="$(ld_run_processes "$1")"
    [ -n "$pids" ] || return 0
    sleep 0.1
  done
  kill -KILL $pids 2>/dev/null || true
  for _ in $(seq 30); do
    pids="$(ld_run_processes "$1")"
    [ -n "$pids" ] || return 0
    sleep 0.1
  done
  echo "still running with GNUSTEP_HOME=$1: $(echo $pids)" >&2
  return 1
}

# This user's gdnc daemons started by a check-appimage check, whichever way
# the check's own teardown went: their TMPDIR is the check's private folder.
ld_check_daemons() {
  local pid
  for pid in $(pgrep -u "$(id -u)" -x gdnc 2>/dev/null); do
    if tr '\0' '\n' 2>/dev/null < "/proc/$pid/environ" | grep -qE '^TMPDIR=/tmp/ld(fl|of|af)-tmp\.'; then
      echo "$pid"
    fi
  done
}
