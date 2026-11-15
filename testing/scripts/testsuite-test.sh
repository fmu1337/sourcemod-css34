#!/usr/bin/env bash
# SourceMod's own testsuite on srcds v34.
#
# 1. Compile: every scripting/testsuite/*.sp of the installed package must build
#    with the package's spcomp. KNOWN_BROKEN lists the upstream files that no
#    longer compile with the current compiler (old syntax, missing includes);
#    those are reported, not failed.
# 2. Run: SourceMod's self-checking tests (plugins/testsuite/mock, testing.inc
#    prints "... OK" / "... FAIL: ..."; upstream runs them on hl2sdk-mock) run on
#    the real v34 server, one boot per test. A test passes when it prints at
#    least one OK, no FAIL, and SourceMod logs no error for it.
# 3. The other testsuite plugins print results without asserting them: one boot
#    loads each over RCON, runs its commands and changes the map; a SourceMod
#    error log line, a load failure or a crash fails (MANUAL_RUN / MANUAL_SKIP).
#
# Usage: SERVER_DIR=<srcds root with MM + SM installed> \
#        TESTSUITE_MOCK_DIR=<packages/test-plugins/testsuite-mock> testsuite-test.sh
# The build copies the mock sources of the line's SourceMod tree to
# packages/test-plugins/testsuite-mock (builder/run/linux.sh, never released).
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SERVER_DIR="${SERVER_DIR:?SERVER_DIR is required}"
TESTSUITE_MOCK_DIR="${TESTSUITE_MOCK_DIR:-}"
TESTSUITE_TIMEOUT="${TESTSUITE_TIMEOUT:-120}"
# Frames and async file callbacks (test_format's RequestFrame, test_async_file)
# finish within a few ticks; give them a few seconds after RCON answers.
TESTSUITE_SETTLE="${TESTSUITE_SETTLE:-5}"
CSS34_CI="${CSS34_CI:-0}"
sm="${SERVER_DIR}/cstrike/addons/sourcemod"
scripting="${sm}/scripting"
work="${TESTSUITE_WORK:-${SERVER_DIR}/testsuite}"
KNOWN_BROKEN=(fakenative2 fwdtest2 goto_test sorttest sqltest stacktest structtest)
fail=0
srcds_binary="${SRCDS_BINARY:-./srcds_i686}"
if [[ ! -x "${SERVER_DIR}/${srcds_binary#./}" && -x "${SERVER_DIR}/srcds_i486" ]]; then
  srcds_binary=./srcds_i486
fi

[[ -x "${scripting}/spcomp" || -f "${scripting}/spcomp" ]] || { echo "FAIL: no spcomp in ${scripting}" >&2; exit 1; }
chmod +x "${scripting}/spcomp"
rm -rf "${work}"
mkdir -p "${work}/compile" "${work}/mock"

is_known_broken() {
  local name="$1" b
  for b in "${KNOWN_BROKEN[@]}"; do
    [[ "${b}" == "${name}" ]] && return 0
  done
  return 1
}

echo "==> Compiling scripting/testsuite with $("${scripting}/spcomp" 2>&1 | head -n1 || true)"
compiled=0
shopt -s nullglob
for sp in "${scripting}"/testsuite/*.sp; do
  name="$(basename "${sp}" .sp)"
  log="${work}/compile/${name}.log"
  if (cd "${scripting}/testsuite" && "${scripting}/spcomp" -i"${scripting}/include" \
      -o"${work}/compile/${name}.smx" "${sp}") >"${log}" 2>&1; then
    compiled=$((compiled + 1))
    if is_known_broken "${name}"; then
      echo "OK: compile ${name}.sp (in KNOWN_BROKEN: fails on another line)"
    else
      echo "OK: compile ${name}.sp"
    fi
  elif is_known_broken "${name}"; then
    echo "NOTE: ${name}.sp does not compile (known upstream breakage): $(grep -m1 -E 'error [0-9]+' "${log}" || true)"
  else
    echo "FAIL: compile ${name}.sp" >&2
    cat "${log}" >&2
    fail=1
  fi
done
if [[ "${compiled}" -lt 1 ]]; then
  echo "FAIL: no scripting/testsuite plugin compiled" >&2
  fail=1
fi

mock_sources=()
if [[ -n "${TESTSUITE_MOCK_DIR}" && -d "${TESTSUITE_MOCK_DIR}" ]]; then
  mock_sources=("${TESTSUITE_MOCK_DIR}"/*.sp)
fi
shopt -u nullglob
if [[ "${#mock_sources[@]}" -eq 0 ]]; then
  if [[ "${CSS34_CI}" == 1 ]]; then
    echo "FAIL: no SourceMod mock tests in '${TESTSUITE_MOCK_DIR}' (the build copies them to packages/test-plugins)" >&2
    exit 1
  fi
  echo "SKIP: mock tests (set TESTSUITE_MOCK_DIR)"
fi
if [[ ! -x "${SERVER_DIR}/${srcds_binary#./}" ]]; then
  if [[ "${CSS34_CI}" == 1 ]]; then
    echo "FAIL: no srcds binary ${srcds_binary} in ${SERVER_DIR}" >&2
    exit 1
  fi
  echo "SKIP: in-game tests (no srcds in ${SERVER_DIR})"
  [[ "${fail}" -eq 0 ]] && echo "Testsuite compile PASSED"
  exit "${fail}"
fi

rcon_pw="css34testsuite"
rcon() { python3 "${root}/testing/scripts/rcon.py" 127.0.0.1 "${rcon_pw}" "$@"; }
errors_lines() { cat "${sm}"/logs/errors_*.log 2>/dev/null | wc -l || true; }
srcds_pid=""
plugin_file=""
manual_files=()
cleanup() {
  if [[ -n "${srcds_pid}" ]]; then kill "${srcds_pid}" 2>/dev/null || true; fi
  if [[ -n "${plugin_file}" ]]; then rm -f "${plugin_file}"; fi
  if [[ "${#manual_files[@]}" -gt 0 ]]; then rm -f "${manual_files[@]}"; fi
}
trap cleanup EXIT

run_test() {
  local sp="$1" name smx session console errors_before
  name="$(basename "${sp}" .sp)"
  smx="${work}/mock/${name}.smx"
  session="${work}/mock/${name}.log"
  console="${SERVER_DIR}/cstrike/console.log"

  if ! "${scripting}/spcomp" -i"${scripting}/include" -o"${smx}" "${sp}" >"${work}/mock/${name}.compile.log" 2>&1; then
    echo "FAIL: compile mock ${name}.sp" >&2
    cat "${work}/mock/${name}.compile.log" >&2
    fail=1
    return 0
  fi

  # Autoloaded at boot, so OnPluginStart output goes to the console, not to an
  # RCON reply. One plugin per boot keeps every OK / FAIL line attributable.
  plugin_file="${sm}/plugins/css34_testsuite_${name}.smx"
  cp -f "${smx}" "${plugin_file}"
  rm -f "${console}"
  errors_before="$(errors_lines)"
  (
    cd "${SERVER_DIR}"
    export LD_LIBRARY_PATH=".:bin:${LD_LIBRARY_PATH:-}"
    exec "${srcds_binary}" -game cstrike -console -condebug -nohltv -nomaster -localcser \
      -tickrate 66 -ip 127.0.0.1 -port 27015 +ip 127.0.0.1 +sv_lan 1 +maxplayers 4 \
      +rcon_password "${rcon_pw}" +map de_dust2
  ) </dev/null >"${session}.console" 2>&1 &
  srcds_pid=$!

  local deadline=$((SECONDS + TESTSUITE_TIMEOUT)) up=1
  until rcon "echo css34-testsuite-up" 2>/dev/null | grep -q css34-testsuite-up; do
    if ! kill -0 "${srcds_pid}" 2>/dev/null || (( SECONDS >= deadline )); then
      up=0
      break
    fi
    sleep 2
  done
  if [[ "${up}" == 1 ]]; then
    sleep "${TESTSUITE_SETTLE}"
    rcon "sm plugins list" >"${session}.plugins" 2>&1 || true
    rcon "quit" >/dev/null 2>&1 || true
  fi
  local waited=0
  while kill -0 "${srcds_pid}" 2>/dev/null && (( waited < 15 )); do
    sleep 1
    waited=$((waited + 1))
  done
  kill "${srcds_pid}" 2>/dev/null || true
  wait "${srcds_pid}" 2>/dev/null || true
  srcds_pid=""
  rm -f "${plugin_file}"
  plugin_file=""

  {
    cat "${session}.console"
    [[ -f "${console}" ]] && cat "${console}"
  } >"${session}"
  local errors_new
  errors_new="$(cat "${sm}"/logs/errors_*.log 2>/dev/null | tail -n +"$((errors_before + 1))" || true)"

  local ok_count fail_lines test_fail=0
  # stdout and console.log hold the same lines; count each test line once.
  ok_count="$(tr -d '\r' <"${session}" | grep -E '^\[[0-9]+\] .* OK *$' | sort -u | wc -l || true)"
  fail_lines="$(tr -d '\r' <"${session}" | grep -E '^\[[0-9]+\] .* FAIL' | sort -u || true)"
  echo "----- ${name}: ${ok_count} OK line(s) -----"
  if [[ "${up}" != 1 ]]; then
    echo "FAIL: ${name}: srcds did not answer RCON within ${TESTSUITE_TIMEOUT}s" >&2
    tail -n 40 "${session}" >&2 || true
    test_fail=1
  fi
  if [[ -n "${fail_lines}" ]]; then
    echo "FAIL: ${name}: test assertions failed" >&2
    printf '%s\n' "${fail_lines}" >&2
    test_fail=1
  fi
  if [[ -n "${errors_new}" ]]; then
    echo "FAIL: ${name}: SourceMod logged errors" >&2
    printf '%s\n' "${errors_new}" >&2
    test_fail=1
  fi
  if grep -Eq 'Segmentation fault|SIGSEGV|Aborted|SIGABRT' "${session}"; then
    echo "FAIL: ${name}: srcds crashed" >&2
    test_fail=1
  fi
  if [[ "${up}" == 1 && "${ok_count}" -lt 1 ]]; then
    echo "FAIL: ${name}: printed no OK line (did the plugin run?)" >&2
    grep -E 'css34_testsuite|\[SM\]' "${session}" "${session}.plugins" >&2 || true
    test_fail=1
  fi
  if [[ "${test_fail}" == 0 ]]; then
    echo "OK: ${name} on srcds v34"
  else
    fail=1
  fi
}

echo "==> Running ${#mock_sources[@]} SourceMod mock test(s) on srcds v34"
for sp in ${mock_sources[@]+"${mock_sources[@]}"}; do
  run_test "${sp}"
done

# 3. The other scripting/testsuite plugins print their results instead of
#    asserting them, so they are judged by what SourceMod and srcds report: one
#    srcds boot loads each plugin over RCON, runs its server commands, then
#    changes the map once (OnMapInit / OnMapStart plugins). Any line SourceMod
#    adds to its error log (ThrowError, native errors, exceptions, load
#    failures), a plugin that does not load, or a crash fails the run.
#    "name|command;command" (no commands: the load itself is the test). Order
#    matters: fwdtest1 finds fwdtest2.smx by file name.
MANUAL_RUN=(
  "bug4059|test_bug4059"
  "callfunctest|test_callfunc;test_callfunc_reentrant"
  "capstest|sm_test_caps1"
  "clientprefstest|"
  "cstrike-test|"
  "entpropelements|sm_teststrings"
  "fakenative1|"
  "filetest|test_fread1"
  "findmap|test_findmap de_dust2;test_findmap de_css34_missing"
  "floats|test_floats"
  "fwdtest2|"
  "fwdtest1|test_create_gforward;test_create_pforward;test_exec_gforward;test_exec_pforward"
  "keyvalues|test_keyvalues"
  "mapdisplayname|test_mapdisplayname de_dust2"
  "ptstest|"
  "sorttest|test_sort_ints;test_sort_floats;test_sort_strings;test_sort_1d;test_sort_2d;test_adtsort_ints;test_adtsort_floats;test_adtsort_strings;test_adtsort_custom"
  "tries|test_maps;test_int_maps"
  "entitylumptest|"
  "outputtest|"
)
# Not run, with the reason. capstest's sm_test_caps2 / 3 fail the plugin on
# purpose (RequireFeature of a missing native), so only sm_test_caps1 runs.
declare -A MANUAL_SKIP=(
  [benchmark]="needs translations/fakedict-sourcemod.cfg, which SourceMod does not ship"
  [gamerules-props]="TF2 / Alien Swarm only (AskPluginLoad2 refuses other games)"
  [tf2-test]="TF2 natives; packages ship no tf2 extension"
)

run_manual() {
  local session="${work}/manual.log" entry name cmds cmd reply errors_before up=1
  local -a cmd_list
  mkdir -p "${work}/manual"
  local listed=" "
  for entry in "${MANUAL_RUN[@]}"; do listed+="${entry%%|*} "; done
  for smx in "${work}"/compile/*.smx; do
    name="$(basename "${smx}" .smx)"
    if [[ "${listed}" != *" ${name} "* && -z "${MANUAL_SKIP[${name}]:-}" ]]; then
      echo "FAIL: ${name}.smx compiles but is neither in MANUAL_RUN nor MANUAL_SKIP" >&2
      fail=1
    fi
  done
  for name in "${!MANUAL_SKIP[@]}"; do
    echo "SKIP: ${name}: ${MANUAL_SKIP[${name}]}"
  done

  rm -f "${SERVER_DIR}/cstrike/console.log"
  errors_before="$(errors_lines)"
  (
    cd "${SERVER_DIR}"
    export LD_LIBRARY_PATH=".:bin:${LD_LIBRARY_PATH:-}"
    exec "${srcds_binary}" -game cstrike -console -condebug -nohltv -nomaster -localcser \
      -tickrate 66 -ip 127.0.0.1 -port 27015 +ip 127.0.0.1 +sv_lan 1 +maxplayers 4 \
      +rcon_password "${rcon_pw}" +map de_dust2
  ) </dev/null >"${session}.console" 2>&1 &
  srcds_pid=$!

  wait_rcon() {
    local deadline=$((SECONDS + TESTSUITE_TIMEOUT))
    until rcon "echo css34-testsuite-up" 2>/dev/null | grep -q css34-testsuite-up; do
      if ! kill -0 "${srcds_pid}" 2>/dev/null || (( SECONDS >= deadline )); then
        return 1
      fi
      sleep 2
    done
  }

  : >"${session}"
  if ! wait_rcon; then
    echo "FAIL: manual testsuite: srcds did not answer RCON within ${TESTSUITE_TIMEOUT}s" >&2
    up=0
  fi
  local ran=0
  for entry in "${MANUAL_RUN[@]}"; do
    [[ "${up}" == 1 ]] || break
    name="${entry%%|*}"
    cmds="${entry#*|}"
    if [[ ! -f "${work}/compile/${name}.smx" ]]; then
      echo "SKIP: ${name}: does not compile on this line"
      continue
    fi
    # Plugins look each other up by file name (fwdtest1 -> fwdtest2.smx), so
    # they go straight into plugins/; copied after boot, so never autoloaded.
    cp -f "${work}/compile/${name}.smx" "${sm}/plugins/${name}.smx"
    manual_files+=("${sm}/plugins/${name}.smx")
    reply="$(rcon "sm plugins load ${name}" 2>&1 || true)"
    printf '>>> sm plugins load %s\n%s\n' "${name}" "${reply}" >>"${session}"
    if ! grep -q 'successfully' <<<"${reply}"; then
      echo "FAIL: ${name}: did not load: ${reply}" >&2
      fail=1
      continue
    fi
    cmd_list=()
    [[ -z "${cmds}" ]] || IFS=';' read -r -a cmd_list <<<"${cmds}"
    # ${arr[@]+...}: an empty array is "unbound" under set -u in bash 4.2 (centos:7).
    for cmd in ${cmd_list[@]+"${cmd_list[@]}"}; do
      [[ -n "${cmd}" ]] || continue
      reply="$(rcon "${cmd}" 2>&1 || true)"
      printf '>>> %s\n%s\n' "${cmd}" "${reply}" >>"${session}"
      if ! kill -0 "${srcds_pid}" 2>/dev/null; then
        echo "FAIL: ${name}: srcds died on '${cmd}'" >&2
        up=0
        fail=1
        break
      fi
    done
    ran=$((ran + 1))
    echo "OK: ${name} loaded${cmds:+, ran ${cmds//;/, }}"
  done

  if [[ "${up}" == 1 ]]; then
    # OnMapInit (entity lump) and OnMapStart (entity outputs) need a map load.
    rcon "changelevel de_dust2" >>"${session}" 2>&1 || true
    sleep 5
    if wait_rcon; then
      sleep "${TESTSUITE_SETTLE}"
      rcon "sm plugins list" >>"${session}" 2>&1 || true
      echo "OK: map change with the testsuite plugins loaded"
    else
      echo "FAIL: manual testsuite: srcds did not come back after changelevel" >&2
      fail=1
    fi
    rcon "quit" >/dev/null 2>&1 || true
  else
    fail=1
  fi
  local waited=0
  while kill -0 "${srcds_pid}" 2>/dev/null && (( waited < 15 )); do
    sleep 1
    waited=$((waited + 1))
  done
  kill "${srcds_pid}" 2>/dev/null || true
  wait "${srcds_pid}" 2>/dev/null || true
  srcds_pid=""
  if [[ "${#manual_files[@]}" -gt 0 ]]; then rm -f "${manual_files[@]}"; fi
  manual_files=()

  cat "${session}.console" >>"${session}"
  [[ -f "${SERVER_DIR}/cstrike/console.log" ]] && cat "${SERVER_DIR}/cstrike/console.log" >>"${session}"
  local errors_new
  errors_new="$(cat "${sm}"/logs/errors_*.log 2>/dev/null | tail -n +"$((errors_before + 1))" || true)"
  if [[ -n "${errors_new}" ]]; then
    echo "FAIL: manual testsuite: SourceMod logged errors" >&2
    printf '%s\n' "${errors_new}" >&2
    fail=1
  fi
  if grep -Eq 'Segmentation fault|SIGSEGV|Aborted|SIGABRT' "${session}"; then
    echo "FAIL: manual testsuite: srcds crashed" >&2
    fail=1
  fi
  if grep -Eq '<Failed>|<Error>' "${session}"; then
    echo "FAIL: manual testsuite: a plugin is in a failed state" >&2
    grep -E '<Failed>|<Error>' "${session}" >&2 || true
    fail=1
  fi
  echo "----- manual testsuite: ${ran} plugin(s) run (log: ${session}) -----"
}

echo "==> Running the other scripting/testsuite plugins on srcds v34"
run_manual

if [[ "${fail}" -ne 0 ]]; then
  echo "Testsuite test FAILED"
  exit 1
fi
echo "Testsuite test PASSED"
