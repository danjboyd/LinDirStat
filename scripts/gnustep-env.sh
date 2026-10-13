# Sourced by the other scripts: the GNUstep install LinDirStat builds, tests
# and packages against.
#
# The default is the gnustep-clang apt packages in /usr/GNUstep. Set
# LINDIRSTAT_GNUSTEP_ROOT to use another install, such as a gnustep-cli-new
# prefix (~/.local/share/gnustep-cli).
#
# Sets gnustep_root, gnustep_makefiles, gnustep_library (resources, bundles
# and libraries) and gnustep_tools. The apt packages install into the System
# domain and gnustep-cli-new into Local. gnustep_source_env loads the
# environment (GNUstep.sh).

gnustep_root="${LINDIRSTAT_GNUSTEP_ROOT:-/usr/GNUstep}"
gnustep_makefiles="$gnustep_root/System/Library/Makefiles"
if [[ -d "$gnustep_root/Local/Library/Libraries/gnustep-base" ]]; then
  gnustep_library="$gnustep_root/Local/Library"
  gnustep_tools="$gnustep_root/Local/Tools"
else
  gnustep_library="$gnustep_root/System/Library"
  gnustep_tools="$gnustep_root/System/Tools"
fi

gnustep_source_env() {
  if [[ ! -f "$gnustep_makefiles/GNUstep.sh" ]]; then
    echo "no GNUstep install at $gnustep_root (install the gnustep-clang packages or set LINDIRSTAT_GNUSTEP_ROOT)" >&2
    exit 1
  fi
  local nounset=0
  [[ $- == *u* ]] && nounset=1
  set +u
  # shellcheck disable=SC1091
  . "$gnustep_makefiles/GNUstep.sh"
  [[ $nounset == 1 ]] && set -u
  return 0
}
