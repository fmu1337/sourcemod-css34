#!/usr/bin/env bash
# Download and assemble a CS:S v34 dedicated server tree.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SERVER_DIR="${SERVER_DIR:-${ROOT}/.ci-server}"
CACHE_DIR="${CACHE_DIR:-${ROOT}/.ci-cache}"

BASE_ZIP_URL="${BASE_ZIP_URL:-https://bitbucket.org/rom4s/other.get/downloads/srcds_css34_4044.zip}"
BIN_ZIP_URL="${BIN_ZIP_URL:-https://bitbucket.org/rom4s/other.get/downloads/srcds_css34_l_a.zip}"
ESTEAM_ZIP_URL="${ESTEAM_ZIP_URL:-https://bitbucket.org/rom4s/other.get/downloads/srcds_css34_l_eSTEAMATiON.zip}"

mkdir -p "${CACHE_DIR}" "${SERVER_DIR}"

download() {
  local url="$1" out="$2"
  if [[ -f "${out}" && -s "${out}" ]]; then
    echo "Using cached $(basename "${out}")"
    return 0
  fi
  echo "Downloading ${url}"
  curl -fL --retry 5 --retry-delay 3 -o "${out}.partial" "${url}"
  mv "${out}.partial" "${out}"
}

download "${BASE_ZIP_URL}" "${CACHE_DIR}/srcds_css34_4044.zip"
download "${BIN_ZIP_URL}" "${CACHE_DIR}/srcds_css34_l_a.zip"
download "${ESTEAM_ZIP_URL}" "${CACHE_DIR}/srcds_css34_l_eSTEAMATiON.zip"

echo "Assembling server into ${SERVER_DIR}"
rm -rf "${SERVER_DIR}"
mkdir -p "${SERVER_DIR}"

# Base content (maps/materials/cfg/platform/hl2)
unzip -q -o "${CACHE_DIR}/srcds_css34_4044.zip" -d "${SERVER_DIR}"
# Binaries + srcds_run
unzip -q -o "${CACHE_DIR}/srcds_css34_l_a.zip" -d "${SERVER_DIR}"
# eSTEAMATiON overlay (steamclient etc.)
unzip -q -o "${CACHE_DIR}/srcds_css34_l_eSTEAMATiON.zip" -d "${SERVER_DIR}"

chmod +x \
  "${SERVER_DIR}/srcds_amd" \
  "${SERVER_DIR}/srcds_i486" \
  "${SERVER_DIR}/srcds_i686" \
  "${SERVER_DIR}/srcds_run" \
  "${SERVER_DIR}/start.sh" 2>/dev/null || true

# Minimal server.cfg for CI
mkdir -p "${SERVER_DIR}/cstrike/cfg"
cat >"${SERVER_DIR}/cstrike/cfg/server.cfg" <<'EOF'
hostname sourcemod-css34-ci
sv_lan 1
sv_cheats 0
mp_timelimit 0
mp_autokick 0
exec banned_ip.cfg
exec banned_user.cfg
writeid
writeip
EOF

# Debian 9+ valve.rc workaround (also applied explicitly by apply-valve-rc-fix.sh)
cp -f "${ROOT}/testing/configs/valve.rc" "${SERVER_DIR}/cstrike/cfg/valve.rc"

echo "Server tree ready at ${SERVER_DIR}"
du -sh "${SERVER_DIR}"
