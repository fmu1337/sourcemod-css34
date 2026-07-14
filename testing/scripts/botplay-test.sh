#!/usr/bin/env bash
# Rom4s or built packages + SMAC + botplay recording session.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SERVER_DIR="${SERVER_DIR:?SERVER_DIR is required}"

BOTPLAY_PROFILE="${BOTPLAY_PROFILE:-rom4s}"
MAP="${MAP:-de_dust2}"
PORT="${PORT:-27015}"
RECORD_SECS="${RECORD_SECS:-600}"
TIMEOUT_SECS="${TIMEOUT_SECS:-$((RECORD_SECS + 180))}"
LOG_FILE="${LOG_FILE:-${SERVER_DIR}/botplay-run.log}"
BOTPLAY_LOG="${BOTPLAY_LOG:-${SERVER_DIR}/botplay.log}"
REPORT_JSON="${REPORT_JSON:-${SERVER_DIR}/botplay-report.json}"
REPORT_TXT="${REPORT_TXT:-${SERVER_DIR}/botplay-report.txt}"
SRCDS_BINARY="${SRCDS_BINARY:-./srcds_i686}"
SMOKE_VERBOSE="${SMOKE_VERBOSE:-1}"
SMOKE_CONDEBUG="${SMOKE_CONDEBUG:-1}"
ENGINE_CONSOLE_LOG="${SERVER_DIR}/cstrike/console.log"
SM_LOG_DIR="${SERVER_DIR}/cstrike/addons/sourcemod/logs"

case "${BOTPLAY_PROFILE}" in
  built)
    MM_VERSION_EXPECT="${MM_VERSION_EXPECT:-1.10.7}"
    SM_VERSION_EXPECT="${SM_VERSION_EXPECT:-1.11.0.6572}"
    ;;
  rom4s)
    MM_URL="${MM_URL:-https://bitbucket.org/rom4s/mmsdrop-1.10/downloads/mmsource-1.10.6-css34-linux.tar.gz}"
    SM_URL="${SM_URL:-https://github.com/rom4s/sourcemod-css34/releases/download/v1.11.0.6572/sourcemod-1.11.0-git6572-css34-linux.tar.gz}"
    MM_VERSION_EXPECT="${MM_VERSION_EXPECT:-1.10.6}"
    SM_VERSION_EXPECT="${SM_VERSION_EXPECT:-1.11.0.6572}"
    ;;
  *)
    echo "Unknown BOTPLAY_PROFILE=${BOTPLAY_PROFILE} (use rom4s or built)" >&2
    exit 1
    ;;
esac

MIN_ROUND_START="${MIN_ROUND_START:-3}"
MIN_ROUND_END="${MIN_ROUND_END:-3}"
MIN_PLAYER_DEATH="${MIN_PLAYER_DEATH:-8}"
MIN_SMAC_RUNNING="${MIN_SMAC_RUNNING:-14}"

cd "${SERVER_DIR}"
export LD_LIBRARY_PATH=".:bin:${LD_LIBRARY_PATH:-}"

rm -f "${LOG_FILE}" "${BOTPLAY_LOG}" "${REPORT_JSON}" "${REPORT_TXT}"
rm -f "${SM_LOG_DIR}"/L*.log 2>/dev/null || true
mkdir -p "${SM_LOG_DIR}"

if [[ ! -x "${SRCDS_BINARY}" ]]; then
  if [[ -x ./srcds_i486 ]]; then
    SRCDS_BINARY=./srcds_i486
  else
    echo "No srcds_i686/i486 binary found" >&2
    exit 1
  fi
fi

if ! command -v expect >/dev/null 2>&1; then
  echo "expect is required for botplay recording" >&2
  exit 1
fi

if [[ "${SKIP_INSTALL_ADDONS:-0}" != "1" ]]; then
  case "${BOTPLAY_PROFILE}" in
    built)
      if [[ -z "${SM_PACKAGE:-}" || -z "${MM_PACKAGE:-}" ]]; then
        echo "built profile requires SM_PACKAGE and MM_PACKAGE" >&2
        exit 1
      fi
      export SM_PACKAGE MM_PACKAGE SERVER_DIR
      "${ROOT}/testing/scripts/install-addons.sh"
      ;;
    rom4s)
      unset MM_PACKAGE SM_PACKAGE USE_BUILT_MM BUILT_MM_DIR BUILT_MM_PACKAGE || true
      export MM_URL SM_URL SERVER_DIR
      "${ROOT}/testing/scripts/install-addons.sh"
      ;;
  esac
fi

mkdir -p "${SERVER_DIR}/cstrike/cfg"
cp -f "${ROOT}/testing/cfg/botplay-server.cfg" "${SERVER_DIR}/cstrike/cfg/botplay-server.cfg"

export SERVER_DIR BOTPLAY_PROFILE MM_VERSION_EXPECT SM_VERSION_EXPECT
"${ROOT}/testing/scripts/install-smac.sh"

echo "Starting ${BOTPLAY_PROFILE} botplay recording (binary=${SRCDS_BINARY}, map=${MAP}, record=${RECORD_SECS}s)"
export SERVER_DIR MAP PORT SRCDS_BINARY BOTPLAY_LOG RECORD_SECS
export CONSOLE_PROBE_TIMEOUT="${TIMEOUT_SECS}"
export SMOKE_VERBOSE SMOKE_CONDEBUG
rm -f "${ENGINE_CONSOLE_LOG}"

/usr/bin/expect "${ROOT}/testing/scripts/botplay-record.exp" >"${LOG_FILE}" 2>&1 || {
  echo "Botplay recording failed (see ${LOG_FILE})" >&2
  tail -n 120 "${LOG_FILE}" >&2 || true
  if [[ -f "${BOTPLAY_LOG}" ]]; then
    echo "----- botplay.log (last 120) -----" >&2
    tail -n 120 "${BOTPLAY_LOG}" >&2 || true
  fi
  if [[ -f "${ENGINE_CONSOLE_LOG}" ]]; then
    echo "----- cstrike/console.log (last 120) -----" >&2
    tail -n 120 "${ENGINE_CONSOLE_LOG}" >&2 || true
  fi
  exit 1
}

export RECORD_SECS MAP BOTPLAY_PROFILE MM_VERSION_EXPECT SM_VERSION_EXPECT
chmod +x "${ROOT}/testing/scripts/parse-botplay-logs.sh"
"${ROOT}/testing/scripts/parse-botplay-logs.sh" "${SERVER_DIR}" "${REPORT_JSON}" "${REPORT_TXT}"

fail=0
require_min() {
  local label="$1" actual="$2" min="$3"
  if [[ "${actual}" -ge "${min}" ]]; then
    echo "OK: ${label} (${actual} >= ${min})"
  else
    echo "FAIL: ${label} (${actual} < ${min})" >&2
    fail=1
  fi
}

json_events_field() {
  local file="$1" key="$2"
  awk -v key="${key}" '
    $0 ~ "\"events\"" { in_events=1; next }
    in_events && $0 ~ "\"" key "\"" {
      for (i = 1; i <= NF; i++) {
        if ($i ~ /^[0-9]+,?$/ || $i ~ /^[0-9]+$/) {
          gsub(/,/, "", $i)
          print $i
          exit
        }
      }
    }
    in_events && $0 ~ /^\s*\}/ { in_events=0 }
  ' "${file}"
}

json_nested_field() {
  local file="$1" section="$2" key="$3"
  awk -v section="${section}" -v key="${key}" '
    $0 ~ "\"" section "\"" { in_section=1; next }
    in_section && $0 ~ "\"" key "\"" {
      for (i = 1; i <= NF; i++) {
        if ($i ~ /^[0-9]+,?$/ || $i ~ /^[0-9]+$/ || $i ~ /^true,?$/ || $i ~ /^false,?$/) {
          gsub(/,/, "", $i)
          print $i
          exit
        }
      }
    }
    in_section && $0 ~ /^\s*\}/ { in_section=0 }
  ' "${file}"
}

round_start="$(json_events_field "${REPORT_JSON}" round_start)"
round_end="$(json_events_field "${REPORT_JSON}" round_end)"
player_death="$(json_events_field "${REPORT_JSON}" player_death)"
smac_running="$(json_nested_field "${REPORT_JSON}" smac running_plugins)"
crash="$(json_nested_field "${REPORT_JSON}" stability crash)"

require_min "round_start events" "${round_start}" "${MIN_ROUND_START}"
require_min "round_end events" "${round_end}" "${MIN_ROUND_END}"
require_min "player_death events" "${player_death}" "${MIN_PLAYER_DEATH}"
require_min "SMAC running plugins" "${smac_running}" "${MIN_SMAC_RUNNING}"

if [[ "${crash}" == "True" || "${crash}" == "true" ]]; then
  echo "FAIL: crash marker in botplay logs" >&2
  fail=1
else
  echo "OK: no crash marker"
fi

if grep -Fq "${MM_VERSION_EXPECT}" "${BOTPLAY_LOG}" 2>/dev/null; then
  echo "OK: Metamod version ${MM_VERSION_EXPECT}"
else
  echo "FAIL: Metamod version ${MM_VERSION_EXPECT} not found in botplay log" >&2
  fail=1
fi
if grep -Fq "${SM_VERSION_EXPECT}" "${BOTPLAY_LOG}" 2>/dev/null; then
  echo "OK: SourceMod version ${SM_VERSION_EXPECT}"
else
  echo "FAIL: SourceMod version ${SM_VERSION_EXPECT} not found in botplay log" >&2
  fail=1
fi

if [[ "${fail}" -ne 0 ]]; then
  echo "Botplay test FAILED"
  exit 1
fi

echo "Botplay test PASSED"
exit 0
