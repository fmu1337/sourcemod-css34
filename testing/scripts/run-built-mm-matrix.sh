#!/usr/bin/env bash
# Smoke matrix: our Metamod + SourceMod packages (and optional reference mixes).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
export SERVER_DIR="${SERVER_DIR:-${ROOT}/.ci-server}"
export CACHE_DIR="${CACHE_DIR:-${ROOT}/.ci-cache}"
RESULTS="${RESULTS:-${CACHE_DIR}/smoke-matrix-results.txt}"

BUILT_SM="${BUILT_SM:-}"
if [[ -z "${BUILT_SM}" ]]; then
  BUILT_SM="$(ls "${ROOT}"/packages/sourcemod-*-css34-linux.tar.gz 2>/dev/null | head -n1 || true)"
fi
BUILT_MM="${BUILT_MM:-}"
if [[ -z "${BUILT_MM}" ]]; then
  BUILT_MM="$(ls "${ROOT}"/packages/mmsource-*-css34-linux.tar.gz 2>/dev/null | head -n1 || true)"
fi
ROM4S_SM="${ROM4S_SM:-${CACHE_DIR}/rom4s-sm.tar.gz}"
MYARENA_SM_DIR="${MYARENA_SM_DIR:-${CACHE_DIR}/extract/myarena}"

chmod +x "${ROOT}/testing/scripts/"*.sh

: >"${RESULTS}"

run_case() {
  local name="$1" sm_pkg="$2" sm_expect="$3" mm_mode="${4:-built-dir}"
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

  case "${mm_mode}" in
    package)
      if [[ -z "${BUILT_MM}" || ! -f "${BUILT_MM}" ]]; then
        echo "BUILT_MM package missing for package mode" >&2
        return 1
      fi
      rm -rf "${SERVER_DIR}/cstrike/addons/metamod" "${SERVER_DIR}/cstrike/addons/metamod.vdf"
      tar -xzf "${BUILT_MM}" -C "${SERVER_DIR}/cstrike"
      echo "Installed Metamod from package ${BUILT_MM}"
      ;;
    built-dir|*)
      "${ROOT}/testing/scripts/install-built-metamod.sh"
      ;;
  esac

  if [[ "${sm_pkg}" == myarena ]]; then
    SM_PACKAGE="${MYARENA_SM_DIR}" "${ROOT}/testing/scripts/install-sourcemod-package.sh"
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

# Primary: our packaged MM + our packaged SM (same combo as CI test-built-*).
if [[ -n "${BUILT_SM}" && -f "${BUILT_SM}" && -n "${BUILT_MM}" && -f "${BUILT_MM}" ]]; then
  run_case "built-MM-package + built-SM-6572" "${BUILT_SM}" "1.11.0.6572" "package" || fail=1
else
  echo "NOTE: packages/*.tar.gz not found; skipping primary built-package case" | tee -a "${RESULTS}"
fi

# Mixed: build-dir Metamod + rom4s SM (compatibility check).
if [[ -f "${ROM4S_SM}" ]]; then
  run_case "built-MM + rom4s-SM-6572" "${ROM4S_SM}" "1.11.0.6572" || fail=1
fi

# myarena SM targets MM 1.11 / sourcemod.2.ep1 (no CreateInterface bridge, no 1.ep1 core).
# On MM 1.10.x this typically hangs or never loads.
if [[ "${SKIP_MYARENA_SMOKE:-0}" != "1" && -d "${MYARENA_SM_DIR}/addons/sourcemod" ]]; then
  if run_case "built-MM + myarena-SM-6522" "myarena" "1.11.0.6522"; then
    :
  else
    echo "NOTE: myarena SM failure is expected on MM 1.10.x (missing CreateInterface, 2.ep1-only layout)" | tee -a "${RESULTS}"
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
