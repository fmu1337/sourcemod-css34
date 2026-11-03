#!/usr/bin/env bash
# T4.5 MySQL/MariaDB probe, inside a smoke image with SourceMod installed and the
# server of testing/scripts/mysql-tls-server.sh reachable as css34-mariadb.
#
# Runs only when the installed dbi.mysql.ext embeds our static OpenSSL (sm13's
# MariaDB Connector/C; sm12's MySQL 5.6 client bundles yaSSL and is skipped):
#   1. css34_mysql_tls_probe (built from the extension's own static archives,
#      packages/test-plugins): verified TLS to a REQUIRE SSL account succeeds,
#      client and server both see the session encrypted, the TLS library is the
#      OpenSSL the build used; SourceMod's options (no TLS) are refused, and so
#      is TLS against an unrelated CA.
#   2. css34_mysql_probe.sp in srcds: a dbi.mysql.ext connect + query round trip,
#      so the OpenSSL inside the shipped extension runs (password hashing) in
#      the game server process. SourceMod 1.13's driver never requests TLS
#      (MyDriver.cpp turns peer verification off and sets no TLS option), so
#      this session is plaintext; its Ssl_cipher is reported, not required.
#
#   SERVER_DIR=... MYSQL_TLS_PROBE=packages/test-plugins/css34_mysql_tls_probe \
#   MYSQL_TLS_CERTS=<mysql-tls-server.sh DIR> mysql-tls-test.sh
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SERVER_DIR="${SERVER_DIR:?SERVER_DIR is required}"
MYSQL_TLS_CERTS="${MYSQL_TLS_CERTS:?MYSQL_TLS_CERTS is required}"
sm="${SERVER_DIR}/cstrike/addons/sourcemod"
ext="${sm}/extensions/dbi.mysql.ext.so"
session="${MYSQL_TLS_LOG:-${SERVER_DIR}/mysql-tls.log}"
export MYSQL_TLS_HOST="${MYSQL_TLS_HOST:-css34-mariadb}"
export MYSQL_TLS_PORT="${MYSQL_TLS_PORT:-3306}"
export MYSQL_TLS_CA="${MYSQL_TLS_CERTS}/ca.pem"
export MYSQL_TLS_WRONG_CA="${MYSQL_TLS_CERTS}/wrong-ca.pem"
fail=0

die() { echo "FAIL: $*" >&2; exit 1; }

[[ -f "${ext}" ]] || die "${ext} missing: install the SourceMod package first"
if ! grep -aq 'OpenSSL [0-9]' "${ext}"; then
  echo "SKIP: dbi.mysql.ext links no OpenSSL of ours (MySQL 5.6 client with bundled yaSSL)"
  exit 0
fi
MYSQL_TLS_PROBE="${MYSQL_TLS_PROBE:?MYSQL_TLS_PROBE is required: dbi.mysql.ext links OpenSSL}"
[[ -x "${MYSQL_TLS_PROBE}" ]] || die "TLS probe not found or not executable: ${MYSQL_TLS_PROBE}"
[[ -f "${MYSQL_TLS_CA}" && -f "${MYSQL_TLS_WRONG_CA}" ]] || die "certificates missing in ${MYSQL_TLS_CERTS}"
echo "==> dbi.mysql.ext embeds $(grep -ao 'OpenSSL [0-9][0-9.]* [0-9]* [A-Z][a-z]* [0-9]*' "${ext}" | head -n1)"

probe() { # mode user password
  local out rc=0
  out="$(MYSQL_TLS_USER="$2" MYSQL_TLS_PASS="$3" "${MYSQL_TLS_PROBE}" "$1" 2>&1)" || rc=$?
  printf '%s\n' "${out}"
  if [[ "${rc}" -ne 0 ]]; then
    echo "FAIL: css34_mysql_tls_probe $1 (exit ${rc})" >&2
    fail=1
  fi
}

echo "==> TLS through the extension's MariaDB Connector/C + OpenSSL archives"
probe tls css34_tls css34-tls-probe
probe plain css34_tls css34-tls-probe
probe wrong-ca css34_tls css34-tls-probe

echo "==> dbi.mysql.ext round trip in srcds"
spcomp="${sm}/scripting/spcomp"
[[ -x "${spcomp}" ]] || chmod +x "${spcomp}" 2>/dev/null || true
[[ -x "${spcomp}" ]] || die "spcomp missing in ${sm}/scripting"
"${spcomp}" -i"${sm}/scripting/include" -o"${sm}/plugins/css34_mysql_probe.smx" \
  "${root}/testing/plugins/css34_mysql_probe/css34_mysql_probe.sp" >"${session}.spcomp" 2>&1 ||
  { cat "${session}.spcomp"; die "spcomp failed for css34_mysql_probe.sp"; }

databases="${sm}/configs/databases.cfg"
cp -p "${databases}" "${databases}.mysql-tls"
cleanup() {
  [[ -n "${srcds_pid:-}" ]] && kill "${srcds_pid}" 2>/dev/null || true
  mv -f "${databases}.mysql-tls" "${databases}"
  rm -f "${sm}/plugins/css34_mysql_probe.smx"
}
trap cleanup EXIT
# Add an entry before the closing brace of "Databases".
awk -v host="${MYSQL_TLS_HOST}" -v port="${MYSQL_TLS_PORT}" '
  { lines[NR] = $0 }
  END {
    last = 0
    for (i = NR; i > 0; i--) if (lines[i] ~ /^[[:space:]]*}[[:space:]]*$/) { last = i; break }
    if (!last) exit 1
    for (i = 1; i < last; i++) print lines[i]
    print "\t\"css34_mysql_probe\""
    print "\t{"
    print "\t\t\"driver\"\t\t\"mysql\""
    print "\t\t\"host\"\t\t\"" host "\""
    print "\t\t\"port\"\t\t\"" port "\""
    print "\t\t\"database\"\t\t\"\""
    print "\t\t\"user\"\t\t\"css34_plain\""
    print "\t\t\"pass\"\t\t\"css34-plain-probe\""
    print "\t}"
    for (i = last; i <= NR; i++) print lines[i]
  }' "${databases}.mysql-tls" >"${databases}" || die "cannot add the probe entry to ${databases}"

rcon_pw="css34mysql"
rcon() { python3 "${root}/testing/scripts/rcon.py" 127.0.0.1 "${rcon_pw}" "$@"; }
(
  cd "${SERVER_DIR}"
  export LD_LIBRARY_PATH=".:bin:${LD_LIBRARY_PATH:-}"
  exec "${SRCDS_BINARY:-./srcds_i686}" -game cstrike -console -nohltv -nomaster -localcser -tickrate 66 \
    -ip 127.0.0.1 -port 27015 +ip 127.0.0.1 +sv_lan 1 +maxplayers 4 +rcon_password "${rcon_pw}" +map de_dust2
) </dev/null >"${session}.console" 2>&1 &
srcds_pid=$!
deadline=$((SECONDS + ${MYSQL_TLS_TIMEOUT:-120}))
until rcon "echo css34-mysql-up" 2>/dev/null | grep -q css34-mysql-up; do
  kill -0 "${srcds_pid}" 2>/dev/null || { tail -n 30 "${session}.console"; die "srcds exited during boot"; }
  (( SECONDS < deadline )) || { tail -n 30 "${session}.console"; die "srcds did not answer RCON"; }
  sleep 3
done
{
  rcon "sm plugins list" "css34_mysql_probe css34_mysql_probe" "sleep 1" "sm exts list"
  rcon "quit" || true
} >"${session}" 2>&1
sleep 3
cat "${session}.console" >>"${session}"
result="$(grep -h '\[css34_mysql_probe\] ' "${sm}"/logs/L*.log 2>/dev/null | tail -n1 || true)"
echo "${result:-"(no [css34_mysql_probe] line in ${sm}/logs)"}"
if [[ "${result}" =~ \[css34_mysql_probe\]\ ok\ driver=mysql\ result=css34-42\ server=[^\ ]*MariaDB ]]; then
  echo "OK: dbi.mysql.ext connected and queried MariaDB from srcds"
else
  grep -E 'css34_mysql_probe|MySQL|dbi\.mysql' "${session}" | tail -n 20 >&2 || true
  echo "FAIL: dbi.mysql.ext round trip" >&2
  fail=1
fi

[[ "${fail}" -eq 0 ]] && echo "MySQL/MariaDB TLS probe PASSED"
exit "${fail}"
