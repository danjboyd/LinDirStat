#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  printf 'usage: %s <stage-root>\n' "$0" >&2
  exit 2
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
stage_root="$1"
app_source="$repo_root/Source/LinDirStat.app"

if [[ ! -x "$app_source/LinDirStat" ]]; then
  "$repo_root/scripts/package-build.sh"
fi

rm -rf "$stage_root"
mkdir -p "$stage_root/app" "$stage_root/runtime/bin" "$stage_root/runtime/config" "$stage_root/metadata/icons" "$stage_root/metadata/licenses"

cp -R "$app_source" "$stage_root/app/LinDirStat.app"

defaults_tool=""
for candidate in \
  "$HOME/.local/share/gnustep-cli/Local/Tools/defaults" \
  "/usr/GNUstep/Local/Tools/defaults" \
  "/usr/GNUstep/System/Tools/defaults"; do
  if [[ -x "$candidate" ]]; then
    defaults_tool="$candidate"
    break
  fi
done

if [[ -n "$defaults_tool" ]]; then
  cp "$defaults_tool" "$stage_root/runtime/bin/defaults"
fi

cat > "$stage_root/runtime/config/theme.conf" <<'EOF'
GSTheme=Adwaita
EOF

cat > "$stage_root/metadata/licenses/LinDirStat.txt" <<'EOF'
LinDirStat is a GNUstep disk usage viewer inspired by WinDirStat.

This staged notice is a placeholder for the project's own license text until a
repository license is selected.
EOF

cat > "$stage_root/metadata/licenses/WinDirStat-reference.txt" <<'EOF'
WinDirStat source is included as local reference material only under
references/WinDirStat. It is not compiled into this staged LinDirStat payload.
EOF

base64 -d > "$stage_root/metadata/icons/lindirstat.png" <<'EOF'
iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAIAAAAlC+aJAAAANElEQVR4nO3PQQ0AIBDAMMC/5+ONAvZoFSzZnpld0A8AAAAAAAAAAAAAAAAAAAAAAAAAAID3A2vgAUv8nL1OAAAAAElFTkSuQmCC
EOF

cat > "$stage_root/metadata/stage-summary.json" <<EOF
{
  "app": "LinDirStat.app",
  "defaultTheme": "Adwaita",
  "referenceSource": "references/WinDirStat"
}
EOF
