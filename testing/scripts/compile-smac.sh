#!/usr/bin/env bash
# Compile smac_v34 plugins against an installed or packaged SourceMod tree.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CACHE_DIR="${CACHE_DIR:-${ROOT}/.ci-cache}"
SMAC_SRC="${SMAC_SRC:-${CACHE_DIR}/smac_v34}"
SMAC_REF="${SMAC_REF:-https://github.com/fmu1337/smac_v34.git}"
SMAC_OUT="${SMAC_OUT:-${ROOT}/.ci-artifacts/smac-plugins}"
SM_PACKAGE="${SM_PACKAGE:-}"
SERVER_DIR="${SERVER_DIR:-}"
SM_EXTRACT_DIR=""

cleanup() {
  if [[ -n "${SM_EXTRACT_DIR}" && -d "${SM_EXTRACT_DIR}" ]]; then
    rm -rf "${SM_EXTRACT_DIR}"
  fi
}
trap cleanup EXIT

fetch_smac_src() {
  if [[ -d "${SMAC_SRC}/.git" ]]; then
    echo "Using cached SMAC source at ${SMAC_SRC}"
    return 0
  fi
  mkdir -p "$(dirname "${SMAC_SRC}")"
  echo "Cloning SMAC from ${SMAC_REF}"
  git clone --depth 1 "${SMAC_REF}" "${SMAC_SRC}"
}

materialize_sm_tree() {
  if [[ -n "${SERVER_DIR}" && -d "${SERVER_DIR}/cstrike/addons/sourcemod/scripting" ]]; then
    echo "${SERVER_DIR}/cstrike/addons/sourcemod/scripting"
    return 0
  fi
  if [[ -n "${SM_PACKAGE}" && -f "${SM_PACKAGE}" ]]; then
    SM_EXTRACT_DIR="$(mktemp -d)"
    tar -xzf "${SM_PACKAGE}" -C "${SM_EXTRACT_DIR}" addons/sourcemod/scripting
    echo "${SM_EXTRACT_DIR}/addons/sourcemod/scripting"
    return 0
  fi
  echo "compile-smac: set SM_PACKAGE or SERVER_DIR with installed SM" >&2
  return 1
}

main() {
  fetch_smac_src
  local sm_scripting spcomp
  sm_scripting="$(materialize_sm_tree)"
  spcomp="${sm_scripting}/spcomp"
  chmod +x "${spcomp}"

  mkdir -p "${SMAC_OUT}"
  rm -f "${SMAC_OUT}"/*.smx 2>/dev/null || true

  local -a inc_args=(
    "-i${sm_scripting}/include"
    "-i${SMAC_SRC}/addons/sourcemod/scripting/include"
  )

  local compiled=0 failed=0
  local sp
  for sp in "${SMAC_SRC}/addons/sourcemod/scripting"/smac*.sp; do
    [[ -f "${sp}" ]] || continue
    local base out
    base="$(basename "${sp}" .sp)"
    out="${SMAC_OUT}/${base}.smx"
    echo "Compiling ${base}.sp -> ${out}"
    if "${spcomp}" "${inc_args[@]}" -o"${out}" "${sp}"; then
      compiled=$((compiled + 1))
    else
      echo "FAIL: ${base}.sp" >&2
      failed=$((failed + 1))
    fi
  done

  if [[ "${compiled}" -lt 1 ]]; then
    echo "FAIL: no SMAC plugins compiled" >&2
    exit 1
  fi
  if [[ "${failed}" -gt 0 ]]; then
    echo "FAIL: ${failed} SMAC plugin(s) failed to compile" >&2
    exit 1
  fi

  echo "Compiled ${compiled} SMAC plugin(s) into ${SMAC_OUT}"
  ls -la "${SMAC_OUT}"/*.smx
}

main "$@"
