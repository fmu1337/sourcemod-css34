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
ENGINE_CONSOLE_LOG="${SERVER_DIR}/cstrike/console.log"

# Expected versions. Defaults match our in-tree packages (MM 1.10.7 + SM 6572).
# Override to 1.10.6 for rom4s reference legacy jobs.
MM_VERSION_EXPECT="${MM_VERSION_EXPECT:-1.10.7}"
SM_VERSION_EXPECT="${SM_VERSION_EXPECT:-1.11.0.6572}"
# Explicit upstream commits baked into `meta version` / `sm version` Built from.
MM_COMMIT_EXPECT="${MM_COMMIT_EXPECT:-80e8ff0be3b62386bbd6f937e97b819ef8be6dd2}"
SM_COMMIT_EXPECT="${SM_COMMIT_EXPECT:-832519ab647cdecb85763918dbfed1cb5e79c6cb}"
# Packaging repo commit (CSS34 pack line). Empty skips the check.
CSS34_PACK_COMMIT_EXPECT="${CSS34_PACK_COMMIT_EXPECT:-}"

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
rm -f "${ENGINE_CONSOLE_LOG}"
/usr/bin/expect "${ROOT}/testing/scripts/console-probe.exp" >"${LOG_FILE}" 2>&1 || {
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

# Explicit build identity from version headers (Built from / CSS34 pack).
require_grep "${CONSOLE_PROBE_LOG}" \
  "metamod-source/commit/${MM_COMMIT_EXPECT}" \
  "meta Built from commit ${MM_COMMIT_EXPECT}"
require_grep "${CONSOLE_PROBE_LOG}" \
  "sourcemod/commit/${SM_COMMIT_EXPECT}" \
  "sm Built from commit ${SM_COMMIT_EXPECT}"
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

# css34 OnTakeDamage vtables must be the packaged overlay (windows 60 / linux 61).
sdkhooks_gd="${SERVER_DIR}/cstrike/addons/sourcemod/gamedata/sdkhooks.games/game.cstrike.txt"
if [[ -f "${sdkhooks_gd}" ]]; then
  if ! grep -A2 '"OnTakeDamage"' "${sdkhooks_gd}" | grep -q '"linux"[[:space:]]*"61"'; then
    echo "FAIL: sdkhooks OnTakeDamage linux offset is not css34 61 in ${sdkhooks_gd}" >&2
    grep -A5 '"OnTakeDamage"' "${sdkhooks_gd}" >&2 || true
    fail=1
  else
    echo "OK: sdkhooks OnTakeDamage linux offset is 61 (css34)"
  fi
else
  echo "FAIL: missing sdkhooks gamedata ${sdkhooks_gd}" >&2
  fail=1
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

if grep -Eiq 'Error loading|Failed to load|could not be loaded|Encountered error' "${CONSOLE_PROBE_LOG}"; then
  echo "FAIL: plugin load errors in console probe log" >&2
  grep -Ei 'Error loading|Failed to load|could not be loaded|Encountered error' "${CONSOLE_PROBE_LOG}" >&2 || true
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
require_grep_glob "${SM_LOG_DIR}/L*.log" 'Mapchange to' "SourceMod saw mapchange"

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
