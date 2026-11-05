#!/usr/bin/env bash
# Third-party Socket extension (builder/third-party/socket.sh) on a running srcds:
#   - `sm exts load socket.ext` loads it and `sm exts list` reports "Socket (3.0.2)"
#   - css34_socket_probe (testing/plugins/css34_socket_probe.sp, legacy natives
#     SocketCreate / SocketSetArg / SocketConnect / SocketSend) sends A2S_INFO over
#     UDP to 127.0.0.1:<port> and gets the server's reply, type 0x49.
#
# Usage: SERVER_DIR=<srcds root with MM + SM installed> \
#        SOCKET_PACKAGE=<packages/third-party/socket-*.tar.gz> \
#        SOCKET_PROBE=<packages/test-plugins/css34_socket_probe.smx> socket-ext-test.sh
#
# The archive and the probe are removed from the server tree afterwards.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SERVER_DIR="${SERVER_DIR:?SERVER_DIR is required}"
SOCKET_PACKAGE="${SOCKET_PACKAGE:?SOCKET_PACKAGE is required}"
SOCKET_PROBE="${SOCKET_PROBE:?SOCKET_PROBE is required}"
PORT="${SOCKET_TEST_PORT:-27015}"
# shellcheck source=../../builder/third-party/socket.env
source "${root}/builder/third-party/socket.env"
cstrike="${SERVER_DIR}/cstrike"
sm="${cstrike}/addons/sourcemod"
session="${SOCKET_TEST_LOG:-${SERVER_DIR}/socket-ext.log}"
results="${sm}/logs/css34_socket_probe.log"
fail=0

die() { echo "FAIL: $*" >&2; exit 1; }
check() { # pattern file label
  if grep -Eq -- "$1" "$2"; then
    echo "OK: $3"
  else
    echo "FAIL: $3 (no line matching: $1)" >&2
    fail=1
  fi
}

[[ -f "${SOCKET_PACKAGE}" ]] || die "Socket archive not found: ${SOCKET_PACKAGE}"
[[ -f "${SOCKET_PROBE}" ]] || die "probe plugin not found: ${SOCKET_PROBE}"
[[ -d "${sm}/extensions" ]] || die "${sm} has no extensions/: install SourceMod first"

mapfile -t installed < <(tar -tzf "${SOCKET_PACKAGE}" | grep -v '/$')
tar -xzf "${SOCKET_PACKAGE}" -C "${cstrike}"
# disabled/: SourceMod does not load it at boot, so the extension is loaded by
# `sm exts load` first, not as the plugin's dependency.
mkdir -p "${sm}/plugins/disabled"
cp -f "${SOCKET_PROBE}" "${sm}/plugins/disabled/css34_socket_probe.smx"
rm -f "${results}"
srcds_pid=""
cleanup() {
  [[ -z "${srcds_pid}" ]] || kill "${srcds_pid}" 2>/dev/null || true
  local f
  for f in "${installed[@]}"; do rm -f "${cstrike:?}/${f}"; done
  rm -f "${sm}/plugins/disabled/css34_socket_probe.smx"
}
trap cleanup EXIT

echo "==> Booting srcds for the Socket extension test (UDP ${PORT})"
rcon_pw="css34socket"
rcon() { python3 "${root}/testing/scripts/rcon.py" 127.0.0.1 "${rcon_pw}" "$@"; }
(
  cd "${SERVER_DIR}"
  export LD_LIBRARY_PATH=".:bin:${LD_LIBRARY_PATH:-}"
  exec "${SRCDS_BINARY:-./srcds_i686}" -game cstrike -console -nohltv -nomaster -localcser -tickrate 66 \
    -ip 127.0.0.1 -port "${PORT}" +ip 127.0.0.1 +sv_lan 1 +maxplayers 4 \
    +rcon_password "${rcon_pw}" +map de_dust2
) </dev/null >"${session}.console" 2>&1 &
srcds_pid=$!
deadline=$((SECONDS + ${SOCKET_TEST_TIMEOUT:-120}))
until rcon "echo css34-socket-up" 2>/dev/null | grep -q css34-socket-up; do
  kill -0 "${srcds_pid}" 2>/dev/null || { tail -n 30 "${session}.console"; die "srcds exited during boot"; }
  (( SECONDS < deadline )) || { tail -n 30 "${session}.console"; die "srcds did not answer RCON"; }
  sleep 3
done
{
  rcon "sm exts load socket.ext"
  rcon "sm exts list"
  rcon "sm plugins load disabled/css34_socket_probe"
  rcon "css34_socket_probe 127.0.0.1 ${PORT}"
} >"${session}" 2>&1
# The reply arrives in a later frame: wait for the probe's verdict.
probe_deadline=$((SECONDS + 20))
until grep -qE '^(PASS|FAIL)' "${results}" 2>/dev/null || (( SECONDS >= probe_deadline )); do
  sleep 1
done
{
  rcon "sm plugins list" "sm exts list"
  # Unloading stops the extension's asio thread; srcds must keep running.
  rcon "sm plugins unload disabled/css34_socket_probe"
  ext_id="$(rcon "sm exts list" | sed -nE 's/^\[0*([0-9]+)\] Socket \(.*/\1/p' | head -n1)"
  if [[ -n "${ext_id}" ]]; then
    rcon "sm exts unload ${ext_id}"
  fi
  sleep 2
  rcon "echo css34-socket-alive"
  # srcds v34 also exits with SIGSEGV on quit without this extension.
  rcon "quit" || true
} >>"${session}" 2>&1
sleep 3
cat "${session}.console" >>"${session}"

echo "==== socket-ext session (SourceMod lines) ===="
grep -E '\[SM\]|Socket|socket|css34_socket_probe' "${session}" | tail -n 40 || true
echo "==== ${results##*/} ===="
cat "${results}" 2>/dev/null || echo "(missing)"

check '\[SM\] Loaded extension socket\.ext\.so successfully' "${session}" "sm exts load socket.ext"
check "\\] Socket \\(${SOCKET_VERSION//./\\.}\\)" "${session}" "sm exts list reports Socket (${SOCKET_VERSION})"
check 'Loaded plugin disabled/css34_socket_probe\.smx successfully' "${session}" "the probe plugin loaded"
check '\[SM\] Extension socket\.ext\.so is now unloaded' "${session}" "sm exts unload socket.ext"
check '^css34-socket-alive' "${session}" "srcds still answers after the unload"
refused='socket\.ext\.so.*(failed to load|too (old|new))|Extension version is too (old|new)'
if grep -Eq "${refused}" "${session}"; then
  echo "FAIL: SourceMod refused the extension" >&2
  grep -E "${refused}" "${session}" | head -5 >&2
  fail=1
fi
if [[ -f "${results}" ]]; then
  check '^PASS reply type 0x49 ' "${results}" "A2S_INFO over socket.ext got a 0x49 reply"
  check ' hostname_match=1 ' "${results}" "the reply names this server (hostname)"
  if grep -q '^FAIL' "${results}"; then
    echo "FAIL: probe: $(grep '^FAIL' "${results}" | head -n1)" >&2
    fail=1
  fi
else
  echo "FAIL: the probe wrote no ${results##*/}" >&2
  fail=1
fi

[[ "${fail}" -eq 0 ]] && echo "Socket extension test PASSED"
exit "${fail}"
