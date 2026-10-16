#!/usr/bin/env bash
# Builds, checks and (with --publish) publishes a LinDirStat AppImage
# release that installed copies update to (docs/updates.md).
#
#   scripts/release-linux.sh            # dry run: build, validate, sign, test
#   scripts/release-linux.sh --publish  # the same, then publish
#
# The version is package.version in package.manifest.json; the release is
# tag v<version> in the public releases repository (updates.github in the
# manifest). Run it from a clean checkout of main at the commit to release.
#
# Steps:
#   1. scripts/package-linux.sh: package the AppImage from the pinned inputs
#      and validate it, with the smoke launch on a private Xvfb, then check a
#      new user's first launch without GNUstep, opening a folder, and that
#      Alt+F4 under GNOME Shell closes windows rather than killing the app
#      (needs gnome-shell); the release workflow runs the same script;
#   2. sign the update feed with the update key (UPDATE_ED_PRIVATE_KEY, else
#      the file UPDATE_ED_PRIVATE_KEY_FILE, default
#      ~/.config/lindirstat/update-ed25519.key), which must match the
#      manifest's updates.publicEDKey;
#   3. when the releases repository has a release, check that it updates to
#      this one (scripts/test-appimage-update.sh);
#   4. with --publish: create the GitHub release with the AppImage, its .zsync
#      and the sidecars, attach SHA256SUMS (scripts/release-sha256sums.sh),
#      then publish the feed to the releases repository's
#      gh-pages branch at updates/linux/stable.json, and tag the source
#      commit. A version with "-" (0.2.0-rc1) is a pre-release: it gets a
#      release but not the feed, so installed copies are not offered it.
#
# Inputs: gnustep-packager, the Adwaita theme and appimagetool at their pins
# in packaging/release-inputs.json (in out/), libs-back from its
# lock file, and the GNUstep build inputs docs/packaging.md lists. For a dry
# run GNUSTEP_PACKAGER, ADWAITA_THEME and LIBS_BACK_BUNDLE may name local
# trees; --publish refuses any that is not at its pin.
set -euo pipefail

publish=0
case "${1:-}" in
  "") ;;
  --publish) publish=1 ;;
  *) sed -n '2,35p' "$0" >&2; exit 2 ;;
esac

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

die() { echo "release-linux: $*" >&2; exit 1; }
manifest_value() {
  python3 -c 'import json, sys
value = json.load(open("package.manifest.json"))
for key in sys.argv[1].split("."):
    value = value[key]
print(value)' "$1"
}

version="$(manifest_value package.version)"
tag="v$version"
owner="$(manifest_value updates.github.owner)"
releases_repo="$owner/$(manifest_value updates.github.repo)"
public_key="$(manifest_value updates.publicEDKey)"
feed_url="$(manifest_value backends.appimage.updates.feedUrl)"
prerelease=0
[[ "$version" == *-* ]] && prerelease=1

# The source is what gets released: a clean main.
commit="$(git rev-parse HEAD)"
[ -z "$(git status --porcelain)" ] || die "the working tree has changes; release a commit"
if [ "$publish" = 1 ]; then
  [ "$(git rev-parse --abbrev-ref HEAD)" = main ] || die "publish from main"
  git fetch -q origin main
  [ "$(git rev-parse origin/main)" = "$commit" ] || die "HEAD is not origin/main"
fi
if [ "$publish" = 1 ]; then
  gh repo view "$releases_repo" >/dev/null 2>&1 || die "no releases repository $releases_repo (see docs/updates.md)"
fi
if gh release view "$tag" --repo "$releases_repo" >/dev/null 2>&1; then
  die "$releases_repo already has $tag; bump package.version"
fi

if [ -z "${UPDATE_ED_PRIVATE_KEY:-}" ]; then
  key_file="${UPDATE_ED_PRIVATE_KEY_FILE:-$HOME/.config/lindirstat/update-ed25519.key}"
  [ -r "$key_file" ] || die "no update key (UPDATE_ED_PRIVATE_KEY or $key_file)"
  UPDATE_ED_PRIVATE_KEY="$(cat "$key_file")"
fi
export UPDATE_ED_PRIVATE_KEY UPDATE_ED_PUBLIC_KEY="$public_key"

echo "release-linux: LinDirStat $version from $(git rev-parse --short HEAD)"

work="$(mktemp -d "${TMPDIR:-/tmp}/lindirstat-release.XXXXXX")"
trap 'rm -rf "$work"' EXIT

# 1. Package from the pinned inputs and run the release checks
# (scripts/package-linux.sh; --release refuses inputs off their pins).
package_flags=()
[ "$publish" = 1 ] && package_flags+=(--release)
LINDIRSTAT_ALT_F4=required scripts/package-linux.sh "${package_flags[@]}"

appimage="dist/packages/LinDirStat-$version-x86_64.AppImage"
feed="dist/packages/LinDirStat-$version-x86_64.update-feed.json"
provenance="dist/packages/LinDirStat-$version-x86_64.provenance.json"
packager_commit="$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["inputs"]["gnustep-packager"]["used"][:7])' "$provenance")"
python3 - "$feed" "$feed_url" "$releases_repo" "$tag" <<'PY' || die "the feed does not describe this release"
import json, sys
feed = json.load(open(sys.argv[1], encoding="utf-8-sig"))
assert feed["feedUrl"] == sys.argv[2], feed["feedUrl"]
url = feed["releases"][0]["assets"][0]["url"]
assert url.startswith("https://github.com/%s/releases/download/%s/" % (sys.argv[3], sys.argv[4])), url
PY

# 2. Sign every payload in the feed.
python3 scripts/sign-update-feed.py "$feed" dist/packages

# 3. The current release must update to this one.
if gh release view --repo "$releases_repo" >/dev/null 2>&1; then
  mkdir -p "$work/previous"
  gh release download --repo "$releases_repo" --pattern '*.AppImage' --dir "$work/previous"
  previous="$(ls "$work/previous"/*.AppImage | head -1)"
  scripts/test-appimage-update.sh "$previous" "$appimage" "$feed"
else
  echo "release-linux: $releases_repo has no release yet; the update test needs one, skipped"
fi

if [ "$publish" = 0 ]; then
  echo "release-linux: dry run done; dist/packages has the signed release. Publish with --publish."
  exit 0
fi

# 4. Publish: the release, then the feed that offers it, then the tag. The
# .metadata.json and .diagnostics.txt sidecars stay in dist/packages: they
# hold the build machine's paths, and neither users nor the updater need them.
notes="$work/notes.md"
{
  echo "LinDirStat $version for Linux (x86_64 AppImage)."
  echo
  echo "Built from danjboyd/LinDirStat \`$(git rev-parse --short HEAD)\` with gnustep-packager \`$packager_commit\`."
  # What changed, from packaging/linux/release-notes/<version>.md if there is one.
  if [ -f "packaging/linux/release-notes/$version.md" ]; then
    echo
    cat "packaging/linux/release-notes/$version.md"
  fi
} > "$notes"
release_flags=()
[ "$prerelease" = 1 ] && release_flags+=(--prerelease)
gh release create "$tag" --repo "$releases_repo" --title "LinDirStat $version" --notes-file "$notes" \
  "${release_flags[@]}" \
  "$appimage" "$appimage.zsync" "$feed"
scripts/release-sha256sums.sh "$tag"

if [ "$prerelease" = 0 ]; then
  pages="$work/pages"
  git clone -q --depth 1 --branch gh-pages "https://github.com/$releases_repo.git" "$pages" 2>/dev/null || {
    git init -q "$pages"
    git -C "$pages" checkout -q --orphan gh-pages
    git -C "$pages" remote add origin "https://github.com/$releases_repo.git"
  }
  mkdir -p "$pages/updates/linux"
  cp "$feed" "$pages/updates/linux/stable.json"
  touch "$pages/.nojekyll"
  git -C "$pages" add .nojekyll updates/linux/stable.json
  git -C "$pages" commit -q -m "Linux stable feed: LinDirStat $version"
  git -C "$pages" push -q origin HEAD:gh-pages
  echo "release-linux: feed published; $feed_url offers $version once Pages has deployed"
fi

git tag -a "$tag" -m "LinDirStat $version" "$commit"
git push -q origin "$tag"
echo "release-linux: released $tag"
