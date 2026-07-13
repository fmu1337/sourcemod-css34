#!/usr/bin/env bash
# Break on SourceMod mapchange path when hung.
set -euo pipefail
SERVER_DIR="${SERVER_DIR:-/workspace/.ci-server}"
WAIT="${WAIT:-70}"
PORT=27017
cd "${SERVER_DIR}"
export LD_LIBRARY_PATH=".:bin:${LD_LIBRARY_PATH:-}"

LOGIC="${1:-built}"
case "${LOGIC}" in
  rom4s) cp cstrike/addons/sourcemod/bin/sourcemod.logic.so.rom4s cstrike/addons/sourcemod/bin/sourcemod.logic.so ;;
  built) cp /workspace/sourcemod/build/core/logic/sourcemod.logic/sourcemod.logic.so cstrike/addons/sourcemod/bin/sourcemod.logic.so ;;
  *) echo "usage: $0 [built|rom4s]" >&2; exit 2 ;;
esac

./srcds_i686 -game cstrike -console -nohltv -nomaster -localcser -tickrate 66 \
  -ip 127.0.0.1 -port "${PORT}" +ip 127.0.0.1 +sv_lan 1 +maxplayers 10 +map de_dust2 \
  >/tmp/gdb-smoke-srcds.log 2>&1 &
PID=$!
trap 'kill -TERM $PID 2>/dev/null || true' EXIT

echo "logic=${LOGIC} pid=${PID}, waiting ${WAIT}s before gdb breakpoints..."
sleep "${WAIT}"

if ! kill -0 "${PID}" 2>/dev/null; then
  echo "srcds exited"
  tail -40 /tmp/gdb-smoke-srcds.log
  exit 1
fi

gdb -batch -n \
  -ex "set pagination off" \
  -ex "attach ${PID}" \
  -ex "info functions LevelInit" \
  -ex "info functions OnSourceModLevelChange" \
  -ex "info functions _MapChange" \
  -ex "break Logger::OnSourceModLevelChange" \
  -ex "break SourceModBase::LevelInit" \
  -ex "break Logger::_MapChange" \
  -ex "continue" \
  -ex "bt 25" \
  -ex "thread apply all bt 12" \
  -ex "detach" -ex "quit" \
  2>&1 | tee "/tmp/gdb-breakpoints-${LOGIC}.txt"

echo "=== srcds tail ==="
tail -30 /tmp/gdb-smoke-srcds.log
echo "=== SM logs ==="
cat cstrike/addons/sourcemod/logs/L*.log 2>/dev/null || echo "(none)"
