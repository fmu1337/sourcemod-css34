#!/usr/bin/env bash
# Ensure configs/geoip/ has a GeoIP2 (.mmdb) DB for SM 1.12+ geoip.ext.
# SM 1.11 packages ship legacy GeoIP.dat; SM 1.12+ needs any *.mmdb here.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SERVER_DIR="${SERVER_DIR:?SERVER_DIR is required}"
CACHE_DIR="${CACHE_DIR:-${ROOT}/.ci-cache}"
GEOIP_DIR="${SERVER_DIR}/cstrike/addons/sourcemod/configs/geoip"
# Community mirror of MaxMind GeoLite2-Country (official SM does not ship the DB).
GEOLITE2_URL="${GEOLITE2_URL:-https://github.com/P3TERX/GeoLite.mmdb/raw/download/GeoLite2-Country.mmdb}"
GEOLITE2_NAME="${GEOLITE2_NAME:-GeoLite2-Country.mmdb}"
CACHE_FILE="${CACHE_DIR}/geoip/${GEOLITE2_NAME}"

mkdir -p "${GEOIP_DIR}" "${CACHE_DIR}/geoip"

shopt -s nullglob
existing_mmdb=("${GEOIP_DIR}"/*.mmdb)
shopt -u nullglob
if [[ ${#existing_mmdb[@]} -gt 0 ]]; then
  echo "GeoIP2 database already present: ${existing_mmdb[*]}"
  exit 0
fi

# Only needed when the installed geoip.ext is the GeoIP2 loader (no legacy .dat path).
if [[ ! -f "${SERVER_DIR}/cstrike/addons/sourcemod/extensions/geoip.ext.so" ]]; then
  echo "No geoip.ext.so installed; skipping GeoIP2 DB"
  exit 0
fi

if [[ ! -f "${CACHE_FILE}" ]]; then
  echo "Downloading ${GEOLITE2_NAME} from ${GEOLITE2_URL}"
  tmp="$(mktemp)"
  if ! curl -fsSL --retry 3 --retry-delay 2 -o "${tmp}" "${GEOLITE2_URL}"; then
    rm -f "${tmp}"
    echo "FAIL: could not download GeoIP2 database" >&2
    exit 1
  fi
  # Reject tiny/error pages.
  size="$(wc -c < "${tmp}" | tr -d ' ')"
  if [[ "${size}" -lt 1000000 ]]; then
    rm -f "${tmp}"
    echo "FAIL: downloaded GeoIP2 database looks too small (${size} bytes)" >&2
    exit 1
  fi
  mv -f "${tmp}" "${CACHE_FILE}"
fi

cp -f "${CACHE_FILE}" "${GEOIP_DIR}/${GEOLITE2_NAME}"
echo "Installed ${GEOIP_DIR}/${GEOLITE2_NAME} ($(wc -c < "${GEOIP_DIR}/${GEOLITE2_NAME}" | tr -d ' ') bytes)"
