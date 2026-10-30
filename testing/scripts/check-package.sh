#!/usr/bin/env bash
# Static checks on a SourceMod css34 package before/without a full server boot.
set -euo pipefail

SM_PACKAGE="${SM_PACKAGE:?SM_PACKAGE is required}"
TMP="$(mktemp -d)"
cleanup() { rm -rf "${TMP}"; }
trap cleanup EXIT

tar -xzf "${SM_PACKAGE}" -C "${TMP}"
MM_SO="${TMP}/addons/sourcemod/bin/sourcemod_mm_i486.so"
CORE_SO="${TMP}/addons/sourcemod/bin/sourcemod.2.ep1.so"
if [[ ! -f "${CORE_SO}" ]]; then
  CORE_SO="${TMP}/addons/sourcemod/bin/sourcemod.1.ep1.so"
fi
LOGIC_SO="${TMP}/addons/sourcemod/bin/sourcemod.logic.so"
JIT_SO="${TMP}/addons/sourcemod/bin/sourcepawn.jit.x86.so"
SDKHOOKS_GAMEDATA="${TMP}/addons/sourcemod/gamedata/sdkhooks.games"
GAMEDATA_ROOT="${TMP}/addons/sourcemod/gamedata"
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

fail=0
STATIC_SP=0

echo "==> Checking self-contained CS:S v34 gamedata"
if ! python3 "${REPO_ROOT}/testing/scripts/check-css34-gamedata.py" "${GAMEDATA_ROOT}"; then
  fail=1
fi

if [[ ! -f "${MM_SO}" ]]; then
  echo "FAIL: missing sourcemod_mm_i486.so" >&2
  exit 1
fi
if [[ ! -f "${CORE_SO}" ]]; then
  echo "FAIL: missing sourcemod.2.ep1.so / sourcemod.1.ep1.so" >&2
  exit 1
fi
if [[ ! -f "${LOGIC_SO}" ]]; then
  echo "FAIL: missing sourcemod.logic.so" >&2
  exit 1
fi
if [[ ! -f "${JIT_SO}" ]]; then
  echo "OK: no sourcepawn.jit.x86.so (static SourcePawn in logic.so, SM 1.13+)"
  STATIC_SP=1
else
  STATIC_SP=0
fi

echo "==> Checking CS:S v34 SDKHooks gamedata"
for file in common.games.txt game.cstrike.txt master.games.txt; do
  if [[ -f "${SDKHOOKS_GAMEDATA}/${file}" ]]; then
    echo "OK: sdkhooks.games/${file} present"
  else
    echo "FAIL: missing sdkhooks.games/${file}" >&2
    fail=1
  fi
done
if [[ -f "${SDKHOOKS_GAMEDATA}/master.games.txt" ]] \
  && grep -Fq '"game.cstrike.txt"' "${SDKHOOKS_GAMEDATA}/master.games.txt"; then
  echo "OK: SDKHooks master loads game.cstrike.txt"
else
  echo "FAIL: SDKHooks master does not load game.cstrike.txt" >&2
  fail=1
fi
if [[ -f "${SDKHOOKS_GAMEDATA}/game.cstrike.txt" ]] \
  && grep -Fq '"OnTakeDamage"' "${SDKHOOKS_GAMEDATA}/game.cstrike.txt"; then
  echo "OK: SDKHooks CS:S gamedata contains OnTakeDamage"
else
  echo "FAIL: SDKHooks CS:S gamedata lacks OnTakeDamage" >&2
  fail=1
fi

# SMAC smac_wallhack hooks these; a missing offset → "Hook type not supported"
# (1.13.0.7394 release shipped without game.cstrike.txt, see README).
for hook in SetTransmit Think Weapon_Equip Weapon_Drop PreThink PostThink; do
  if [[ -f "${SDKHOOKS_GAMEDATA}/game.cstrike.txt" ]] \
    && grep -Fq "\"${hook}\"" "${SDKHOOKS_GAMEDATA}/game.cstrike.txt"; then
    echo "OK: SDKHooks CS:S gamedata contains ${hook}"
  else
    echo "FAIL: SDKHooks CS:S gamedata lacks ${hook}" >&2
    fail=1
  fi
done

echo "==> Checking ready-to-run layout (plain tar -x over cstrike/)"
SM_ROOT="${TMP}/addons/sourcemod"
if [[ -f "${TMP}/addons/metamod/sourcemod.vdf" ]]; then
  echo "OK: addons/metamod/sourcemod.vdf present"
else
  echo "FAIL: missing addons/metamod/sourcemod.vdf" >&2
  fail=1
fi
if grep -Eq '"DisableAutoUpdate"[[:space:]]+"yes"' "${SM_ROOT}/configs/core.cfg" 2>/dev/null; then
  echo "OK: core.cfg DisableAutoUpdate=yes"
else
  echo "FAIL: core.cfg does not disable the auto updater" >&2
  fail=1
fi
while IFS= read -r -d '' bin; do
  if [[ ! -x "${bin}" ]]; then
    echo "FAIL: ${bin#"${TMP}"/} is not executable in the tarball" >&2
    fail=1
  fi
done < <(find "${SM_ROOT}/bin" "${SM_ROOT}/extensions" -type f -name '*.so' -print0)
if [[ -f "${SM_ROOT}/scripting/spcomp" && ! -x "${SM_ROOT}/scripting/spcomp" ]]; then
  echo "FAIL: scripting/spcomp is not executable in the tarball" >&2
  fail=1
fi
# SM 1.12+ (single 2.ep1 core) geoip.ext needs a *.mmdb; 1.11 dual-core uses GeoIP.dat.
if [[ -f "${SM_ROOT}/extensions/geoip.ext.so" && ! -f "${SM_ROOT}/bin/sourcemod.1.ep1.so" ]]; then
  mmdb="${SM_ROOT}/configs/geoip/GeoLite2-Country.mmdb"
  if [[ ! -s "${mmdb}" ]]; then
    echo "FAIL: missing configs/geoip/GeoLite2-Country.mmdb (SM 1.12+ geoip.ext)" >&2
    fail=1
  elif [[ "$(stat -c %a "${mmdb}")" != *4 && "$(stat -c %a "${mmdb}")" != *6 ]]; then
    echo "FAIL: GeoLite2-Country.mmdb is not world-readable ($(stat -c %a "${mmdb}"))" >&2
    fail=1
  else
    echo "OK: GeoLite2-Country.mmdb present and readable"
  fi
fi
manifest="${SM_ROOT}/css34-package.json"
if [[ ! -f "${manifest}" ]]; then
  echo "FAIL: missing addons/sourcemod/css34-package.json" >&2
  fail=1
elif ! python3 - "${manifest}" "${TMP}" <<'PY'
import json, sys, os
d = json.load(open(sys.argv[1]))
tmp_dir = sys.argv[2]
need = ["line", "sm_version", "sm_commit", "mm_version", "mm_commit",
        "extension_api", "extension_api_min", "metamod_binary", "build_date"]
missing = [k for k in need if k not in d or d[k] in ("", None)]
if missing:
    sys.exit("FAIL: css34-package.json missing " + ", ".join(missing))
if d["metamod_binary"] not in ("metamod.1.ep1", "metamod.2.ep1"):
    sys.exit("FAIL: css34-package.json metamod_binary=" + d["metamod_binary"])
if not (int(d["extension_api_min"]) <= int(d["extension_api"])):
    sys.exit("FAIL: css34-package.json extension_api_min > extension_api")

# Dual-core checks
is_dual = (os.path.exists(os.path.join(tmp_dir, "addons/sourcemod/bin/sourcemod.1.ep1.so")) and
           os.path.exists(os.path.join(tmp_dir, "addons/sourcemod/bin/sourcemod.2.ep1.so"))) or d.get("line") == "sm11-oldstable"

if is_dual:
    if d.get("cores") != ["1.ep1", "2.ep1"]:
        sys.exit("FAIL: css34-package.json missing cores=['1.ep1', '2.ep1'] in dual package")
    if d.get("metamod_binaries") != {"1.ep1": "metamod.1.ep1", "2.ep1": "metamod.2.ep1"}:
        sys.exit("FAIL: css34-package.json missing metamod_binaries mapping in dual package")
    if d.get("metamod_binary") != "metamod.2.ep1":
        sys.exit("FAIL: css34-package.json default metamod_binary must be metamod.2.ep1 in dual package")

print("OK: css34-package.json", json.dumps(d, sort_keys=True))
PY
then
  fail=1
fi

# Runtime PLAPI validation runs in the required plapi-runtime CI job,
# with the pinned game server providers and a working 32-bit compiler.

if [[ -f "${TMP}/addons/sourcemod/bin/sourcemod.1.ep1.so" && -f "${TMP}/addons/sourcemod/bin/sourcemod.2.ep1.so" ]]; then
  if [[ -f "${TMP}/addons/sourcemod/extensions/dhooks.ext.2.ep1.so" ]]; then
    echo "OK: dhooks.ext.2.ep1.so present in dual package"
  else
    echo "FAIL: missing dhooks.ext.2.ep1.so in dual package" >&2
    fail=1
  fi
  if [[ -f "${TMP}/addons/sourcemod/extensions/dhooks.ext.so" ]]; then
    echo "FAIL: unexpected dhooks.ext.so in dual package (must be dhooks.ext.2.ep1.so)" >&2
    fail=1
  fi
fi

echo "==> Checking Metamod bridge exports"
if nm -D "${MM_SO}" 2>/dev/null | grep -E ' T CreateInterface([[:space:]]|$)' >/dev/null; then
  echo "OK: CreateInterface export present (MM:S 1.10 V1 bridge)"
elif nm -D "${MM_SO}" 2>/dev/null | grep 'CreateInterface_MMS' >/dev/null; then
  echo "OK: CreateInterface_MMS present (MM:S 1.12 modern load path; no V1 CreateInterface needed)"
else
  echo "FAIL: sourcemod_mm_i486.so missing CreateInterface / CreateInterface_MMS" >&2
  echo "      present symbols:" >&2
  nm -D "${MM_SO}" 2>/dev/null | grep CreateInterface || true
  fail=1
fi

if nm -D "${MM_SO}" 2>/dev/null | grep 'CreateInterface_MMS' >/dev/null; then
  echo "OK: CreateInterface_MMS present"
else
  echo "FAIL: missing CreateInterface_MMS" >&2
  fail=1
fi

echo "==> Checking logic module exports"
logic_dynsyms="$(nm -D "${LOGIC_SO}" 2>/dev/null || true)"
if printf '%s\n' "${logic_dynsyms}" | grep -F ' T logic_load' >/dev/null; then
  echo "OK: logic_load export present"
else
  echo "FAIL: sourcemod.logic.so missing logic_load" >&2
  fail=1
fi

logic_needed="$(readelf -d "${LOGIC_SO}" 2>/dev/null | awk '/\(NEEDED\)/ {print $NF}' | tr -d '[]')"
for lib in libpthread.so.0 librt.so.1; do
  if printf '%s\n' "${logic_needed}" | grep -qx "${lib}"; then
    echo "OK: sourcemod.logic.so NEEDED ${lib}"
  else
    echo "WARN: sourcemod.logic.so missing DT_NEEDED ${lib} (rom4s lists both)"
  fi
done

echo "==> Checking sourcepawn.jit pthread/rt (required on glibc < 2.34)"
if [[ "${STATIC_SP}" -eq 1 ]]; then
  echo "SKIP: static SourcePawn — pthread/rt checked on logic.so only"
else
jit_needed="$(readelf -d "${JIT_SO}" 2>/dev/null | awk '/\(NEEDED\)/ {print $NF}' | tr -d '[]')"
for lib in libpthread.so.0 librt.so.1; do
  if printf '%s\n' "${jit_needed}" | grep -qx "${lib}"; then
    echo "OK: sourcepawn.jit.x86.so NEEDED ${lib}"
  else
    echo "FAIL: sourcepawn.jit.x86.so missing DT_NEEDED ${lib} (Debian 11 cannot resolve pthread_key_create)" >&2
    fail=1
  fi
done
fi
if printf '%s\n' "${logic_needed}" | grep -qx 'libstdc++.so.6'; then
  echo "WARN: sourcemod.logic.so links libstdc++.so.6 dynamically (rom4s embeds static libstdc++; hang risk)"
else
  echo "OK: sourcemod.logic.so does not DT_NEEDED libstdc++.so.6 (static embed like rom4s)"
fi
logic_cxx11="$(printf '%s\n' "${logic_dynsyms}" | grep -c '__cxx11' || true)"
if [[ "${logic_cxx11}" -gt 0 ]]; then
  if [[ "${STATIC_SP}" -eq 1 ]]; then
    echo "WARN: logic.so exports ${logic_cxx11} __cxx11 symbols (static SourcePawn embed; verify on manylinux smoke)"
  else
    echo "FAIL: logic.so exports ${logic_cxx11} C++11 std::string ABI symbols (rom4s logic has none)" >&2
    fail=1
  fi
else
  echo "OK: logic.so has no __cxx11 ABI exports"
fi

logic_sized_delete="$(readelf -Ws "${LOGIC_SO}" 2>/dev/null | awk '$7=="UND" && ($8=="_ZdlPvj" || $8=="_ZdaPvj") {print $8}' || true)"
if [[ -n "${logic_sized_delete}" ]]; then
  echo "FAIL: logic.so has unresolved sized-delete imports (dlopen into srcds fails): ${logic_sized_delete}" >&2
  fail=1
else
  echo "OK: logic.so has no UND _ZdlPvj/_ZdaPvj sized-delete imports"
fi

logic_thread_und="$(readelf -Ws "${LOGIC_SO}" 2>/dev/null | awk '$7=="UND" && $8 ~ /^_ZNSt6thread/' || true)"
if [[ -n "${logic_thread_und}" ]]; then
  echo "FAIL: logic.so has unresolved libstdc++ std::thread symbols (static SP link order)" >&2
  printf '%s\n' "${logic_thread_und}" | head -5 | sed 's/^/        /' >&2
  fail=1
else
  echo "OK: logic.so has no UND std::thread symbols"
fi

logic_t_count="$(printf '%s\n' "${logic_dynsyms}" | grep -c ' T ' || true)"
if [[ "${logic_t_count}" -lt 1 ]]; then
  echo "FAIL: logic.so exports no defined symbols" >&2
  fail=1
else
  echo "OK: logic.so exports ${logic_t_count} defined symbols"
fi

# Portable stand-in for `objdump -T --defined-only`: drop *UND* rows.
# A missing objdump dump is a failure, not a zero count.
logic_dyn="$(objdump -T "${LOGIC_SO}" 2>/dev/null || true)"
if [[ -z "${logic_dyn}" ]]; then
  echo "FAIL: objdump -T produced no dynamic symbols for sourcemod.logic.so" >&2
  fail=1
  logic_std_exports=0
else
  logic_std_exports="$(printf '%s\n' "${logic_dyn}" | awk '$0 !~ /\*UND\*/' | c++filt | grep -cE 'std::|__cxxabiv1' || true)"
fi
if [[ "${logic_std_exports}" -ne 0 ]]; then
  echo "FAIL: sourcemod.logic.so exports ${logic_std_exports} std::/__cxxabiv1 symbols (static libstdc++ leak)" >&2
  fail=1
else
  echo "OK: sourcemod.logic.so exports no std::/__cxxabiv1 symbols"
fi

echo "==> Checking DT_NEEDED for game libs (GetCVarIF / tier0)"
needed="$(readelf -d "${CORE_SO}" 2>/dev/null | awk '/\(NEEDED\)/ {print $NF}' | tr -d '[]')"
for lib in tier0_i486.so vstdlib_i486.so; do
  if printf '%s\n' "${needed}" | grep -qx "${lib}"; then
    echo "OK: ${CORE_SO##*/} NEEDED ${lib}"
  else
    echo "FAIL: ${CORE_SO##*/} missing DT_NEEDED ${lib} (empty link stubs / --as-needed)" >&2
    echo "      NEEDED entries:" >&2
    printf '%s\n' "${needed}" | sed 's/^/        /' >&2
    fail=1
  fi
done

echo "==> Checking ConVar is embedded from static tier1 (not imported from vstdlib)"
# Link order must put tier1_i486.a before vstdlib; otherwise FindCommand hangs on a
# circular engine cvar list. rom4s embeds these as T/B.
# Avoid `nm | grep -q` under pipefail (SIGPIPE from nm makes the pipeline fail).
core_dynsyms="$(nm -D "${CORE_SO}" 2>/dev/null || true)"
if printf '%s\n' "${core_dynsyms}" | grep -F ' T _ZN6ConVarC1EPKcS1_i' >/dev/null; then
  echo "OK: ConVar ctor is defined locally (static tier1)"
else
  echo "FAIL: ConVar ctor not embedded — likely linked from vstdlib (hang risk)" >&2
  printf '%s\n' "${core_dynsyms}" | grep 'ConVarC1' || true
  fail=1
fi
if printf '%s\n' "${core_dynsyms}" | grep -F ' B _ZN14ConCommandBase18s_pConCommandBasesE' >/dev/null; then
  echo "OK: ConCommandBase::s_pConCommandBases is local"
else
  echo "FAIL: missing local s_pConCommandBases" >&2
  fail=1
fi

if printf '%s\n' "${core_dynsyms}" | grep -E ' U GetCVarIF$' >/dev/null; then
  echo "OK: GetCVarIF is an undefined ref (resolved via vstdlib at runtime)"
elif printf '%s\n' "${core_dynsyms}" | grep -F 'GetCVarIF' >/dev/null; then
  echo "OK: GetCVarIF present in dynamic symbol table"
  printf '%s\n' "${core_dynsyms}" | grep GetCVarIF || true
else
  echo "WARN: GetCVarIF not found in dynamic symbols (may still be fine if unused)"
fi

echo "==> Checking engine interface strings (css34 expects EP1, not OB CSS)"
# Avoid `strings | grep -q` under `set -o pipefail` (SIGPIPE makes the pipeline "fail").
iface_strings="$(strings "${CORE_SO}" 2>/dev/null || true)"
if printf '%s\n' "${iface_strings}" | grep -F 'ServerGameDLL006' >/dev/null; then
  echo "OK: ServerGameDLL006 present"
else
  echo "FAIL: ${CORE_SO##*/} missing ServerGameDLL006 (ep1c/SDK mismatch)" >&2
  fail=1
fi
if printf '%s\n' "${iface_strings}" | grep -F 'VEngineServer023' >/dev/null; then
  echo "FAIL: ${CORE_SO##*/} still embeds VEngineServer023 (SE_CSS shim; css34 needs EP1 path)" >&2
  fail=1
else
  echo "OK: no VEngineServer023 shim"
fi
if printf '%s\n' "${iface_strings}" | grep -F 'VEngineServer021' >/dev/null; then
  echo "OK: VEngineServer021 present"
else
  echo "FAIL: missing VEngineServer021" >&2
  fail=1
fi

echo "==> Checking GLIBC floor and libstdc++ linkage on every ELF"
GLIBC_FLOOR="${GLIBC_FLOOR:-2.17}"
GLIBCXX_SPCOMP_MAX="${GLIBCXX_SPCOMP_MAX:-3.4.19}"
version_gt() {
  [[ "$1" != "$2" && "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -1)" == "$1" ]]
}
max_glibc=""
while IFS= read -r -d '' elf; do
  readelf -h "${elf}" >/dev/null 2>&1 || continue
  rel="${elf#"${TMP}"/}"
  base="$(basename "${elf}")"
  elf_glibc="$(
    objdump -T "${elf}" 2>/dev/null \
      | grep -oE 'GLIBC_[0-9.]+' \
      | sed 's/GLIBC_//' \
      | sort -V \
      | tail -1 || true
  )"
  if [[ -n "${elf_glibc}" ]]; then
    if [[ -z "${max_glibc}" ]] || version_gt "${elf_glibc}" "${max_glibc}"; then
      max_glibc="${elf_glibc}"
    fi
    if version_gt "${elf_glibc}" "${GLIBC_FLOOR}"; then
      echo "FAIL: ${rel} requires GLIBC_${elf_glibc} > ${GLIBC_FLOOR}" >&2
      fail=1
    fi
  fi
  if readelf -d "${elf}" 2>/dev/null | grep -q 'libstdc++\.so\.6'; then
    if [[ "${base}" == "spcomp" || "${base}" == "oldspcomp" ]]; then
      elf_cxx="$(
        objdump -T "${elf}" 2>/dev/null \
          | grep -oE 'GLIBCXX_[0-9.]+' \
          | sed 's/GLIBCXX_//' \
          | sort -V \
          | tail -1 || true
      )"
      if [[ -n "${elf_cxx}" ]] && version_gt "${elf_cxx}" "${GLIBCXX_SPCOMP_MAX}"; then
        echo "FAIL: spcomp requires GLIBCXX_${elf_cxx} > ${GLIBCXX_SPCOMP_MAX}" >&2
        fail=1
      else
        echo "OK: spcomp links libstdc++.so.6 dynamically (GLIBCXX_${elf_cxx:-none} <= ${GLIBCXX_SPCOMP_MAX})"
      fi
    else
      echo "FAIL: ${rel} NEEDED libstdc++.so.6 (libstdc++ must be static except spcomp)" >&2
      fail=1
    fi
  fi
done < <(find "${TMP}" -type f -print0)
echo "Highest GLIBC symbol version referenced: ${max_glibc:-none} (floor ${GLIBC_FLOOR})"

if ! python3 "$(dirname "$0")/check-unversioned-imports.py" "${TMP}"; then
  fail=1
fi

if [[ "${fail}" -ne 0 ]]; then
  echo "Package ABI check FAILED"
  exit 1
fi
echo "Package ABI check PASSED"
