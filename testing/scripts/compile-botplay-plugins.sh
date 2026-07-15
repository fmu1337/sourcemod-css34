#!/usr/bin/env bash
# Compile in-repo botplay helper plugins against installed or packaged SourceMod.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CACHE_DIR="${CACHE_DIR:-${ROOT}/.ci-cache}"
PLUGIN_SRC="${PLUGIN_SRC:-${ROOT}/testing/plugins}"
BOTPLAY_OUT="${BOTPLAY_OUT:-${ROOT}/.ci-artifacts/botplay-plugins}"
SM_PACKAGE="${SM_PACKAGE:-}"
SERVER_DIR="${SERVER_DIR:-}"
SM_EXTRACT_DIR=""

cleanup() {
  if [[ -n "${SM_EXTRACT_DIR}" && -d "${SM_EXTRACT_DIR}" ]]; then
    rm -rf "${SM_EXTRACT_DIR}"
  fi
}
trap cleanup EXIT

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
  echo "compile-botplay-plugins: set SM_PACKAGE or SERVER_DIR with installed SM" >&2
  return 1
}

main() {
  local sm_scripting spcomp
  sm_scripting="$(materialize_sm_tree)"
  spcomp="${sm_scripting}/spcomp"
  chmod +x "${spcomp}"

  mkdir -p "${BOTPLAY_OUT}"
  rm -f "${BOTPLAY_OUT}"/*.smx 2>/dev/null || true

  local compiled=0 failed=0
  local sp
  shopt -s nullglob
  for sp in "${PLUGIN_SRC}"/*.sp; do
    [[ -f "${sp}" ]] || continue
    local base out
    base="$(basename "${sp}" .sp)"
    out="${BOTPLAY_OUT}/${base}.smx"
    echo "Compiling ${base}.sp -> ${out}"
    if "${spcomp}" -i"${sm_scripting}/include" -o"${out}" "${sp}"; then
      compiled=$((compiled + 1))
    else
      echo "FAIL: ${base}.sp" >&2
      failed=$((failed + 1))
    fi
  done
  shopt -u nullglob

  if [[ "${compiled}" -lt 1 ]]; then
    echo "FAIL: no botplay plugins compiled" >&2
    exit 1
  fi
  if [[ "${failed}" -gt 0 ]]; then
    echo "FAIL: ${failed} botplay plugin(s) failed to compile" >&2
    exit 1
  fi

  echo "Compiled ${compiled} botplay plugin(s) into ${BOTPLAY_OUT}"
  ls -la "${BOTPLAY_OUT}"/*.smx
}

main "$@"
