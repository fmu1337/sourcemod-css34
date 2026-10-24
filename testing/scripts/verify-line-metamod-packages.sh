#!/usr/bin/env bash
# Verify that all expected Metamod packages for a line exist and pass check-metamod-package.sh.
set -euo pipefail

LINE="${1:?CSS34_LINE required}"
PACKAGES_DIR="${2:-packages}"
BUILDER_DIR="${3:-builder}"

source "$BUILDER_DIR/versions.env"

# Resolve line metamod and secondary_metamod pins from lines.json
python_code='
import json, sys
data = json.load(open("builder/lines.json"))
line = data["lines"].get(sys.argv[1], {})
pri = line.get("metamod", "MM_110")
sec = line.get("secondary_metamod", "")
print(f"{pri} {sec}")
'
read -r pri_pin sec_pin < <(python3 -c "$python_code" "$LINE" 2>/dev/null || echo "MM_110 ")

# Check Primary Metamod Package
pri_commit_var="${pri_pin}_COMMIT"
pri_rev_var="${pri_pin}_REV"
pri_mode_var="${pri_pin}_MODE"

primary_commit="${!pri_commit_var:-${MMS_COMMIT:-}}"
primary_rev="${!pri_rev_var:-${MMS_GIT_REV:-}}"
primary_mode="${!pri_mode_var:-${MMS_MODE:-1.12}}"

primary_pkg="${PACKAGES_DIR}/mmsource-${primary_mode}.0-git${primary_rev}-css34-linux.tar.gz"
if [[ ! -f "$primary_pkg" ]]; then
  echo "FAIL: expected primary Metamod package $primary_pkg not found for line $LINE" >&2
  exit 1
fi
echo "Checking primary Metamod package $primary_pkg"
EXPECTED_MM_COMMIT="$primary_commit" EXPECTED_MM_REV="$primary_rev" MM_PACKAGE="$primary_pkg" "${CHECK_METAMOD_SCRIPT:-testing/scripts/check-metamod-package.sh}"

# Check Secondary Metamod Package if line requires it
if [[ -n "$sec_pin" ]]; then
  sec_commit_var="${sec_pin}_COMMIT"
  sec_rev_var="${sec_pin}_REV"
  sec_mode_var="${sec_pin}_MODE"

  sec_commit="${!sec_commit_var:-}"
  sec_rev="${!sec_rev_var:-}"
  sec_mode="${!sec_mode_var:-1.12}"

  if [[ -n "$sec_commit" && -n "$sec_rev" ]]; then
    sec_pkg="${PACKAGES_DIR}/mmsource-${sec_mode}.0-git${sec_rev}-css34-linux.tar.gz"
    if [[ ! -f "$sec_pkg" ]]; then
      echo "FAIL: expected secondary Metamod package $sec_pkg not found for line $LINE" >&2
      exit 1
    fi
    echo "Checking secondary Metamod package $sec_pkg"
    EXPECTED_MM_COMMIT="$sec_commit" EXPECTED_MM_REV="$sec_rev" MM_PACKAGE="$sec_pkg" "${CHECK_METAMOD_SCRIPT:-testing/scripts/check-metamod-package.sh}"
  fi
fi

echo "OK: All expected Metamod packages for line $LINE verified successfully"
