#!/usr/bin/env bash
# End-to-end: deps → server → patch → addons → smoke.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
export SERVER_DIR="${SERVER_DIR:-${ROOT}/.ci-server}"
export CACHE_DIR="${CACHE_DIR:-${ROOT}/.ci-cache}"
export APPLY_SRCDS_PATCH="${APPLY_SRCDS_PATCH:-1}"
export APPLY_VALVE_RC="${APPLY_VALVE_RC:-1}"

chmod +x "${ROOT}/testing/scripts/"*.sh

"${ROOT}/testing/scripts/install-deps.sh"
"${ROOT}/testing/scripts/fetch-server.sh"

if [[ "${APPLY_VALVE_RC}" == "1" ]]; then
  "${ROOT}/testing/scripts/apply-valve-rc-fix.sh"
fi
if [[ "${APPLY_SRCDS_PATCH}" == "1" ]]; then
  "${ROOT}/testing/scripts/apply-srcds-patch.sh"
fi

"${ROOT}/testing/scripts/install-addons.sh"
"${ROOT}/testing/scripts/smoke-test.sh"
