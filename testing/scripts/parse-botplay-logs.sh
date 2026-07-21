#!/usr/bin/env bash
# Parse botplay recording logs and emit a machine-readable report + summary.
set -euo pipefail

SERVER_DIR="${1:?SERVER_DIR is required}"
OUT_JSON="${2:-${SERVER_DIR}/botplay-report.json}"
OUT_TXT="${3:-${SERVER_DIR}/botplay-report.txt}"

BOTPLAY_LOG="${BOTPLAY_LOG:-${SERVER_DIR}/botplay.log}"
ENGINE_CONSOLE_LOG="${SERVER_DIR}/cstrike/console.log"
SM_LOG_DIR="${SERVER_DIR}/cstrike/addons/sourcemod/logs"

count_pattern() {
  local file="$1" pat="$2"
  if [[ ! -f "${file}" ]]; then
    echo 0
    return 0
  fi
  local n
  n="$(grep -Eic -- "${pat}" "${file}" 2>/dev/null || true)"
  echo "${n:-0}"
}

first_matches() {
  local file="$1" pat="$2" limit="${3:-5}"
  if [[ ! -f "${file}" ]]; then
    return 0
  fi
  grep -Ein -- "${pat}" "${file}" 2>/dev/null | head -n "${limit}" || true
}

# HL2/CSS console.log and expect session both use these event shapes.
ROUND_START_PAT='(World triggered "Round_Start"|GameEvent "round_start"|"round_start")'
ROUND_END_PAT='(World triggered "Round_End"|GameEvent "round_end"|"round_end")'
PLAYER_DEATH_PAT='(triggered "player_death"|GameEvent "player_death"|"player_death"|[[:space:]]killed[[:space:]]+)'
CRASH_PAT='(Bad entity in IndexOfEdict|Segmentation fault|SIGSEGV|Aborted|SIGABRT)'

round_start_console=0
round_end_console=0
player_death_console=0
round_start_botplay=0
round_end_botplay=0
player_death_botplay=0

if [[ -f "${ENGINE_CONSOLE_LOG}" ]]; then
  round_start_console="$(count_pattern "${ENGINE_CONSOLE_LOG}" "${ROUND_START_PAT}")"
  round_end_console="$(count_pattern "${ENGINE_CONSOLE_LOG}" "${ROUND_END_PAT}")"
  player_death_console="$(count_pattern "${ENGINE_CONSOLE_LOG}" "${PLAYER_DEATH_PAT}")"
fi
if [[ -f "${BOTPLAY_LOG}" ]]; then
  round_start_botplay="$(count_pattern "${BOTPLAY_LOG}" "${ROUND_START_PAT}")"
  round_end_botplay="$(count_pattern "${BOTPLAY_LOG}" "${ROUND_END_PAT}")"
  player_death_botplay="$(count_pattern "${BOTPLAY_LOG}" "${PLAYER_DEATH_PAT}")"
fi

round_start=$((round_start_console + round_start_botplay))
round_end=$((round_end_console + round_end_botplay))
player_death=$((player_death_console + player_death_botplay))

# De-dupe when condebug mirrors the same lines into botplay.log is hard;
# prefer console.log counts when present.
if [[ -f "${ENGINE_CONSOLE_LOG}" ]]; then
  round_start="${round_start_console}"
  round_end="${round_end_console}"
  player_death="${player_death_console}"
fi

smac_running=0
smac_failed=0
if [[ -f "${BOTPLAY_LOG}" ]]; then
  smac_running="$(
    sed -n '/sm plugins list/,/^quit$/p' "${BOTPLAY_LOG}" 2>/dev/null \
      | grep -Eic '^[[:space:]]*[0-9]+[[:space:]]+"SMAC:' || true
  )"
  smac_failed="$(
    sed -n '/sm plugins list/,/^quit$/p' "${BOTPLAY_LOG}" 2>/dev/null \
      | grep -Eic '^[[:space:]]*[0-9]+[[:space:]]+<Failed>.*"SMAC:' || true
  )"
fi

crash=0
for f in "${BOTPLAY_LOG}" "${ENGINE_CONSOLE_LOG}"; do
  if [[ -f "${f}" ]] && grep -Eiq "${CRASH_PAT}" "${f}"; then
    crash=1
  fi
done

sm_log_files=0
sm_log_errors=0
probe_ok=0
probe_fail=0
map_rotations=0
if [[ -d "${SM_LOG_DIR}" ]]; then
  shopt -s nullglob
  sm_logs=("${SM_LOG_DIR}"/*.log)
  shopt -u nullglob
  sm_log_files="${#sm_logs[@]}"
  if [[ ${#sm_logs[@]} -gt 0 ]]; then
    sm_log_errors="$(grep -Eic \
      '(\[SM\][[:space:]]+(Encountered error|Fatal|Exception|Error))|(Failed to (load|open|create|initialize))|(Native error)|(Parse error)' \
      "${sm_logs[@]}" 2>/dev/null || true)"
    sm_log_errors="${sm_log_errors:-0}"
    probe_ok=0
    probe_fail=0
    probe_clean=0
    map_rotations=0
    for f in "${sm_logs[@]}"; do
      n="$(grep -c '\[css34_botplay\] abi_probe ok=' "${f}" 2>/dev/null || true)"
      probe_ok=$((probe_ok + n))
      n="$(grep -Ec '\[css34_botplay\] abi_probe ok=[0-9]+ fail=0($|[^0-9])' "${f}" 2>/dev/null || true)"
      probe_clean=$((probe_clean + n))
      n="$(grep -Ec '\[css34_botplay\] abi_probe ok=[0-9]+ fail=[1-9]' "${f}" 2>/dev/null || true)"
      probe_fail=$((probe_fail + n))
      n="$(grep -c '\[css34_botplay\] map_rotate' "${f}" 2>/dev/null || true)"
      map_rotations=$((map_rotations + n))
    done
  fi
fi

if [[ "${map_rotations}" -eq 0 ]]; then
  map_rotations="$(count_pattern "${ENGINE_CONSOLE_LOG}" 'Started map|changelevel|Loading map')"
fi

record_secs="${RECORD_SECS:-600}"
map_name="${MAP:-de_dust2}"
profile_name="${BOTPLAY_PROFILE:-rom4s}"
botplay_cfg_name="${BOTPLAY_CFG:-botplay-stress.cfg}"
mm_version="${MM_VERSION_EXPECT:-}"
sm_version="${SM_VERSION_EXPECT:-}"

mkdir -p "$(dirname "${OUT_JSON}")"
cat >"${OUT_JSON}" <<EOF
{
  "profile": "${profile_name}",
  "packages": {
    "metamod": "${mm_version}",
    "sourcemod": "${sm_version}"
  },
  "map": "${map_name}",
  "record_secs": ${record_secs},
  "botplay_cfg": "${botplay_cfg_name}",
  "sources": {
    "botplay_log": "$(basename "${BOTPLAY_LOG}")",
    "engine_console_log": "$(basename "${ENGINE_CONSOLE_LOG}")",
    "sm_log_dir": "addons/sourcemod/logs"
  },
  "events": {
    "round_start": ${round_start},
    "round_end": ${round_end},
    "player_death": ${player_death}
  },
  "per_source": {
    "console": {
      "round_start": ${round_start_console},
      "round_end": ${round_end_console},
      "player_death": ${player_death_console}
    },
    "botplay_log": {
      "round_start": ${round_start_botplay},
      "round_end": ${round_end_botplay},
      "player_death": ${player_death_botplay}
    }
  },
  "smac": {
    "running_plugins": ${smac_running},
    "failed_plugins": ${smac_failed}
  },
  "stability": {
    "crash": $( [[ "${crash}" -eq 1 ]] && echo true || echo false ),
    "sm_log_files": ${sm_log_files},
    "sm_log_errors": ${sm_log_errors}
  },
  "stress": {
    "map_rotations": ${map_rotations},
    "abi_probe_rounds": ${probe_ok},
    "abi_probe_clean_rounds": ${probe_clean},
    "abi_probe_fail_rounds": ${probe_fail}
  }
}
EOF

{
  echo "Botplay parse report"
  echo "===================="
  echo "Profile:          ${profile_name}"
  echo "Packages:         MM ${mm_version:-?} + SM ${sm_version:-?}"
  echo "Map:              ${map_name}"
  echo "Botplay cfg:      ${botplay_cfg_name}"
  echo "Record duration:  ${record_secs}s"
  echo ""
  echo "Game events (engine console preferred):"
  echo "  round_start:   ${round_start}"
  echo "  round_end:     ${round_end}"
  echo "  player_death:  ${player_death}"
  echo ""
  echo "SMAC plugins:"
  echo "  running: ${smac_running}"
  echo "  failed:  ${smac_failed}"
  echo ""
  echo "Stability:"
  echo "  crash markers: $( [[ "${crash}" -eq 1 ]] && echo yes || echo no )"
  echo "  SM log files:  ${sm_log_files}"
  echo "  SM log errors: ${sm_log_errors}"
  echo ""
  echo "Stress:"
  echo "  map rotations: ${map_rotations}"
  echo "  abi_probe rounds logged: ${probe_ok}"
  echo "  abi_probe clean (fail=0): ${probe_clean}"
  echo "  abi_probe fail rounds: ${probe_fail}"
  echo ""
  echo "Sample round_start lines:"
  first_matches "${ENGINE_CONSOLE_LOG}" "${ROUND_START_PAT}" 3 | sed 's/^/  /'
  first_matches "${BOTPLAY_LOG}" "${ROUND_START_PAT}" 3 | sed 's/^/  /'
  echo ""
  echo "Sample player_death lines:"
  first_matches "${ENGINE_CONSOLE_LOG}" "${PLAYER_DEATH_PAT}" 3 | sed 's/^/  /'
  first_matches "${BOTPLAY_LOG}" "${PLAYER_DEATH_PAT}" 3 | sed 's/^/  /'
} >"${OUT_TXT}"

cat "${OUT_TXT}"
echo ""
echo "JSON report: ${OUT_JSON}"
