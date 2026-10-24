#!/usr/bin/env bash
# Verify that all expected Metamod packages for a line exist and pass check-metamod-package.sh.
set -euo pipefail

LINE="${1:?CSS34_LINE required}"
PACKAGES_DIR="${2:-packages}"
BUILDER_DIR="${3:-builder}"

mm_inputs="$(bash "$BUILDER_DIR/py.sh" "$BUILDER_DIR/resolve-metamod-pins.py" "$LINE")"
while IFS=$'\t' read -r role dirname mode branch commit rev version; do
  package="${PACKAGES_DIR}/mmsource-${version}-git${rev}-css34-linux.tar.gz"
  if [[ ! -f "$package" ]]; then
    echo "FAIL: expected $role Metamod package $package not found for line $LINE" >&2
    exit 1
  fi
  echo "Checking $role Metamod package $package"
  EXPECTED_MM_COMMIT="$commit" EXPECTED_MM_REV="$rev" MM_PACKAGE="$package" "${CHECK_METAMOD_SCRIPT:-testing/scripts/check-metamod-package.sh}"
done <<< "$mm_inputs"

echo "OK: All expected Metamod packages for line $LINE verified successfully"
