#!/usr/bin/env bash
# Compile SMAC and install .smx into SERVER_DIR/cstrike/addons/sourcemod/plugins.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SERVER_DIR="${SERVER_DIR:?SERVER_DIR is required}"
CACHE_DIR="${CACHE_DIR:-${ROOT}/.ci-cache}"
SM_PLUGINS_DIR="${SERVER_DIR}/cstrike/addons/sourcemod/plugins"
SMAC_SRC="${SMAC_SRC:-${CACHE_DIR}/smac_v34}"
SMAC_OUT="${SMAC_OUT:-${ROOT}/.ci-artifacts/smac-plugins}"

export SERVER_DIR
"${ROOT}/testing/scripts/compile-smac.sh"

mkdir -p "${SM_PLUGINS_DIR}"
cp -f "${SMAC_OUT}"/*.smx "${SM_PLUGINS_DIR}/"

# SMAC phrase file is required at runtime (smac.sp welcome timer).
SM_TRANS_DIR="${SERVER_DIR}/cstrike/addons/sourcemod/translations"
mkdir -p "${SM_TRANS_DIR}"
if [[ -f "${SMAC_SRC}/addons/sourcemod/translations/smac.phrases.txt" ]]; then
  cp -f "${SMAC_SRC}/addons/sourcemod/translations/smac.phrases.txt" "${SM_TRANS_DIR}/"
fi
if [[ -d "${SMAC_SRC}/addons/sourcemod/translations/ru" ]]; then
  mkdir -p "${SM_TRANS_DIR}/ru"
  cp -f "${SMAC_SRC}/addons/sourcemod/translations/ru/smac.phrases.txt" "${SM_TRANS_DIR}/ru/" 2>/dev/null || true
fi

echo "Installed SMAC plugins:"
ls -la "${SM_PLUGINS_DIR}"/smac*.smx
