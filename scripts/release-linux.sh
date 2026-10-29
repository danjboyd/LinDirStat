#!/usr/bin/env bash
# Builds or takes, checks and (with --publish) publishes a LinDirStat release
# that installed copies update to (docs/updates.md, "Releasing").
#
#   scripts/release-linux.sh                     # dry run: build here, check, sign, test
#   scripts/release-linux.sh --from-ci RUN_ID    # dry run from a release workflow run
#   scripts/release-linux.sh [--from-ci RUN_ID] --publish   # the same, then publish
#
# Run it from a clean checkout of main at the commit to release. Built here,
# the version is package.version in package.manifest.json. With --from-ci it
# is the version the run packaged (a release candidate such as 0.1.4-rc1, or
# package.version), and the checkout must be at the run's commit; for a pull
# request's run (a dry run only) that is GitHub's merge commit, which it
# built and its provenance names (git fetch origin <sha>; pull/N/merge while
# the pull request is open). Use a clone, not a git worktree: the sandbox
# can't follow a worktree's link to its repository. The release
# is tag v<version> in the public releases repository (updates.github in the
# manifest).
#
# Steps:
#   1. built here: scripts/package-linux.sh packages the AppImage from the
#      pinned inputs and validates it, with the smoke launch on a private
#      Xvfb, then checks a new user's first launch without GNUstep, opening a
#      folder, and that Alt+F4 under GNOME Shell closes windows rather than
#      killing the app (needs gnome-shell).
#      --from-ci: downloads the run's "release" artifact (the AppImage, .zsync,
#      unsigned feed, provenance and the macOS DMG), checks it against its
#      SHA256SUMS, checks that the provenance names this commit and the pins
#      in this checkout and that the build IDs of the Adwaita theme and
#      libs-back inside the AppImage are the provenance's and those of local
#      builds of the pins (scripts/build-adwaita.sh, build-libs-back.sh), then
#      runs the first-launch, open-folder and Alt+F4 checks on the AppImage
#      again here, on a desktop machine rather than a container;
#   2. checks the feed describes this release and its files (URL, sha256,
#      size), then signs it with the update key (UPDATE_ED_PRIVATE_KEY, else
#      the file UPDATE_ED_PRIVATE_KEY_FILE, default
#      ~/.config/lindirstat/update-ed25519.key), which must match the
#      manifest's updates.publicEDKey; the key never leaves this machine;
#   3. when the releases repository has a release, checks that it updates to
#      this one (scripts/test-appimage-update.sh);
#   4. with --publish: creates the GitHub release with the AppImage, its .zsync
#      and the feed (and, from CI, the DMG and its .sha256), attaches
#      SHA256SUMS (scripts/release-sha256sums.sh), publishes the feed to the
#      releases repository's gh-pages branch at updates/linux/stable.json, and
#      tags the source commit unless the tag is already there. A version with
#      "-" (0.2.0-rc1) is a pre-release: it gets a release but not the feed,
#      so installed copies are not offered it.
#
# Inputs (built here): gnustep-packager, the Adwaita theme and appimagetool
# at their pins in packaging/release-inputs.json (in out/), libs-back from
# its lock file, and the GNUstep build inputs docs/packaging.md lists. For a
# dry run GNUSTEP_PACKAGER, ADWAITA_THEME and LIBS_BACK_BUNDLE may name local
# trees; --publish refuses any that is not at its pin.
set -euo pipefail
# Runs again inside a private-home bwrap sandbox (scripts/sandbox.sh).
. "$(dirname "${BASH_SOURCE[0]}")/sandbox.sh"
ld_sandbox "$@"

publish=0
run_id=""
while [ $# -gt 0 ]; do
  case "$1" in
    --publish) publish=1; shift ;;
    --from-ci) run_id="${2:?--from-ci needs a run id}"; shift 2 ;;
    *) sed -n '2,49p' "$0" >&2; exit 2 ;;
  esac
done

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
json_value() { # file key.path
  python3 -c 'import json, sys
value = json.load(open(sys.argv[1], encoding="utf-8-sig"))
for key in sys.argv[2].split("."):
    value = value[key]
print(value)' "$1" "$2"
}
build_id() { # file
  readelf -n "$1" 2>/dev/null | sed -n 's/^ *Build ID: *//p' | head -1
}

owner="$(manifest_value updates.github.owner)"
releases_repo="$owner/$(manifest_value updates.github.repo)"
public_key="$(manifest_value updates.publicEDKey)"
feed_url="$(manifest_value backends.appimage.updates.feedUrl)"
manifest_version="$(manifest_value package.version)"

# The source is what gets released: a clean main.
commit="$(git rev-parse HEAD)"
[ -z "$(git status --porcelain)" ] || die "the working tree has changes; release a commit"
if [ "$publish" = 1 ]; then
  [ "$(git rev-parse --abbrev-ref HEAD)" = main ] || die "publish from main"
  git fetch -q origin main
  [ "$(git rev-parse origin/main)" = "$commit" ] || die "HEAD is not origin/main"
  gh repo view "$releases_repo" >/dev/null 2>&1 || die "no releases repository $releases_repo (see docs/updates.md)"
fi

work="$(mktemp -d "${TMPDIR:-/tmp}/lindirstat-release.XXXXXX")"
trap 'rm -rf "$work"' EXIT

if [ -z "$run_id" ]; then
  # 1. Package here from the pinned inputs and run the release checks
  # (scripts/package-linux.sh; --release refuses inputs off their pins).
  version="$manifest_version"
  package_flags=()
  [ "$publish" = 1 ] && package_flags+=(--release)
  LINDIRSTAT_ALT_F4=required scripts/package-linux.sh "${package_flags[@]}"
  built_by="Built from danjboyd/LinDirStat \`${commit:0:7}\`"
else
  # 1. Take a release workflow run's artifacts, and check them.
  run_json="$(gh run view "$run_id" --json workflowName,headSha,status,conclusion,url,event)" || die "no workflow run $run_id"
  [ "$(printf '%s' "$run_json" | python3 -c 'import json,sys; r=json.load(sys.stdin); print(r["workflowName"], r["status"], r["conclusion"])')" = "Release completed success" ] ||
    die "run $run_id is not a successful Release workflow run"
  run_sha="$(printf '%s' "$run_json" | python3 -c 'import json,sys; print(json.load(sys.stdin)["headSha"])')"
  run_url="$(printf '%s' "$run_json" | python3 -c 'import json,sys; print(json.load(sys.stdin)["url"])')"
  run_event="$(printf '%s' "$run_json" | python3 -c 'import json,sys; print(json.load(sys.stdin)["event"])')"
  if [ "$run_event" = pull_request ]; then
    # A pull request's run builds GitHub's merge of the branch into main
    # (refs/pull/N/merge), and its provenance names that merge: check it
    # out (git fetch origin pull/N/merge). Dry runs only.
    [ "$publish" = 0 ] || die "run $run_id is a pull request's; publish a run on main"
    [ "$(git rev-parse -q --verify "$commit^2" || true)" = "$run_sha" ] ||
      die "run $run_id is pull request ${run_sha:0:7}'s; check out the merge commit its provenance names (git fetch origin <sha>)"
  else
    [ "$run_sha" = "$commit" ] || die "run $run_id built ${run_sha:0:7}; check out that commit (HEAD is ${commit:0:7})"
  fi

  ci="dist/ci/run-$run_id"
  rm -rf "$ci"
  gh run download "$run_id" --name release --dir "$ci" || die "could not download the run's release artifact"
  scripts/release-sha256sums.sh --check-dir "$ci" || die "the run's artifact does not match its SHA256SUMS"
  set -- "$ci"/*.provenance.json
  [ -f "$1" ] && [ $# -eq 1 ] || die "the run's artifact has no single provenance file"
  ci_provenance="$1"
  version="$(json_value "$ci_provenance" version)"
  [ "$(json_value "$ci_provenance" commit)" = "$commit" ] || die "the provenance names another commit"
  if [ "$version" != "$manifest_version" ] && [[ "$version" != *-* ]]; then
    die "the run packaged $version, not package.version $manifest_version; only a pre-release may differ"
  fi

  # The provenance must name the pins in this checkout.
  python3 - "$ci_provenance" <<'PY' || die "the provenance's inputs are not this checkout's pins"
import json, sys
p = json.load(open(sys.argv[1]))["inputs"]
inputs = json.load(open("packaging/release-inputs.json"))
lock = json.load(open("packaging/linux/libs-back/libs-back.lock.json"))
for name in ("adwaita", "gnustep-packager", "appimagetool"):
    want = {k: v for k, v in inputs[name].items() if k != "comment"}
    got = {k: v for k, v in p[name].items() if k != "used"}
    assert got == want, (name, got, want)
assert p["gnustep-packager"]["used"] == inputs["gnustep-packager"]["revision"], p["gnustep-packager"]
assert p["libs-back"]["revision"] == lock["revision"], p["libs-back"]
assert p["libs-back"]["patches"] == [{"path": x["path"], "sha256": x["sha256"]} for x in lock["patches"]], p["libs-back"]
PY

  rm -rf dist/packages
  mkdir -p dist/packages
  cp "$ci"/LinDirStat-"$version"-x86_64.* dist/packages/
  # Workflow artifacts lose the execute bit.
  chmod +x "dist/packages/LinDirStat-$version-x86_64.AppImage"
  appimage="dist/packages/LinDirStat-$version-x86_64.AppImage"

  # The build IDs inside the AppImage, against the provenance and against
  # builds of the pins made here.
  (cd "$work" && "$repo_root/$appimage" --appimage-extract >/dev/null 2>&1) || die "could not extract $appimage"
  theme_id="$(build_id "$work/squashfs-root/usr/runtime/System/Library/Themes/Adwaita.theme/Adwaita")"
  back_id="$(build_id "$work/squashfs-root/usr/runtime/System/Library/Bundles/libgnustep-back-032.bundle/libgnustep-back-032")"
  [ "$theme_id" = "$(json_value "$ci_provenance" buildIds.adwaita)" ] || die "the AppImage's Adwaita is not the one its provenance names"
  [ "$back_id" = "$(json_value "$ci_provenance" buildIds.libs-back)" ] || die "the AppImage's libs-back is not the one its provenance names"
  local_theme_id="$(build_id "$(scripts/build-adwaita.sh)/Adwaita")"
  local_back_id="$(build_id "$(scripts/build-libs-back.sh)/libgnustep-back-032")"
  [ "$theme_id" = "$local_theme_id" ] || die "the AppImage's Adwaita ($theme_id) is not the pinned build ($local_theme_id)"
  [ "$back_id" = "$local_back_id" ] || die "the AppImage's libs-back ($back_id) is not the pinned build ($local_back_id)"
  echo "release-linux: build IDs match the pins: Adwaita $theme_id, libs-back $back_id"

  # The release checks, here, on the AppImage CI built.
  scripts/check-appimage-first-launch.sh "$appimage" || die "the AppImage does not start for a new user"
  scripts/check-appimage-open-folder.sh "$appimage" || die "the AppImage does not offer to open folders, or does not scan the folder it is given"
  LINDIRSTAT_ALT_F4_REQUIRED=1 scripts/check-appimage-alt-f4.sh "$appimage" || die "Alt+F4 under GNOME Shell does not close the AppImage's windows cleanly"
  built_by="Built by the release workflow ($run_url) from danjboyd/LinDirStat \`${commit:0:7}\`"
fi

tag="v$version"
prerelease=0
[[ "$version" == *-* ]] && prerelease=1
if gh release view "$tag" --repo "$releases_repo" >/dev/null 2>&1; then
  die "$releases_repo already has $tag; bump package.version"
fi
appimage="dist/packages/LinDirStat-$version-x86_64.AppImage"
feed="dist/packages/LinDirStat-$version-x86_64.update-feed.json"
provenance="dist/packages/LinDirStat-$version-x86_64.provenance.json"
packager_commit="$(json_value "$provenance" inputs.gnustep-packager.used)"
echo "release-linux: LinDirStat $version from ${commit:0:7}, gnustep-packager ${packager_commit:0:7}"

# 2. The feed must describe this release and these files; then sign it.
python3 - "$feed" "$feed_url" "$releases_repo" "$tag" dist/packages <<'PY' || die "the feed does not describe this release"
import hashlib, json, os, sys
feed_path, feed_url, repo, tag, folder = sys.argv[1:]
feed = json.load(open(feed_path, encoding="utf-8-sig"))
assert feed["feedUrl"] == feed_url, feed["feedUrl"]
prefix = "https://github.com/%s/releases/download/%s/" % (repo, tag)
def check(entry):
    assert entry["url"] == prefix + entry["name"], entry["url"]
    path = os.path.join(folder, entry["name"])
    data = open(path, "rb").read()
    assert entry["sha256"] == hashlib.sha256(data).hexdigest(), (entry["name"], "sha256")
    assert entry["sizeBytes"] == len(data), (entry["name"], "size")
for release in feed["releases"]:
    for asset in release["assets"]:
        check(asset)
        if "zsync" in asset:
            check(asset["zsync"])
PY

if [ -z "${UPDATE_ED_PRIVATE_KEY:-}" ]; then
  key_file="${UPDATE_ED_PRIVATE_KEY_FILE:-$HOME/.config/lindirstat/update-ed25519.key}"
  [ -r "$key_file" ] || die "no update key (UPDATE_ED_PRIVATE_KEY or $key_file)"
  UPDATE_ED_PRIVATE_KEY="$(cat "$key_file")"
fi
export UPDATE_ED_PRIVATE_KEY UPDATE_ED_PUBLIC_KEY="$public_key"
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
assets=("$appimage" "$appimage.zsync" "$feed")
platforms="Linux (x86_64 AppImage)"
if [ -n "$run_id" ]; then
  dmg="$ci/LinDirStat-$version-macos-universal.dmg"
  if [ -f "$dmg" ]; then
    assets+=("$dmg" "$dmg.sha256")
    platforms="$platforms and macOS (universal DMG, ad-hoc signed)"
  fi
fi
notes="$work/notes.md"
{
  echo "LinDirStat $version for $platforms."
  echo
  echo "$built_by with gnustep-packager \`${packager_commit:0:7}\`."
  # What changed, from packaging/linux/release-notes/<version>.md if there
  # is one (a release candidate uses its release's notes).
  notes_file="packaging/linux/release-notes/${version%%-*}.md"
  if [ -f "$notes_file" ]; then
    echo
    cat "$notes_file"
  fi
} > "$notes"
release_flags=()
[ "$prerelease" = 1 ] && release_flags+=(--prerelease)
gh release create "$tag" --repo "$releases_repo" --title "LinDirStat $version" --notes-file "$notes" \
  "${release_flags[@]}" "${assets[@]}"
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

# A tag push may have started the run: then the tag is already there.
if remote_tag="$(git ls-remote origin "refs/tags/$tag^{}" | cut -f1)" && [ -n "$remote_tag" ]; then
  [ "$remote_tag" = "$commit" ] || die "tag $tag already names ${remote_tag:0:7}, not ${commit:0:7}"
  echo "release-linux: tag $tag was already pushed"
else
  git tag -a "$tag" -m "LinDirStat $version" "$commit"
  git push -q origin "$tag"
fi
echo "release-linux: released $tag"
