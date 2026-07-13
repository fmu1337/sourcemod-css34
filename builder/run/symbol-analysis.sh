#!/usr/bin/env bash
# Compare symbols/sections between original rom4s release and a repro artifact.
set -euo pipefail

artifact="${1:?repro tarball required}"
original_url="${ORIGINAL_RELEASE_URL:-https://github.com/rom4s/sourcemod-css34/releases/download/v1.11.0.6572/sourcemod-1.11.0-git6572-css34-linux.tar.gz}"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

orig_dir="$tmpdir/original"
repro_dir="$tmpdir/repro"
orig_tar="$tmpdir/original.tar.gz"

echo "==> Fetching original release"
curl -fsSL -o "$orig_tar" "$original_url"
mkdir -p "$orig_dir" "$repro_dir"
tar -xzf "$orig_tar" -C "$orig_dir"
tar -xzf "$artifact" -C "$repro_dir"

detail_flag=()
if [ "${SYMBOL_DETAIL:-1}" = "1" ]; then
  detail_flag=(--detail)
fi

python3 "$(dirname "$0")/../symbol-analysis.py" "$orig_dir" "$repro_dir" "${detail_flag[@]}"
