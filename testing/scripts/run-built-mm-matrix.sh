#!/usr/bin/env bash
# Smoke matrix: locally built Metamod + rom4s / myarena SourceMod packages.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
export SERVER_DIR="${SERVER_DIR:-${ROOT}/.ci-server}"
export CACHE_DIR="${CACHE_DIR:-${ROOT}/.ci-cache}"
RESULTS="${RESULTS:-${CACHE_DIR}/smoke-matrix-results.txt}"

ROM4S_SM="${ROM4S_SM:-${CACHE_DIR}/rom4s-sm.tar.gz}"
MYARENA_ZIP="${MYARENA_ZIP:-${CACHE_DIR}/myarena-bundle.zip}"
MYARENA_SM_DIR="${MYARENA_SM_DIR:-${CACHE_DIR}/extract/myarena}"

chmod +x "${ROOT}/testing/scripts/"*.sh

: >"${RESULTS}"

run_case() {
  local name="$1" sm_pkg="$2" sm_expect="$3" use_1ep1="${4:-auto}"
  echo ""
  echo "========== CASE: ${name} =========="
  {
    echo "========== CASE: ${name} =========="
    echo "started: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  } >>"${RESULTS}"

  # Fresh server tree (addons only reset via reinstall)
  if [[ ! -x "${SERVER_DIR}/srcds_i686" && ! -x "${SERVER_DIR}/srcds_i486" ]]; then
    "${ROOT}/testing/scripts/fetch-server.sh"
    "${ROOT}/testing/scripts/apply-valve-rc-fix.sh"
    "${ROOT}/testing/scripts/apply-srcds-patch.sh"
  fi

  rm -rf "${SERVER_DIR}/cstrike/addons"
  mkdir -p "${SERVER_DIR}/cstrike/addons"

  "${ROOT}/testing/scripts/install-built-metamod.sh"

  if [[ "${sm_pkg}" == myarena ]]; then
    SM_PACKAGE="${MYARENA_SM_DIR}" "${ROOT}/testing/scripts/install-sourcemod-package.sh"
    # myarena ships 2.ep1 core only; ensure bridge can find it
    if [[ ! -f "${SERVER_DIR}/cstrike/addons/sourcemod/bin/sourcemod.1.ep1.so" \
      && -f "${SERVER_DIR}/cstrike/addons/sourcemod/bin/sourcemod.2.ep1.so" ]]; then
      echo "NOTE: myarena has sourcemod.2.ep1.so only (no 1.ep1)"
    fi
  else
    SM_PACKAGE="${sm_pkg}" "${ROOT}/testing/scripts/install-sourcemod-package.sh"
  fi

  export MM_VERSION_EXPECT="${MM_VERSION_EXPECT:-1.10.7}"
  export SM_VERSION_EXPECT="${sm_expect}"

  if "${ROOT}/testing/scripts/smoke-test.sh"; then
    echo "PASSED: ${name}" | tee -a "${RESULTS}"
    echo "result: PASSED" >>"${RESULTS}"
  else
    echo "FAILED: ${name}" | tee -a "${RESULTS}"
    echo "result: FAILED" >>"${RESULTS}"
    tail -n 40 "${SERVER_DIR}/console-probe.log" >>"${RESULTS}" 2>/dev/null || true
    return 1
  fi
}

"${ROOT}/testing/scripts/install-deps.sh"
"${ROOT}/testing/scripts/fetch-server.sh"
"${ROOT}/testing/scripts/apply-valve-rc-fix.sh"
"${ROOT}/testing/scripts/apply-srcds-patch.sh"

fail=0
run_case "built-MM + rom4s-SM-6572" "${ROM4S_SM}" "1.11.0.6572" || fail=1

# myarena SM targets MM 1.11 / sourcemod.2.ep1 (no CreateInterface bridge, no 1.ep1 core).
# On MM 1.10.x this typically hangs or never loads; documented in testing/README if needed.
if [[ "${SKIP_MYARENA_SMOKE:-0}" != "1" ]]; then
  if run_case "built-MM + myarena-SM-6522" "myarena" "1.11.0.6522"; then
    :
  else
    echo "NOTE: myarena SM failure is expected on MM 1.10.x (missing CreateInterface, 2.ep1-only layout)" | tee -a "${RESULTS}"
    # Do not fail the matrix solely for myarena-on-MM10 unless MYARENA_REQUIRED=1
    if [[ "${MYARENA_REQUIRED:-0}" == "1" ]]; then
      fail=1
    fi
  fi
fi

echo ""
echo "Matrix results: ${RESULTS}"
if [[ "${fail}" -ne 0 ]]; then
  exit 1
fi
