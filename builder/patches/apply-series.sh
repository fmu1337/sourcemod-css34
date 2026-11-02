#!/usr/bin/env bash
# Apply a CS:S v34 patch series to a clean checkout (T3.4).
#
#   builder/patches/apply-series.sh <series dir> <checkout dir>
#
# <series dir> (builder/patches/series/<line or pin>/) holds one directory per
# repository: <root>/ for the checkout itself (series.json "root": sourcemod by
# default, metamod for a Metamod series), and <path>/ for a submodule of it at
# that path (sourcepawn, hl2sdk-manifests, ...). Each holds NNNN-*.patch files
# applied in order with `git apply --index`. series.json names the commit the
# series is made for and the tree (`git write-tree`) every repository must
# have afterwards; any difference fails the build.
# builder/scripts/patch-series.sh regenerates it.
set -euo pipefail

series="${1:?series directory required}"
sm="${2:?checkout directory required}"
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

root="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("root", "sourcemod"))' "$manifest")"
base="$(expect commit)"
head="$(git -C "$sm" rev-parse HEAD)"
[[ "$head" == "$base" ]] || {
  echo "FAIL: $series is made for $root $base, the checkout is at $head" >&2
  echo "      (refresh it with builder/scripts/patch-series.sh after a pin bump)" >&2
  exit 1
}

# Submodules first, then the root: its tree records their gitlinks, not their files.
repos=()
for dir in "$series"/*/; do
  name="$(basename "$dir")"
  [[ "$name" == "$root" ]] || repos+=("$name")
done
[[ -d "$series/$root" ]] || { echo "FAIL: $series has no $root/ patches" >&2; exit 1; }
repos+=("$root")

for repo in "${repos[@]}"; do
  if [[ "$repo" == "$root" ]]; then target="$sm"; else target="$sm/$repo"; fi
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
