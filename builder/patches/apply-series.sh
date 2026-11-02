#!/usr/bin/env bash
# Apply a line's CS:S v34 patch series to a clean SourceMod checkout (T3.4).
#
#   builder/patches/apply-series.sh <series dir> <sourcemod dir>
#
# <series dir> (builder/patches/series/<line>/) holds one directory per
# repository: sourcemod/ for the SourceMod tree itself, and <path>/ for a
# SourceMod submodule at that path (sourcepawn, hl2sdk-manifests, ...). Each
# holds NNNN-*.patch files applied in order with `git apply --index`.
# series.json names the SourceMod commit the series is made for and the tree
# (`git write-tree`) every repository must have afterwards; any difference
# fails the build. builder/scripts/patch-series.sh regenerates it.
set -euo pipefail

series="${1:?series directory required}"
sm="${2:?sourcemod directory required}"
manifest="$series/series.json"
[[ -f "$manifest" ]] || { echo "FAIL: $manifest missing" >&2; exit 1; }

expect() { # <json key path...>
  python3 - "$manifest" "$@" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
for key in sys.argv[2:]:
    data = data[key]
print(data)
PY
}

base="$(expect commit)"
head="$(git -C "$sm" rev-parse HEAD)"
[[ "$head" == "$base" ]] || {
  echo "FAIL: $series is made for SourceMod $base, the checkout is at $head" >&2
  echo "      (refresh it with builder/scripts/patch-series.sh after a pin bump)" >&2
  exit 1
}

# Submodules first, then SourceMod: its tree records their gitlinks, not their files.
repos=()
for dir in "$series"/*/; do
  name="$(basename "$dir")"
  [[ "$name" == sourcemod ]] || repos+=("$name")
done
[[ -d "$series/sourcemod" ]] || { echo "FAIL: $series has no sourcemod/ patches" >&2; exit 1; }
repos+=(sourcemod)

for repo in "${repos[@]}"; do
  if [[ "$repo" == sourcemod ]]; then target="$sm"; else target="$sm/$repo"; fi
  [[ -e "$target/.git" ]] || { echo "FAIL: $target is not a git checkout" >&2; exit 1; }
  for patch in "$series/$repo"/*.patch; do
    git -c core.autocrlf=false -C "$target" apply --index --whitespace=nowarn "$(cd "$(dirname "$patch")" && pwd)/$(basename "$patch")" ||
      { echo "FAIL: $patch does not apply to $target" >&2; exit 1; }
    echo "==> $repo: applied $(basename "$patch")"
  done
  tree="$(git -C "$target" write-tree)"
  want="$(expect trees "$repo")"
  [[ "$tree" == "$want" ]] || { echo "FAIL: $repo tree is $tree after the series, expected $want" >&2; exit 1; }
  echo "==> $repo: tree $tree matches series.json"
done
