#!/usr/bin/env bash
# Overlay rom4s reference bintools.ext.* into an installed server tree.
set -euo pipefail

SERVER_DIR="${SERVER_DIR:?SERVER_DIR is required}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CACHE_DIR="${CACHE_DIR:-${ROOT}/.ci-cache}"
REF_URL="${REFERENCE_SM_URL:-https://github.com/rom4s/sourcemod-css34/releases/download/v1.11.0.6572/sourcemod-1.11.0-git6572-css34-linux.tar.gz}"
REF_TGZ="${CACHE_DIR}/rom4s-sm-bintools-overlay.tar.gz"
EXT_DIR="${SERVER_DIR}/cstrike/addons/sourcemod/extensions"

mkdir -p "${CACHE_DIR}" "${EXT_DIR}"
if [[ ! -f "${REF_TGZ}" || ! -s "${REF_TGZ}" ]]; then
  echo "Downloading rom4s SM reference for bintools overlay"
  curl -fL --retry 5 --retry-delay 3 -o "${REF_TGZ}.partial" "${REF_URL}"
  mv "${REF_TGZ}.partial" "${REF_TGZ}"
fi

tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT
tar -xzf "${REF_TGZ}" -C "${tmp}" addons/sourcemod/extensions

for ext in bintools.ext.1.ep1.so bintools.ext.2.ep1.so bintools.ext.so; do
  if [[ -f "${tmp}/addons/sourcemod/extensions/${ext}" ]]; then
    cp -f "${tmp}/addons/sourcemod/extensions/${ext}" "${EXT_DIR}/${ext}"
    echo "Overlaid ${ext} from rom4s reference"
  fi
done

ls -la "${EXT_DIR}"/bintools.ext* 2>/dev/null || true
