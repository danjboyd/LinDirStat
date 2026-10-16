#!/usr/bin/env bash
# The release workflow's macOS job (.github/workflows/release.yml), on a
# macos-15 runner: the universal DMG through gnustep-packager's dmg backend,
# with the packager at its pin in packaging/release-inputs.json, then the
# backend's validation with the launch smoke. The DMG stays ad-hoc signed
# (backends.dmg.signing in package.manifest.json); no secrets are used.
# Collects the DMG and its .sha256 in dist/ci/macos (the packager's sidecars,
# which hold the runner's paths, stay in the logs).
#
#   scripts/ci-release-macos.sh [VERSION]   # default: package.version
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

die() { echo "ci-release-macos: $*" >&2; exit 1; }
step() { printf '\n== %s\n' "$*"; }

version="${1:-$(python3 -c 'import json; print(json.load(open("package.manifest.json"))["package"]["version"])')}"
version_args=()
[ -n "${1:-}" ] && version_args=(-PackageVersion "$1")

step "gnustep-packager"
packager_root="$(scripts/pinned-checkout.sh gnustep-packager "$repo_root/out/gnustep-packager")"
packager="$packager_root/scripts/gnustep-packager.ps1"
git -C "$packager_root" log -1 --format='%H %s'
pwsh -NoLogo -NoProfile -Command '$PSVersionTable.PSVersion.ToString()'
xcodebuild -version

step "Package and validate"
rm -rf dist/packages
for command in manifest-check build stage validate; do
  pwsh "$packager" -Manifest package.manifest.json -Command "$command" ${version_args[@]+"${version_args[@]}"}
done
pwsh "$packager" -Manifest package.manifest.json -Command package -Backend dmg ${version_args[@]+"${version_args[@]}"}
pwsh "$packager" -Manifest package.manifest.json -Command validate -Backend dmg -RunSmoke ${version_args[@]+"${version_args[@]}"}

dmg="dist/packages/LinDirStat-$version-macos-universal.dmg"
[ -f "$dmg" ] || die "packaging did not produce $dmg"
codesign --verify --deep --strict --verbose=2 macos/build/LinDirStat.app

step "Collect"
out="dist/ci/macos"
rm -rf "$out"
mkdir -p "$out"
cp "$dmg" "$out/"
(cd "$out" && shasum -a 256 "$(basename "$dmg")" > "$(basename "$dmg").sha256")
ls -l "$out"
