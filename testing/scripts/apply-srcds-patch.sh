#!/usr/bin/env bash
# Apply bruno_args srcds_patch (memcpy→memmove binary rewrite).
# Downloads the rar from the bufferfix branch unless SRCDS_PATCH_RAR is set.
set -euo pipefail

SERVER_DIR="${SERVER_DIR:?SERVER_DIR is required}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CACHE_DIR="${CACHE_DIR:-${ROOT}/.ci-cache}"
SRCDS_PATCH_URL="${SRCDS_PATCH_URL:-https://github.com/fmu1337/sourcemod-css34/raw/bufferfix/srcds_patch%20(1).rar}"
SRCDS_PATCH_RAR="${SRCDS_PATCH_RAR:-${CACHE_DIR}/srcds_patch.rar}"

mkdir -p "${CACHE_DIR}"
if [[ ! -f "${SRCDS_PATCH_RAR}" || ! -s "${SRCDS_PATCH_RAR}" ]]; then
  echo "Downloading srcds_patch from ${SRCDS_PATCH_URL}"
  curl -fL --retry 5 --retry-delay 3 -o "${SRCDS_PATCH_RAR}.partial" "${SRCDS_PATCH_URL}"
  mv "${SRCDS_PATCH_RAR}.partial" "${SRCDS_PATCH_RAR}"
fi

if ! command -v unrar >/dev/null 2>&1; then
  if command -v apt-get >/dev/null 2>&1; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get install -y unrar || apt-get install -y unrar-free || true
  elif command -v yum >/dev/null 2>&1; then
    yum -y install unrar || yum -y install rar || true
  elif command -v dnf >/dev/null 2>&1; then
    dnf -y install unrar || true
  fi
fi

TMP="$(mktemp -d)"
cleanup() { rm -rf "${TMP}"; }
trap cleanup EXIT

if command -v unrar >/dev/null 2>&1; then
  unrar x -o+ -y "${SRCDS_PATCH_RAR}" "${TMP}/"
elif command -v 7z >/dev/null 2>&1; then
  7z x -y "-o${TMP}" "${SRCDS_PATCH_RAR}"
else
  echo "Need unrar or 7z to extract srcds_patch.rar" >&2
  exit 1
fi

# Archive layout: bin/*.so and cstrike/bin/server_i486.so
install -m 0644 "${TMP}/bin/engine_amd.so" "${SERVER_DIR}/bin/engine_amd.so"
install -m 0644 "${TMP}/bin/engine_i486.so" "${SERVER_DIR}/bin/engine_i486.so"
install -m 0644 "${TMP}/bin/engine_i686.so" "${SERVER_DIR}/bin/engine_i686.so"
install -m 0644 "${TMP}/bin/steamclient_i486.so" "${SERVER_DIR}/bin/steamclient_i486.so"
install -m 0644 "${TMP}/cstrike/bin/server_i486.so" "${SERVER_DIR}/cstrike/bin/server_i486.so"

echo "Applied srcds_patch (engine/server/steamclient)"
