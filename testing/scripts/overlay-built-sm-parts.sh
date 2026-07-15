#!/usr/bin/env bash
# Overlay selected built SM binaries onto an installed server tree (reverse bisect).
set -euo pipefail

SERVER_DIR="${SERVER_DIR:?SERVER_DIR is required}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BUILT_TGZ="${BUILT_SM_PACKAGE:?BUILT_SM_PACKAGE is required}"
PARTS="${BUILT_OVERLAY_PARTS:?BUILT_OVERLAY_PARTS is required}"

tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT
tar -xzf "${BUILT_TGZ}" -C "${tmp}"

overlay_one() {
  local rel="$1"
  local src="${tmp}/${rel}"
  local dst="${SERVER_DIR}/cstrike/${rel}"
  if [[ -f "${src}" ]]; then
    mkdir -p "$(dirname "${dst}")"
    cp -f "${src}" "${dst}"
    echo "Overlaid built ${rel}"
  fi
}

case "${PARTS}" in
  logic)
    overlay_one addons/sourcemod/bin/sourcemod.logic.so
    ;;
  core)
    overlay_one addons/sourcemod/bin/sourcemod.1.ep1.so
    overlay_one addons/sourcemod/bin/sourcemod.2.ep1.so
    ;;
  sdkhooks)
    overlay_one addons/sourcemod/extensions/sdkhooks.ext.1.ep1.so
    overlay_one addons/sourcemod/extensions/sdkhooks.ext.2.ep1.so
    ;;
  sdktools)
    overlay_one addons/sourcemod/extensions/sdktools.ext.1.ep1.so
    overlay_one addons/sourcemod/extensions/sdktools.ext.2.ep1.so
    ;;
  gamecstrike)
    overlay_one addons/sourcemod/extensions/game.cstrike.ext.1.ep1.so
    overlay_one addons/sourcemod/extensions/game.cstrike.ext.2.ep1.so
    ;;
  jit)
    overlay_one addons/sourcemod/bin/sourcepawn.jit.x86.so
    ;;
  bintools)
    overlay_one addons/sourcemod/extensions/bintools.ext.so
    ;;
  logic+core)
    overlay_one addons/sourcemod/bin/sourcemod.logic.so
    overlay_one addons/sourcemod/bin/sourcemod.1.ep1.so
    overlay_one addons/sourcemod/bin/sourcemod.2.ep1.so
    ;;
  all-bin)
    while IFS= read -r -d '' src; do
      rel="${src#${tmp}/}"
      overlay_one "${rel}"
    done < <(find "${tmp}" -name '*.so' -print0)
    ;;
  *)
    echo "Unknown BUILT_OVERLAY_PARTS=${PARTS}" >&2
    exit 1
    ;;
esac
