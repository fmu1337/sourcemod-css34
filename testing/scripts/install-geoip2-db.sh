#!/usr/bin/env bash
# Ensure configs/geoip/ has a GeoIP2 (.mmdb) DB for SM 1.12+ geoip.ext.
# SM 1.11 packages ship legacy GeoIP.dat; SM 1.12+ needs any *.mmdb here.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SERVER_DIR="${SERVER_DIR:?SERVER_DIR is required}"
CACHE_DIR="${CACHE_DIR:-${ROOT}/.ci-cache}"
GEOIP_DIR="${SERVER_DIR}/cstrike/addons/sourcemod/configs/geoip"
# Same pinned release asset as builder/download-geolite2.sh. The P3TERX
# `download` branch is force-replaced, so a commit URL there does not stay valid.
GEOLITE2_URL="${GEOLITE2_URL:-https://github.com/fmu1337/sourcemod-css34/releases/download/deps-geolite2-20261019/GeoLite2-Country.mmdb}"
GEOLITE2_SHA256="${GEOLITE2_SHA256:-55fb913b4a5ab69fb0bbe11f86242b8a3f64061205227f4c1efceef7e14e5dbc}"
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

verify_geolite() {
  local got
  got="$(sha256sum "$1" | awk '{print $1}')"
  if [[ "${got}" != "${GEOLITE2_SHA256}" ]]; then
    echo "FAIL: GeoLite2 sha256 mismatch for $1" >&2
    echo "  expected: ${GEOLITE2_SHA256}" >&2
    echo "  got:      ${got}" >&2
    exit 1
  fi
}

if [[ -f "${CACHE_FILE}" ]]; then
  if ! sha256sum "${CACHE_FILE}" | awk '{print $1}' | grep -qx "${GEOLITE2_SHA256}"; then
    echo "Cached GeoLite2 does not match the pin; re-downloading" >&2
    rm -f "${CACHE_FILE}"
  fi
fi

if [[ ! -f "${CACHE_FILE}" ]]; then
  echo "Downloading ${GEOLITE2_NAME} from ${GEOLITE2_URL}"
  tmp="$(mktemp)"
  if ! curl -fsSL --retry 3 --retry-delay 2 -o "${tmp}" "${GEOLITE2_URL}"; then
    rm -f "${tmp}"
    echo "FAIL: could not download GeoIP2 database" >&2
    exit 1
  fi
  size="$(wc -c < "${tmp}" | tr -d ' ')"
  if [[ "${size}" -lt 1000000 ]]; then
    rm -f "${tmp}"
    echo "FAIL: downloaded GeoIP2 database looks too small (${size} bytes)" >&2
    exit 1
  fi
  verify_geolite "${tmp}"
  mv -f "${tmp}" "${CACHE_FILE}"
fi
verify_geolite "${CACHE_FILE}"

cp -f "${CACHE_FILE}" "${GEOIP_DIR}/${GEOLITE2_NAME}"
echo "Installed ${GEOIP_DIR}/${GEOLITE2_NAME} ($(wc -c < "${GEOIP_DIR}/${GEOLITE2_NAME}" | tr -d ' ') bytes)"
