#!/usr/bin/env bash
# Fetch GeoLite2-Country.mmdb into a SourceMod package tree (configs/geoip/).
# Required by SM 1.12+ geoip.ext (looks for any *.mmdb under configs/geoip).
set -euo pipefail

TARGET_DIR="${1:?target configs/geoip directory required}"
CACHE_DIR="${CACHE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/.ci-cache}"
# Pinned to P3TERX/GeoLite.mmdb commit 0ee3c9de (download branch, 2026-10-19).
GEOLITE2_URL="${GEOLITE2_URL:-https://raw.githubusercontent.com/P3TERX/GeoLite.mmdb/0ee3c9de3f817dd71b4d9c2a7dacfb6dc475c712/GeoLite2-Country.mmdb}"
GEOLITE2_SHA256="${GEOLITE2_SHA256:-55fb913b4a5ab69fb0bbe11f86242b8a3f64061205227f4c1efceef7e14e5dbc}"
GEOLITE2_NAME="${GEOLITE2_NAME:-GeoLite2-Country.mmdb}"
CACHE_FILE="${CACHE_DIR}/geoip/${GEOLITE2_NAME}"
ATTRIBUTION="${TARGET_DIR}/GeoLite2-Attribution.txt"

mkdir -p "${TARGET_DIR}" "${CACHE_DIR}/geoip"

shopt -s nullglob
existing=("${TARGET_DIR}"/*.mmdb)
shopt -u nullglob
write_attribution() {
  cat > "${ATTRIBUTION}" <<'EOF'
This package includes GeoLite2 Data created by MaxMind, available from
https://www.maxmind.com.
EOF
  chmod 0644 "${ATTRIBUTION}"
}

verify_geolite() {
  local file="$1"
  local got
  got="$(sha256sum "${file}" | awk '{print $1}')"
  if [[ "${got}" != "${GEOLITE2_SHA256}" ]]; then
    echo "FAIL: GeoLite2 sha256 mismatch for ${file}" >&2
    echo "  expected: ${GEOLITE2_SHA256}" >&2
    echo "  got:      ${got}" >&2
    exit 1
  fi
}

if [[ ${#existing[@]} -gt 0 ]]; then
  verify_geolite "${existing[0]}"
  write_attribution
  echo "==> GeoIP2 database already in package: ${existing[*]}"
  exit 0
fi

if [[ -f "${CACHE_FILE}" ]]; then
  if ! sha256sum "${CACHE_FILE}" | awk '{print $1}' | grep -qx "${GEOLITE2_SHA256}"; then
    echo "==> Cached GeoLite2 does not match the pin; re-downloading" >&2
    rm -f "${CACHE_FILE}"
  fi
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
  verify_geolite "${tmp}"
  chmod 0644 "${tmp}"
  mv -f "${tmp}" "${CACHE_FILE}"
fi

verify_geolite "${CACHE_FILE}"
cp -f "${CACHE_FILE}" "${TARGET_DIR}/${GEOLITE2_NAME}"
write_attribution
echo "==> Packaged ${TARGET_DIR}/${GEOLITE2_NAME} (MaxMind GeoLite2)"
