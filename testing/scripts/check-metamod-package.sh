#!/usr/bin/env bash
# Static checks on a Metamod:Source css34 package (episode1 / 1.ep1 or 2.ep1).
set -euo pipefail

MM_PACKAGE="${MM_PACKAGE:?MM_PACKAGE is required}"
TMP="$(mktemp -d)"
cleanup() { rm -rf "${TMP}"; }
trap cleanup EXIT

tar -xzf "${MM_PACKAGE}" -C "${TMP}"

CORE_SO="${TMP}/addons/metamod/bin/metamod.2.ep1.so"
if [[ ! -f "${CORE_SO}" ]]; then
  CORE_SO="${TMP}/addons/metamod/bin/metamod.1.ep1.so"
fi
LOADER_SO="${TMP}/addons/metamod/bin/server.so"
VDF="${TMP}/addons/metamod.vdf"

fail=0

if [[ ! -f "${CORE_SO}" ]]; then
  echo "FAIL: missing metamod.2.ep1.so / metamod.1.ep1.so" >&2
  exit 1
fi
if [[ ! -f "${LOADER_SO}" ]]; then
  echo "FAIL: missing server.so loader" >&2
  exit 1
fi
if [[ ! -f "${VDF}" ]]; then
  echo "FAIL: missing addons/metamod.vdf" >&2
  fail=1
else
  echo "OK: metamod.vdf present"
fi

echo "==> Checking loader exports"
if nm -D "${LOADER_SO}" 2>/dev/null | grep -q ' T CreateInterface$'; then
  echo "OK: server.so exports CreateInterface"
else
  echo "FAIL: server.so missing CreateInterface" >&2
  fail=1
fi

echo "==> Checking ConVar embedding (vstdlib import hangs srcds GameDLLInit)"
core_syms="$(nm -D "${CORE_SO}" 2>/dev/null || true)"
if printf '%s\n' "${core_syms}" | grep -F ' T _ZN6ConVarC1EPKcS1_i' >/dev/null; then
  echo "OK: ConVar ctor is defined locally (static tier1)"
elif printf '%s\n' "${core_syms}" | grep -F ' U _ZN6ConVarC1EPKcS1_i' >/dev/null; then
  echo "FAIL: ConVar ctor imported from vstdlib (tier1 must precede vstdlib on link line)" >&2
  fail=1
else
  echo "WARN: ConVar ctor not found in dynamic symbols"
fi

if printf '%s\n' "${core_syms}" | grep -F ' B _ZN14ConCommandBase18s_pConCommandBasesE' >/dev/null; then
  echo "OK: ConCommandBase::s_pConCommandBases is local"
elif printf '%s\n' "${core_syms}" | grep -F ' U _ZN14ConCommandBase18s_pConCommandBasesE' >/dev/null; then
  echo "FAIL: s_pConCommandBases imported (link order / missing static tier1)" >&2
  fail=1
else
  echo "WARN: s_pConCommandBases not found"
fi

cxx11="$(printf '%s\n' "${core_syms}" | grep -c '__cxx11' || true)"
if [[ "${cxx11}" -gt 0 ]]; then
  echo "WARN: ${CORE_SO##*/} exports ${cxx11} __cxx11 symbols (prefer ABI0 / old libstdc++)"
else
  echo "OK: no __cxx11 ABI exports"
fi

echo "==> Checking GLIBC requirements"
max_glibc="$(
  objdump -T "${CORE_SO}" "${LOADER_SO}" 2>/dev/null \
    | grep -oE 'GLIBC_[0-9.]+' \
    | sed 's/GLIBC_//' \
    | sort -t. -k1,1n -k2,2n -k3,3n \
    | tail -n1 || true
)"
echo "Highest GLIBC symbol version referenced: ${max_glibc:-unknown}"
glibc_too_new() {
  local ver="$1"
  [[ -z "${ver}" ]] && return 1
  local major="${ver%%.*}"
  local rest="${ver#*.}"
  local minor="${rest%%.*}"
  [[ "${major}" -gt 2 || ( "${major}" -eq 2 && "${minor}" -ge 34 ) ]]
}
if glibc_too_new "${max_glibc}"; then
  echo "FAIL: Metamod requires GLIBC_${max_glibc} (>= 2.34); too new for Debian 11 smoke" >&2
  fail=1
elif [[ -n "${max_glibc}" ]]; then
  echo "OK: GLIBC_${max_glibc} is within Debian 11 range"
fi

if [[ "${fail}" -ne 0 ]]; then
  echo "Metamod ABI check FAILED"
  exit 1
fi
echo "Metamod ABI check PASSED"
