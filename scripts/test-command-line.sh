#!/usr/bin/env bash
# End-to-end test of the command line (WinDirStat's /savetocsv,
# /savedupestocsv): runs the built app without a display on a copy of the
# basic-tree fixture and checks the CSV files and exit codes.
#
#   scripts/test-command-line.sh [path/to/LinDirStat binary]
#
# The default binary is the GNUstep build (make -C Source).
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app="${1:-$repo_root/Source/LinDirStat.app/LinDirStat}"
if [ ! -x "$app" ]; then
  echo "test-command-line: $app is not built" >&2
  exit 1
fi

# macOS sets TMPDIR with a trailing slash; the app prints normalized paths.
tmp="${TMPDIR:-/tmp}"
work="$(mktemp -d "${tmp%/}/lindirstat-cli.XXXXXX")"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/home"
cp -R "$repo_root/Tests/Fixtures/basic-tree" "$work/tree"
printf 'duplicate contents\n' > "$work/tree/copy-1.txt"
printf 'duplicate contents\n' > "$work/tree/src/copy-2.txt"

failures=0
fail() {
  echo "FAIL: $*" >&2
  failures=$((failures + 1))
}

run_app() {
  # No display: the save flags must not need one. A private GNUstep home
  # keeps the user's filters out of the result and the run out of the user's
  # defaults. (gnustep-base ignores GNUSTEP_USER_DEFAULTS_DIR, and GNUstep.sh
  # unsets GNUSTEP_HOME, so it is set here, after GNUstep.sh.)
  env -u DISPLAY -u WAYLAND_DISPLAY GNUSTEP_HOME="$work/home" "$app" "$@"
}

# Results and duplicates in one run, with the Windows spelling for one flag.
status=0
(cd "$work" && run_app /SaveToCSV out.csv --savedupestocsv dupes.csv tree) 2>"$work/stderr" || status=$?
[ "$status" -eq 0 ] || fail "export exited $status: $(cat "$work/stderr")"

# Owner is there when the Owner column is shown.
header='"Name","Files","Folders","Logical Size","Physical Size","Attributes","Last Change","WinDirStat Attributes","Index"'
case "$(head -n 1 "$work/out.csv" | tr -d '\r')" in
  "$header" | "$header,\"Owner\"") ;;
  *) fail "results header" ;;
esac
# Every row is preceded by CRLF, so the row count is the newline count.
rows="$(tr -cd '\n' < "$work/out.csv" | wc -c | tr -d ' ')"
entries="$(find "$work/tree" | wc -l | tr -d ' ')"
[ "$rows" = "$entries" ] || fail "results have $rows rows for $entries entries"
grep -q "^\"$work/tree\",6,1," "$work/out.csv" || fail "root row: $(sed -n 2p "$work/out.csv")"
grep -q "^\"$work/tree/src/main.m\",0,0," "$work/out.csv" || fail "file row for src/main.m"

dupes_header='"Hash Prefix","Name","Logical Size","Physical Size","Last Change","Attributes","Sampled hash"'
[ "$(head -n 1 "$work/dupes.csv" | tr -d '\r')" = "$dupes_header" ] || fail "duplicates header"
grep -q "\"$work/tree/copy-1.txt\",19," "$work/dupes.csv" || fail "copy-1.txt is not listed as a duplicate"
grep -q "\"$work/tree/src/copy-2.txt\",19," "$work/dupes.csv" || fail "copy-2.txt is not listed as a duplicate"

# Failures exit with 1.
status=0
run_app --savetocsv "$work/missing-dir/out.csv" "$work/tree" 2>/dev/null || status=$?
[ "$status" -eq 1 ] || fail "unwritable CSV exited $status"
status=0
run_app --savetocsv "$work/none.csv" "$work/no-such-folder" 2>/dev/null || status=$?
[ "$status" -eq 1 ] || fail "missing folder exited $status"
[ ! -e "$work/none.csv" ] || fail "a CSV was written without a folder"

if [ "$failures" -ne 0 ]; then
  echo "test-command-line: $failures failure(s)" >&2
  exit 1
fi
echo "test-command-line: PASSED"
