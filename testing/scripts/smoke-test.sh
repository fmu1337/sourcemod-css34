#!/usr/bin/env bash
# Smoke-test: boot CS:S v34 + MM + SM, run console probes, assert versions.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SERVER_DIR="${SERVER_DIR:?SERVER_DIR is required}"
MAP="${MAP:-de_dust2}"
PORT="${PORT:-27015}"
TIMEOUT_SECS="${TIMEOUT_SECS:-120}"
LOG_FILE="${LOG_FILE:-${SERVER_DIR}/smoke.log}"
CONSOLE_PROBE_LOG="${CONSOLE_PROBE_LOG:-${SERVER_DIR}/console-probe.log}"
SM_LOG_DIR="${SERVER_DIR}/cstrike/addons/sourcemod/logs"
SRCDS_BINARY="${SRCDS_BINARY:-./srcds_i686}"

# Expected versions (rom4s reference drops by default).
MM_VERSION_EXPECT="${MM_VERSION_EXPECT:-1.10.6}"
SM_VERSION_EXPECT="${SM_VERSION_EXPECT:-1.11.0.6572}"

cd "${SERVER_DIR}"
export LD_LIBRARY_PATH=".:bin:${LD_LIBRARY_PATH:-}"

rm -f "${LOG_FILE}" "${CONSOLE_PROBE_LOG}"
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
  echo "expect is required for console command probes" >&2
  exit 1
fi

echo "Starting srcds (binary=${SRCDS_BINARY}, map=${MAP}, port=${PORT}, args=-nomaster -localcser, timeout=${TIMEOUT_SECS}s)"

export SERVER_DIR MAP PORT SRCDS_BINARY CONSOLE_PROBE_LOG
export CONSOLE_PROBE_TIMEOUT="${TIMEOUT_SECS}"
/usr/bin/expect "${ROOT}/testing/scripts/console-probe.exp" >"${LOG_FILE}" 2>&1 || {
  echo "Console probe failed (see ${LOG_FILE})" >&2
  tail -n 60 "${LOG_FILE}" || true
  exit 1
}

echo "----- console probe log (first 40 lines) -----"
head -n 40 "${CONSOLE_PROBE_LOG}" || true
echo "----- console probe log (last 80 lines) -----"
tail -n 80 "${CONSOLE_PROBE_LOG}" || true
echo "----- SourceMod log -----"
if compgen -G "${SM_LOG_DIR}/L*.log" >/dev/null; then
  cat "${SM_LOG_DIR}"/L*.log
else
  echo "(no SourceMod log files)"
fi

fail=0
require_grep() {
  local file="$1" pat="$2" label="$3"
  if [[ -f "${file}" ]] && grep -Eiq -- "${pat}" "${file}"; then
    echo "OK: ${label}"
  else
    echo "FAIL: ${label} (/${pat}/ in ${file})" >&2
    fail=1
  fi
}

require_grep "${CONSOLE_PROBE_LOG}" 'Mapchange to de_dust2|Mapchange to '"${MAP}" "map loaded (${MAP})"
require_grep "${CONSOLE_PROBE_LOG}" 'hostname|# [0-9]+' "status command output"
require_grep "${CONSOLE_PROBE_LOG}" 'Protocol version|version' "version command output"
require_grep "${CONSOLE_PROBE_LOG}" 'Metamod|metamod|MM:S' "meta version command output"
require_grep "${CONSOLE_PROBE_LOG}" 'SourceMod|SM' "sm version command output"

require_grep "${CONSOLE_PROBE_LOG}" "${MM_VERSION_EXPECT}" "Metamod version ${MM_VERSION_EXPECT}"
require_grep "${CONSOLE_PROBE_LOG}" "${SM_VERSION_EXPECT}" "SourceMod version ${SM_VERSION_EXPECT}"

require_grep_glob() {
  local glob="$1" pat="$2" label="$3"
  if compgen -G "${glob}" >/dev/null && grep -Eihq -- "${pat}" ${glob}; then
    echo "OK: ${label}"
  else
    echo "FAIL: ${label} (/${pat}/ in ${glob})" >&2
    fail=1
  fi
}

require_grep_glob "${SM_LOG_DIR}/L*.log" 'SourceMod log file session started' "SourceMod session started"
require_grep_glob "${SM_LOG_DIR}/L*.log" 'Version "' "SourceMod version recorded in log"
require_grep_glob "${SM_LOG_DIR}/L*.log" 'Mapchange to' "SourceMod saw mapchange"

if grep -Eiq 'Segmentation fault|SIGSEGV|Aborted|SIGABRT' "${CONSOLE_PROBE_LOG}"; then
  echo "FAIL: crash marker in console probe log" >&2
  fail=1
else
  echo "OK: absent crash marker in console probe log"
fi

unknown_count="$(grep -c 'Unknown command' "${CONSOLE_PROBE_LOG}" || true)"
echo "Unknown command count: ${unknown_count}"
if [[ "${unknown_count}" -gt 40 ]]; then
  echo "FAIL: too many Unknown command lines (${unknown_count})" >&2
  fail=1
fi

if [[ "${fail}" -ne 0 ]]; then
  echo "Smoke test FAILED"
  exit 1
fi

echo "Smoke test PASSED"
exit 0
