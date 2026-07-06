#!/usr/bin/env bash
set -euo pipefail

PACKAGE_DIR="${1:?package directory required}"
OUTPUT_DIR="${2:?output directory required}"
SOURCEMOD_DIR="${3:?sourcemod directory required}"

mkdir -p "$OUTPUT_DIR"

rev="${SOURCEMOD_GIT_REV:-$(git -C "$SOURCEMOD_DIR" rev-list --count HEAD)}"
version="$(tr -d '\r\n' < "$SOURCEMOD_DIR/product.version")"
filename="sourcemod-${version}-git${rev}-css34-linux.tar.gz"
archive="$OUTPUT_DIR/$filename"

required=(
  "addons/metamod/sourcemod.vdf"
  "addons/sourcemod/bin/sourcemod.1.ep1.so"
  "addons/sourcemod/bin/sourcemod.2.ep1.so"
  "addons/sourcemod/extensions/dbi.mysql.ext.so"
  "addons/sourcemod/extensions/dbi.sqlite.ext.so"
  "addons/sourcemod/extensions/game.cstrike.ext.1.ep1.so"
  "addons/sourcemod/extensions/game.cstrike.ext.2.ep1.so"
  "cfg/sourcemod/sourcemod.cfg"
)

for rel in "${required[@]}"; do
  if [ ! -e "$PACKAGE_DIR/$rel" ]; then
    echo "Missing required package file: $rel" >&2
    exit 1
  fi
done

tar -C "$PACKAGE_DIR" -czf "$archive" addons cfg
echo "$archive"
