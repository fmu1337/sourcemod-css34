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
SM_PLUGINS_DIR="${SERVER_DIR}/cstrike/addons/sourcemod/plugins"
SM_EXTENSIONS_DIR="${SERVER_DIR}/cstrike/addons/sourcemod/extensions"
SRCDS_BINARY="${SRCDS_BINARY:-./srcds_i686}"
SMOKE_VERBOSE="${SMOKE_VERBOSE:-0}"
SMOKE_CONDEBUG="${SMOKE_CONDEBUG:-1}"
CSS34_CI="${CSS34_CI:-0}"
ENGINE_CONSOLE_LOG="${SERVER_DIR}/cstrike/console.log"

# Expected versions. Always resolve pins so build-number checks have MM_REV
# even when CI passes only the short product version (1.12.0 / 1.10.7).
# versions.env defaults CSS34_LINE to sm13-latest. Smoke containers often have
# the pinned commits but not the line name, and sm11's Metamod rev is not 1226.
RESOLVED_SM_REV=""
RESOLVED_MM_REV=""
RESOLVED_MM_MODE=""
resolve_line="${CSS34_LINE:-}"
if [[ -z "$resolve_line" && -f "${ROOT}/builder/versions.env" ]]; then
  # shellcheck disable=SC1091
  eval "$(grep -E '^(SM_|MM_)[A-Z0-9_]+=' "${ROOT}/builder/versions.env")"
  case "${MM_COMMIT_EXPECT:-}" in
    "${MM_110_COMMIT:-}") resolve_line=sm11-oldstable ;;
    "${MM_112_COMMIT:-}")
      case "${SM_COMMIT_EXPECT:-}" in
        "${SM_LATEST_COMMIT:-}") resolve_line=sm12-latest ;;
        "${SM_DEV_COMMIT:-}") resolve_line=sm13-dev ;;
        *) resolve_line=sm13-latest ;;
      esac
      ;;
    *) resolve_line=sm13-latest ;;
  esac
fi
resolve_line="${resolve_line:-sm13-latest}"
if [[ -f "${ROOT}/builder/resolve-version.sh" ]]; then
  eval "$(
    CSS34_LINE="${resolve_line}" bash -c "
      source '${ROOT}/builder/resolve-version.sh' >/dev/null 2>&1
      echo \"RESOLVED_SM_COMMIT='\${SOURCEMOD_BUILD_COMMIT:-\$SOURCEMOD_COMMIT}'\"
      echo \"RESOLVED_SM_REV='\${SOURCEMOD_GIT_REV}'\"
      echo \"RESOLVED_SM_MAJOR='\${SOURCEMOD_MAJOR}'\"
      echo \"RESOLVED_MM_COMMIT='\${MMS_COMMIT}'\"
      echo \"RESOLVED_MM_REV='\${MMS_GIT_REV}'\"
      echo \"RESOLVED_MM_MODE='\${MMS_MODE}'\"
    "
  )"
fi
if [[ -n "${RESOLVED_SM_REV:-}" ]]; then
  SM_VERSION_EXPECT="${SM_VERSION_EXPECT:-1.${RESOLVED_SM_MAJOR}.0.${RESOLVED_SM_REV}}"
  SM_COMMIT_EXPECT="${SM_COMMIT_EXPECT:-${RESOLVED_SM_COMMIT}}"
  MM_COMMIT_EXPECT="${MM_COMMIT_EXPECT:-${RESOLVED_MM_COMMIT}}"
  if [[ -z "${MM_VERSION_EXPECT:-}" ]]; then
    case "${RESOLVED_MM_MODE:-}" in
      1.10) MM_VERSION_EXPECT="1.10.7" ;;
      1.11) MM_VERSION_EXPECT="1.11.0" ;;
      1.12) MM_VERSION_EXPECT="1.12.0" ;;
      2.0)  MM_VERSION_EXPECT="2.0.0" ;;
      *)    MM_VERSION_EXPECT="1.12.0" ;;
    esac
  fi
fi

MM_VERSION_EXPECT="${MM_VERSION_EXPECT:-1.10.7}"
SM_VERSION_EXPECT="${SM_VERSION_EXPECT:-1.11.0.6970}"
MM_COMMIT_EXPECT="${MM_COMMIT_EXPECT:-80e8ff0be3b62386bbd6f937e97b819ef8be6dd2}"
SM_COMMIT_EXPECT="${SM_COMMIT_EXPECT:-f53cb134ef83b580c83e1f4bf35f60d11c4571dd}"
MM_REV_EXPECT="${MM_REV_EXPECT:-${RESOLVED_MM_REV}}"
# Packaging repo commit (CSS34 pack line). Empty skips the check.
CSS34_PACK_COMMIT_EXPECT="${CSS34_PACK_COMMIT_EXPECT:-}"
# Upstream prints the abbreviated commit. Seven characters is git's minimum.
MM_SHA_PREFIX="${MM_COMMIT_EXPECT:0:7}"
SM_SHA_PREFIX="${SM_COMMIT_EXPECT:0:7}"
# 1.12.0-dev+1226 / 1.10.7-dev+976. CI often sets only the product prefix.
if [[ -n "${MM_REV_EXPECT}" && "${MM_VERSION_EXPECT}" != *"+${MM_REV_EXPECT}" ]]; then
  META_VERSION_NEEDLE="${MM_VERSION_EXPECT}-dev+${MM_REV_EXPECT}"
else
  META_VERSION_NEEDLE="${MM_VERSION_EXPECT}"
fi
META_BUILD_ID_NEEDLE="Build ID: ${MM_REV_EXPECT}:${MM_SHA_PREFIX}"
SM_VERSION_NEEDLE="SourceMod Version: ${SM_VERSION_EXPECT}"

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

echo "Starting srcds (binary=${SRCDS_BINARY}, map=${MAP}, port=${PORT}, args=-nomaster -localcser -tickrate 66, timeout=${TIMEOUT_SECS}s)"
echo "Smoke logging: SMOKE_VERBOSE=${SMOKE_VERBOSE} SMOKE_CONDEBUG=${SMOKE_CONDEBUG}"
if [[ -f "${SERVER_DIR}/cstrike/mapcycle.txt" ]]; then
  echo "----- mapcycle.txt -----"
  cat "${SERVER_DIR}/cstrike/mapcycle.txt"
fi
ls -la "${SERVER_DIR}/cstrike/maps"/*.bsp 2>/dev/null || echo "(no .bsp maps found)"

export SERVER_DIR MAP PORT SRCDS_BINARY CONSOLE_PROBE_LOG
export CONSOLE_PROBE_TIMEOUT="${TIMEOUT_SECS}"
export SMOKE_VERBOSE SMOKE_CONDEBUG
export META_VERSION_NEEDLE META_BUILD_ID_NEEDLE SM_VERSION_NEEDLE
rm -f "${ENGINE_CONSOLE_LOG}"
probe_rc=0
/usr/bin/expect "${ROOT}/testing/scripts/console-probe.exp" >"${LOG_FILE}" 2>&1 || probe_rc=$?
if [[ "${probe_rc}" -ne 0 ]]; then
  echo "Console probe failed (see ${LOG_FILE})" >&2
  echo "----- smoke.log (last 120) -----" >&2
  tail -n 120 "${LOG_FILE}" >&2 || true
  echo "----- console-probe.log (last 120) -----" >&2
  tail -n 120 "${CONSOLE_PROBE_LOG}" >&2 || true
  if [[ -f "${ENGINE_CONSOLE_LOG}" ]]; then
    echo "----- cstrike/console.log (last 120) -----" >&2
    tail -n 120 "${ENGINE_CONSOLE_LOG}" >&2 || true
  fi
  if compgen -G "${SM_LOG_DIR}/L*.log" >/dev/null; then
    echo "----- SourceMod logs on failure -----" >&2
    cat "${SM_LOG_DIR}"/L*.log >&2 || true
  fi
fi

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
if [[ "${probe_rc}" -ne 0 ]]; then
  fail=1
fi
require_grep() {
  local file="$1" pat="$2" label="$3"
  if [[ -f "${file}" ]] && grep -Eiq -- "${pat}" "${file}"; then
    echo "OK: ${label}"
  else
    echo "FAIL: ${label} (/${pat}/ in ${file})" >&2
    fail=1
  fi
}

require_fixed() {
  local file="$1" pat="$2" label="$3"
  if [[ -f "${file}" ]] && grep -Fq -- "${pat}" "${file}"; then
    echo "OK: ${label}"
  else
    echo "FAIL: ${label} (fixed '${pat}' in ${file})" >&2
    fail=1
  fi
}

require_grep "${CONSOLE_PROBE_LOG}" 'Started map "'"${MAP}"'"' "engine started map (${MAP})"
require_grep "${CONSOLE_PROBE_LOG}" 'hostname|# [0-9]+' "status command output"
require_grep "${CONSOLE_PROBE_LOG}" 'Protocol version|version' "version command output"
require_grep "${CONSOLE_PROBE_LOG}" 'Metamod|metamod|MM:S' "meta version command output"
require_grep "${CONSOLE_PROBE_LOG}" 'SourceMod|SM' "sm version command output"

require_fixed "${CONSOLE_PROBE_LOG}" "${META_VERSION_NEEDLE}" \
  "meta version ${META_VERSION_NEEDLE}"
require_fixed "${CONSOLE_PROBE_LOG}" "${META_BUILD_ID_NEEDLE}" \
  "meta ${META_BUILD_ID_NEEDLE}"
require_fixed "${CONSOLE_PROBE_LOG}" "${SM_VERSION_NEEDLE}" \
  "sm version ${SM_VERSION_EXPECT}"

# Upstream prints the abbreviated commit in Built from. The prefix is the
# pinned SHA, so a longer abbreviation still matches.
require_fixed "${CONSOLE_PROBE_LOG}" \
  "metamod-source/commit/${MM_SHA_PREFIX}" \
  "meta Built from commit ${MM_SHA_PREFIX}"
require_fixed "${CONSOLE_PROBE_LOG}" \
  "sourcemod/commit/${SM_SHA_PREFIX}" \
  "sm Built from commit ${SM_SHA_PREFIX}"
if [[ -n "${CSS34_PACK_COMMIT_EXPECT}" ]]; then
  require_grep "${CONSOLE_PROBE_LOG}" \
    "sourcemod-css34/commit/${CSS34_PACK_COMMIT_EXPECT}" \
    "CSS34 pack commit ${CSS34_PACK_COMMIT_EXPECT}"
else
  require_grep "${CONSOLE_PROBE_LOG}" \
    'sourcemod-css34/commit/[0-9a-f]{7,40}' \
    "CSS34 pack commit present in version output"
fi

print_console_section() {
  local start_pat="$1" end_pat="$2" label="$3"
  echo "----- ${label} -----"
  if [[ ! -f "${CONSOLE_PROBE_LOG}" ]]; then
    echo "(missing ${CONSOLE_PROBE_LOG})"
    return 0
  fi
  awk -v start="${start_pat}" -v end="${end_pat}" '
    $0 ~ start { show=1 }
    show { print }
    show && $0 ~ end && $0 !~ start { exit }
  ' "${CONSOLE_PROBE_LOG}" || true
}

print_console_section 'sm exts list' 'sm plugins list' 'sm exts list (console)'
print_console_section 'sm plugins list' '^quit$' 'sm plugins list (console)'

# Extensions must load — stock plugins depend on sdktools/sdkhooks/game.cstrike/etc.
if grep -Eiq '\[SM\] No extensions are loaded\.' "${CONSOLE_PROBE_LOG}"; then
  echo "FAIL: sm exts list reports no loaded extensions" >&2
  fail=1
else
  require_grep "${CONSOLE_PROBE_LOG}" '\[SM\] Displaying [0-9]+ extensions:' \
    "sm exts list header (Displaying N extensions)"
fi

ext_header_count="$(
  grep -Eo '\[SM\] Displaying [0-9]+ extensions:' "${CONSOLE_PROBE_LOG}" 2>/dev/null \
    | grep -Eo '[0-9]+' \
    | tail -n1 || true
)"
listed_exts="$(
  sed -n '/sm exts list/,/sm plugins list/p' "${CONSOLE_PROBE_LOG}" 2>/dev/null \
    | grep -Ec '^\[[0-9]+\]' || true
)"
echo "Extensions: header=${ext_header_count:-?} listed_lines=${listed_exts:-0}"
if [[ -n "${ext_header_count}" && "${listed_exts}" -ne "${ext_header_count}" ]]; then
  echo "FAIL: sm exts list header says ${ext_header_count} but saw ${listed_exts} extension line(s)" >&2
  fail=1
else
  echo "OK: sm exts list enumerates ${listed_exts} extension(s)"
fi

if [[ "${listed_exts:-0}" -lt 5 ]]; then
  echo "FAIL: too few extensions loaded (${listed_exts:-0}); logic/core likely broken" >&2
  fail=1
fi

for required_ext in 'BinTools' 'SDK Tools' 'CS Tools' 'SDK Hooks'; do
  require_grep "${CONSOLE_PROBE_LOG}" "${required_ext}" "required extension (${required_ext})"
done

# Explicit loads. Autoload never opens dbi.mysql / dbi.pgsql, so a bad link
# (OpenSSL, glibc) used to pass smoke. geoip and regex stay optional.
require_ext_loaded() {
  local ext="$1"
  require_grep "${CONSOLE_PROBE_LOG}" \
    "Loaded extension ${ext}(\\.so)? successfully|Extension ${ext}(\\.so)? is already loaded" \
    "sm exts load ${ext}"
}
require_ext_loaded dbi.mysql.ext
require_ext_loaded dbi.pgsql.ext
for optional_ext in geoip.ext regex.ext; do
  if grep -Eiq "Loaded extension ${optional_ext}(\\.so)? successfully|Extension ${optional_ext}(\\.so)? is already loaded" \
      "${CONSOLE_PROBE_LOG}"; then
    echo "OK: sm exts load ${optional_ext}"
  else
    echo "NOTE: optional extension ${optional_ext} did not load"
  fi
done

# Which SourceMod core runs: MM 1.10 loads sourcemod.1.ep1, newer Metamod
# sourcemod.2.ep1. DHooks exists for 2.ep1 only, so `sm exts list` must show
# it exactly on the 2.ep1 core (console-probe.exp loads it explicitly).
SMOKE_EXPECT_CORE="${SMOKE_EXPECT_CORE:-}"
dhooks_listed=0
if sed -n '/sm exts list/,/sm plugins list/p' "${CONSOLE_PROBE_LOG}" 2>/dev/null \
    | grep -Eq '^\[[0-9]+\] DHooks '; then
  dhooks_listed=1
fi
case "${SMOKE_EXPECT_CORE}" in
  "") echo "NOTE: SMOKE_EXPECT_CORE unset; core identity not checked (DHooks listed=${dhooks_listed})" ;;
  2.ep1)
    if [[ "${dhooks_listed}" == 1 ]]; then
      echo "OK: 2.ep1 core runs (DHooks loaded)"
    else
      echo "FAIL: expected the 2.ep1 core, but DHooks is not in sm exts list" >&2
      fail=1
    fi
    ;;
  1.ep1)
    if [[ "${dhooks_listed}" == 0 ]]; then
      echo "OK: 1.ep1 core runs (DHooks not loadable)"
    else
      echo "FAIL: expected the 1.ep1 core, but DHooks loaded (2.ep1 core running)" >&2
      fail=1
    fi
    ;;
  *) echo "FAIL: unknown SMOKE_EXPECT_CORE=${SMOKE_EXPECT_CORE}" >&2; fail=1 ;;
esac

# css34 OnTakeDamage vtables must be the packaged overlay (windows 60 / linux 61).
# Match the exact Offsets key (not OnTakeDamage_Alive). linux is 3 lines after the key
# when windows is listed first — use enough context.
sdkhooks_gd="${SERVER_DIR}/cstrike/addons/sourcemod/gamedata/sdkhooks.games/game.cstrike.txt"
if [[ -f "${sdkhooks_gd}" ]]; then
  if ! grep -A4 -E '^[[:space:]]*"OnTakeDamage"[[:space:]]*$' "${sdkhooks_gd}" \
      | grep -qE '"linux"[[:space:]]+"61"'; then
    echo "FAIL: sdkhooks OnTakeDamage linux offset is not css34 61 in ${sdkhooks_gd}" >&2
    grep -A5 -E '^[[:space:]]*"OnTakeDamage"[[:space:]]*$' "${sdkhooks_gd}" >&2 || true
    fail=1
  else
    echo "OK: sdkhooks OnTakeDamage linux offset is 61 (css34)"
  fi
else
  echo "FAIL: missing sdkhooks gamedata ${sdkhooks_gd}" >&2
  fail=1
fi

# Every SDKTools / SDKHooks vtable offset must match the v34 CCSPlayer vtable
# (upstream CS:S offsets crash GivePlayerItem / GetPlayerWeaponSlot on v34).
server_so="${SERVER_DIR}/cstrike/bin/server_i486.so"
vtable_check="${ROOT}/testing/scripts/check-css34-vtables.py"
if command -v python3 >/dev/null 2>&1 && command -v c++filt >/dev/null 2>&1 && [[ -f "${server_so}" ]]; then
  if python3 "${vtable_check}" "${server_so}" "${SERVER_DIR}/cstrike/addons/sourcemod/gamedata"; then
    echo "OK: css34 SDKTools/SDKHooks vtable offsets match server_i486.so"
  else
    echo "FAIL: css34 gamedata vtable offsets do not match server_i486.so" >&2
    fail=1
  fi
else
  echo "SKIP: css34 vtable check (needs python3 + c++filt + ${server_so})"
  if [[ "${CSS34_CI}" == "1" ]]; then
    echo "FAIL: CSS34_CI requires the css34 vtable check" >&2
    fail=1
  fi
fi

if grep -Eiq '<FAILED>' "${CONSOLE_PROBE_LOG}"; then
  echo "FAIL: failed extension(s) in sm exts list" >&2
  grep -Ei '<FAILED>' "${CONSOLE_PROBE_LOG}" >&2 || true
  fail=1
else
  echo "OK: no <FAILED> extensions in console probe log"
fi

# All enabled .smx plugins must be listed as running.
expected_plugins="$(find "${SM_PLUGINS_DIR}" -maxdepth 1 -name '*.smx' 2>/dev/null | wc -l | tr -d ' ')"
if [[ "${expected_plugins}" -lt 1 ]]; then
  echo "FAIL: no enabled plugins found under ${SM_PLUGINS_DIR}" >&2
  fail=1
else
  require_grep "${CONSOLE_PROBE_LOG}" "\\[SM\\] Listing ${expected_plugins} plugins:" \
    "sm plugins list reports ${expected_plugins} running plugins"
fi

# geoip/regex failures are optional and must not fail the run. DBI failures are not.
# The DHooks probe is expected to fail on the 1.ep1 core (no dhooks.ext.1.ep1);
# the core identity check above already judged it.
dhooks_expected_failure='^$'
if [[ "${SMOKE_EXPECT_CORE}" == 1.ep1 ]]; then
  dhooks_expected_failure='Extension dhooks(\.ext)?(\.so)? failed to load'
fi
plugin_errors="$(
  grep -Ei 'Error loading|Failed to load|could not be loaded|Encountered error|Unable to load extension' \
    "${CONSOLE_PROBE_LOG}" 2>/dev/null \
    | grep -Eiv 'geoip|regex' \
    | grep -Ev "${dhooks_expected_failure}" || true
)"
if [[ -n "${plugin_errors}" ]]; then
  echo "FAIL: plugin load errors in console probe log" >&2
  printf '%s\n' "${plugin_errors}" >&2
  fail=1
else
  echo "OK: no plugin load errors in console probe log"
fi

# Each listed plugin entry must be Running (quoted name), not Failed.
listed_plugins="$(grep -Ec '^[[:space:]]*[0-9]+[[:space:]]+"' "${CONSOLE_PROBE_LOG}" || true)"
failed_plugins="$(grep -Ec '^[[:space:]]*[0-9]+[[:space:]]+<Failed>' "${CONSOLE_PROBE_LOG}" || true)"
if [[ "${failed_plugins:-0}" -gt 0 ]]; then
  echo "FAIL: ${failed_plugins} plugin(s) in Failed state" >&2
  grep -E '^[[:space:]]*[0-9]+[[:space:]]+<Failed>' "${CONSOLE_PROBE_LOG}" >&2 || true
  fail=1
fi
if [[ "${expected_plugins:-0}" -gt 0 && "${listed_plugins}" -ne "${expected_plugins}" ]]; then
  echo "FAIL: expected ${expected_plugins} plugin lines in sm plugins list, saw ${listed_plugins}" >&2
  fail=1
else
  echo "OK: sm plugins list enumerates ${listed_plugins} plugin(s)"
fi

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

chmod +x "${ROOT}/testing/scripts/check-sm-logs.sh"
if ! "${ROOT}/testing/scripts/check-sm-logs.sh" "${SM_LOG_DIR}"; then
  fail=1
fi

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
