#!/usr/bin/env bash
# The teardown the AppImage checks use (scripts/run-processes.sh), with
# stand-in daemons: it stops the run's processes in their own sessions,
# including one that ignores TERM, and leaves another run's alone (#147).
#
#   scripts/test-run-processes.sh
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/run-processes.sh"

work="$(mktemp -d "${TMPDIR:-/tmp}/ldrp.XXXXXX")"
cleanup() {
  local pid
  for pid in $(jobs -p); do
    kill -KILL "$pid" 2>/dev/null || true
  done
  rm -rf "$work"
}
trap cleanup EXIT
fail() { echo "test-run-processes: FAILED: $*" >&2; exit 1; }

GNUSTEP_HOME="$work/run" setsid sleep 300 &
GNUSTEP_HOME="$work/run" setsid bash -c 'trap "" TERM; while :; do sleep 1; done' &
GNUSTEP_HOME="$work/run-other" setsid sleep 300 &
sleep 0.5
other_pid="$(ld_run_processes "$work/run-other")"
[ -n "$other_pid" ] || fail "did not find the other run's process"
[ "$(ld_run_processes "$work/run" | wc -l)" -ge 2 ] || fail "did not find this run's processes"

ld_stop_run_processes "$work/run" || fail "did not stop this run's processes"
[ -z "$(ld_run_processes "$work/run")" ] || fail "this run's processes are still there"
[ "$(ld_run_processes "$work/run-other")" = "$other_pid" ] || fail "stopped another run's process"
ld_stop_run_processes "$work/no-such-run" || fail "a run without processes failed"

# A run's teardown must fail when it cannot stop one.
kill() { :; }
GNUSTEP_HOME="$work/stuck" setsid sleep 300 &
sleep 0.5
stuck_pid="$(ld_run_processes "$work/stuck")"
stuck_status=0
ld_stop_run_processes "$work/stuck" 2>/dev/null || stuck_status=$?
unset -f kill
kill -KILL $stuck_pid 2>/dev/null || true
[ "$stuck_status" -ne 0 ] || fail "a process that would not stop did not fail the teardown"

# package-linux.sh's look for a check's gdnc, which needs no GNUSTEP_HOME.
cp "$(command -v sleep)" "$work/gdnc"
before="$(ld_check_daemons)"
TMPDIR=/tmp/ldfl-tmp.test "$work/gdnc" 300 &
daemon_pid=$!
TMPDIR=/tmp/other-tmp.test "$work/gdnc" 300 &
sleep 0.5
left="$(ld_check_daemons | grep -vxF -e "$before" || true)"
[ "$left" = "$daemon_pid" ] || fail "looked for a check's gdnc and found: ${left:-nothing}"

echo "test-run-processes: PASSED"
