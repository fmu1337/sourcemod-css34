#!/usr/bin/env bash
# Compile and install botplay helper plugins into SERVER_DIR.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SERVER_DIR="${SERVER_DIR:?SERVER_DIR is required}"
SM_PLUGINS_DIR="${SERVER_DIR}/cstrike/addons/sourcemod/plugins"
BOTPLAY_OUT="${BOTPLAY_OUT:-${ROOT}/.ci-artifacts/botplay-plugins}"

export SERVER_DIR
"${ROOT}/testing/scripts/compile-botplay-plugins.sh"

mkdir -p "${SM_PLUGINS_DIR}"
cp -f "${BOTPLAY_OUT}"/*.smx "${SM_PLUGINS_DIR}/"

echo "Installed botplay plugins:"
ls -la "${SM_PLUGINS_DIR}"/css34_*.smx
