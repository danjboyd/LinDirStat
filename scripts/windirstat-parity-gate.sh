#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/gnustep-env.sh
. "$repo_root/scripts/gnustep-env.sh"
gnustep_source_env

cd "$repo_root"

python3 scripts/windirstat-parity-gate.py
