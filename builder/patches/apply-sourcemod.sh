#!/usr/bin/env bash
# CS:S v34 patches for SourceMod: the entry point of builder/run/linux.sh and
# builder/run/windows.sh. Master builds SourceMod 1.12+ only: a line's patch
# series, or apply-sourcemod-v112.sh. SourceMod 1.11 (sm11-oldstable) is
# frozen: its patcher is rebuilt only from the sm11-freeze tag (docs/FREEZE.md).
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
# T3.4: a line with a patch series (builder/patches/series/<line>/) applies it
# with `git apply` and checks the resulting trees; the others still run the
# scripted patcher.
series="$script_dir/series/${CSS34_LINE:-}"
if [[ -n "${CSS34_LINE:-}" && -f "$series/series.json" ]]; then
  bash "$script_dir/apply-series.sh" "$series" "$sourcemod_dir"
  # Boot traces are a local diagnostic aid and must never enter release packages.
  if [[ "${CSS34_DEBUG_TRACE:-0}" == "1" ]]; then
    bash "$script_dir/apply-sm-boot-trace.sh" "$sourcemod_dir"
  fi
  exit 0
fi
exec bash "$script_dir/apply-sourcemod-v112.sh" "$sourcemod_dir"
