#!/usr/bin/env bash
# Run a matrix of short botplay cases to isolate built-package crashes.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${BISECT_OUT:-${ROOT}/.ci-bisect/results.tsv}"
RECORD_SECS="${RECORD_SECS:-90}"
BISECT_SET="${BISECT_SET:-full}"

: "${SM_PACKAGE:?SM_PACKAGE is required for built bisect}"
: "${MM_PACKAGE:?MM_PACKAGE is required for built bisect}"

mkdir -p "$(dirname "${OUT}")"
echo -e "case\tresult\tround_start\tround_end\tkills\tcrash\trc" >"${OUT}"

run_case() {
  local name="$1"
  shift
  echo "===== CASE ${name} ====="
  line="$(
    env CASE_NAME="${name}" RECORD_SECS="${RECORD_SECS}" SM_PACKAGE="${SM_PACKAGE}" MM_PACKAGE="${MM_PACKAGE}" \
      "$@" \
      "${ROOT}/testing/scripts/botplay-bisect-case.sh"
  )"
  echo "${line}"
  IFS='|' read -r c result _rs rs _re re _kd kd _crash crash _rc rc <<<"${line}"
  rs="${rs#rs=}"; re="${re#re=}"; kd="${kd#kd=}"; crash="${crash#crash=}"; rc="${rc#rc=}"
  echo -e "${name}\t${result}\t${rs}\t${re}\t${kd}\t${crash}\t${rc}" >>"${OUT}"
}

run_quick_cases() {
  # Minimal set: baseline built, SMAC, hybrid MM/SM, sdkhooks gamedata fix, rom4s control.
  run_case "A-built-no-smac" \
    BOTPLAY_PROFILE=built INSTALL_SMAC=0 DISABLE_STOCK_PLUGINS=0

  run_case "E-built-smac-full" \
    BOTPLAY_PROFILE=built INSTALL_SMAC=1 SMAC_SET=all DISABLE_STOCK_PLUGINS=0

  run_case "I-built-mm-rom4s-sm" \
    BOTPLAY_PROFILE=built INSTALL_SMAC=0 DISABLE_STOCK_PLUGINS=0 USE_ROM4S_SM=1

  run_case "V-built-plus-sdkhooks-gd" \
    BOTPLAY_PROFILE=built INSTALL_SMAC=0 DISABLE_STOCK_PLUGINS=0 ROM4S_OVERLAY_PARTS=gamedata/sdkhooks.games

  run_case "H-rom4s-smac-full" \
    BOTPLAY_PROFILE=rom4s INSTALL_SMAC=1 SMAC_SET=all DISABLE_STOCK_PLUGINS=0
}

run_full_cases() {
run_case "A-built-no-smac" \
  BOTPLAY_PROFILE=built INSTALL_SMAC=0 DISABLE_STOCK_PLUGINS=0

run_case "C-built-smac-core" \
  BOTPLAY_PROFILE=built INSTALL_SMAC=1 SMAC_SET=core DISABLE_STOCK_PLUGINS=1

run_case "D-built-smac-no-hooks" \
  BOTPLAY_PROFILE=built INSTALL_SMAC=1 SMAC_SET=no-hooks DISABLE_STOCK_PLUGINS=1

run_case "E-built-smac-full" \
  BOTPLAY_PROFILE=built INSTALL_SMAC=1 SMAC_SET=all DISABLE_STOCK_PLUGINS=0

run_case "F-built-smac-full-rom4s-bintools" \
  BOTPLAY_PROFILE=built INSTALL_SMAC=1 SMAC_SET=all DISABLE_STOCK_PLUGINS=0 OVERLAY_ROM4S_BINTOOLS=1

run_case "G-built-smac-full-rom4s-mm" \
  BOTPLAY_PROFILE=built INSTALL_SMAC=1 SMAC_SET=all DISABLE_STOCK_PLUGINS=0 USE_ROM4S_MM=1

run_case "I-built-mm-rom4s-sm" \
  BOTPLAY_PROFILE=built INSTALL_SMAC=0 DISABLE_STOCK_PLUGINS=0 USE_ROM4S_SM=1

run_case "J-built-mm-rom4s-sm-smac" \
  BOTPLAY_PROFILE=built INSTALL_SMAC=1 SMAC_SET=all DISABLE_STOCK_PLUGINS=0 USE_ROM4S_SM=1

run_case "K-built-overlay-logic" \
  BOTPLAY_PROFILE=built INSTALL_SMAC=0 DISABLE_STOCK_PLUGINS=0 ROM4S_OVERLAY_PARTS=logic

run_case "L-built-overlay-core" \
  BOTPLAY_PROFILE=built INSTALL_SMAC=0 DISABLE_STOCK_PLUGINS=0 ROM4S_OVERLAY_PARTS=core

run_case "M-built-overlay-sdkhooks" \
  BOTPLAY_PROFILE=built INSTALL_SMAC=0 DISABLE_STOCK_PLUGINS=0 ROM4S_OVERLAY_PARTS=sdkhooks

run_case "N-built-overlay-logic-core" \
  BOTPLAY_PROFILE=built INSTALL_SMAC=0 DISABLE_STOCK_PLUGINS=0 ROM4S_OVERLAY_PARTS=logic+core

run_case "P-built-overlay-gamecstrike" \
  BOTPLAY_PROFILE=built INSTALL_SMAC=0 DISABLE_STOCK_PLUGINS=0 ROM4S_OVERLAY_PARTS=gamecstrike

run_case "Q-built-overlay-jit" \
  BOTPLAY_PROFILE=built INSTALL_SMAC=0 DISABLE_STOCK_PLUGINS=0 ROM4S_OVERLAY_PARTS=jit

run_case "R-built-overlay-gamecstrike-jit" \
  BOTPLAY_PROFILE=built INSTALL_SMAC=0 DISABLE_STOCK_PLUGINS=0 ROM4S_OVERLAY_PARTS=gamecstrike+jit

run_case "O-built-overlay-all" \
  BOTPLAY_PROFILE=built INSTALL_SMAC=0 DISABLE_STOCK_PLUGINS=0 ROM4S_OVERLAY_PARTS=all

run_case "T-built-plus-rom4s-gamedata" \
  BOTPLAY_PROFILE=built INSTALL_SMAC=0 DISABLE_STOCK_PLUGINS=0 ROM4S_OVERLAY_PARTS=gamedata

run_case "V-built-plus-sdkhooks-gd" \
  BOTPLAY_PROFILE=built INSTALL_SMAC=0 DISABLE_STOCK_PLUGINS=0 ROM4S_OVERLAY_PARTS=gamedata/sdkhooks.games

run_case "H-rom4s-smac-full" \
  BOTPLAY_PROFILE=rom4s INSTALL_SMAC=1 SMAC_SET=all DISABLE_STOCK_PLUGINS=0
}

case "${BISECT_SET}" in
  quick)
    echo "Running quick bisect set (5 cases, ${RECORD_SECS}s each)"
    run_quick_cases
    ;;
  full)
    echo "Running full bisect set (19 cases, ${RECORD_SECS}s each)"
    run_full_cases
    ;;
  *)
    echo "Unknown BISECT_SET=${BISECT_SET} (expected quick or full)" >&2
    exit 1
    ;;
esac

echo ""
echo "Bisect summary (${OUT}):"
column -t "${OUT}" 2>/dev/null || cat "${OUT}"
