#!/usr/bin/env bash
# Shrink a CI server tree to selected maps and keep mapcycle files consistent.
set -euo pipefail

SERVER_DIR="${SERVER_DIR:?SERVER_DIR is required}"
KEEP_MAPS="${KEEP_MAPS:-${KEEP_MAP:-de_dust2}}"
MAPS_DIR="${SERVER_DIR}/cstrike/maps"

if [[ ! -d "${MAPS_DIR}" ]]; then
  echo "Maps directory not found: ${MAPS_DIR}" >&2
  exit 1
fi

map_allowed() {
  local file="$1"
  local base="${file##*/}"
  local keep
  IFS=',' read -ra MAP_LIST <<< "${KEEP_MAPS}"
  for keep in "${MAP_LIST[@]}"; do
    keep="${keep// /}"
    [[ -n "${keep}" ]] || continue
    if [[ "${base}" == "${keep}"* ]]; then
      return 0
    fi
  done
  return 1
}

echo "==> Trimming maps under ${MAPS_DIR} (keeping: ${KEEP_MAPS})"
while IFS= read -r -d '' file; do
  if ! map_allowed "${file}"; then
    rm -f "${file}"
  fi
done < <(find "${MAPS_DIR}" -type f -print0)
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

write_botplay_mapcycle() {
  local file="${SERVER_DIR}/cstrike/mapcycle.txt"
  local map
  IFS=',' read -ra MAP_LIST <<< "${KEEP_MAPS}"
  : >"${file}"
  for map in "${MAP_LIST[@]}"; do
    map="${map// /}"
    [[ -n "${map}" ]] || continue
    if map_exists "${map}"; then
      echo "${map}" >>"${file}"
    fi
  done
  echo "mapcycle: wrote botplay rotation list to ${file}"
}

sync_mapcycle_file "${SERVER_DIR}/cstrike/mapcycle.txt"
sync_mapcycle_file "${SERVER_DIR}/cstrike/cfg/mapcycle.txt"
sync_mapcycle_file "${SERVER_DIR}/cstrike/cfg/mapcycle_default.txt"
write_botplay_mapcycle

IFS=',' read -ra MAP_LIST <<< "${KEEP_MAPS}"
for map in "${MAP_LIST[@]}"; do
  map="${map// /}"
  if [[ -n "${map}" ]] && ! map_exists "${map}"; then
    echo "FAIL: required map ${map}.bsp is missing after trim" >&2
    exit 1
  fi
done

echo "OK: server maps trimmed to ${KEEP_MAPS}"
ls -la "${MAPS_DIR}" || true
