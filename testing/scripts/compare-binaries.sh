#!/usr/bin/env bash
# Compare Metamod / SourceMod .so binaries (sizes, NEEDED, GLIBC, key symbols, strings).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CACHE="${CACHE_DIR:-${ROOT}/.ci-cache}/extract"
OUT="${1:-${ROOT}/.ci-cache/binary-compare.txt}"

mkdir -p "$(dirname "${OUT}")"

report() {
  printf '%s\n' "$*" | tee -a "${OUT}"
}

section() {
  report ""
  report "================================================================"
  report " $1"
  report "================================================================"
}

analyze_so() {
  local label="$1" path="$2"
  [[ -f "${path}" ]] || { report "MISSING ${label}: ${path}"; return; }
  section "${label}  (${path})"
  report "size: $(stat -c '%s bytes (%h)' "${path}")"
  report "sha256: $(sha256sum "${path}" | awk '{print $1}')"
  report "file: $(file -b "${path}")"
  report ""
  report "-- DT_NEEDED --"
  readelf -d "${path}" 2>/dev/null | awk '/\(NEEDED\)/ {print "  " $NF}' | tr -d '[]' | tee -a "${OUT}" || true
  report ""
  report "-- GLIBC (max) --"
  local max_glibc
  max_glibc="$(
    objdump -T "${path}" 2>/dev/null \
      | grep -oE 'GLIBC_[0-9.]+' \
      | sed 's/GLIBC_//' \
      | sort -t. -k1,1n -k2,2n -k3,3n \
      | tail -n1 || true
  )"
  report "  GLIBC_${max_glibc:-unknown}"
  report ""
  report "-- exports (CreateInterface / ISmm / SourceHook sample) --"
  nm -D "${path}" 2>/dev/null | grep -E ' T (CreateInterface|CreateInterface_MMS|Plugin|_ZN10SourceHook)' | head -20 | sed 's/^/  /' | tee -a "${OUT}" || true
  report ""
  report "-- version / engine interface strings --"
  strings "${path}" 2>/dev/null | grep -iE \
    'metamod:source version|sourcemod version|sourcehook version|built from|ServerGameDLL|VEngineServer|PLAPI|1\.10|1\.11|6572|6522|6541|git' \
    | sort -u | head -25 | sed 's/^/  /' | tee -a "${OUT}" || true
}

pair_diff() {
  local a_label="$1" a_path="$2" b_label="$3" b_path="$4"
  [[ -f "${a_path}" && -f "${b_path}" ]] || return
  section "DIFF ${a_label} vs ${b_label}"
  if cmp -s "${a_path}" "${b_path}"; then
    report "  IDENTICAL bytes"
    return
  fi
  report "  sizes: $(stat -c '%s' "${a_path}") vs $(stat -c '%s' "${b_path}")"
  report "  sha256:"
  report "    ${a_label}: $(sha256sum "${a_path}" | awk '{print $1}')"
  report "    ${b_label}: $(sha256sum "${b_path}" | awk '{print $1}')"
  report ""
  report "  SourceHook FHCls symbol counts:"
  report "    ${a_label}: $(nm -D "${a_path}" 2>/dev/null | grep -c '__SourceHook_FHCls' || echo 0)"
  report "    ${b_label}: $(nm -D "${b_path}" 2>/dev/null | grep -c '__SourceHook_FHCls' || echo 0)"
}

: >"${OUT}"
report "Binary comparison report — $(date -u +%Y-%m-%dT%H:%M:%SZ)"
report "Cache root: ${CACHE}"

# Metamod cores
analyze_so "rom4s MM metamod.1.ep1" "${CACHE}/rom4s-mm/addons/metamod/bin/metamod.1.ep1.so"
analyze_so "built MM metamod.1.ep1" "${CACHE}/built-mm/metamod/bin/metamod.1.ep1.so"
analyze_so "myarena MM metamod.2.ep1" "${CACHE}/myarena/addons/metamod/bin/metamod.2.ep1.so"

pair_diff "rom4s MM" "${CACHE}/rom4s-mm/addons/metamod/bin/metamod.1.ep1.so" \
  "built MM" "${CACHE}/built-mm/metamod/bin/metamod.1.ep1.so"

# SourceMod cores + bridge
analyze_so "rom4s SM bridge" "${CACHE}/rom4s-sm/addons/sourcemod/bin/sourcemod_mm_i486.so"
analyze_so "rom4s SM core 1.ep1" "${CACHE}/rom4s-sm/addons/sourcemod/bin/sourcemod.1.ep1.so"
analyze_so "rom4s SM core 2.ep1" "${CACHE}/rom4s-sm/addons/sourcemod/bin/sourcemod.2.ep1.so"
analyze_so "myarena SM bridge" "${CACHE}/myarena/addons/sourcemod/bin/sourcemod_mm_i486.so"
analyze_so "myarena SM core 2.ep1" "${CACHE}/myarena/addons/sourcemod/bin/sourcemod.2.ep1.so"

pair_diff "rom4s SM 1.ep1" "${CACHE}/rom4s-sm/addons/sourcemod/bin/sourcemod.1.ep1.so" \
  "rom4s SM 2.ep1" "${CACHE}/rom4s-sm/addons/sourcemod/bin/sourcemod.2.ep1.so"
pair_diff "rom4s SM 2.ep1" "${CACHE}/rom4s-sm/addons/sourcemod/bin/sourcemod.2.ep1.so" \
  "myarena SM 2.ep1" "${CACHE}/myarena/addons/sourcemod/bin/sourcemod.2.ep1.so"
pair_diff "rom4s SM bridge" "${CACHE}/rom4s-sm/addons/sourcemod/bin/sourcemod_mm_i486.so" \
  "myarena SM bridge" "${CACHE}/myarena/addons/sourcemod/bin/sourcemod_mm_i486.so"

# ConVar embedding check (rom4s hang fix)
section "ConVar embedding (rom4s vs myarena 2.ep1 core)"
check_convar_embed() {
  local label="$1" path="$2"
  local dynsyms
  dynsyms="$(nm -D "${path}" 2>/dev/null || true)"
  if printf '%s\n' "${dynsyms}" | grep -F ' T _ZN6ConVarC1EPKcS1_i' >/dev/null; then
    report "  ${label}: ConVar ctor embedded (T)"
  else
    report "  ${label}: ConVar ctor NOT embedded (U or missing — vstdlib import risk)"
  fi
}
check_convar_embed "rom4s 1.ep1" "${CACHE}/rom4s-sm/addons/sourcemod/bin/sourcemod.1.ep1.so"
check_convar_embed "rom4s 2.ep1" "${CACHE}/rom4s-sm/addons/sourcemod/bin/sourcemod.2.ep1.so"
check_convar_embed "myarena 2.ep1" "${CACHE}/myarena/addons/sourcemod/bin/sourcemod.2.ep1.so"

report ""
report "Report written to ${OUT}"
