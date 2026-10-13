#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=scripts/gnustep-env.sh
. "$repo_root/scripts/gnustep-env.sh"
gnustep_source_env

python3 "$HOME/git/gnustep/gnustep-cli-new/scripts/internal/build.py" --execute "$repo_root"
