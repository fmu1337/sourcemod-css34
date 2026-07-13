#!/usr/bin/env bash
# End-to-end: deps → server → patch → addons → smoke.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
export SERVER_DIR="${SERVER_DIR:-${ROOT}/.ci-server}"
export CACHE_DIR="${CACHE_DIR:-${ROOT}/.ci-cache}"
export APPLY_SRCDS_PATCH="${APPLY_SRCDS_PATCH:-1}"
export APPLY_VALVE_RC="${APPLY_VALVE_RC:-1}"

# Prefer in-tree packages when present and not overridden.
if [[ -z "${SM_PACKAGE:-}" && -z "${SM_URL:-}" ]]; then
  auto_sm="$(ls "${ROOT}"/packages/sourcemod-*-css34-linux.tar.gz 2>/dev/null | head -n1 || true)"
  if [[ -n "${auto_sm}" ]]; then
    export SM_PACKAGE="${auto_sm}"
  fi
fi
if [[ -z "${MM_PACKAGE:-}" && -z "${MM_URL:-}" && "${USE_BUILT_MM:-0}" != "1" ]]; then
  auto_mm="$(ls "${ROOT}"/packages/mmsource-*-css34-linux.tar.gz 2>/dev/null | head -n1 || true)"
  if [[ -n "${auto_mm}" ]]; then
    export MM_PACKAGE="${auto_mm}"
  fi
fi

# Version expects: our packages → 1.10.7; rom4s reference download → 1.10.6.
if [[ -z "${MM_VERSION_EXPECT:-}" ]]; then
  if [[ -n "${MM_PACKAGE:-}" || "${USE_BUILT_MM:-0}" == "1" || -n "${BUILT_MM_PACKAGE:-}" || -n "${BUILT_MM_DIR:-}" ]]; then
    export MM_VERSION_EXPECT=1.10.7
  else
    export MM_VERSION_EXPECT=1.10.6
  fi
fi
export SM_VERSION_EXPECT="${SM_VERSION_EXPECT:-1.11.0.6572}"

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
