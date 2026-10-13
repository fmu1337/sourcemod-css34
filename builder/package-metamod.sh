#!/usr/bin/env bash
# Package built Metamod:Source tree for CS:S v34 server install (cstrike/ layout).
set -euo pipefail

MMS_PACKAGE_DIR="${1:?metamod package directory required}"
OUTPUT_DIR="${2:?output directory required}"
MMS_DIR="${3:?mmsource directory required}"

mkdir -p "$OUTPUT_DIR"

version="$(tr -d '\r\n' < "$MMS_DIR/product.version")"
# Revision in the name keeps assets unique across releases ("1.12.0-dev" →
# mmsource-1.12.0-git1226-css34-linux.tar.gz). MMS_GIT_REV is pinned in
# versions.env because deps/ clones are shallow.
rev="${MMS_GIT_REV:-$(git -C "$MMS_DIR" rev-list --count HEAD)}"
filename="mmsource-${version%%-*}-git${rev}-css34-linux.tar.gz"
archive="$OUTPUT_DIR/$filename"
staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT

cp -a "$MMS_PACKAGE_DIR/addons" "$staging/"

# Match rom4s/css34 gameinfo path (relative to hl2/cstrike).
vdf="$staging/addons/metamod.vdf"
if [[ -f "$vdf" ]]; then
  sed -i 's|"file"[[:space:]]*"addons/metamod/bin/server"|"file"\t"../cstrike/addons/metamod/bin/server"|' "$vdf"
fi

echo "==> Stripping Metamod Linux binaries" >&2
while IFS= read -r -d '' binary; do
  strip --strip-unneeded "$binary"
done < <(find "$staging/addons/metamod/bin" -type f -name '*.so' -print0)

# Prefer modern 2.ep1 (MM 1.12); fall back to legacy 1.ep1 (MM 1.10 css34).
mm_core=""
for cand in metamod.2.ep1.so metamod.1.ep1.so; do
  if [[ -e "$staging/addons/metamod/bin/$cand" ]]; then
    mm_core="$cand"
    break
  fi
done
if [[ -z "$mm_core" ]]; then
  echo "Missing metamod.2.ep1.so / metamod.1.ep1.so in Metamod package" >&2
  exit 1
fi

required=(
  "addons/metamod.vdf"
  "addons/metamod/bin/${mm_core}"
  "addons/metamod/bin/server_i486.so"
  "addons/metamod/bin/server.so"
)

for rel in "${required[@]}"; do
  if [[ ! -e "$staging/$rel" ]]; then
    echo "Missing required Metamod package file: $rel" >&2
    exit 1
  fi
done

builder_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MMS_DIR="$MMS_DIR" MMS_GIT_REV="$rev" \
  bash "$builder_dir/write-package-manifest.sh" \
  "$staging/addons/metamod/css34-package.json" "${mm_core%.so}"

tar -C "$staging" -czf "$archive" addons
echo "$archive"
