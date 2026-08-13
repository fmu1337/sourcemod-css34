#!/usr/bin/env bash
# Package built Metamod:Source tree for CS:S v34 server install (cstrike/ layout).
set -euo pipefail

MMS_PACKAGE_DIR="${1:?metamod package directory required}"
OUTPUT_DIR="${2:?output directory required}"
MMS_DIR="${3:?mmsource directory required}"

mkdir -p "$OUTPUT_DIR"

version="$(tr -d '\r\n' < "$MMS_DIR/product.version")"
filename="mmsource-${version}-css34-linux.tar.gz"
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

tar -C "$staging" -czf "$archive" addons
echo "$archive"
