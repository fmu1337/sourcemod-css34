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
logic_cxx11="$(printf '%s\n' "${logic_dynsyms}" | grep -c '__cxx11' || true)"
if [[ "${logic_cxx11}" -gt 0 ]]; then
  echo "FAIL: logic.so exports ${logic_cxx11} C++11 std::string ABI symbols (rom4s logic has none)" >&2
  fail=1
else
  echo "OK: logic.so has no __cxx11 ABI exports"
fi

logic_t_count="$(printf '%s\n' "${logic_dynsyms}" | grep -c ' T ' || true)"
if [[ "${logic_t_count}" -lt 100 ]]; then
  echo "FAIL: logic.so exports only ${logic_t_count} defined symbols (rom4s ~285; missing libstdc++ EH exports?)" >&2
  fail=1
else
  echo "OK: logic.so exports ${logic_t_count} defined symbols (libstdc++ EH visible)"
fi

# Guard against rom4s logic splice masking in-tree build regressions.
REF_URL="${REFERENCE_SM_URL:-https://github.com/rom4s/sourcemod-css34/releases/download/v1.11.0.6572/sourcemod-1.11.0-git6572-css34-linux.tar.gz}"
ref_tmp="$(mktemp -d)"
if curl -fsSL -o "${ref_tmp}/ref.tar.gz" "${REF_URL}" \
  && tar -xzf "${ref_tmp}/ref.tar.gz" -C "${ref_tmp}" addons/sourcemod/bin/sourcemod.logic.so 2>/dev/null; then
  ref_logic="${ref_tmp}/addons/sourcemod/bin/sourcemod.logic.so"
  pkg_logic="${TMP}/logic-cmp.so"
  cp -f "${LOGIC_SO}" "${pkg_logic}"
  strip --strip-unneeded "${ref_logic}" 2>/dev/null || true
  strip --strip-unneeded "${pkg_logic}" 2>/dev/null || true
  if cmp -s "${pkg_logic}" "${ref_logic}"; then
    echo "FAIL: sourcemod.logic.so is byte-identical to stripped rom4s reference (logic splice mask)" >&2
    fail=1
  else
    echo "OK: logic.so is not a rom4s splice copy"
  fi
fi
rm -rf "${ref_tmp}"

echo "==> Checking logic.so dlopen (libstdc++ link sanity)"
if command -v gcc >/dev/null 2>&1; then
  dlopen_test="$(mktemp -t sm-logic-dlopen.XXXXXX.c)"
  dlopen_bin="$(mktemp -t sm-logic-dlopen.XXXXXX)"
  cat >"${dlopen_test}" <<'EOF'
#include <dlfcn.h>
#include <stdio.h>
int main(int argc, char **argv) {
  void *h = dlopen(argv[1], RTLD_NOW);
  if (!h) {
    fprintf(stderr, "%s\n", dlerror());
    return 1;
  }
  if (!dlsym(h, "logic_load")) {
    fprintf(stderr, "logic_load missing: %s\n", dlerror());
    return 2;
  }
  return 0;
}
EOF
  if gcc -m32 -o "${dlopen_bin}" "${dlopen_test}" -ldl 2>/dev/null \
    && "${dlopen_bin}" "${LOGIC_SO}" >/dev/null 2>&1; then
    echo "OK: logic.so dlopen + logic_load resolve"
  else
    echo "FAIL: logic.so failed dlopen (sized-delete / static libstdc++ mismatch?)" >&2
    gcc -m32 -o "${dlopen_bin}" "${dlopen_test}" -ldl 2>/dev/null || true
    "${dlopen_bin}" "${LOGIC_SO}" 2>&1 | sed 's/^/      /' >&2 || true
    fail=1
  fi
  rm -f "${dlopen_test}" "${dlopen_bin}"
else
  echo "WARN: gcc not available; skipping logic.so dlopen probe"
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
  objdump -T "${MM_SO}" "${CORE_SO}" "${LOGIC_SO}" 2>/dev/null \
    | grep -oE 'GLIBC_[0-9.]+' \
    | sed 's/GLIBC_//' \
    | sort -t. -k1,1n -k2,2n -k3,3n \
    | tail -n1 || true
)"
logic_max_glibc="$(
  objdump -T "${LOGIC_SO}" 2>/dev/null \
    | grep -oE 'GLIBC_[0-9.]+' \
    | sed 's/GLIBC_//' \
    | sort -t. -k1,1n -k2,2n -k3,3n \
    | tail -n1 || true
)"
echo "Highest GLIBC symbol version referenced: ${max_glibc:-unknown} (logic: ${logic_max_glibc:-unknown})"
# Debian 10 = 2.28, Debian 9 = 2.24, CentOS 7 = 2.17. rom4s logic stays on 2.12-era symbols.
# jammy-built logic pulls GLIBC 2.34+; legacy docker (bullseye) stays <= 2.31.
glibc_too_new_for_logic() {
  local ver="$1"
  [[ -z "${ver}" ]] && return 1
  local major="${ver%%.*}"
  local rest="${ver#*.}"
  local minor="${rest%%.*}"
  [[ "${major}" -gt 2 || ( "${major}" -eq 2 && "${minor}" -ge 34 ) ]]
}
if glibc_too_new_for_logic "${logic_max_glibc}"; then
  echo "FAIL: sourcemod.logic.so requires GLIBC_${logic_max_glibc} (>= 2.34); jammy-native logic hangs srcds" >&2
  fail=1
elif [[ -n "${logic_max_glibc}" ]]; then
  echo "OK: logic GLIBC_${logic_max_glibc} is within legacy-server range"
fi
if glibc_too_new_for_logic "${max_glibc}"; then
  echo "WARN: package requires GLIBC_${max_glibc} (>= 2.29); too new for Debian 8-10 / CentOS 7"
  echo "      Use the rom4s reference package on legacy distros; host-built packages need newer glibc."
else
  echo "OK: GLIBC_${max_glibc} is within legacy-server range"
fi

if [[ "${fail}" -ne 0 ]]; then
  echo "Package ABI check FAILED"
  exit 1
fi
echo "Package ABI check PASSED"
