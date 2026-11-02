#!/usr/bin/env bash
# CS:S v34 patches for SourceMod: the entry point of builder/run/linux.sh and
# builder/run/windows.sh. Master builds SourceMod 1.12+ only, each line from
# its patch series (builder/patches/series/<line>/, T3.4). SourceMod 1.11
# (sm11-oldstable) is frozen: its patcher is rebuilt only from the sm11-freeze
# tag (docs/FREEZE.md).
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
# T3.4: the line's patch series, applied with `git apply` and checked tree by tree.
line="${CSS34_LINE:?CSS34_LINE is required (source builder/resolve-version.sh)}"
series="$script_dir/series/$line"
[[ -f "$series/series.json" ]] || {
  echo "FAIL: $line has no patch series ($series/series.json);" \
    "make one with builder/scripts/patch-series.sh (docs/PATCHES.md)" >&2
  exit 1
}
bash "$script_dir/apply-series.sh" "$series" "$sourcemod_dir"
# Boot traces are a local diagnostic aid and must never enter release packages.
if [[ "${CSS34_DEBUG_TRACE:-0}" == "1" ]]; then
  bash "$script_dir/apply-sm-boot-trace.sh" "$sourcemod_dir"
fi
