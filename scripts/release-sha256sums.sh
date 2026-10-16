#!/usr/bin/env bash
# Writes SHA256SUMS for a LinDirStat release from the assets on the release
# itself, and uploads it there (docs/updates.md, "Releasing").
#
#   scripts/release-sha256sums.sh v0.1.3          # regenerate and upload
#   scripts/release-sha256sums.sh --check v0.1.3  # verify only
#   scripts/release-sha256sums.sh --dir DIR       # write DIR/SHA256SUMS, no upload
#   scripts/release-sha256sums.sh --check-dir DIR # verify DIR/SHA256SUMS only
#
# SHA256SUMS covers every platform's payloads: each asset except SHA256SUMS
# itself, per-file *.sha256 checksums and the signed *.update-feed.json.
# release-linux.sh --publish runs it after creating the release; run it
# again whenever another platform's asset (the macOS DMG) is attached, so
# the file always lists everything on the release.
#
# The default mode downloads the payloads, writes SHA256SUMS, uploads it
# with --clobber, then downloads the release again and checks it. --check
# only does that last step, and fails if any payload is missing from
# SHA256SUMS or does not match. Hashing is done with python3 so it runs the
# same on Linux and macOS. --dir writes SHA256SUMS for the payloads in a
# local folder by the same rule (the release workflow's artifacts) and checks
# it; it needs no gh.
set -euo pipefail

check_only=0
local_dir=""
case "${1:-}" in
  --check) check_only=1; shift ;;
  --dir|--check-dir)
    [ "$1" = --check-dir ] && check_only=1
    local_dir="${2:-}"; [ -d "$local_dir" ] || { echo "release-sha256sums: $1 needs a folder" >&2; exit 2; } ;;
esac
if [ -z "$local_dir" ]; then
  case "${1:-}" in
    v*) tag="$1" ;;
    *) sed -n '2,22p' "$0" >&2; exit 2 ;;
  esac
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[ -n "$local_dir" ] && local_dir="$(cd "$local_dir" && pwd)"
cd "$repo_root"
[ -n "$local_dir" ] || releases_repo="$(python3 -c 'import json
github = json.load(open("package.manifest.json"))["updates"]["github"]
print(github["owner"] + "/" + github["repo"])')"

die() { echo "release-sha256sums: $*" >&2; exit 1; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# Prints SHA256SUMS for the payloads in a directory ("<hash>  <name>", in
# name order), or with --check verifies one against them.
sums() {
  python3 - "$@" <<'EOF'
import hashlib, os, sys

check = sys.argv[1] == "--check"
directory = sys.argv[-1]

def payload(name):
    return not (name == "SHA256SUMS" or name.endswith(".sha256")
                or name.endswith(".update-feed.json"))

def digest(name):
    h = hashlib.sha256()
    with open(os.path.join(directory, name), "rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()

names = sorted(n for n in os.listdir(directory) if payload(n))
if not check:
    for name in names:
        print(f"{digest(name)}  {name}")
    sys.exit(0)

listed = {}
with open(os.path.join(directory, "SHA256SUMS")) as f:
    for line in f:
        if line.strip():
            value, name = line.rstrip("\n").split("  ", 1)
            listed[name] = value
failed = False
for name in names:
    if name not in listed:
        print(f"{name}: MISSING from SHA256SUMS")
        failed = True
    elif listed[name] != digest(name):
        print(f"{name}: FAILED")
        failed = True
    else:
        print(f"{name}: OK")
for name in sorted(set(listed) - set(names)):
    print(f"{name}: listed but not on the release")
    failed = True
sys.exit(1 if failed else 0)
EOF
}

if [ -n "$local_dir" ] && [ "$check_only" = 1 ]; then
  [ -f "$local_dir/SHA256SUMS" ] || die "$local_dir has no SHA256SUMS"
  sums --check "$local_dir" || die "$local_dir/SHA256SUMS does not match"
  echo "release-sha256sums: $local_dir/SHA256SUMS covers every payload"
  exit 0
fi
if [ -n "$local_dir" ]; then
  rm -f "$local_dir/SHA256SUMS"
  sums --write "$local_dir" > "$work/SHA256SUMS"
  [ -s "$work/SHA256SUMS" ] || die "$local_dir has no payloads"
  mv "$work/SHA256SUMS" "$local_dir/SHA256SUMS"
  sums --check "$local_dir" || die "$local_dir/SHA256SUMS does not match"
  echo "release-sha256sums: $local_dir/SHA256SUMS covers every payload"
  exit 0
fi

if [ "$check_only" = 0 ]; then
  mkdir "$work/assets"
  gh release download "$tag" --repo "$releases_repo" --dir "$work/assets"
  rm -f "$work/assets/SHA256SUMS"
  sums --write "$work/assets" > "$work/SHA256SUMS"
  [ -s "$work/SHA256SUMS" ] || die "$tag has no assets"
  gh release upload "$tag" --repo "$releases_repo" --clobber "$work/SHA256SUMS"
fi

mkdir "$work/check"
gh release download "$tag" --repo "$releases_repo" --dir "$work/check"
[ -f "$work/check/SHA256SUMS" ] || die "$tag has no SHA256SUMS"
sums --check "$work/check" || die "$tag: SHA256SUMS does not match the release"
echo "release-sha256sums: $tag SHA256SUMS covers every payload"
