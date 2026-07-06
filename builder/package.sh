#!/usr/bin/env bash
set -euo pipefail

WDIR="${WDIR:-$(pwd)}"
PACKAGE_DIR="${1:?package directory required}"
OUTPUT_DIR="${2:-$WDIR/packages}"
SM_DIR="$WDIR/sourcemod"

mkdir -p "$OUTPUT_DIR"

rev="$(git -C "$SM_DIR" rev-list --count HEAD)"
version="$(tr -d '\r\n' < "$SM_DIR/product.version")"
filename="sourcemod-${version}-git${rev}-css34-linux.tar.gz"
archive="$(cd "$OUTPUT_DIR" && pwd)/$filename"

cd "$PACKAGE_DIR"
tar czf "$archive" addons cfg

echo "Created $archive"
