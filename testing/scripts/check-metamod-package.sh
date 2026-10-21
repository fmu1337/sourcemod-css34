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
if nm -D "${LOADER_SO}" 2>/dev/null | grep -E ' T CreateInterface([[:space:]]|$)' >/dev/null; then
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
  echo "FAIL: ConVar ctor not found in dynamic symbols" >&2
  fail=1
fi

if printf '%s\n' "${core_syms}" | grep -F ' B _ZN14ConCommandBase18s_pConCommandBasesE' >/dev/null; then
  echo "OK: ConCommandBase::s_pConCommandBases is local"
elif printf '%s\n' "${core_syms}" | grep -F ' U _ZN14ConCommandBase18s_pConCommandBasesE' >/dev/null; then
  echo "FAIL: s_pConCommandBases imported (link order / missing static tier1)" >&2
  fail=1
else
  echo "FAIL: s_pConCommandBases not found in dynamic symbols" >&2
  fail=1
fi

cxx11="$(printf '%s\n' "${core_syms}" | grep -c '__cxx11' || true)"
if [[ "${cxx11}" -gt 0 ]]; then
  echo "WARN: ${CORE_SO##*/} exports ${cxx11} __cxx11 symbols (prefer ABI0 / old libstdc++)"
else
  echo "OK: no __cxx11 ABI exports"
fi

echo "==> Checking libstdc++ is not a DT_NEEDED and GLIBC floor"
GLIBC_FLOOR="${GLIBC_FLOOR:-2.17}"
version_gt() {
  [[ "$1" != "$2" && "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -1)" == "$1" ]]
}
max_glibc=""
while IFS= read -r -d '' elf; do
  readelf -h "${elf}" >/dev/null 2>&1 || continue
  rel="${elf#"${TMP}"/}"
  if readelf -d "${elf}" 2>/dev/null | grep -q 'libstdc++\.so\.6'; then
    echo "FAIL: ${rel} NEEDED libstdc++.so.6" >&2
    fail=1
  fi
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
done < <(find "${TMP}" -type f -name '*.so' -print0)
echo "Highest GLIBC symbol version referenced: ${max_glibc:-none} (floor ${GLIBC_FLOOR})"

manifest="${TMP}/addons/metamod/css34-package.json"
if [[ ! -f "${manifest}" ]]; then
  echo "FAIL: missing addons/metamod/css34-package.json" >&2
  fail=1
elif python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); b=d.get("metamod_binary"); sys.exit(0 if b in ("metamod.1.ep1","metamod.2.ep1") and d.get("mm_version") and d.get("mm_commit") else 1)' "${manifest}"; then
  echo "OK: addons/metamod/css34-package.json"
else
  echo "FAIL: invalid addons/metamod/css34-package.json" >&2
  fail=1
fi

if [[ "${fail}" -ne 0 ]]; then
  echo "Metamod ABI check FAILED"
  exit 1
fi
echo "Metamod ABI check PASSED"
