#!/usr/bin/env bash
# Verify that all expected Metamod packages for a line exist and pass check-metamod-package.sh.
#
# Each primary / secondary input of the line is its own package. A bridge input
# (bridge_metamod) is not: its metamod.1.ep1.so must be inside the primary MM 1.12
# package, built from that pin, with legacy_bridge in the manifest.
set -euo pipefail

LINE="${1:?CSS34_LINE required}"
PACKAGES_DIR="${2:-packages}"
BUILDER_DIR="${3:-builder}"

mm_inputs="$(bash "$BUILDER_DIR/py.sh" "$BUILDER_DIR/resolve-metamod-pins.py" "$LINE")"
primary_package=""
bridge_commit=""
bridge_rev=""
bridge_version=""
while IFS=$'\t' read -r role dirname mode branch commit rev version; do
  if [[ "$role" == bridge ]]; then
    bridge_commit="$commit" bridge_rev="$rev" bridge_version="$version"
    continue
  fi
  package="${PACKAGES_DIR}/mmsource-${version}-git${rev}-css34-linux.tar.gz"
  if [[ ! -f "$package" ]]; then
    echo "FAIL: expected $role Metamod package $package not found for line $LINE" >&2
    exit 1
  fi
  [[ "$role" != primary ]] || primary_package="$package"
  echo "Checking $role Metamod package $package"
  EXPECTED_MM_COMMIT="$commit" EXPECTED_MM_REV="$rev" MM_PACKAGE="$package" "${CHECK_METAMOD_SCRIPT:-testing/scripts/check-metamod-package.sh}"
done <<< "$mm_inputs"

if [[ -n "$bridge_commit" ]]; then
  echo "Checking the legacy-plugin bridge core (MM ${bridge_version} git${bridge_rev}) in $primary_package"
  # List first: `tar | grep -q` would kill tar with SIGPIPE and fail under pipefail.
  listing="$(tar -tzf "$primary_package")"
  if ! grep -Eq '(^|/)addons/metamod/bin/metamod\.1\.ep1\.so$' <<< "$listing"; then
    echo "FAIL: $primary_package has no addons/metamod/bin/metamod.1.ep1.so (bridge_metamod of $LINE)" >&2
    exit 1
  fi
  core="$(mktemp)"
  trap 'rm -f "$core"' EXIT
  tar -xzOf "$primary_package" addons/metamod/bin/metamod.1.ep1.so >"$core"
  # The legacy core prints "<version>-dev+<rev>" and the short commit it was built from.
  for needle in "${bridge_version}-dev+${bridge_rev}" "${bridge_commit:0:7}"; do
    if ! grep -aqF -- "$needle" "$core"; then
      echo "FAIL: metamod.1.ep1.so in $primary_package was not built from the bridge pin (no '$needle')" >&2
      exit 1
    fi
  done
  if ! tar -xzOf "$primary_package" addons/metamod/css34-package.json |
      python3 -c 'import json, sys; sys.exit(0 if json.load(sys.stdin).get("legacy_bridge") is True else 1)'; then
    echo "FAIL: $primary_package css34-package.json does not set legacy_bridge" >&2
    exit 1
  fi
  echo "OK: $primary_package ships the MM ${bridge_version} git${bridge_rev} legacy core for the bridge"
fi

echo "OK: All expected Metamod packages for line $LINE verified successfully"
