#!/usr/bin/env bash
# The release workflow's Linux job (.github/workflows/release.yml), on a
# clean Debian 13 container: the toolchain as Linux CI sets it up
# (scripts/ci-linux.sh setup), PowerShell for gnustep-packager from its pin in
# packaging/release-inputs.json, then scripts/package-linux.sh with the
# Alt+F4 check tried (LINDIRSTAT_ALT_F4=try). Collects the unsigned release
# files in dist/ci/linux: the AppImage, its .zsync, the unsigned feed and the
# provenance. Nothing is signed: the update key stays off GitHub, and the
# local publish step signs the feed.
#
#   scripts/ci-release-linux.sh [VERSION]   # default: package.version
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"
pin="$repo_root/scripts/pinned-checkout.sh"
work="${CI_WORK:-${RUNNER_TEMP:-/tmp}/lindirstat-ci}"
mkdir -p "$work"

die() { echo "ci-release-linux: $*" >&2; exit 1; }
step() { printf '\n== %s\n' "$*"; }

version_args=()
[ -n "${1:-}" ] && version_args=(--version "$1")

scripts/ci-linux.sh setup

step "PowerShell $("$pin" --field powershell version)"
if ! command -v pwsh >/dev/null 2>&1; then
  archive="$work/powershell.tar.gz"
  curl -fsSL -o "$archive" "$("$pin" --field powershell url)"
  echo "$("$pin" --field powershell sha256)  $archive" | sha256sum -c -
  mkdir -p "$work/powershell"
  tar -xzf "$archive" -C "$work/powershell"
  chmod +x "$work/powershell/pwsh"
  export PATH="$work/powershell:$PATH"
fi
pwsh -NoLogo -NoProfile -Command '$PSVersionTable.PSVersion.ToString()'

step "Package and check"
# When the Alt+F4 check fails here, its screenshot, window tree and logs go
# with the job's logs (dist/logs, uploaded as linux-logs).
LINDIRSTAT_ALT_F4=try LINDIRSTAT_ALT_F4_DEBUG="$repo_root/dist/logs/alt-f4" \
  scripts/package-linux.sh --release "${version_args[@]}"

step "Collect"
out="dist/ci/linux"
rm -rf "$out"
mkdir -p "$out"
for pattern in '*.AppImage' '*.AppImage.zsync' '*.update-feed.json' '*.provenance.json'; do
  # shellcheck disable=SC2086
  set -- dist/packages/$pattern
  [ -f "$1" ] || die "packaging did not produce $pattern"
  cp "$@" "$out/"
done
ls -l "$out"
