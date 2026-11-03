#!/usr/bin/env bash
# T4.5 MySQL/MariaDB TLS probe, inside a smoke image with SourceMod installed
# and the servers of testing/scripts/mysql-tls-server.sh reachable as
# css34-mariadb (MariaDB 11.8), css34-mysql (MySQL 8.4, caching_sha2_password)
# and css34-mysql-notls (the same without TLS).
#
# Runs only when the installed dbi.mysql.ext embeds our static OpenSSL (sm13's
# MariaDB Connector/C; sm12's MySQL 5.6 client bundles yaSSL and is skipped):
#   1. css34_mysql_tls_probe (built from the extension's own static archives,
#      packages/test-plugins) against MariaDB: verified TLS to a REQUIRE SSL
#      account succeeds, client and server both see the session encrypted, the
#      TLS library is the OpenSSL the build used; a plaintext login is refused,
#      and so is TLS against an unrelated CA.
#   2. css34_mysql_probe.sp in srcds: dbi.mysql.ext itself, configured through
#      databases.cfg (ssl_mode / ssl_ca, sm13 patch 0009), SQL_ConnectCustom and
#      a threaded Database.Connect. Every connection that must be encrypted is
#      checked on the server's side (Ssl_version TLSv1.2+, Ssl_cipher), and so
#      are the refusals: ssl_mode disabled to a REQUIRE SSL account, a wrong CA,
#      verify_identity by IP address (the certificate names hosts only), an
#      unknown ssl_mode, a verify mode without ssl_ca, required and verify modes
#      against a server without TLS (while preferred falls back to plaintext).
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

echo "==> dbi.mysql.ext in srcds: ssl_mode / ssl_ca against MySQL 8.4 and MariaDB"
spcomp="${sm}/scripting/spcomp"
[[ -x "${spcomp}" ]] || chmod +x "${spcomp}" 2>/dev/null || true
[[ -x "${spcomp}" ]] || die "spcomp missing in ${sm}/scripting"
"${spcomp}" -i"${sm}/scripting/include" -o"${sm}/plugins/css34_mysql_probe.smx" \
  "${root}/testing/plugins/css34_mysql_probe/css34_mysql_probe.sp" >"${session}.spcomp" 2>&1 ||
  { cat "${session}.spcomp"; die "spcomp failed for css34_mysql_probe.sp"; }

mysql_host="${MYSQL_TLS_MYSQL_HOST:-css34-mysql}"
notls_host="${MYSQL_TLS_NOTLS_HOST:-css34-mysql-notls}"
# The certificate names hosts only: by address, verify_ca must pass and
# verify_identity must not.
mysql_ip="$(python3 -c 'import socket, sys; print(socket.gethostbyname(sys.argv[1]))' "${mysql_host}")" ||
  die "cannot resolve ${mysql_host}"
[[ "${mysql_ip}" =~ ^[0-9]+(\.[0-9]+){3}$ ]] || die "${mysql_host} resolved to '${mysql_ip}'"
# ssl_ca relative to addons/sourcemod/, as an admin would write it.
cadir="${sm}/configs/css34-mysql-probe"
ca="configs/css34-mysql-probe/ca.pem"
wrong_ca="configs/css34-mysql-probe/wrong-ca.pem"
databases="${sm}/configs/databases.cfg"
cp -p "${databases}" "${databases}.mysql-tls"
cleanup() {
  [[ -n "${srcds_pid:-}" ]] && kill "${srcds_pid}" 2>/dev/null || true
  mv -f "${databases}.mysql-tls" "${databases}"
  rm -rf "${cadir}"
  rm -f "${sm}/plugins/css34_mysql_probe.smx"
}
trap cleanup EXIT
mkdir -p "${cadir}"
cp "${MYSQL_TLS_CA}" "${cadir}/ca.pem"
cp "${MYSQL_TLS_WRONG_CA}" "${cadir}/wrong-ca.pem"

# name host user [key value]... -> one databases.cfg entry
entries=""
entry() {
  local name="$1" host="$2" user="$3" pass
  shift 3
  if [[ "${user}" == css34_tls ]]; then pass=css34-tls-probe; else pass=css34-plain-probe; fi
  entries+=$'\t"'"${name}"$'"\n\t{\n\t\t"driver"\t\t"mysql"\n'
  entries+=$'\t\t"host"\t\t"'"${host}"$'"\n\t\t"port"\t\t"'"${MYSQL_TLS_PORT}"$'"\n'
  entries+=$'\t\t"database"\t\t""\n\t\t"user"\t\t"'"${user}"$'"\n\t\t"pass"\t\t"'"${pass}"$'"\n'
  while (( $# >= 2 )); do
    entries+=$'\t\t"'"$1"$'"\t\t"'"$2"$'"\n'
    shift 2
  done
  entries+=$'\t}\n'
}
entry css34_my_identity "${mysql_host}" css34_tls ssl_mode verify_identity ssl_ca "${ca}"
entry css34_my_ca_ip "${mysql_ip}" css34_tls ssl_mode VERIFY_CA ssl_ca "${ca}"
entry css34_my_identity_ip "${mysql_ip}" css34_tls ssl_mode verify_identity ssl_ca "${ca}"
entry css34_my_required "${mysql_host}" css34_tls ssl_mode required
entry css34_my_default "${mysql_host}" css34_plain
entry css34_my_disabled_plain "${mysql_host}" css34_plain ssl_mode disabled
entry css34_my_disabled "${mysql_host}" css34_tls ssl_mode disabled
entry css34_my_wrong_ca "${mysql_host}" css34_tls ssl_mode verify_identity ssl_ca "${wrong_ca}"
entry css34_my_bad_mode "${mysql_host}" css34_tls ssl_mode verify_full ssl_ca "${ca}"
entry css34_my_no_ca "${mysql_host}" css34_tls ssl_mode verify_ca
entry css34_notls_default "${notls_host}" css34_plain
entry css34_notls_required "${notls_host}" css34_plain ssl_mode required
entry css34_notls_verify "${notls_host}" css34_plain ssl_mode verify_ca ssl_ca "${ca}"
entry css34_mdb_default "${MYSQL_TLS_HOST}" css34_plain
entry css34_mdb_identity "${MYSQL_TLS_HOST}" css34_tls ssl_mode verify_identity ssl_ca "${ca}"
# Add the entries before the closing brace of "Databases".
ENTRIES="${entries}" awk '
  { lines[NR] = $0 }
  END {
    last = 0
    for (i = NR; i > 0; i--) if (lines[i] ~ /^[[:space:]]*}[[:space:]]*$/) { last = i; break }
    if (!last) exit 1
    for (i = 1; i < last; i++) print lines[i]
    printf "%s", ENVIRON["ENTRIES"]
    for (i = last; i <= NR; i++) print lines[i]
  }' "${databases}.mysql-tls" >"${databases}" || die "cannot add the probe entries to ${databases}"

# label | server command | expected result (regex after "[css34_mysql_probe] <label> ")
tls="ok driver=mysql result=css34-42 server=8\.4\.[0-9]+ charset=utf8mb4 ssl_version='TLSv1\.[23]' ssl_cipher='[^']+'"
mdb_tls="ok driver=mysql result=css34-42 server=[^ ]*MariaDB[^ ]* charset=utf8mb4 ssl_version='TLSv1\.[23]' ssl_cipher='[^']+'"
cases=(
  "identity|css34_mysql_probe identity css34_my_identity|${tls}"
  "ca_ip|css34_mysql_probe ca_ip css34_my_ca_ip|${tls}"
  "identity_ip|css34_mysql_probe identity_ip css34_my_identity_ip|FAIL connect css34_my_identity_ip: \[2026\]: .*[Hh]ostname"
  "required|css34_mysql_probe required css34_my_required|${tls}"
  "default|css34_mysql_probe default css34_my_default|${tls}"
  "disabled_plain|css34_mysql_probe disabled_plain css34_my_disabled_plain|ok driver=mysql result=css34-42 server=8\.4\.[0-9]+ charset=utf8mb4 ssl_version='' ssl_cipher=''"
  "disabled|css34_mysql_probe disabled css34_my_disabled|FAIL connect css34_my_disabled: \[1045\]: Access denied"
  "wrong_ca|css34_mysql_probe wrong_ca css34_my_wrong_ca|FAIL connect css34_my_wrong_ca: \[2026\]: "
  "bad_mode|css34_mysql_probe bad_mode css34_my_bad_mode|FAIL connect css34_my_bad_mode: \[0\]: ssl_mode \"verify_full\" is not one of disabled, preferred, required, verify_ca, verify_identity"
  "no_ca|css34_mysql_probe no_ca css34_my_no_ca|FAIL connect css34_my_no_ca: \[0\]: ssl_mode verify_ca needs ssl_ca"
  "async|css34_mysql_probe_async async css34_my_identity|${tls}"
  # A persistent plaintext session must not be handed to a TLS configuration
  # with the same host, user, password, database and port.
  "persist_plain|css34_mysql_probe_persistent persist_plain css34_my_disabled_plain|ok driver=mysql result=css34-42 server=8\.4\.[0-9]+ charset=utf8mb4 ssl_version='' ssl_cipher=''"
  "persist_tls|css34_mysql_probe_persistent persist_tls css34_my_default|${tls}"
  "custom|css34_mysql_probe_custom custom ${mysql_host} css34_tls css34-tls-probe verify_identity \"${ca}\"|${tls}"
  "custom_bad|css34_mysql_probe_custom custom_bad ${mysql_host} css34_tls css34-tls-probe sslmode_typo|FAIL connect \(custom\): \[0\]: ssl_mode \"sslmode_typo\" is not one of"
  "notls_default|css34_mysql_probe notls_default css34_notls_default|ok driver=mysql result=css34-42 server=8\.4\.[0-9]+ charset=utf8mb4 ssl_version='' ssl_cipher=''"
  "notls_required|css34_mysql_probe notls_required css34_notls_required|FAIL connect css34_notls_required: \[2026\]: .*SSL is required, but the server does not support it"
  "notls_verify|css34_mysql_probe notls_verify css34_notls_verify|FAIL connect css34_notls_verify: \[2026\]: .*SSL is required, but the server does not support it"
  "mdb_default|css34_mysql_probe mdb_default css34_mdb_default|${mdb_tls}"
  "mdb_identity|css34_mysql_probe mdb_identity css34_mdb_identity|${mdb_tls}"
)
commands=()
for c in "${cases[@]}"; do
  IFS='|' read -r _ command _ <<<"${c}"
  commands+=("${command}")
done

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
  # The threaded connect answers on a later frame.
  rcon "sm plugins list" "${commands[@]}" "sleep 3" "sm exts list"
  rcon "quit" || true
} >"${session}" 2>&1
sleep 3
cat "${session}.console" >>"${session}"
passed=0
for c in "${cases[@]}"; do
  IFS='|' read -r label _ expect <<<"${c}"
  result="$(grep -h "\[css34_mysql_probe\] ${label} " "${sm}"/logs/L*.log 2>/dev/null | tail -n1 || true)"
  result="${result#*\[css34_mysql_probe\] ${label} }"
  if [[ -n "${result}" && "${result}" =~ ^${expect} ]]; then
    echo "OK   ${label}: ${result}"
    passed=$((passed + 1))
  else
    echo "FAIL ${label}: ${result:-"(no result line in ${sm}/logs)"}" >&2
    echo "     expected: ${expect}" >&2
    fail=1
  fi
done
echo "==> ${passed}/${#cases[@]} srcds cases as expected"
if [[ "${fail}" -ne 0 ]]; then
  grep -E 'css34_mysql_probe|MySQL|MYSQL|dbi\.mysql' "${session}" | tail -n 40 >&2 || true
fi

[[ "${fail}" -eq 0 ]] && echo "MySQL/MariaDB TLS probe PASSED"
exit "${fail}"
