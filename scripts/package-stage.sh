#!/usr/bin/env bash
# Stage the LinDirStat payload for gnustep-packager (see docs/packaging.md).
#
# Layout under <stage-root>:
#   app/LinDirStat.app            the built app bundle
#   runtime/lib                   bundled shared libraries (GNUstep, libobjc2,
#                                 libdispatch, libs-OpenSave and their
#                                 non-host dependencies)
#   runtime/System/Library        GNUstep resources, the back bundle, and the
#                                 Adwaita theme (Themes/Adwaita.theme)
#   runtime/bin                   GNUstep tools (defaults, gpbs, gdnc)
#   runtime/etc/GNUstep           a relocatable GNUstep.conf
#   metadata/                     icon and license notices
#
# Inputs (override with environment variables):
#   GNUSTEP_CLI_ROOT   gnustep-cli-new install (~/.local/share/gnustep-cli)
#   OPENSAVE_ROOT      libs-OpenSave build (~/git/gnustep/libs-OpenSave)
#   ADWAITA_THEME      built Adwaita.theme
#                      (~/git/gnustep/plugins-themes-adwaita/Adwaita.theme)
set -euo pipefail

if [[ $# -ne 1 ]]; then
  printf 'usage: %s <stage-root>\n' "$0" >&2
  exit 2
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
stage_root="$1"
app_source="$repo_root/Source/LinDirStat.app"
gnustep_root="${GNUSTEP_CLI_ROOT:-$HOME/.local/share/gnustep-cli}"
opensave_root="${OPENSAVE_ROOT:-$HOME/git/gnustep/libs-OpenSave}"
adwaita_theme="${ADWAITA_THEME:-$HOME/git/gnustep/plugins-themes-adwaita/Adwaita.theme}"
gnustep_library="$gnustep_root/Local/Library"
gnustep_tools="$gnustep_root/Local/Tools"

require() {
  if [[ ! -e "$1" ]]; then
    printf 'package-stage: missing %s (%s)\n' "$1" "$2" >&2
    exit 1
  fi
}

if [[ ! -x "$app_source/LinDirStat" ]]; then
  "$repo_root/scripts/package-build.sh"
fi

require "$gnustep_library/Libraries/libgnustep-base.so" "gnustep-cli-new GNUstep install; set GNUSTEP_CLI_ROOT"
require "$opensave_root/Source/obj/libOpenSave.so.0" "libs-OpenSave build; set OPENSAVE_ROOT"
require "$adwaita_theme/Adwaita" "built Adwaita GNUstep theme; set ADWAITA_THEME"

rm -rf "$stage_root"
runtime="$stage_root/runtime"
system_library="$runtime/System/Library"
mkdir -p "$stage_root/app" "$runtime/bin" "$runtime/lib" "$runtime/etc/GNUstep" \
  "$system_library/Libraries" "$system_library/Themes" \
  "$stage_root/metadata/icons" "$stage_root/metadata/licenses"

cp -R "$app_source" "$stage_root/app/LinDirStat.app"
# gnustep-make's launcher entry points at the build machine's openapp; the
# AppImage writes its own desktop entry.
rm -f "$stage_root/app/LinDirStat.app/Resources/LinDirStat.desktop" "$stage_root/app/LinDirStat.app/stamp.make"

# GNUstep resources: base/gui library resources, the back bundle, images,
# key bindings, colour pickers, fonts and printing support. Headers,
# documentation and make files are build-time only.
for item in Bundles ColorPickers Fonts Images KeyBindings PostScript Services Sounds; do
  if [[ -d "$gnustep_library/$item" ]]; then
    cp -R "$gnustep_library/$item" "$system_library/$item"
  fi
done
for item in gnustep-base gnustep-gui; do
  cp -R "$gnustep_library/Libraries/$item" "$system_library/Libraries/$item"
done
cp -R "$adwaita_theme" "$system_library/Themes/Adwaita.theme"
rm -f "$system_library/Themes/Adwaita.theme/stamp.make"

# Tools: defaults seeds packaged defaults from AppRun; gpbs and gdnc are the
# pasteboard and distributed-notification servers gnustep-gui starts.
for tool in defaults gpbs gdnc; do
  cp "$gnustep_tools/$tool" "$runtime/bin/$tool"
done

# The libraries themselves. libs-OpenSave and the GNUstep install come first;
# remaining dependencies come from the host (see scripts/stage-linux-runtime.py).
python3 "$repo_root/scripts/stage-linux-runtime.py" "$stage_root" \
  "$opensave_root/Source/obj" "$gnustep_library/Libraries" "$gnustep_root/lib"

# GNUstep.conf with paths relative to itself (gnustep-base resolves './' and
# '../' against the config file's directory), so the AppImage mount point can
# move. AppRun points GNUSTEP_CONFIG_FILE here. The user domain stays in the
# user's home directory as usual.
conf="$runtime/etc/GNUstep/GNUstep.conf"
{
  printf 'GNUSTEP_USER_CONFIG_FILE=.GNUstep.conf\n'
  printf 'GNUSTEP_USER_DEFAULTS_DIR=GNUstep/Defaults\n'
  printf 'GNUSTEP_MAKEFILES=../../System/Library/Makefiles\n'
  for users in SYSTEM NETWORK LOCAL; do
    printf 'GNUSTEP_%s_USERS_DIR=/home\n' "$users"
  done
  for domain in SYSTEM NETWORK LOCAL; do
    printf 'GNUSTEP_%s_APPS=../../System/Applications\n' "$domain"
    printf 'GNUSTEP_%s_ADMIN_APPS=../../System/Applications/Admin\n' "$domain"
    printf 'GNUSTEP_%s_WEB_APPS=../../System/Library/WebApplications\n' "$domain"
    printf 'GNUSTEP_%s_TOOLS=../../bin\n' "$domain"
    printf 'GNUSTEP_%s_ADMIN_TOOLS=../../bin\n' "$domain"
    printf 'GNUSTEP_%s_LIBRARY=../../System/Library\n' "$domain"
    printf 'GNUSTEP_%s_HEADERS=../../System/Library/Headers\n' "$domain"
    printf 'GNUSTEP_%s_LIBRARIES=../../lib\n' "$domain"
    printf 'GNUSTEP_%s_DOC=../../System/Library/Documentation\n' "$domain"
    printf 'GNUSTEP_%s_DOC_MAN=../../System/Library/Documentation/man\n' "$domain"
    printf 'GNUSTEP_%s_DOC_INFO=../../System/Library/Documentation/info\n' "$domain"
  done
  for dir in APPS:Applications ADMIN_APPS:Applications/Admin WEB_APPS:Library/WebApplications \
             TOOLS:Tools ADMIN_TOOLS:Tools/Admin LIBRARY:Library HEADERS:Library/Headers \
             LIBRARIES:Library/Libraries DOC:Library/Documentation \
             DOC_MAN:Library/Documentation/man DOC_INFO:Library/Documentation/info; do
    printf 'GNUSTEP_USER_DIR_%s=GNUstep/%s\n' "${dir%%:*}" "${dir#*:}"
  done
} > "$conf"
# Adwaita as the packaged default theme, with ifUnset semantics: gnustep-base
# reads GlobalDefaults.plist next to GNUstep.conf below the user's own
# NSGlobalDomain and app defaults, so a theme the user picked still wins.
# (GNUstep reads GSTheme only from defaults, never from the environment.)
#
# The rest is what the Adwaita theme needs from settings a GNOME user's
# GNUstep does not have yet, with the same ifUnset semantics:
# - GSX11HandlesWindowDecorations = NO: the theme draws the header bar (title,
#   window buttons, the toolbar in the bar's row). The theme asks for this
#   itself only with a patched libs-gui (plugins-themes-adwaita README,
#   "Header bar"); the bundled libs-gui is stock.
# - The Control key acts as GNUstep's Command key, so shortcuts are Ctrl+…
#   as in GNOME apps; Alt and Super take GNUstep's Control and Alternate.
cat > "$runtime/etc/GNUstep/GlobalDefaults.plist" <<'EOF'
{
  GSTheme = Adwaita;
  GSX11HandlesWindowDecorations = NO;
  GSFirstCommandKey = Control_L;
  GSSecondCommandKey = Control_R;
  GSFirstControlKey = Alt_L;
  GSSecondControlKey = Alt_R;
  GSFirstAlternateKey = Super_L;
  GSSecondAlternateKey = Super_R;
}
EOF
# gnustep-base ignores config files that group or others can write.
chmod 0644 "$conf" "$runtime/etc/GNUstep/GlobalDefaults.plist"

cp "$repo_root/packaging/linux/lindirstat.png" "$stage_root/metadata/icons/lindirstat.png"

licenses="$stage_root/metadata/licenses"
cat > "$licenses/WinDirStat-reference.txt" <<'EOF'
WinDirStat (GPL-2.0-or-later, https://github.com/windirstat/windirstat):
LinDirStat's translations (Resources/*.lproj) are generated from WinDirStat's
language files. Its source code is kept under references/WinDirStat as
reference material and is not compiled into LinDirStat.
EOF

notice() {
  local file="$1" name="$2" license="$3" url="$4" text="${5:-}"
  {
    printf '%s\nLicense: %s\nSource: %s\n' "$name" "$license" "$url"
    if [[ -n "$text" && -f "$text" ]]; then
      printf '\n'
      cat "$text"
    fi
  } > "$licenses/$file"
}
notice LinDirStat.txt "LinDirStat, a disk usage viewer inspired by WinDirStat" "GPL-2.0-or-later" \
  "https://github.com/danjboyd/LinDirStat" "$repo_root/COPYING"
notice GNUstep-base.txt "GNUstep Base (libgnustep-base)" "LGPL-2.1-or-later" \
  "https://github.com/gnustep/libs-base" "$HOME/git/gnustep/libs-base/COPYING.LIB"
notice GNUstep-gui.txt "GNUstep GUI (libgnustep-gui)" "LGPL-2.1-or-later" \
  "https://github.com/gnustep/libs-gui" "$HOME/git/gnustep/libs-gui/COPYING.LIB"
notice GNUstep-back.txt "GNUstep Back (libgnustep-back)" "LGPL-2.1-or-later" \
  "https://github.com/gnustep/libs-back" "$HOME/git/gnustep/libs-back/COPYING.LIB"
notice libobjc2.txt "libobjc2 (GNUstep Objective-C runtime)" "MIT" \
  "https://github.com/gnustep/libobjc2" "$HOME/git/gnustep/libobjc2/COPYING"
notice libdispatch.txt "libdispatch (swift-corelibs-libdispatch)" "Apache-2.0" \
  "https://github.com/swiftlang/swift-corelibs-libdispatch" "$HOME/git/gnustep/libdispatch/LICENSE"
notice libs-OpenSave.txt "libs-OpenSave" "LGPL-2.1-or-later" \
  "https://github.com/danjboyd/libs-OpenSave" "$opensave_root/LICENSE"
notice Adwaita-theme.txt "Adwaita GNUstep theme (plugins-themes-adwaita)" "LGPL-2.1-or-later" \
  "https://github.com/danjboyd/plugins-themes-Adwaita""$adwaita_theme/../COPYING.LIB"

cat > "$stage_root/metadata/stage-summary.json" <<EOF
{
  "app": "LinDirStat.app",
  "defaultTheme": "Adwaita",
  "referenceSource": "references/WinDirStat"
}
EOF

printf 'package-stage: staged %s (%s)\n' "$stage_root" "$(du -sh "$stage_root" | cut -f1)"
