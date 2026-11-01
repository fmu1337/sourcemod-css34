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

echo "==> Checking the css34 legacy-plugin bridge (T2.9)"
# Every MM 1.10 legacy core exports the nested-mode API; every MM 1.12 core
# carries the loader for it (the PLAPI 7-12 path names css34_old_init).
LEGACY_SO="${TMP}/addons/metamod/bin/metamod.1.ep1.so"
MODERN_SO="${TMP}/addons/metamod/bin/metamod.2.ep1.so"
if [[ -f "${LEGACY_SO}" ]]; then
  legacy_syms="$(nm -D --defined-only "${LEGACY_SO}" 2>/dev/null || true)"
  bridge_fail=0
  for sym in css34_old_api css34_old_init css34_old_all_loaded css34_old_load \
             css34_old_unload css34_old_pause css34_old_running css34_old_info; do
    if ! grep -Eq " T ${sym}\$" <<<"${legacy_syms}"; then
      echo "FAIL: metamod.1.ep1.so does not export ${sym}" >&2
      bridge_fail=1
      fail=1
    fi
  done
  [[ "${bridge_fail}" -ne 0 ]] || echo "OK: metamod.1.ep1.so exports the css34_old_* bridge API"
fi
if [[ -f "${MODERN_SO}" ]]; then
  if grep -aq 'css34_old_init' "${MODERN_SO}"; then
    echo "OK: metamod.2.ep1.so hands PLAPI 7-12 plugins to metamod.1.ep1"
  else
    echo "FAIL: metamod.2.ep1.so has no css34 legacy-plugin bridge" >&2
    fail=1
  fi
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

if ! python3 "$(dirname "$0")/check-unversioned-imports.py" "${TMP}"; then
  fail=1
fi

manifest="${TMP}/addons/metamod/css34-package.json"
if [[ ! -f "${manifest}" ]]; then
  echo "FAIL: missing addons/metamod/css34-package.json" >&2
  fail=1
elif python3 -c '
import json, sys, os, re
d = json.load(open(sys.argv[1]))
b = d.get("metamod_binary")
exp_commit = os.environ.get("EXPECTED_MM_COMMIT")
exp_rev = os.environ.get("EXPECTED_MM_REV")
if b not in ("metamod.1.ep1", "metamod.2.ep1") or not d.get("mm_version") or not d.get("mm_commit"):
    sys.exit(1)
if exp_commit and d.get("mm_commit") != exp_commit:
    print("FAIL: manifest mm_commit " + str(d.get("mm_commit")) + " != expected " + str(exp_commit), file=sys.stderr)
    sys.exit(1)
version = d.get("mm_version")
revision = re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+-git([0-9]+)", version) if isinstance(version, str) else None
if exp_rev and (revision is None or revision.group(1) != str(exp_rev)):
    print("FAIL: manifest mm_version " + str(version) + " does not have exact revision git" + str(exp_rev), file=sys.stderr)
    sys.exit(1)
' "${manifest}"; then
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
