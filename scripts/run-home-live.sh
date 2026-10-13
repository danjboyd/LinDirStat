#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
scan_path="${1:-$HOME}"
# shellcheck source=scripts/gnustep-env.sh
. "$repo_root/scripts/gnustep-env.sh"
gnustep_source_env

cd "$repo_root"
make -C Source

Source/LinDirStat.app/LinDirStat "$scan_path"
