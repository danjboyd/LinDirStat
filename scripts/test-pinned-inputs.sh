#!/usr/bin/env bash
# Checks packaging/release-inputs.json and scripts/pinned-checkout.sh:
# every pinned tag still points at its revision upstream, a checkout lands on
# the pin, and --verify refuses a tree that is off its pin or has changes.
#
#   scripts/test-pinned-inputs.sh   # needs the network (git ls-remote)
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pin="$repo_root/scripts/pinned-checkout.sh"
work="$(mktemp -d "${TMPDIR:-/tmp}/lindirstat-pins.XXXXXX")"
trap 'rm -rf "$work"' EXIT

fail() { echo "test-pinned-inputs: FAILED: $*" >&2; exit 1; }

for name in adwaita gnustep-packager tools-xctest; do
  url="$("$pin" --field "$name" url)"
  tag="$("$pin" --field "$name" tag)"
  revision="$("$pin" --field "$name" revision)"
  [[ "$revision" =~ ^[0-9a-f]{40}$ ]] || fail "$name: revision $revision is not a full commit id"
  if [[ -n "$tag" ]]; then
    remote="$(git ls-remote "$url" "refs/tags/$tag^{}" "refs/tags/$tag" | sort -k2 | tail -1 | cut -f1)"
    [[ "$remote" == "$revision" ]] || fail "$name: tag $tag is at ${remote:-nothing} upstream, the pin says $revision"
  fi
done

# appimagetool is a download: a tagged release (not the moving continuous
# build) with its sha256.
url="$("$pin" --field appimagetool url)"
[[ "$url" == */releases/download/"$("$pin" --field appimagetool version)"/* ]] || fail "appimagetool: $url is not the pinned release"
[[ "$("$pin" --field appimagetool sha256)" =~ ^[0-9a-f]{64}$ ]] || fail "appimagetool: no sha256"

# A checkout of the smallest input, then --verify on it and on broken copies.
dir="$work/tools-xctest"
[[ "$("$pin" tools-xctest "$dir")" == "$dir" ]] || fail "checkout did not print its folder"
[[ "$(git -C "$dir" rev-parse HEAD)" == "$("$pin" --field tools-xctest revision)" ]] || fail "checkout is not at the pin"
"$pin" --verify tools-xctest "$dir" 2>/dev/null || fail "--verify refused a checkout at the pin"

git -C "$dir" -c user.name=t -c user.email=t@t commit -q --allow-empty -m off-pin
if "$pin" --verify tools-xctest "$dir" 2>/dev/null; then fail "--verify accepted a tree off its pin"; fi
"$pin" tools-xctest "$dir" >/dev/null
"$pin" --verify tools-xctest "$dir" 2>/dev/null || fail "a second checkout did not return to the pin"

echo changed >> "$dir/README.md"
if "$pin" --verify tools-xctest "$dir" 2>/dev/null; then fail "--verify accepted a tree with local changes"; fi

if "$pin" --field no-such-input url 2>/dev/null; then fail "--field accepted an unknown input"; fi

echo "test-pinned-inputs: PASSED"
