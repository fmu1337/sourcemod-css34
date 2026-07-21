#!/usr/bin/env bash
# Overlay selected rom4s reference SM binaries onto an installed server tree.
set -euo pipefail

SERVER_DIR="${SERVER_DIR:?SERVER_DIR is required}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CACHE_DIR="${CACHE_DIR:-${ROOT}/.ci-cache}"
REF_URL="${REFERENCE_SM_URL:-https://github.com/rom4s/sourcemod-css34/releases/download/v1.11.0.6572/sourcemod-1.11.0-git6572-css34-linux.tar.gz}"
REF_TGZ="${CACHE_DIR}/rom4s-sm-overlay.tar.gz"
PARTS="${ROM4S_OVERLAY_PARTS:-all}"

mkdir -p "${CACHE_DIR}"
if [[ ! -f "${REF_TGZ}" || ! -s "${REF_TGZ}" ]]; then
  echo "Downloading rom4s SM reference for overlay"
  curl -fL --retry 5 --retry-delay 3 -o "${REF_TGZ}.partial" "${REF_URL}"
  mv "${REF_TGZ}.partial" "${REF_TGZ}"
fi

tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT
tar -xzf "${REF_TGZ}" -C "${tmp}"

overlay_one() {
  local rel="$1"
  local src="${tmp}/${rel}"
  local dst="${SERVER_DIR}/cstrike/${rel}"
  if [[ -f "${src}" ]]; then
    mkdir -p "$(dirname "${dst}")"
    cp -f "${src}" "${dst}"
    echo "Overlaid ${rel}"
  fi
}

overlay_gamedata_subdir() {
  local rel="$1"
  local src="${tmp}/addons/sourcemod/gamedata/${rel}"
  local dst="${SERVER_DIR}/cstrike/addons/sourcemod/gamedata/${rel}"
  if [[ -d "${src}" ]]; then
    rm -rf "${dst}"
    mkdir -p "$(dirname "${dst}")"
    cp -a "${src}" "${dst}"
    echo "Overlaid addons/sourcemod/gamedata/${rel}"
  else
    echo "Missing gamedata path ${rel} in reference package" >&2
    exit 1
  fi
}

if [[ "${PARTS}" == gamedata/* ]]; then
  overlay_gamedata_subdir "${PARTS#gamedata/}"
  exit 0
fi

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
  gamecstrike)
    overlay_one addons/sourcemod/extensions/game.cstrike.ext.1.ep1.so
    overlay_one addons/sourcemod/extensions/game.cstrike.ext.2.ep1.so
    ;;
  jit)
    overlay_one addons/sourcemod/bin/sourcepawn.jit.x86.so
    ;;
  mmplugin)
    overlay_one addons/sourcemod/bin/sourcemod_mm_i486.so
    ;;
  bintools)
    overlay_one addons/sourcemod/extensions/bintools.ext.1.ep1.so
    overlay_one addons/sourcemod/extensions/bintools.ext.2.ep1.so
    overlay_one addons/sourcemod/extensions/bintools.ext.so
    ;;
  logic+core)
    overlay_one addons/sourcemod/bin/sourcemod.logic.so
    overlay_one addons/sourcemod/bin/sourcemod.1.ep1.so
    overlay_one addons/sourcemod/bin/sourcemod.2.ep1.so
    ;;
  gamecstrike+jit)
    overlay_one addons/sourcemod/extensions/game.cstrike.ext.1.ep1.so
    overlay_one addons/sourcemod/extensions/game.cstrike.ext.2.ep1.so
    overlay_one addons/sourcemod/bin/sourcepawn.jit.x86.so
    ;;
  all)
    overlay_one addons/sourcemod/bin/sourcemod.logic.so
    overlay_one addons/sourcemod/bin/sourcemod.1.ep1.so
    overlay_one addons/sourcemod/bin/sourcemod.2.ep1.so
    overlay_one addons/sourcemod/extensions/bintools.ext.1.ep1.so
    overlay_one addons/sourcemod/extensions/bintools.ext.2.ep1.so
    overlay_one addons/sourcemod/extensions/sdkhooks.ext.1.ep1.so
    overlay_one addons/sourcemod/extensions/sdkhooks.ext.2.ep1.so
    overlay_one addons/sourcemod/extensions/sdktools.ext.1.ep1.so
    overlay_one addons/sourcemod/extensions/sdktools.ext.2.ep1.so
    ;;
  gamedata)
    if [[ -d "${tmp}/addons/sourcemod/gamedata" ]]; then
      rm -rf "${SERVER_DIR}/cstrike/addons/sourcemod/gamedata"
      cp -a "${tmp}/addons/sourcemod/gamedata" "${SERVER_DIR}/cstrike/addons/sourcemod/"
      echo "Overlaid addons/sourcemod/gamedata"
    fi
    ;;
  *)
    echo "Unknown ROM4S_OVERLAY_PARTS=${PARTS}" >&2
    exit 1
    ;;
esac
