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

echo "==> Stripping Metamod Linux binaries"
while IFS= read -r -d '' binary; do
  strip --strip-unneeded "$binary"
done < <(find "$staging/addons/metamod/bin" -type f -name '*.so' -print0)

required=(
  "addons/metamod.vdf"
  "addons/metamod/bin/metamod.1.ep1.so"
  "addons/metamod/bin/server_i486.so"
  "addons/metamod/bin/server.so"
)

for rel in "${required[@]}"; do
  if [[ ! -e "$staging/$rel" ]]; then
    echo "Missing required Metamod package file: $rel" >&2
    exit 1
  fi
done

if ! grep -Eq '"file"[[:space:]]*"addons/metamod/bin/server"' \
  "$staging/addons/metamod.vdf"; then
  echo "Invalid Metamod VDF path; package would load outside the active game root" >&2
  exit 1
fi

tar -C "$staging" -czf "$archive" addons
echo "$archive"
