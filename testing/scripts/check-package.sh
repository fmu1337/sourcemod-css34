#!/usr/bin/env bash
# Static checks on a SourceMod css34 package before/without a full server boot.
set -euo pipefail

SM_PACKAGE="${SM_PACKAGE:?SM_PACKAGE is required}"
TMP="$(mktemp -d)"
cleanup() { rm -rf "${TMP}"; }
trap cleanup EXIT

tar -xzf "${SM_PACKAGE}" -C "${TMP}"
MM_SO="${TMP}/addons/sourcemod/bin/sourcemod_mm_i486.so"
CORE_SO="${TMP}/addons/sourcemod/bin/sourcemod.1.ep1.so"
LOGIC_SO="${TMP}/addons/sourcemod/bin/sourcemod.logic.so"

fail=0

if [[ ! -f "${MM_SO}" ]]; then
  echo "FAIL: missing sourcemod_mm_i486.so" >&2
  exit 1
fi
if [[ ! -f "${CORE_SO}" ]]; then
  echo "FAIL: missing sourcemod.1.ep1.so" >&2
  exit 1
fi
if [[ ! -f "${LOGIC_SO}" ]]; then
  echo "FAIL: missing sourcemod.logic.so" >&2
  exit 1
fi

echo "==> Checking Metamod bridge exports"
if nm -D "${MM_SO}" 2>/dev/null | grep -q ' T CreateInterface$'; then
  echo "OK: CreateInterface export present (needed by MM:S 1.10 / EP1)"
else
  echo "FAIL: sourcemod_mm_i486.so missing CreateInterface (MM:S 1.10 cannot load it)" >&2
  echo "      present symbols:" >&2
  nm -D "${MM_SO}" 2>/dev/null | grep CreateInterface || true
  fail=1
fi

if nm -D "${MM_SO}" 2>/dev/null | grep -q 'CreateInterface_MMS'; then
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
if printf '%s\n' "${logic_needed}" | grep -qx 'libstdc++.so.6'; then
  echo "WARN: sourcemod.logic.so links libstdc++.so.6 dynamically (rom4s embeds static libstdc++; hang risk)"
else
  echo "OK: sourcemod.logic.so does not DT_NEEDED libstdc++.so.6 (static embed like rom4s)"
fi
if printf '%s\n' "${logic_dynsyms}" | grep -q '__cxx11'; then
  echo "WARN: logic.so exports C++11 std::string ABI symbols (rom4s logic has none)"
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
  echo "FAIL: sourcemod.1.ep1.so missing ServerGameDLL006 (ep1c/SDK mismatch)" >&2
  fail=1
fi
if printf '%s\n' "${iface_strings}" | grep -F 'VEngineServer023' >/dev/null; then
  echo "FAIL: sourcemod.1.ep1.so still embeds VEngineServer023 (SE_CSS shim; css34 MM needs EP1 path)" >&2
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

echo "==> Checking GLIBC requirements (css34 targets old distros)"
max_glibc="$(
  objdump -T "${MM_SO}" "${CORE_SO}" 2>/dev/null \
    | grep -oE 'GLIBC_[0-9.]+' \
    | sed 's/GLIBC_//' \
    | sort -t. -k1,1n -k2,2n -k3,3n \
    | tail -n1 || true
)"
echo "Highest GLIBC symbol version referenced: ${max_glibc:-unknown}"
# Debian 10 = 2.28, Debian 9 = 2.24, CentOS 7 = 2.17. rom4s builds stay on 2.4-era symbols.
# Ubuntu 22.04 host builds typically pull 2.33/2.34 from system libc; that still loads on
# Debian 12+ / modern Rocky. Soft-warn so CreateInterface/DT_NEEDED stay the hard gates.
if [[ -n "${max_glibc}" ]]; then
  major="${max_glibc%%.*}"
  rest="${max_glibc#*.}"
  minor="${rest%%.*}"
  if [[ "${major}" -gt 2 || ( "${major}" -eq 2 && "${minor}" -ge 29 ) ]]; then
    echo "WARN: package requires GLIBC_${max_glibc} (>= 2.29); too new for Debian 8-10 / CentOS 7"
    echo "      Use the rom4s reference package on legacy distros; host-built packages need newer glibc."
  else
    echo "OK: GLIBC_${max_glibc} is within legacy-server range"
  fi
fi

if [[ "${fail}" -ne 0 ]]; then
  echo "Package ABI check FAILED"
  exit 1
fi
echo "Package ABI check PASSED"
