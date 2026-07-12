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

fail=0

if [[ ! -f "${MM_SO}" ]]; then
  echo "FAIL: missing sourcemod_mm_i486.so" >&2
  exit 1
fi
if [[ ! -f "${CORE_SO}" ]]; then
  echo "FAIL: missing sourcemod.1.ep1.so" >&2
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
if [[ -n "${max_glibc}" ]]; then
  major="${max_glibc%%.*}"
  rest="${max_glibc#*.}"
  minor="${rest%%.*}"
  if [[ "${major}" -gt 2 || ( "${major}" -eq 2 && "${minor}" -ge 29 ) ]]; then
    echo "FAIL: package requires GLIBC_${max_glibc} (>= 2.29); too new for Debian 8-10 / CentOS 7" >&2
    fail=1
  else
    echo "OK: GLIBC_${max_glibc} is within legacy-server range"
  fi
fi

if [[ "${fail}" -ne 0 ]]; then
  echo "Package ABI check FAILED"
  exit 1
fi
echo "Package ABI check PASSED"
