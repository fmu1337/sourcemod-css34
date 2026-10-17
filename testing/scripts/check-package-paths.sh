#!/usr/bin/env bash
# Regression: stale archives must never be selected instead of the pinned pair.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/packages with spaces"
export PACKAGES_DIR="$tmp/packages with spaces"
touch "$PACKAGES_DIR/sourcemod-1.0.0-git1-css34-linux.tar.gz"
touch "$PACKAGES_DIR/mmsource-1.0.0-git1-css34-linux.tar.gz"

for line in sm11-oldstable sm12-latest sm13-latest; do
  (
    export CSS34_LINE="$line"
    source "$root/builder/package-paths.sh"
    [[ ! -e "$SM_PACKAGE" && ! -e "$MM_PACKAGE" ]]
    [[ "$SM_PACKAGE" == "$PACKAGES_DIR/"* && "$MM_PACKAGE" == "$PACKAGES_DIR/"* ]]
    touch "$SM_PACKAGE" "$MM_PACKAGE"
    expected_sm="$SM_PACKAGE" expected_mm="$MM_PACKAGE"
    source "$root/builder/package-paths.sh"
    [[ "$SM_PACKAGE" == "$expected_sm" && "$MM_PACKAGE" == "$expected_mm" ]]
    [[ -f "$SM_PACKAGE" && -f "$MM_PACKAGE" ]]
    rm "$SM_PACKAGE" "$MM_PACKAGE"
  )
done
for line in sm13-mm20 sm13-mm2 sm13-mm20-khook sm13-khook khook; do
  if CSS34_LINE="$line" bash "$root/builder/package-paths.sh" >"$tmp/output" 2>&1; then
    echo "Archived line unexpectedly resolved: $line" >&2
    exit 1
  fi
  grep -q 'archive/khook' "$tmp/output"
done
echo 'OK: exact package selection and archived-line rejection'
