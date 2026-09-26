#!/usr/bin/env bash
# Boot the Windows CS:S v34 dedicated server (srcds.exe) under Wine with the
# Windows Metamod + SourceMod packages and probe them over RCON.
#
# Inputs (env):
#   SM_WIN_PACKAGE / MM_WIN_PACKAGE  Windows zips (sourcemod-*-windows.zip, mmsource-*-windows.zip)
#   SERVER_TGZ    optional prepared server tree (test-server.yml prepare-server); game content only
#   PDB_DIR       optional directory of .pdb files, copied next to the matching .dll so a crash
#                 backtrace (winedbg --auto) is symbolized
#   SM_VERSION_EXPECT / MM_VERSION_EXPECT, EXPECT_EXTS (comma list of `sm exts list` names),
#   LOAD_EXTS     comma list of extensions to `sm exts load` first (no plugin requires them)
#   DHOOKS_PROBE_SECS  > 0: compile css34_dhooks_probe.sp with the package's spcomp.exe, play
#                 that long with bots and require the probe's hooks to fire with clean values
#                 (skipped when the package has no dhooks.ext.dll)
# Needs: wine32 (i386), xvfb, unzip, python3.
set -euo pipefail

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
export WINEPREFIX="${WINEPREFIX:-${HOME}/.wine-css34}" WINEARCH=win32 WINEDEBUG="${WINEDEBUG:-err+all,+seh,+loaddll}" DISPLAY="${DISPLAY:-:97}"
WINE_LOG="${SERVER_DIR}/wine.log"

fail() { echo "FAIL: $*" >&2; dump; exit 1; }
dump() {
  echo "==== engine console.log (tail) ===="; tail -n 60 "${SERVER_DIR}/cstrike/console.log" 2>/dev/null || true
  echo "==== SourceMod logs ===="; tail -n 40 "${SERVER_DIR}"/cstrike/addons/sourcemod/logs/*.log 2>/dev/null || true
  echo "==== exceptions ===="; python3 "${ROOT}/testing/scripts/wine-crash-report.py" "${WINE_LOG}" "${SERVER_DIR}" || true
  echo "==== wine log (errors) ===="; grep ':err:' "${WINE_LOG}" 2>/dev/null | tail -n 40 || true
}

mkdir -p "${CACHE_DIR}"
rm -rf "${SERVER_DIR}"; mkdir -p "${SERVER_DIR}"
if [[ -n "${SERVER_TGZ:-}" && -f "${SERVER_TGZ}" ]]; then
  tar -xzf "${SERVER_TGZ}" -C "${SERVER_DIR}" ./cstrike ./hl2 ./platform
else
  [[ -s "${CACHE_DIR}/srcds_css34_4044.zip" ]] || curl -fL --retry 5 -o "${CACHE_DIR}/srcds_css34_4044.zip" https://bitbucket.org/rom4s/other.get/downloads/srcds_css34_4044.zip
  unzip -q "${CACHE_DIR}/srcds_css34_4044.zip" -d "${SERVER_DIR}"
fi
[[ -s "${CACHE_DIR}/srcds_css34_w_a.zip" ]] || curl -fL --retry 5 -o "${CACHE_DIR}/srcds_css34_w_a.zip" "${WIN_BIN_ZIP_URL}"
unzip -qo "${CACHE_DIR}/srcds_css34_w_a.zip" -d "${SERVER_DIR}"
# Only the Windows server binaries and addons from here on
rm -rf "${SERVER_DIR}/cstrike/addons" "${SERVER_DIR}/cstrike/cfg/sourcemod"
cat >"${SERVER_DIR}/cstrike/cfg/server.cfg" <<'CFG'
hostname sourcemod-css34-wine-ci
sv_lan 1
mp_timelimit 0
CFG

# Windows zips may use '\' separators; unzip converts them (exit code 1 = warning)
for z in "${MM_WIN_PACKAGE:?}" "${SM_WIN_PACKAGE:?}"; do
  unzip -qo "$z" -d "${SERVER_DIR}/cstrike" || [[ $? -eq 1 ]]
done
[[ -f "${SERVER_DIR}/cstrike/addons/metamod.vdf" ]] || fail "metamod.vdf missing after install"

DHOOKS_PROBE_SECS="${DHOOKS_PROBE_SECS:-0}"
SM_DIR="${SERVER_DIR}/cstrike/addons/sourcemod"
if [[ "${DHOOKS_PROBE_SECS}" -gt 0 && ! -f "${SM_DIR}/extensions/dhooks.ext.dll" ]]; then
  echo "==> No dhooks.ext.dll in the package, skipping the DHooks probe"
  DHOOKS_PROBE_SECS=0
fi

if [[ -n "${PDB_DIR:-}" && -d "${PDB_DIR}" ]]; then
  while IFS= read -r dll; do
    pdb="${PDB_DIR}/$(basename "${dll%.dll}").pdb"
    [[ -f "$pdb" ]] && cp -f "$pdb" "$(dirname "$dll")/"
  done < <(find "${SERVER_DIR}/cstrike/addons" -name '*.dll')
fi

# Wine prefix without crash dialog, so winedbg --auto prints the backtrace
if [[ ! -d "${WINEPREFIX}" ]]; then
  wineboot -i >/dev/null 2>&1 || true
fi
wine reg add 'HKCU\Software\Wine\WineDbg' /v ShowCrashDialog /t REG_DWORD /d 0 /f >/dev/null 2>&1
wineserver -w || true

if [[ "${DHOOKS_PROBE_SECS}" -gt 0 ]]; then
  cp -f "${ROOT}/testing/plugins/css34_dhooks_probe.sp" "${SM_DIR}/scripting/"
  cp -f "${ROOT}/testing/plugins/gamedata/css34_dhooks_probe.games.txt" "${SM_DIR}/gamedata/"
  (cd "${SM_DIR}/scripting" && wine spcomp.exe css34_dhooks_probe.sp -i include -o ../plugins/css34_dhooks_probe.smx) \
    >"${SERVER_DIR}/spcomp.log" 2>&1 || { cat "${SERVER_DIR}/spcomp.log"; fail "spcomp.exe failed for css34_dhooks_probe.sp"; }
  [[ -f "${SM_DIR}/plugins/css34_dhooks_probe.smx" ]] || { cat "${SERVER_DIR}/spcomp.log"; fail "css34_dhooks_probe.smx missing"; }
  echo "==> css34_dhooks_probe.smx compiled"
fi

Xvfb "${DISPLAY}" -screen 0 800x600x16 >/dev/null 2>&1 &
XVFB_PID=$!
cleanup() { wineserver -k >/dev/null 2>&1 || true; kill "${XVFB_PID}" 2>/dev/null || true; }
trap cleanup EXIT
sleep 2

cd "${SERVER_DIR}"
rm -f cstrike/console.log
wine srcds.exe -console -condebug -game cstrike -insecure -nohltv +maxplayers 12 \
  +rcon_password "${RCON_PASSWORD}" +ip 127.0.0.1 +map "${MAP}" >"${WINE_LOG}" 2>&1 &

rcon() { python3 "${ROOT}/testing/scripts/rcon.py" 127.0.0.1 "${RCON_PASSWORD}" "$@"; }
deadline=$((SECONDS + BOOT_SECS))
until rcon "echo css34-up" 2>/dev/null | grep -q css34-up; do
  (( SECONDS < deadline )) || fail "server did not answer RCON within ${BOOT_SECS}s"
  sleep 3
done
echo "==> srcds.exe answers RCON"

IFS=',' read -r -a load <<<"${LOAD_EXTS:-}"
for e in "${load[@]}"; do
  rcon "sm exts load ${e}"
done

out="$(rcon "meta version" "meta list" "sm version" "sm exts list" "sm plugins list")"
echo "$out"
grep -q "Metamod:Source version ${MM_VERSION_EXPECT}" <<<"$out" || fail "Metamod ${MM_VERSION_EXPECT} not reported"
grep -q "SourceMod Version: ${SM_VERSION_EXPECT}" <<<"$out" || fail "SourceMod ${SM_VERSION_EXPECT} not reported"
IFS=',' read -r -a exts <<<"${EXPECT_EXTS}"
for e in "${exts[@]}"; do
  grep -q "\] ${e} (" <<<"$out" || fail "extension '${e}' not loaded"
done
grep -qi "<FAILED>\|<ERROR>" <<<"$out" && fail "an extension or plugin failed to load"

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

rcon "quit" >/dev/null 2>&1 || true
echo "Wine smoke test PASSED"
