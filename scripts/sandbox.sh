# Sourced by the scripts that launch LinDirStat's AppImage (the check-appimage
# checks, test-appimage-update.sh, package-linux.sh and release-linux.sh):
#
#   . "$(dirname "${BASH_SOURCE[0]}")/sandbox.sh"
#   ld_sandbox "$@"
#
# ld_sandbox runs the calling script again inside bwrap with an empty home
# bound over the real one, and exits with its status; inside, it returns at
# once. A packaged AppImage's AppRun points GNUstep at its own GNUstep.conf,
# whose relative defaults folder resolves against the passwd home, so a
# private HOME or GNUSTEP_HOME alone does not keep a launch out of your
# ~/GNUstep/Defaults. Only these are bound back from the real home: this
# checkout (read-write), and read-only the update signing key
# (~/.config/lindirstat, or UPDATE_ED_PRIVATE_KEY_FILE), the gnustep-cli
# toolchain (GNUSTEP_CLI_ROOT), ~/.gitconfig, the trees GNUSTEP_PACKAGER,
# ADWAITA_THEME, LIBS_BACK_BUNDLE and TOOLS_XCTEST_ROOT name, and any path
# argument. DISPLAY, WAYLAND_DISPLAY and the session bus are dropped, so
# nothing can reach your desktop; GitHub access goes through GH_TOKEN (taken
# from `gh auth token` when unset, as the keyring is out of reach), which
# gh and git's gh credential helper use. /dev has no fuse device in there
# (setuid fusermount cannot work under bwrap), so AppImages run extracted.
# LinDirStat's own defaults and the global domain in the real
# ~/GNUstep/Defaults are compared before and after (other apps' files may
# change meanwhile); a change fails the run.
#
# LINDIRSTAT_SANDBOX: auto (the default: sandbox when bwrap works, not on CI,
# where there is no one's home to protect), required, or off.

ld_sandbox() {
  [ -n "${LINDIRSTAT_SANDBOXED:-}" ] && return 0
  local mode="${LINDIRSTAT_SANDBOX:-auto}"
  case "$mode" in
    off) return 0 ;;
    auto) [ "${CI:-}" = true ] && return 0 ;;
    required) ;;
    *) echo "sandbox: LINDIRSTAT_SANDBOX is auto, required or off" >&2; exit 2 ;;
  esac
  if ! command -v bwrap >/dev/null 2>&1 || ! bwrap --dev-bind / / true 2>/dev/null; then
    if [ "$mode" = required ]; then
      echo "sandbox: bwrap is missing or cannot run here" >&2
      exit 1
    fi
    echo "sandbox: bwrap is missing or cannot run here; running unsandboxed" >&2
    return 0
  fi

  local script real_home repo private
  script="$(realpath "$0")"
  real_home="$(getent passwd "$(id -u)" | cut -d: -f6)"
  repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  private="$(mktemp -d "${TMPDIR:-/tmp}/lindirstat-sandbox-home.XXXXXX")"

  local args=(--dev-bind / / --dev /dev --bind "$private" "$real_home")
  local path
  ld_sandbox_bind() {
    path="$(realpath -e "$2" 2>/dev/null)" || return 0
    case "$path" in
      "$real_home"/*) args+=("$1" "$path" "$path") ;;
    esac
  }
  ld_sandbox_bind --bind "$repo"
  ld_sandbox_bind --ro-bind "${UPDATE_ED_PRIVATE_KEY_FILE:-$real_home/.config/lindirstat}"
  ld_sandbox_bind --ro-bind "${GNUSTEP_CLI_ROOT:-$real_home/.local/share/gnustep-cli}"
  ld_sandbox_bind --ro-bind "$real_home/.gitconfig"
  local tree
  for tree in "${GNUSTEP_PACKAGER:-}" "${ADWAITA_THEME:-}" "${LIBS_BACK_BUNDLE:-}" "${TOOLS_XCTEST_ROOT:-}"; do
    [ -n "$tree" ] && ld_sandbox_bind --ro-bind "$tree"
  done
  local arg
  for arg in "$@"; do
    case "$arg" in
      "$repo"|"$repo"/*) ;;
      *) [ -e "$arg" ] && ld_sandbox_bind --ro-bind "$arg" ;;
    esac
  done
  local dir="$PWD"
  case "$dir" in
    "$real_home"|"$real_home"/*) case "$dir" in "$repo"|"$repo"/*) ;; *) dir="$repo" ;; esac ;;
  esac

  local token="${GH_TOKEN:-}"
  if [ -z "$token" ] && command -v gh >/dev/null 2>&1; then
    token="$(gh auth token 2>/dev/null || true)"
  fi

  ld_sandbox_defaults() {
    stat -c '%n %Y %s' "$real_home"/GNUstep/Defaults/LinDirStat*.plist \
      "$real_home"/GNUstep/Defaults/NSGlobalDomain.plist 2>/dev/null || true
  }
  local before after status
  before="$(ld_sandbox_defaults)"
  set +e
  env -u DISPLAY -u WAYLAND_DISPLAY -u DBUS_SESSION_BUS_ADDRESS \
    LINDIRSTAT_SANDBOXED=1 ${token:+GH_TOKEN="$token"} \
    bwrap "${args[@]}" --chdir "$dir" "$script" "$@"
  status=$?
  set -e
  after="$(ld_sandbox_defaults)"
  rm -rf "${private:?}"
  if [ "$before" != "$after" ]; then
    echo "sandbox: $real_home/GNUstep/Defaults changed during the run:" >&2
    diff <(printf '%s\n' "$before") <(printf '%s\n' "$after") >&2 || true
    [ "$status" -eq 0 ] && status=1
  fi
  exit "$status"
}
