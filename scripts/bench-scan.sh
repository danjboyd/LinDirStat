#!/usr/bin/env bash
# Benchmarks a scan and its completion (docs/performance.md).
#
#   scripts/bench-scan.sh PATH [--runs N] [--stop-after SECONDS] [--logical] [--no-results]
#
# Builds Tools/lindirstat-bench and runs it on PATH with 1 and 4 threads,
# duplicate detection off and on: scan (read) time, finalize (totals and
# sort) time, the completion work done on the scanning thread (extension
# list, Largest Files, treemap layout and render) or, with --no-results, on
# the main thread as before; Stop-to-completion latency with --stop-after;
# and peak RSS. It never writes defaults (a private GNUstep home is used).
#
# For the app itself (main-thread steps, stalls, Stop-to-display), run it
# with LINDIRSTAT_PROFILE=1 (and LINDIRSTAT_PROFILE_STOP_AFTER=seconds) on a
# private display through scripts/run-isolated.sh; see docs/performance.md.
set -euo pipefail

if [[ $# -lt 1 ]]; then
  sed -n 2,4p "$0" >&2
  exit 2
fi
scan_path="$1"
shift
runs=1
extra=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --runs) runs="$2"; shift 2 ;;
    --stop-after) extra+=(--stop-after "$2"); shift 2 ;;
    --logical|--no-results) extra+=("$1"); shift ;;
    *) echo "unknown option $1" >&2; exit 2 ;;
  esac
done

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/gnustep-env.sh
. "$repo_root/scripts/gnustep-env.sh"
gnustep_source_env
bench_home="$(mktemp -d "${TMPDIR:-/tmp}/lindirstat-bench-home.XXXXXX")"
trap 'rm -rf "$bench_home"' EXIT
export GNUSTEP_HOME="$bench_home"

make -C "$repo_root/Tools" >/dev/null
bench="$repo_root/Tools/obj/lindirstat-bench"

for threads in 1 4; do
  for duplicates in off on; do
    flags=(--threads "$threads")
    [[ $duplicates == on ]] && flags+=(--dupes)
    for ((run = 1; run <= runs; run++)); do
      echo "== threads $threads, duplicates $duplicates, run $run"
      "$bench" "$scan_path" "${flags[@]}" ${extra[@]+"${extra[@]}"} | tail -n +2
    done
  done
done
