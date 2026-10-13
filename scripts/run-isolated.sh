#!/usr/bin/env bash
# Runs the app (or any GNUstep app bundle) with its own GNUstep home, so test
# runs never read or write the user's ~/GNUstep/Defaults.
#
#   scripts/run-isolated.sh HOME_DIR [APP_BUNDLE] [ARGS...]
#
# HOME_DIR/GNUstep/Defaults is created and seeded with the user's global
# domain (theme and key mapping); HOME_DIR/GNUstep/Library links to the
# user's so the Adwaita theme is found. Neither $HOME nor
# GNUSTEP_USER_DEFAULTS_DIR isolates gnustep-base (it takes the home from
# the user database and ignores that variable), and openapp's GNUstep.sh
# unsets GNUSTEP_HOME, so a wrapper sets it again just before the app runs.
# Add DISPLAY, DBUS_SESSION_BUS_ADDRESS and XDG_DATA_HOME as needed.
set -euo pipefail

home="$(cd "$1" 2>/dev/null && pwd || { mkdir -p "$1" && cd "$1" && pwd; })"
shift
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app="${1:-$repo_root/Source/LinDirStat.app}"
[[ $# -gt 0 ]] && shift

mkdir -p "$home/GNUstep/Defaults"
if [[ ! -e "$home/GNUstep/Library" && -d "$HOME/GNUstep/Library" ]]; then
  ln -s "$HOME/GNUstep/Library" "$home/GNUstep/Library"
fi
if [[ ! -e "$home/GNUstep/Defaults/NSGlobalDomain.plist" && -f "$HOME/GNUstep/Defaults/NSGlobalDomain.plist" ]]; then
  cp "$HOME/GNUstep/Defaults/NSGlobalDomain.plist" "$home/GNUstep/Defaults/"
fi

wrapper="$home/.run-isolated-wrapper"
cat > "$wrapper" <<EOF
#!/bin/sh
[ "\$1" = "--args" ] && shift
export GNUSTEP_HOME="$home"
exec "\$@"
EOF
chmod +x "$wrapper"

# shellcheck source=scripts/gnustep-env.sh
. "$repo_root/scripts/gnustep-env.sh"
gnustep_source_env
exec openapp --debug --gdb="$wrapper" "$app" "$@"
