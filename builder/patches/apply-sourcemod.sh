#!/usr/bin/env bash
# CS:S v34 patches for SourceMod: the entry point of builder/run/linux.sh and
# builder/run/windows.sh. Master builds SourceMod 1.12+ only
# (apply-sourcemod-v112.sh). SourceMod 1.11 (sm11-oldstable) is frozen: its
# patcher is rebuilt only from the sm11-freeze tag (docs/FREEZE.md).
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
sourcemod_dir="${1:?sourcemod directory required}"

product_version="$(tr -d '\r\n' < "$sourcemod_dir/product.version" 2>/dev/null || true)"
if [[ ! "$product_version" =~ ^([0-9]+)\.([0-9]+)\. ]]; then
  echo "FAIL: cannot read a SourceMod version from $sourcemod_dir/product.version" >&2
  exit 1
fi
if (( BASH_REMATCH[1] == 1 && BASH_REMATCH[2] < 12 )); then
  echo "FAIL: SourceMod $product_version: master builds SourceMod 1.12+ only;" \
    "sm11-oldstable is rebuilt from the sm11-freeze tag (docs/FREEZE.md)" >&2
  exit 1
fi
exec bash "$script_dir/apply-sourcemod-v112.sh" "$sourcemod_dir"
