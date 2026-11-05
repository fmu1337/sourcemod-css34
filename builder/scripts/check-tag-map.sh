#!/usr/bin/env bash
# Check that builder/generated/tag-map.sh agrees with builder/lines.json for
# every line tag and known-bad tag, then render release notes for every
# releasable tag. Nothing is published.
#
#   builder/scripts/check-tag-map.sh [--verbose]
set -euo pipefail

verbose=0
case "${1:-}" in
  "") ;;
  --verbose) verbose=1 ;;
  *) echo "usage: $0 [--verbose]" >&2; exit 2 ;;
esac

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

commit="${GITHUB_SHA:-$(git rev-parse HEAD)}"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
rows="$tmp/tag-map-rows.tsv"

# shellcheck disable=SC1091
source builder/generated/tag-map.sh

python3 - > "$rows" <<'PY'
import importlib.util
from pathlib import Path
spec = importlib.util.spec_from_file_location("lines", "builder/lines.py")
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
data = mod.load_manifest(Path("builder/lines.json"))
for name in data["lines"]:
    part = mod.line_parts(data, name)
    tags = [part["tag"]] + part["extra_tags"]
    for tag in tags:
        print("\t".join([
            tag, name, "1" if part["pointer"] else "0",
            "1" if part["releasable"] else "0",
        ]))
for tag in sorted(data["known_bad"]):
    print("\t".join(["known", tag]))
PY

echo "=== resolved tags ==="
while IFS=$'\t' read -r kind a b c; do
  if [[ "$kind" == "known" ]]; then
    tag="$a"
    css34_tag_is_known_bad "$tag" || { echo "known_bad missing from tag map: $tag" >&2; exit 1; }
    if mapped="$(css34_line_for_tag "$tag")" && css34_line_has_pointer "$mapped"; then
      echo "known-bad tag $tag maps to pointer line $mapped" >&2
      exit 1
    fi
    echo "known-bad $tag (not a pointer)"
    continue
  fi
  tag="$kind"
  name="$a"
  pointer="$b"
  releasable="$c"
  mapped="$(css34_line_for_tag "$tag")" || { echo "tag $tag did not resolve" >&2; exit 1; }
  [[ "$mapped" == "$name" ]] || { echo "tag $tag resolved to $mapped, expected $name" >&2; exit 1; }
  if [[ "$pointer" == 1 ]]; then
    css34_line_has_pointer "$name" || { echo "$name should publish a pointer" >&2; exit 1; }
  elif css34_line_has_pointer "$name"; then
    echo "$name must not publish a pointer" >&2
    exit 1
  fi
  if [[ "$releasable" == 1 ]]; then
    css34_line_can_release "$name" || { echo "$name should be releasable" >&2; exit 1; }
  elif css34_line_can_release "$name"; then
    echo "archived line $name must not take a new release tag" >&2
    exit 1
  fi
  echo "$tag -> $name pointer=$pointer releasable=$releasable"
done < "$rows"
echo "Tag map checks passed (no release published)"

echo "=== release notes ==="
while IFS=$'\t' read -r kind _ _ releasable; do
  [[ "$kind" != known && "$releasable" == 1 ]] || continue
  notes="$tmp/notes.md"
  python3 builder/scripts/release-notes.py "$kind-r2" --commit "$commit" > "$notes" \
    || { echo "release notes failed for $kind-r2" >&2; exit 1; }
  [[ -s "$notes" ]] || { echo "release notes empty for $kind-r2" >&2; exit 1; }
  if [[ "$verbose" == 1 ]]; then
    echo "=== release notes: $kind-r2 ==="
    cat "$notes"
    echo
  fi
  echo "release notes OK: $kind-r2"
done < "$rows"
