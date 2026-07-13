#!/usr/bin/env bash
# Shrink a CI server tree to a single map and keep mapcycle files consistent.
set -euo pipefail

SERVER_DIR="${SERVER_DIR:?SERVER_DIR is required}"
KEEP_MAP="${KEEP_MAP:-de_dust2}"
MAPS_DIR="${SERVER_DIR}/cstrike/maps"

if [[ ! -d "${MAPS_DIR}" ]]; then
  echo "Maps directory not found: ${MAPS_DIR}" >&2
  exit 1
fi

echo "==> Trimming maps under ${MAPS_DIR} (keeping ${KEEP_MAP}*)"
find "${MAPS_DIR}" -type f ! -name "${KEEP_MAP}*" -delete
find "${MAPS_DIR}" -mindepth 1 -type d -empty -delete 2>/dev/null || true

map_exists() {
  local name="$1"
  [[ -f "${MAPS_DIR}/${name}.bsp" ]]
}

sync_mapcycle_file() {
  local file="$1"
  [[ -f "${file}" ]] || return 0

  local tmp
  tmp="$(mktemp)"
  local kept=0 skipped=0

  while IFS= read -r line || [[ -n "${line}" ]]; do
    # Strip CR and inline comments; keep empty lines as-is.
    line="${line//$'\r'/}"
    local trimmed="${line#"${line%%[![:space:]]*}"}"
    trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
    if [[ -z "${trimmed}" || "${trimmed}" == \#* ]]; then
      printf '%s\n' "${line}" >>"${tmp}"
      continue
    fi

    local map="${trimmed%%[[:space:]]*}"
    if map_exists "${map}"; then
      printf '%s\n' "${map}" >>"${tmp}"
      kept=$((kept + 1))
    else
      echo "mapcycle: drop missing map '${map}' from ${file}" >&2
      skipped=$((skipped + 1))
    fi
  done <"${file}"

  mv "${tmp}" "${file}"
  echo "mapcycle: ${file} -> ${kept} map(s) kept, ${skipped} removed"
}

# Default css34 layout: cstrike/mapcycle.txt (mapcyclefile cvar).
sync_mapcycle_file "${SERVER_DIR}/cstrike/mapcycle.txt"
sync_mapcycle_file "${SERVER_DIR}/cstrike/cfg/mapcycle.txt"
sync_mapcycle_file "${SERVER_DIR}/cstrike/cfg/mapcycle_default.txt"

if ! map_exists "${KEEP_MAP}"; then
  echo "FAIL: required map ${KEEP_MAP}.bsp is missing after trim" >&2
  exit 1
fi

echo "OK: server maps trimmed to ${KEEP_MAP}*"
ls -la "${MAPS_DIR}" || true
