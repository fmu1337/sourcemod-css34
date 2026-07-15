#!/usr/bin/env bash
# Fetch GeoLite2-Country.mmdb into a SourceMod package tree (configs/geoip/).
# Required by SM 1.12+ geoip.ext (looks for any *.mmdb under configs/geoip).
set -euo pipefail

TARGET_DIR="${1:?target configs/geoip directory required}"
CACHE_DIR="${CACHE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/.ci-cache}"
GEOLITE2_URL="${GEOLITE2_URL:-https://github.com/P3TERX/GeoLite.mmdb/raw/download/GeoLite2-Country.mmdb}"
GEOLITE2_NAME="${GEOLITE2_NAME:-GeoLite2-Country.mmdb}"
CACHE_FILE="${CACHE_DIR}/geoip/${GEOLITE2_NAME}"

mkdir -p "${TARGET_DIR}" "${CACHE_DIR}/geoip"

shopt -s nullglob
existing=("${TARGET_DIR}"/*.mmdb)
shopt -u nullglob
if [[ ${#existing[@]} -gt 0 ]]; then
  echo "==> GeoIP2 database already in package: ${existing[*]}"
  exit 0
fi

if [[ ! -f "${CACHE_FILE}" ]]; then
  echo "==> Downloading ${GEOLITE2_NAME}"
  tmp="$(mktemp)"
  curl -fsSL --retry 3 --retry-delay 2 -o "${tmp}" "${GEOLITE2_URL}"
  size="$(wc -c < "${tmp}" | tr -d ' ')"
  if [[ "${size}" -lt 1000000 ]]; then
    rm -f "${tmp}"
    echo "FAIL: GeoIP2 download too small (${size} bytes)" >&2
    exit 1
  fi
  mv -f "${tmp}" "${CACHE_FILE}"
fi

cp -f "${CACHE_FILE}" "${TARGET_DIR}/${GEOLITE2_NAME}"
echo "==> Packaged ${TARGET_DIR}/${GEOLITE2_NAME}"
