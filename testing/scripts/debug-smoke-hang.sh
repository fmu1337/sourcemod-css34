#!/usr/bin/env bash
# Sample gdb stacks + optional breakpoints with timeout; collect /tmp/sm-boot-trace.log.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SERVER_DIR="${SERVER_DIR:-${ROOT}/.ci-server}"
WAIT_SECS="${WAIT_SECS:-55}"
OUT_DIR="${OUT_DIR:-/tmp/smoke-debug-$$}"
SRCDS_BINARY="${SRCDS_BINARY:-./srcds_i686}"
LOGIC_MODE="${LOGIC_MODE:-built}"   # built | rom4s | path
LOGIC_PATH="${LOGIC_PATH:-}"
PORT="${PORT:-27016}"
GDB_BREAK_TIMEOUT="${GDB_BREAK_TIMEOUT:-12}"

mkdir -p "${OUT_DIR}"
cd "${SERVER_DIR}"
export LD_LIBRARY_PATH=".:bin:${LD_LIBRARY_PATH:-}"

case "${LOGIC_MODE}" in
  built)
    if [[ -n "${LOGIC_PATH}" ]]; then
      cp -f "${LOGIC_PATH}" cstrike/addons/sourcemod/bin/sourcemod.logic.so
    elif [[ -f "${ROOT}/sourcemod/build/core/logic/sourcemod.logic/sourcemod.logic.so" ]]; then
      cp -f "${ROOT}/sourcemod/build/core/logic/sourcemod.logic/sourcemod.logic.so" \
        cstrike/addons/sourcemod/bin/sourcemod.logic.so
    fi
    ;;
  rom4s)
    cp -f cstrike/addons/sourcemod/bin/sourcemod.logic.so.rom4s \
      cstrike/addons/sourcemod/bin/sourcemod.logic.so 2>/dev/null || {
      echo "rom4s logic reference missing (sourcemod.logic.so.rom4s)" >&2
      exit 1
    }
    ;;
  path)
    [[ -n "${LOGIC_PATH}" ]] || { echo "LOGIC_PATH required for LOGIC_MODE=path" >&2; exit 2; }
    cp -f "${LOGIC_PATH}" cstrike/addons/sourcemod/bin/sourcemod.logic.so
    ;;
esac

rm -f /tmp/sm-boot-trace.log
echo "=== debug-smoke-hang logic=${LOGIC_MODE} wait=${WAIT_SECS}s out=${OUT_DIR} ===" | tee "${OUT_DIR}/summary.txt"

rm -f "${OUT_DIR}/srcds.log"
"${SRCDS_BINARY}" -game cstrike -console -nohltv -nomaster -localcser -tickrate 66 \
  -ip 127.0.0.1 -port "${PORT}" +ip 127.0.0.1 +sv_lan 1 +maxplayers 10 +map de_dust2 \
  >"${OUT_DIR}/srcds.log" 2>&1 &
PID=$!
echo "srcds pid=${PID}" | tee -a "${OUT_DIR}/summary.txt"

cleanup() {
  kill -TERM "${PID}" 2>/dev/null || true
  sleep 1
  kill -KILL "${PID}" 2>/dev/null || true
}
trap cleanup EXIT

sleep "${WAIT_SECS}"

if ! kill -0 "${PID}" 2>/dev/null; then
  echo "srcds exited early" | tee -a "${OUT_DIR}/summary.txt"
  wait "${PID}" || true
  tail -n 80 "${OUT_DIR}/srcds.log" | tee "${OUT_DIR}/srcds-tail.txt"
  exit 1
fi

ps -o pid,ppid,stat,etime,cmd -p "${PID}" | tee "${OUT_DIR}/ps.txt"

if command -v gdb >/dev/null 2>&1; then
  gdb -batch -n -ex "set pagination off" -ex "attach ${PID}" \
    -ex "info threads" \
    -ex "thread apply all bt 25" \
    -ex "detach" -ex "quit" \
    >"${OUT_DIR}/gdb-all-threads.txt" 2>&1 || true

  # Timed breakpoint probe — does not hang if symbols never hit.
  gdb -batch -n \
    -ex "set pagination off" \
    -ex "attach ${PID}" \
    -ex "set confirm off" \
    -ex "break SourceModBase::LevelInit" \
    -ex "break SourceModBase::StartSourceMod" \
    -ex "break Logger::_MapChange" \
    -ex "break CoreProviderImpl::InitializeBridge" \
    -ex "break logic_init" \
    -ex "commands" \
    -ex "continue" \
    >"${OUT_DIR}/gdb-break-commands.txt" 2>&1 &
  GDB_PID=$!
  sleep "${GDB_BREAK_TIMEOUT}"
  kill -TERM "${GDB_PID}" 2>/dev/null || true
  wait "${GDB_PID}" 2>/dev/null || true
fi

if command -v strace >/dev/null 2>&1; then
  timeout 6 strace -f -p "${PID}" -e trace=futex,poll,select,pselect6,read,write,openat \
    2>"${OUT_DIR}/strace-sample.txt" || true
fi

tail -n 80 "${OUT_DIR}/srcds.log" | tee "${OUT_DIR}/srcds-tail.txt"

if [[ -f /tmp/sm-boot-trace.log ]]; then
  echo "=== /tmp/sm-boot-trace.log ===" | tee "${OUT_DIR}/boot-trace.log"
  cat /tmp/sm-boot-trace.log | tee -a "${OUT_DIR}/boot-trace.log"
  cp -f /tmp/sm-boot-trace.log "${OUT_DIR}/sm-boot-trace.log"
else
  echo "(no /tmp/sm-boot-trace.log — rebuild core+logic with SM_BOOT_TRACE)" | tee "${OUT_DIR}/boot-trace.log"
fi

if compgen -G "cstrike/addons/sourcemod/logs/L*.log" >/dev/null; then
  cat cstrike/addons/sourcemod/logs/L*.log | tee "${OUT_DIR}/sm-logs.txt"
else
  echo "(no SourceMod session logs)" | tee "${OUT_DIR}/sm-logs.txt"
fi

file cstrike/addons/sourcemod/bin/sourcemod.logic.so | tee "${OUT_DIR}/logic-file.txt"
echo "Done. Artifacts: ${OUT_DIR}"
