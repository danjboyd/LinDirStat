#!/usr/bin/env bash
# Packages the Linux AppImage from the pinned inputs and runs the release
# checks on it. release-linux.sh runs it locally and the release workflow
# (.github/workflows/release.yml) on GitHub's runners, so both make and check
# the AppImage the same way. Nothing is signed or published here.
#
#   scripts/package-linux.sh [--release] [--version VERSION]
#
# --version packages VERSION instead of package.version (the workflow's
# release candidates). --release refuses inputs that are not at their pins
# (GNUSTEP_PACKAGER, ADWAITA_THEME or LIBS_BACK_BUNDLE naming another tree);
# without it they are used with a warning.
#
# Steps: packager manifest-check, build, stage, validate, package (AppImage)
# and validate with the smoke launch on a private Xvfb; then a new user's
# first launch without GNUstep (check-appimage-first-launch.sh), opening a
# folder (check-appimage-open-folder.sh) and Alt+F4 under GNOME Shell
# (check-appimage-alt-f4.sh). LINDIRSTAT_ALT_F4 is "required" (the default:
# a skip or failure fails) or "try" (the result is recorded; the workflow,
# where gnome-shell may not run, uses this and the local publish step runs
# the check again).
#
# Writes to dist/packages: the AppImage, its .zsync, the unsigned
# .update-feed.json, the packager's sidecars, and
# LinDirStat-VERSION-x86_64.provenance.json: the source commit, every pin,
# the build IDs of the Adwaita theme, libs-back and the GNUstep libraries
# inside the AppImage, and each check's result.
set -euo pipefail

release=0
version_override=""
while [ $# -gt 0 ]; do
  case "$1" in
    --release) release=1; shift ;;
    --version) version_override="${2:?--version needs a value}"; shift 2 ;;
    *) sed -n '2,27p' "$0" >&2; exit 2 ;;
  esac
done
alt_f4_mode="${LINDIRSTAT_ALT_F4:-required}"
case "$alt_f4_mode" in required|try) ;; *) echo "package-linux: LINDIRSTAT_ALT_F4 is required or try" >&2; exit 2 ;; esac

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"
pin="$repo_root/scripts/pinned-checkout.sh"

die() { echo "package-linux: $*" >&2; exit 1; }
warn() { echo "package-linux: warning: $*" >&2; }

# Inputs. A tree named in the environment may be used for a dry run, but a
# release is built only from trees at their pins.
pin_check() { # name dir
  "$pin" --verify "$1" "$2" && return 0
  [ "$release" = 1 ] && die "a release builds only from the pinned $1 (packaging/release-inputs.json)"
  warn "$1 is not at its pin; this is not a release build"
}
if [ -n "${GNUSTEP_PACKAGER:-}" ]; then
  packager_root="$GNUSTEP_PACKAGER"
  pin_check gnustep-packager "$packager_root"
else
  packager_root="$("$pin" gnustep-packager "$repo_root/out/gnustep-packager")"
fi
packager="$packager_root/scripts/gnustep-packager.ps1"
[ -f "$packager" ] || die "no gnustep-packager at $packager_root (set GNUSTEP_PACKAGER)"
"$repo_root/scripts/fetch-appimagetool.sh" "$packager_root" >/dev/null
if [ -n "${ADWAITA_THEME:-}" ]; then
  pin_check adwaita "$(dirname "$ADWAITA_THEME")"
fi
if [ -n "${LIBS_BACK_BUNDLE:-}" ]; then
  [ "$release" = 1 ] && die "a release builds libs-back from its lock file; unset LIBS_BACK_BUNDLE"
  warn "LIBS_BACK_BUNDLE is set; this is not a release build"
fi

version="${version_override:-$(python3 -c 'import json; print(json.load(open("package.manifest.json"))["package"]["version"])')}"
version_args=()
[ -n "$version_override" ] && version_args=(-PackageVersion "$version_override")
packager_commit="$(git -C "$packager_root" rev-parse HEAD)"
echo "package-linux: LinDirStat $version from $(git rev-parse --short HEAD), gnustep-packager ${packager_commit:0:7}"

work="$(mktemp -d "${TMPDIR:-/tmp}/lindirstat-package.XXXXXX")"
xvfb_pid=""
cleanup() {
  [ -n "$xvfb_pid" ] && kill "$xvfb_pid" 2>/dev/null || true
  rm -rf "$work"
}
trap cleanup EXIT

# Package and validate. The smoke launch runs on a private display with a
# private GNUstep home.
rm -rf dist/packages
for command in manifest-check build stage validate; do
  pwsh "$packager" -Manifest package.manifest.json -Command "$command" "${version_args[@]}"
done
pwsh "$packager" -Manifest package.manifest.json -Command package -Backend appimage "${version_args[@]}"

exec 3< <(Xvfb -displayfd 4 -screen 0 1280x800x24 -nolisten tcp 4>&1 2>/dev/null)
xvfb_pid=$!
read -r -t 10 display_number <&3 || die "Xvfb did not start"
mkdir -p "$work/home" "$work/xdg"
DISPLAY=":$display_number" GNUSTEP_HOME="$work/home" XDG_DATA_HOME="$work/xdg" XDG_CONFIG_HOME="$work/xdg" \
  DBUS_SESSION_BUS_ADDRESS=unix:path=/nonexistent \
  pwsh "$packager" -Manifest package.manifest.json -Command validate -Backend appimage -RunSmoke "${version_args[@]}"
kill "$xvfb_pid" 2>/dev/null || true
xvfb_pid=""

appimage="dist/packages/LinDirStat-$version-x86_64.AppImage"
feed="dist/packages/LinDirStat-$version-x86_64.update-feed.json"
for file in "$appimage" "$appimage.zsync" "$feed"; do
  [ -f "$file" ] || die "packaging did not produce $file"
done

# The release checks.
scripts/check-appimage-first-launch.sh "$appimage" || die "the AppImage does not start for a new user"
scripts/check-appimage-open-folder.sh "$appimage" || die "the AppImage does not offer to open folders, or does not scan the folder it is given"
alt_f4_log="$work/alt-f4.log"
if LINDIRSTAT_ALT_F4_REQUIRED=1 scripts/check-appimage-alt-f4.sh "$appimage" 2>&1 | tee "$alt_f4_log"; then
  alt_f4=passed
elif grep -q "alt-f4: SKIPPED" "$alt_f4_log"; then
  alt_f4=skipped
else
  alt_f4=failed
fi
if [ "$alt_f4" != passed ]; then
  [ "$alt_f4_mode" = required ] && die "Alt+F4 under GNOME Shell: $alt_f4"
  warn "Alt+F4 under GNOME Shell: $alt_f4; run scripts/check-appimage-alt-f4.sh on this AppImage before publishing it"
fi

# Provenance: what went in, and the build IDs of what came out.
(cd "$work" && "$repo_root/$appimage" --appimage-extract >/dev/null 2>&1) || die "could not extract $appimage"
build_id() { # file
  readelf -n "$1" 2>/dev/null | sed -n 's/^ *Build ID: *//p' | head -1
}
theme_id="$(build_id "$work/squashfs-root/usr/runtime/System/Library/Themes/Adwaita.theme/Adwaita")"
back_id="$(build_id "$work/squashfs-root/usr/runtime/System/Library/Bundles/libgnustep-back-032.bundle/libgnustep-back-032")"
[ -n "$theme_id" ] || die "no build ID for the AppImage's Adwaita theme"
[ -n "$back_id" ] || die "no build ID for the AppImage's libs-back"
runtime_lib="$work/squashfs-root/usr/runtime/lib"
toolchain_ids="$(for lib in libgnustep-base.so.1.31 libgnustep-gui.so.0.32 libobjc.so.4.6 libdispatch.so; do
  printf '%s=%s\n' "$lib" "$(build_id "$runtime_lib/$lib")"
done)"
python3 - "dist/packages/LinDirStat-$version-x86_64.provenance.json" <<PY
import json, sys
inputs = json.load(open("packaging/release-inputs.json"))
lock = json.load(open("packaging/linux/libs-back/libs-back.lock.json"))
def pin(name):
    return {k: v for k, v in inputs[name].items() if k != "comment"}
json.dump({
    "package": "LinDirStat",
    "version": "$version",
    "commit": "$(git rev-parse HEAD)",
    "builtBy": "${GITHUB_ACTIONS:+github-actions}" or "local",
    "run": "${GITHUB_SERVER_URL:-}/${GITHUB_REPOSITORY:-}/actions/runs/${GITHUB_RUN_ID:-}" if "${GITHUB_RUN_ID:-}" else None,
    "inputs": {
        "adwaita": pin("adwaita"),
        "gnustep-packager": dict(pin("gnustep-packager"), used="$packager_commit"),
        "appimagetool": pin("appimagetool"),
        "libs-back": {"revision": lock["revision"], "patches": [{"path": p["path"], "sha256": p["sha256"]} for p in lock["patches"]]},
    },
    "buildIds": {"adwaita": "$theme_id", "libs-back": "$back_id"},
    # The toolchain the AppImage bundles (the gnustep-cli-new install it was
    # built against), to compare builds made on different machines.
    "toolchainBuildIds": dict(line.split("=", 1) for line in """$toolchain_ids""".split()),
    "checks": {"validate+smoke": "passed", "first-launch": "passed", "open-folder": "passed", "alt-f4": "$alt_f4"},
}, open(sys.argv[1], "w"), indent=2)
open(sys.argv[1], "a").write("\n")
PY
echo "package-linux: $appimage packaged and checked (Alt+F4 $alt_f4); provenance in dist/packages"
