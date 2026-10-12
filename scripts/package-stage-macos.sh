#!/usr/bin/env bash
# Stage the native macOS build of LinDirStat for gnustep-packager's dmg
# backend (see docs/packaging.md, "macOS DMG").
#
# Layout under <stage-root>:
#   app/LinDirStat.app     the universal, signed bundle from `make -C macos`
#   runtime/               empty: the bundle links only Apple frameworks
#   metadata/licenses      LinDirStat and WinDirStat-reference notices
#
# The bundle is copied with ditto so its code signature stays intact; the
# packager signs or re-signs, never this script.
set -euo pipefail

if [[ $# -ne 1 ]]; then
  printf 'usage: %s <stage-root>\n' "$0" >&2
  exit 2
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
stage_root="$1"
app_source="$repo_root/macos/build/LinDirStat.app"

if [[ ! -x "$app_source/Contents/MacOS/LinDirStat" ]]; then
  make -C "$repo_root/macos"
fi
codesign --verify --deep --strict "$app_source"

rm -rf "$stage_root"
mkdir -p "$stage_root/app" "$stage_root/runtime" "$stage_root/metadata/licenses"
ditto "$app_source" "$stage_root/app/LinDirStat.app"

licenses="$stage_root/metadata/licenses"
{
  printf 'LinDirStat, a disk usage viewer inspired by WinDirStat\n'
  printf 'License: GPL-2.0-or-later\nSource: https://github.com/danjboyd/LinDirStat\n'
  if [[ -f "$repo_root/COPYING" ]]; then
    printf '\n'
    cat "$repo_root/COPYING"
  else
    printf '\nSee https://www.gnu.org/licenses/old-licenses/gpl-2.0.html for the license text.\n'
  fi
} > "$licenses/LinDirStat.txt"
cat > "$licenses/WinDirStat-reference.txt" <<'NOTICE'
WinDirStat (GPL-2.0-or-later, https://github.com/windirstat/windirstat):
LinDirStat's translations (Resources/*.lproj) are generated from WinDirStat's
language files. Its source code is kept under references/WinDirStat as
reference material and is not compiled into LinDirStat.
NOTICE

archs="$(lipo -archs "$stage_root/app/LinDirStat.app/Contents/MacOS/LinDirStat")"
cat > "$stage_root/metadata/stage-summary.json" <<SUMMARY
{
  "app": "LinDirStat.app",
  "platform": "macos",
  "archs": "$archs",
  "referenceSource": "references/WinDirStat"
}
SUMMARY

printf 'package-stage-macos: staged %s (%s, %s)\n' "$stage_root" "$(du -sh "$stage_root" | cut -f1)" "$archs"
