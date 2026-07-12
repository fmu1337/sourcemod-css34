#!/usr/bin/env bash
# Smoke-test: boot CS:S v34 + MM + SM, assert load markers, then stop.
set -euo pipefail

SERVER_DIR="${SERVER_DIR:?SERVER_DIR is required}"
MAP="${MAP:-de_dust2}"
PORT="${PORT:-27015}"
TIMEOUT_SECS="${TIMEOUT_SECS:-120}"
LOG_FILE="${LOG_FILE:-${SERVER_DIR}/smoke.log}"
SM_LOG_DIR="${SERVER_DIR}/cstrike/addons/sourcemod/logs"

cd "${SERVER_DIR}"
export LD_LIBRARY_PATH=".:bin:${LD_LIBRARY_PATH:-}"

rm -f "${LOG_FILE}"
rm -f "${SM_LOG_DIR}"/L*.log 2>/dev/null || true
mkdir -p "${SM_LOG_DIR}"

echo "Starting srcds (map=${MAP}, timeout=${TIMEOUT_SECS}s)"

./srcds_run \
  -game cstrike \
  -console \
  -norestart \
  -nohltv \
  -ip 127.0.0.1 \
  -port "${PORT}" \
  +ip 127.0.0.1 \
  +sv_lan 1 \
  +maxplayers 10 \
  +map "${MAP}" \
  >"${LOG_FILE}" 2>&1 &
srcds_pid=$!

cleanup() {
  if kill -0 "${srcds_pid}" 2>/dev/null; then
    kill -TERM "${srcds_pid}" 2>/dev/null || true
    # srcds_run may spawn a child
    pkill -TERM -P "${srcds_pid}" 2>/dev/null || true
    sleep 2
    kill -KILL "${srcds_pid}" 2>/dev/null || true
    pkill -KILL -P "${srcds_pid}" 2>/dev/null || true
  fi
}
trap cleanup EXIT

success=0
for ((i=1; i<=TIMEOUT_SECS; i++)); do
  if ! kill -0 "${srcds_pid}" 2>/dev/null; then
    echo "srcds exited early at t=${i}s"
    break
  fi
  if [[ -f "${LOG_FILE}" ]] && grep -Eiq 'Game\.dll loaded for "Counter-Strike: Source"' "${LOG_FILE}"; then
    if compgen -G "${SM_LOG_DIR}/L*.log" >/dev/null; then
      if grep -Eiq 'SourceMod log file session started.*Version' "${SM_LOG_DIR}"/L*.log; then
        echo "Success markers found at t=${i}s"
        success=1
        break
      fi
    fi
  fi
  sleep 1
done

cleanup
trap - EXIT
wait "${srcds_pid}" 2>/dev/null || true

echo "----- last 60 console lines -----"
tail -n 60 "${LOG_FILE}" || true
echo "----- SourceMod log -----"
if compgen -G "${SM_LOG_DIR}/L*.log" >/dev/null; then
  cat "${SM_LOG_DIR}"/L*.log
else
  echo "(no SourceMod log files)"
fi

fail=0
require_grep_file() {
  local file="$1" pat="$2" label="$3"
  if [[ -f "${file}" ]] && grep -Eiq -- "${pat}" "${file}"; then
    echo "OK: ${label}"
  else
    echo "FAIL: missing marker: ${label} (/${pat}/ in ${file})" >&2
    fail=1
  fi
}

require_grep_glob() {
  local glob="$1" pat="$2" label="$3"
  if compgen -G "${glob}" >/dev/null && grep -Eihq -- "${pat}" ${glob}; then
    echo "OK: ${label}"
  else
    echo "FAIL: missing marker: ${label} (/${pat}/ in ${glob})" >&2
    fail=1
  fi
}

require_grep_file "${LOG_FILE}" 'Game\.dll loaded for "Counter-Strike: Source"' "game dll loaded"
require_grep_file "${LOG_FILE}" 'Executing dedicated server config file|-------- Mapchange to' "map/config started"
# Metamod does not always print to console under eSTEAMATiON; SourceMod log proves MM loaded SM.
require_grep_glob "${SM_LOG_DIR}/L*.log" 'SourceMod log file session started' "SourceMod session started"
require_grep_glob "${SM_LOG_DIR}/L*.log" 'Version "' "SourceMod version recorded"

if grep -Eiq 'Segmentation fault|SIGSEGV' "${LOG_FILE}"; then
  echo "FAIL: segfault in console log" >&2
  fail=1
else
  echo "OK: absent segfault"
fi

unknown_count="$(grep -c 'Unknown command' "${LOG_FILE}" || true)"
echo "Unknown command count: ${unknown_count}"
if [[ "${unknown_count}" -gt 40 ]]; then
  echo "FAIL: too many Unknown command lines (${unknown_count}) — likely buffer bug" >&2
  fail=1
fi

if [[ "${success}" -ne 1 ]]; then
  echo "FAIL: did not observe success markers within ${TIMEOUT_SECS}s" >&2
  fail=1
fi

if [[ "${fail}" -ne 0 ]]; then
  echo "Smoke test FAILED"
  exit 1
fi

echo "Smoke test PASSED"
exit 0
