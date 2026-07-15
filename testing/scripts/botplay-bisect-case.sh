#!/usr/bin/env bash
# Run one botplay bisect case and emit a one-line result.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CASE_NAME="${CASE_NAME:?CASE_NAME is required}"
SERVER_DIR="${SERVER_DIR:-${ROOT}/.ci-bisect/${CASE_NAME}}"
CACHE_DIR="${CACHE_DIR:-${ROOT}/.ci-cache}"
RECORD_SECS="${RECORD_SECS:-90}"

BOTPLAY_PROFILE="${BOTPLAY_PROFILE:-built}"
DISABLE_STOCK_PLUGINS="${DISABLE_STOCK_PLUGINS:-0}"
SMAC_SET="${SMAC_SET:-all}"
INSTALL_SMAC="${INSTALL_SMAC:-1}"
OVERLAY_ROM4S_BINTOOLS="${OVERLAY_ROM4S_BINTOOLS:-0}"
ROM4S_OVERLAY_PARTS="${ROM4S_OVERLAY_PARTS:-}"
BUILT_OVERLAY_PARTS="${BUILT_OVERLAY_PARTS:-}"
BUILT_SM_PACKAGE="${BUILT_SM_PACKAGE:-${SM_PACKAGE:-}}"
USE_ROM4S_MM="${USE_ROM4S_MM:-0}"
USE_ROM4S_SM="${USE_ROM4S_SM:-0}"

export SERVER_DIR CACHE_DIR RECORD_SECS BOTPLAY_PROFILE
export DISABLE_STOCK_PLUGINS SMAC_SET
export MIN_ROUND_START=0 MIN_ROUND_END=0 MIN_PLAYER_DEATH=0 MIN_SMAC_RUNNING=0
export REPORT_JSON="${SERVER_DIR}/botplay-report.json"
export REPORT_TXT="${SERVER_DIR}/botplay-report.txt"

if [[ -d "${ROOT}/.ci-server/cstrike/maps" ]]; then
  SEED_DIR="${ROOT}/.ci-server"
elif [[ -d "${ROOT}/.ci-server-seed/cstrike/maps" ]]; then
  SEED_DIR="${ROOT}/.ci-server-seed"
else
  SEED_DIR="${ROOT}/.ci-server-seed"
  mkdir -p "${SEED_DIR}"
  SERVER_DIR="${SEED_DIR}" "${ROOT}/testing/scripts/fetch-server.sh"
  APPLY_VALVE_RC=1 APPLY_SRCDS_PATCH=1 SERVER_DIR="${SEED_DIR}" "${ROOT}/testing/scripts/apply-valve-rc-fix.sh"
  APPLY_SRCDS_PATCH=1 SERVER_DIR="${SEED_DIR}" "${ROOT}/testing/scripts/apply-srcds-patch.sh"
  KEEP_MAP=de_dust2 SERVER_DIR="${SEED_DIR}" "${ROOT}/testing/scripts/trim-server-maps.sh"
  touch "${CACHE_DIR}/css34-server-ready.stamp"
fi

export SERVER_DIR="${ROOT}/.ci-bisect/${CASE_NAME}"
rm -rf "${SERVER_DIR}"
mkdir -p "${SERVER_DIR}"

echo "Seeding server tree into ${SERVER_DIR} from ${SEED_DIR}"
tar -C "${SEED_DIR}" -cf - . | tar -C "${SERVER_DIR}" -xf -

if [[ "${USE_ROM4S_MM}" == "1" ]]; then
  unset MM_PACKAGE USE_BUILT_MM BUILT_MM_DIR BUILT_MM_PACKAGE || true
  export MM_URL="${MM_URL:-https://bitbucket.org/rom4s/mmsdrop-1.10/downloads/mmsource-1.10.6-css34-linux.tar.gz}"
  MM_VERSION_EXPECT=1.10.6
  export MM_URL MM_VERSION_EXPECT
else
  case "${BOTPLAY_PROFILE}" in
    built)
      export MM_VERSION_EXPECT="${MM_VERSION_EXPECT:-1.10.7}"
      ;;
    rom4s)
      export MM_VERSION_EXPECT="${MM_VERSION_EXPECT:-1.10.6}"
      ;;
  esac
fi

export SKIP_INSTALL_ADDONS=0
case "${BOTPLAY_PROFILE}" in
  built)
    : "${SM_PACKAGE:?SM_PACKAGE required}"
    export SM_PACKAGE
    if [[ "${USE_ROM4S_MM}" == "1" ]]; then
      unset MM_PACKAGE USE_BUILT_MM BUILT_MM_DIR BUILT_MM_PACKAGE || true
      export MM_URL SERVER_DIR
      "${ROOT}/testing/scripts/install-addons.sh"
    elif [[ "${USE_ROM4S_SM:-0}" == "1" ]]; then
      unset SM_PACKAGE || true
      export SM_URL="${SM_URL:-https://github.com/rom4s/sourcemod-css34/releases/download/v1.11.0.6572/sourcemod-1.11.0-git6572-css34-linux.tar.gz}"
      : "${MM_PACKAGE:?MM_PACKAGE required}"
      export MM_PACKAGE SERVER_DIR
      "${ROOT}/testing/scripts/install-addons.sh"
    else
      : "${MM_PACKAGE:?MM_PACKAGE required}"
      export MM_PACKAGE SERVER_DIR
      "${ROOT}/testing/scripts/install-addons.sh"
    fi
    ;;
  rom4s)
    unset MM_PACKAGE SM_PACKAGE USE_BUILT_MM || true
    export MM_URL SM_URL SERVER_DIR
    "${ROOT}/testing/scripts/install-addons.sh"
    ;;
esac

if [[ "${OVERLAY_ROM4S_BINTOOLS}" == "1" ]]; then
  "${ROOT}/testing/scripts/overlay-rom4s-bintools.sh"
fi

if [[ -n "${ROM4S_OVERLAY_PARTS}" ]]; then
  export ROM4S_OVERLAY_PARTS
  "${ROOT}/testing/scripts/overlay-rom4s-sm-parts.sh"
fi

if [[ -n "${BUILT_OVERLAY_PARTS}" ]]; then
  : "${BUILT_SM_PACKAGE:?BUILT_SM_PACKAGE or SM_PACKAGE required for built overlay}"
  export BUILT_SM_PACKAGE BUILT_OVERLAY_PARTS
  "${ROOT}/testing/scripts/overlay-built-sm-parts.sh"
fi

if [[ "${INSTALL_SMAC}" == "1" ]]; then
  export INSTALL_SMAC=1
  export DISABLE_STOCK_PLUGINS SMAC_SET
else
  export INSTALL_SMAC=0
  export DISABLE_STOCK_PLUGINS
fi
export SKIP_INSTALL_ADDONS=1

set +e
"${ROOT}/testing/scripts/botplay-test.sh"
rc=$?
set -e

crash=false
round_start=0
round_end=0
player_death=0
if [[ -f "${REPORT_JSON}" ]]; then
  crash="$(awk -F'"' '/"crash"/ {print $4; exit}' "${REPORT_JSON}")"
  round_start="$(awk '/"events"/ {in_e=1; next} in_e && /"round_start"/ {print $2; gsub(/,/, ""); exit}' "${REPORT_JSON}")"
  round_end="$(awk '/"events"/ {in_e=1; next} in_e && /"round_end"/ {print $2; gsub(/,/, ""); exit}' "${REPORT_JSON}")"
  player_death="$(awk '/"events"/ {in_e=1; next} in_e && /"player_death"/ {print $2; gsub(/,/, ""); exit}' "${REPORT_JSON}")"
fi

if grep -Eiq 'Bad entity in IndexOfEdict|Segmentation fault|SIGSEGV' \
  "${SERVER_DIR}/cstrike/console.log" "${SERVER_DIR}/botplay.log" 2>/dev/null; then
  crash=true
fi

if [[ "${rc}" -eq 0 && "${crash}" != "true" ]]; then
  result="PASS"
else
  result="FAIL"
fi

printf '%s\n' "${CASE_NAME}|${result}|rs=${round_start:-0}|re=${round_end:-0}|kd=${player_death:-0}|crash=${crash}|rc=${rc}"
exit 0
