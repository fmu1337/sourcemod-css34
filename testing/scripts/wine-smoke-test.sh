#!/usr/bin/env bash
# Boot the Windows CS:S v34 dedicated server (srcds.exe) with the Windows
# Metamod + SourceMod packages and probe them over RCON: under Wine on Linux,
# or natively from Git Bash on Windows (MINGW/MSYS, e.g. the windows-2022 runner).
#
# Inputs (env):
#   SM_WIN_PACKAGE / MM_WIN_PACKAGE  Windows zips (sourcemod-*-windows.zip, mmsource-*-windows.zip)
#   SERVER_TGZ    optional prepared server tree (test-server.yml prepare-server); game content only
#   PDB_DIR       optional directory of .pdb files, copied next to the matching .dll so a crash
#                 backtrace (winedbg --auto, or cdb on a native minidump) is symbolized
#   SM_VERSION_EXPECT / MM_VERSION_EXPECT, EXPECT_EXTS (comma list of `sm exts list` names),
#   LOAD_EXTS     comma list of extensions to `sm exts load` first (no plugin requires them)
#   DHOOKS_PROBE_SECS  > 0: compile css34_dhooks_probe.sp with the package's spcomp.exe, play
#                 that long with bots and require the probe's hooks to fire with clean values
#                 (skipped when DHooks is not expected to load)
#   DHOOKS_EXPECT 1: DHooks (dhooks.ext.dll, or dhooks.ext.2.ep1.dll in the dual-core SM 1.11
#                 package) must load; 0: it must not (SM 1.11 on MM 1.10.7 runs the 1.ep1
#                 core, which has no DHooks); unset: required exactly when the zip has it
# Needs: wine32 (i386), xvfb, unzip, python3 (Linux); unzip or 7z, python, curl (Windows).
set -euo pipefail

case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) NATIVE=1; PY=python ;;
  *) NATIVE=0; PY=python3 ;;
esac
# Windows command-line tools take /switches; keep MSYS from turning them into paths
# (only for these: curl, python and 7z need /c/... paths converted)
wincmd() { MSYS2_ARG_CONV_EXCL='*' "$@"; }

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SERVER_DIR="${SERVER_DIR:-${ROOT}/.ci-winserver}"
CACHE_DIR="${CACHE_DIR:-${ROOT}/.ci-cache}"
WIN_BIN_ZIP_URL="${WIN_BIN_ZIP_URL:-https://bitbucket.org/rom4s/other.get/downloads/srcds_css34_w_a.zip}"
MAP="${MAP:-de_dust2}"
MAP2="${MAP2:-de_inferno}"
RCON_PASSWORD="${RCON_PASSWORD:-css34ci}"
BOOT_SECS="${BOOT_SECS:-180}"
SM_VERSION_EXPECT="${SM_VERSION_EXPECT:?}"
MM_VERSION_EXPECT="${MM_VERSION_EXPECT:?}"
EXPECT_EXTS="${EXPECT_EXTS:-CS Tools,SDK Tools,BinTools}"
# Own prefix: in a CI job container $HOME and the workspace belong to another uid
# and wine refuses a prefix it does not own
[[ "${NATIVE}" == 1 ]] || export WINEPREFIX="${WINEPREFIX:-/tmp/wine-css34-$(id -u)}" WINEARCH=win32 WINEDEBUG="${WINEDEBUG:-err+all,+seh,+loaddll}" DISPLAY="${DISPLAY:-:97}"
WINE_LOG="${SERVER_DIR}/wine.log"
DUMP_DIR="${SERVER_DIR}/dumps"
# Runs srcds.exe / spcomp.exe (wine on Linux, directly on Windows)
winexe() { if [[ "${NATIVE}" == 1 ]]; then "$@"; else wine "$@"; fi; }
unz() { # zip dest
  if command -v unzip >/dev/null 2>&1; then
    unzip -qo "$1" -d "$2" || [[ $? -eq 1 ]]
  else
    7z x -y -bso0 -bsp0 "-o$2" "$1"
  fi
}

fail() { echo "FAIL: $*" >&2; dump; exit 1; }
dump() {
  echo "==== engine console.log (tail) ===="; tail -n 60 "${SERVER_DIR}/cstrike/console.log" 2>/dev/null || true
  echo "==== SourceMod logs ===="; tail -n 40 "${SERVER_DIR}"/cstrike/addons/sourcemod/logs/*.log 2>/dev/null || true
  if [[ "${NATIVE}" == 1 ]]; then
    native_crash_report || true
  else
    echo "==== exceptions ===="; python3 "${ROOT}/testing/scripts/wine-crash-report.py" "${WINE_LOG}" "${SERVER_DIR}" || true
    echo "==== wine log (errors) ===="; grep ':err:' "${WINE_LOG}" 2>/dev/null | tail -n 40 || true
  fi
}
# Native: WER LocalDumps writes a minidump of a crashed srcds.exe; cdb (Windows SDK
# debuggers, when installed) prints the faulting stack with the PDBs next to the DLLs
native_crash_report() {
  echo "==== srcds.exe process ===="; wincmd tasklist /FI "IMAGENAME eq srcds.exe" 2>/dev/null || true
  local dmp cdb
  dmp="$(ls -t "${DUMP_DIR}"/*.dmp 2>/dev/null | head -n1 || true)"
  [[ -n "${dmp}" ]] || { echo "(no crash dump)"; return 0; }
  echo "==== crash dump: ${dmp} ===="
  for cdb in "/c/Program Files (x86)/Windows Kits/10/Debuggers/x86/cdb.exe" "/c/Program Files/Windows Kits/10/Debuggers/x86/cdb.exe"; do
    [[ -x "${cdb}" ]] || continue
    local syms; syms="$(find "${SERVER_DIR}/cstrike/addons" -name '*.pdb' -exec dirname {} \; | sort -u | while read -r d; do cygpath -w "$d"; done | paste -sd';')"
    timeout 300 "${cdb}" -z "$(cygpath -w "${dmp}")" -y "${syms}" -lines -c ".ecxr; kb 40; lm; q" 2>&1 | tail -n 120 || true
    return 0
  done
  echo "(cdb.exe not found; the dump is kept in the server directory)"
}

mkdir -p "${CACHE_DIR}"
rm -rf "${SERVER_DIR}"; mkdir -p "${SERVER_DIR}"
if [[ -n "${SERVER_TGZ:-}" && -f "${SERVER_TGZ}" ]]; then
  tar -xzf "${SERVER_TGZ}" -C "${SERVER_DIR}" ./cstrike ./hl2 ./platform
else
  [[ -s "${CACHE_DIR}/srcds_css34_4044.zip" ]] || curl -fL --retry 5 -o "${CACHE_DIR}/srcds_css34_4044.zip" https://bitbucket.org/rom4s/other.get/downloads/srcds_css34_4044.zip
  unz "${CACHE_DIR}/srcds_css34_4044.zip" "${SERVER_DIR}"
fi
[[ -s "${CACHE_DIR}/srcds_css34_w_a.zip" ]] || curl -fL --retry 5 -o "${CACHE_DIR}/srcds_css34_w_a.zip" "${WIN_BIN_ZIP_URL}"
unz "${CACHE_DIR}/srcds_css34_w_a.zip" "${SERVER_DIR}"
# Only the Windows server binaries and addons from here on
rm -rf "${SERVER_DIR}/cstrike/addons" "${SERVER_DIR}/cstrike/cfg/sourcemod"
cat >"${SERVER_DIR}/cstrike/cfg/server.cfg" <<'CFG'
hostname sourcemod-css34-win-ci
sv_lan 1
mp_timelimit 0
CFG

# Windows zips may use '\' separators; unzip converts them (exit code 1 = warning)
for z in "${MM_WIN_PACKAGE:?}" "${SM_WIN_PACKAGE:?}"; do
  unz "$z" "${SERVER_DIR}/cstrike"
done
[[ -f "${SERVER_DIR}/cstrike/addons/metamod.vdf" ]] || fail "metamod.vdf missing after install"

DHOOKS_PROBE_SECS="${DHOOKS_PROBE_SECS:-0}"
SM_DIR="${SERVER_DIR}/cstrike/addons/sourcemod"
dhooks_dll=""
for f in dhooks.ext.dll dhooks.ext.2.ep1.dll; do
  if [[ -f "${SM_DIR}/extensions/${f}" ]]; then dhooks_dll="${f}"; fi
done
case "${DHOOKS_EXPECT:-}" in
  "") if [[ -n "${dhooks_dll}" ]]; then DHOOKS_EXPECT=1; else DHOOKS_EXPECT=0; fi ;;
  1) [[ -n "${dhooks_dll}" ]] || fail "DHOOKS_EXPECT=1 but the package has no dhooks.ext*.dll" ;;
  0) ;;
  *) fail "DHOOKS_EXPECT must be 0 or 1, got ${DHOOKS_EXPECT}" ;;
esac
echo "==> DHooks expected: ${DHOOKS_EXPECT} (package: ${dhooks_dll:-none})"
if [[ "${DHOOKS_PROBE_SECS}" -gt 0 && "${DHOOKS_EXPECT}" != 1 ]]; then
  echo "==> DHooks not expected on this core, skipping the DHooks probe"
  DHOOKS_PROBE_SECS=0
fi

if [[ -n "${PDB_DIR:-}" && -d "${PDB_DIR}" ]]; then
  while IFS= read -r dll; do
    pdb="${PDB_DIR}/$(basename "${dll%.dll}").pdb"
    if [[ -f "$pdb" ]]; then
      cp -f "$pdb" "$(dirname "$dll")/"
    fi
  done < <(find "${SERVER_DIR}/cstrike/addons" -name '*.dll')
fi

if [[ "${NATIVE}" == 1 ]]; then
  # No Windows Error Reporting dialog (it would keep a crashed srcds.exe alive), and a
  # minidump of a crash for native_crash_report
  mkdir -p "${DUMP_DIR}"
  wincmd reg add 'HKCU\Software\Microsoft\Windows\Windows Error Reporting' /v DontShowUI /t REG_DWORD /d 1 /f >/dev/null
  wincmd reg add 'HKLM\SOFTWARE\Microsoft\Windows\Windows Error Reporting\LocalDumps\srcds.exe' /v DumpFolder /t REG_EXPAND_SZ /d "$(cygpath -w "${DUMP_DIR}")" /f >/dev/null \
    && wincmd reg add 'HKLM\SOFTWARE\Microsoft\Windows\Windows Error Reporting\LocalDumps\srcds.exe' /v DumpType /t REG_DWORD /d 1 /f >/dev/null \
    || echo "(no LocalDumps: not elevated)"
else
# Wine prefix without crash dialog, so winedbg --auto prints the backtrace
if [[ ! -d "${WINEPREFIX}" ]]; then
  wineboot -i >"${SERVER_DIR}/wineboot.log" 2>&1 || { tail -n 20 "${SERVER_DIR}/wineboot.log"; fail "wineboot failed (WINEPREFIX=${WINEPREFIX})"; }
fi
wine reg add 'HKCU\Software\Wine\WineDbg' /v ShowCrashDialog /t REG_DWORD /d 0 /f >"${SERVER_DIR}/winereg.log" 2>&1 \
  || { tail -n 20 "${SERVER_DIR}/winereg.log"; fail "wine reg add failed (WINEPREFIX=${WINEPREFIX})"; }
wineserver -w || true
fi

if [[ "${DHOOKS_PROBE_SECS}" -gt 0 ]]; then
  cp -f "${ROOT}/testing/plugins/css34_dhooks_probe.sp" "${SM_DIR}/scripting/"
  cp -f "${ROOT}/testing/plugins/gamedata/css34_dhooks_probe.games.txt" "${SM_DIR}/gamedata/"
  (cd "${SM_DIR}/scripting" && winexe ./spcomp.exe css34_dhooks_probe.sp -i include -o ../plugins/css34_dhooks_probe.smx) \
    >"${SERVER_DIR}/spcomp.log" 2>&1 || { cat "${SERVER_DIR}/spcomp.log"; fail "spcomp.exe failed for css34_dhooks_probe.sp"; }
  [[ -f "${SM_DIR}/plugins/css34_dhooks_probe.smx" ]] || { cat "${SERVER_DIR}/spcomp.log"; fail "css34_dhooks_probe.smx missing"; }
  echo "==> css34_dhooks_probe.smx compiled"
fi

if [[ "${NATIVE}" == 1 ]]; then
  cleanup() { wincmd taskkill /F /IM srcds.exe >/dev/null 2>&1 || true; }
else
  Xvfb "${DISPLAY}" -screen 0 800x600x16 >/dev/null 2>&1 &
  XVFB_PID=$!
  cleanup() { wineserver -k >/dev/null 2>&1 || true; kill "${XVFB_PID}" 2>/dev/null || true; }
fi
trap cleanup EXIT
sleep 2

cd "${SERVER_DIR}"
rm -f cstrike/console.log
SRCDS_ARGS=(-console -condebug -game cstrike -insecure -nohltv +maxplayers 12
  +rcon_password "${RCON_PASSWORD}" +ip 127.0.0.1 +map "${MAP}")
if [[ "${NATIVE}" == 1 ]]; then
  # srcds -console needs a real console for input: started from Git Bash its stdin is a
  # pipe and CTextConsoleWin32 spins on GetNumberOfConsoleInputEvents before the map
  # loads. Start-Process gives it its own console window (output: -condebug console.log).
  wincmd powershell.exe -NoProfile -Command "Start-Process -FilePath '$(cygpath -w "${SERVER_DIR}/srcds.exe")' -WorkingDirectory '$(cygpath -w "${SERVER_DIR}")' -ArgumentList '${SRCDS_ARGS[*]}'"
else
  wine ./srcds.exe "${SRCDS_ARGS[@]}" >"${WINE_LOG}" 2>&1 &
fi

rcon() { "${PY}" "${ROOT}/testing/scripts/rcon.py" 127.0.0.1 "${RCON_PASSWORD}" "$@"; }
deadline=$((SECONDS + BOOT_SECS))
until rcon "echo css34-up" 2>/dev/null | grep -q css34-up; do
  (( SECONDS < deadline )) || fail "server did not answer RCON within ${BOOT_SECS}s"
  sleep 3
done
echo "==> srcds.exe answers RCON"

IFS=',' read -r -a load <<<"${LOAD_EXTS:-}"
for e in "${load[@]}"; do
  [[ -n "$e" ]] || continue
  rcon "sm exts load ${e}"
done
# DHooks ships in sm12/sm13 packages (dhooks.ext.dll) and, for the 2.ep1 core
# only, in the dual-core SM 1.11 package (dhooks.ext.2.ep1.dll).
if [[ "${DHOOKS_EXPECT}" == 1 ]]; then
  case ",${LOAD_EXTS:-}," in
    *,dhooks,*) ;;
    *) rcon "sm exts load dhooks" ;;
  esac
fi

out="$(rcon "meta version" "meta list" "sm version" "sm exts list" "sm plugins list")"
echo "$out"
grep -q "Metamod:Source version ${MM_VERSION_EXPECT}" <<<"$out" || fail "Metamod ${MM_VERSION_EXPECT} not reported"
grep -q "SourceMod Version: ${SM_VERSION_EXPECT}" <<<"$out" || fail "SourceMod ${SM_VERSION_EXPECT} not reported"
if [[ -n "${MM_REV_EXPECT:-}" ]]; then
  grep -q "+${MM_REV_EXPECT}" <<<"$out" || fail "meta version missing +${MM_REV_EXPECT}"
  if [[ -n "${MM_COMMIT_EXPECT:-}" ]]; then
    grep -q "Build ID: ${MM_REV_EXPECT}:${MM_COMMIT_EXPECT:0:7}" <<<"$out" \
      || fail "meta Build ID ${MM_REV_EXPECT}:${MM_COMMIT_EXPECT:0:7} not reported"
  fi
fi
require_exts() {
  local list="$1" e
  IFS=',' read -r -a exts <<<"${EXPECT_EXTS}"
  for e in "${exts[@]}"; do
    [[ -n "$e" ]] || continue
    # A bare grep -q under set -e aborts the caller when this function's
    # status is the miss (1). Keep the failure inside the if.
    if ! grep -q "\] ${e} (" <<<"$list"; then
      fail "extension '${e}' not loaded"
    fi
  done
  if [[ "${DHOOKS_EXPECT}" == 1 ]]; then
    if ! grep -q "\] DHooks (" <<<"$list"; then
      fail "extension 'DHooks' not loaded"
    fi
  elif grep -q "\] DHooks (" <<<"$list"; then
    fail "DHooks loaded, but this Metamod runs a core without DHooks"
  fi
  if grep -qi "<FAILED>\|<ERROR>" <<<"$list"; then
    fail "an extension or plugin failed to load"
  fi
  return 0
}
require_exts "$out"

if [[ "${DHOOKS_PROBE_SECS}" -gt 0 ]]; then
  echo "==> Playing ${DHOOKS_PROBE_SECS}s with bots (DHooks probe)"
  cp -f "${ROOT}/testing/cfg/botplay-server.cfg" "${SERVER_DIR}/cstrike/cfg/"
  rcon "exec botplay-server.cfg" "bot_quota 8" "mp_restartgame 1" >/dev/null
  end=$((SECONDS + DHOOKS_PROBE_SECS))
  while (( SECONDS < end )); do
    rcon "echo css34-alive" 2>/dev/null | grep -q css34-alive || fail "server stopped answering during the DHooks probe"
    sleep 10
  done
  probe="$(grep -h '\[css34_dhooks_probe\] round=' "${SM_DIR}"/logs/L*.log 2>/dev/null | tail -n1 || true)"
  echo "${probe:-no probe line}"
  [[ -n "${probe}" ]] || fail "no [css34_dhooks_probe] round= line (no round ended?)"
  field() { grep -Eo " $1=[0-9]+" <<<"${probe}" | grep -Eo '[0-9]+' | tail -n1; }
  [[ "$(field available)" == "1" && "$(field setup)" == "1" ]] || fail "DHooks probe did not set up"
  for f in vhook detour eye step speed; do
    [[ "$(field "$f")" -ge 1 ]] || fail "DHooks probe: no ${f} hits"
  done
  for f in eye_bad step_bad speed_bad; do
    [[ "$(field "$f")" -eq 0 ]] || fail "DHooks probe: ${f}=$(field "$f")"
  done
  echo "==> DHooks probe OK on Windows"
fi

# Level change: runs LevelShutdown / LevelInit hooks and entity teardown again
rcon "changelevel ${MAP2}" >/dev/null || true
sleep 5
deadline=$((SECONDS + BOOT_SECS))
until rcon "echo css34-up2" 2>/dev/null | grep -q css34-up2; do
  (( SECONDS < deadline )) || fail "server did not come back after changelevel ${MAP2}"
  sleep 3
done
out="$(rcon "status" "sm exts list")"
echo "$out"
grep -q "map     :  ${MAP2}" <<<"$out" || fail "map is not ${MAP2} after changelevel"
require_exts "$out"

rcon "quit" >/dev/null 2>&1 || true
if [[ "${NATIVE}" == 1 ]]; then echo "Windows smoke test PASSED"; else echo "Wine smoke test PASSED"; fi
