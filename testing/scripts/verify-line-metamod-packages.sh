#!/usr/bin/env bash
# Verify that all expected Metamod packages for a line exist and pass check-metamod-package.sh.
set -euo pipefail

LINE="${1:?CSS34_LINE required}"
PACKAGES_DIR="${2:-packages}"
BUILDER_DIR="${3:-builder}"

source "$BUILDER_DIR/versions.env"

# Resolve pins and expected versions directly from lines.json
python_code='
import json, sys
data = json.load(open("builder/lines.json"))
line = data["lines"].get(sys.argv[1], {})
pri_pin = line.get("metamod", "MM_110")
sec_pin = line.get("secondary_metamod", "")
pri = data["pins"][pri_pin]
sec = data["pins"].get(sec_pin, {}) if sec_pin else {}
mode_ver = {"1.10": "1.10.7", "1.11": "1.11.0", "1.12": "1.12.0", "2.0": "2.0.0"}
print(pri["commit"], pri["rev"], mode_ver.get(pri["mode"], "1.12.0"), sec.get("commit", ""), sec.get("rev", ""), mode_ver.get(sec.get("mode", ""), ""))
'
read -r primary_commit primary_rev primary_expect sec_commit sec_rev sec_expect < <(python3 -c "$python_code" "$LINE")

# Check Primary Metamod Package
primary_pkg="${PACKAGES_DIR}/mmsource-${primary_expect}-git${primary_rev}-css34-linux.tar.gz"
if [[ ! -f "$primary_pkg" ]]; then
  echo "FAIL: expected primary Metamod package $primary_pkg not found for line $LINE" >&2
  exit 1
fi
echo "Checking primary Metamod package $primary_pkg"
EXPECTED_MM_COMMIT="$primary_commit" EXPECTED_MM_REV="$primary_rev" MM_PACKAGE="$primary_pkg" "${CHECK_METAMOD_SCRIPT:-testing/scripts/check-metamod-package.sh}"

# Check Secondary Metamod Package if line requires it
if [[ -n "$sec_commit" && -n "$sec_rev" ]]; then
  sec_pkg="${PACKAGES_DIR}/mmsource-${sec_expect}-git${sec_rev}-css34-linux.tar.gz"
  if [[ ! -f "$sec_pkg" ]]; then
    echo "FAIL: expected secondary Metamod package $sec_pkg not found for line $LINE" >&2
    exit 1
  fi
  echo "Checking secondary Metamod package $sec_pkg"
  EXPECTED_MM_COMMIT="$sec_commit" EXPECTED_MM_REV="$sec_rev" MM_PACKAGE="$sec_pkg" "${CHECK_METAMOD_SCRIPT:-testing/scripts/check-metamod-package.sh}"
fi

echo "OK: All expected Metamod packages for line $LINE verified successfully"
