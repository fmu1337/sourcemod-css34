#!/usr/bin/env bash
# Prepare plugins/ for botplay bisect: stock on/off + SMAC subsets.
set -euo pipefail

SERVER_DIR="${SERVER_DIR:?SERVER_DIR is required}"
SM_PLUGINS="${SERVER_DIR}/cstrike/addons/sourcemod/plugins"
SM_DISABLED="${SERVER_DIR}/cstrike/addons/sourcemod/plugins-disabled"
DISABLE_STOCK_PLUGINS="${DISABLE_STOCK_PLUGINS:-0}"
SMAC_SET="${SMAC_SET:-all}"

mkdir -p "${SM_PLUGINS}" "${SM_DISABLED}"

if [[ "${DISABLE_STOCK_PLUGINS}" == "1" ]]; then
  shopt -s nullglob
  for smx in "${SM_PLUGINS}"/*.smx; do
    base="$(basename "${smx}")"
    [[ "${base}" == smac*.smx ]] && continue
    mv -f "${smx}" "${SM_DISABLED}/"
  done
  shopt -u nullglob
  echo "Disabled stock plugins (moved to plugins-disabled/)"
fi

if [[ "${SMAC_SET}" == "none" ]]; then
  rm -f "${SM_PLUGINS}"/smac*.smx 2>/dev/null || true
  echo "SMAC plugins removed (SMAC_SET=none)"
  exit 0
fi

shopt -s nullglob
installed=("${SM_PLUGINS}"/smac*.smx)
shopt -u nullglob
if [[ ${#installed[@]} -eq 0 ]]; then
  echo "No SMAC plugins present" >&2
  exit 1
fi

should_keep() {
  local base="$1"
  case "${SMAC_SET}" in
    all) return 0 ;;
    core)
      case "${base}" in
        smac.smx|smac_client.smx|smac_status.smx|smac_rcon.smx|smac_commands.smx|smac_cvars.smx) return 0 ;;
      esac
      ;;
    no-hooks)
      case "${base}" in
        smac.smx|smac_client.smx|smac_status.smx|smac_rcon.smx|smac_commands.smx|smac_cvars.smx| \
        smac_aimbot.smx|smac_spinhack.smx|smac_speedhack.smx|smac_autotrigger.smx|smac_css_fixes.smx) return 0 ;;
      esac
      ;;
    hooks-only)
      case "${base}" in
        smac_wallhack.smx|smac_antiaim.smx|smac_css_antiflash.smx|smac_css_antismoke.smx|smac_eyetest.smx) return 0 ;;
      esac
      ;;
  esac
  return 1
}

shopt -s nullglob
for smx in "${SM_PLUGINS}"/smac*.smx; do
  base="$(basename "${smx}")"
  if ! should_keep "${base}"; then
    mv -f "${smx}" "${SM_DISABLED}/"
    echo "Disabled ${base}"
  fi
done
shopt -u nullglob

echo "SMAC_SET=${SMAC_SET} active plugins:"
ls -la "${SM_PLUGINS}"/smac*.smx 2>/dev/null || echo "(none)"
