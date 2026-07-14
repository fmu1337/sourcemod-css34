#!/usr/bin/env bash
# Compare a botplay candidate report against a rom4s (or other) baseline.
set -euo pipefail

BASELINE_JSON="${1:?BASELINE_JSON is required}"
CANDIDATE_JSON="${2:?CANDIDATE_JSON is required}"
OUT_TXT="${3:-botplay-compare.txt}"

COMPARE_MIN_RATIO="${COMPARE_MIN_RATIO:-0.75}"

json_field() {
  local file="$1" section="$2" key="$3"
  awk -v section="${section}" -v key="${key}" '
    $0 ~ "\"" section "\"" { in_section=1; next }
    in_section && $0 ~ "\"" key "\"" {
      for (i = 1; i <= NF; i++) {
        if ($i ~ /^[0-9]+,?$/ || $i ~ /^[0-9]+$/ || $i ~ /^true,?$/ || $i ~ /^false,?$/) {
          gsub(/,/, "", $i)
          print $i
          exit
        }
      }
    }
    in_section && $0 ~ /^\s*\}/ { in_section=0 }
  ' "${file}"
}

json_top_string() {
  awk -F'"' -v key="$2" '$0 ~ "\"" key "\"" { print $4; exit }' "$1"
}

min_from_ratio() {
  awk -v b="$1" -v r="${COMPARE_MIN_RATIO}" 'BEGIN { printf "%d", int(b * r + 0.999) }'
}

if [[ ! -f "${BASELINE_JSON}" ]]; then
  echo "FAIL: baseline missing: ${BASELINE_JSON}" >&2
  exit 1
fi
if [[ ! -f "${CANDIDATE_JSON}" ]]; then
  echo "FAIL: candidate missing: ${CANDIDATE_JSON}" >&2
  exit 1
fi

base_profile="$(json_top_string "${BASELINE_JSON}" profile)"
cand_profile="$(json_top_string "${CANDIDATE_JSON}" profile)"
base_mm="$(json_field "${BASELINE_JSON}" packages metamod)"
base_sm="$(json_field "${BASELINE_JSON}" packages sourcemod)"
cand_mm="$(json_field "${CANDIDATE_JSON}" packages metamod)"
cand_sm="$(json_field "${CANDIDATE_JSON}" packages sourcemod)"

base_round_start="$(json_field "${BASELINE_JSON}" events round_start)"
base_round_end="$(json_field "${BASELINE_JSON}" events round_end)"
base_player_death="$(json_field "${BASELINE_JSON}" events player_death)"
base_smac_running="$(json_field "${BASELINE_JSON}" smac running_plugins)"
base_smac_failed="$(json_field "${BASELINE_JSON}" smac failed_plugins)"

cand_round_start="$(json_field "${CANDIDATE_JSON}" events round_start)"
cand_round_end="$(json_field "${CANDIDATE_JSON}" events round_end)"
cand_player_death="$(json_field "${CANDIDATE_JSON}" events player_death)"
cand_smac_running="$(json_field "${CANDIDATE_JSON}" smac running_plugins)"
cand_smac_failed="$(json_field "${CANDIDATE_JSON}" smac failed_plugins)"
cand_crash="$(json_field "${CANDIDATE_JSON}" stability crash)"

fail=0
check_event() {
  local name="$1" base_val="$2" cand_val="$3"
  local min_allowed delta ok
  min_allowed="$(min_from_ratio "${base_val}")"
  delta=$((cand_val - base_val))
  ok="OK"
  if [[ "${cand_val}" -lt "${min_allowed}" ]]; then
    ok="FAIL"
    fail=1
  fi
  printf "  %-14s %5s %5s %+5s  min>=%s  %s\n" \
    "${name}" "${base_val}" "${cand_val}" "${delta}" "${min_allowed}" "${ok}"
}

{
  echo "Botplay comparison"
  echo "=================="
  echo "Baseline:  ${base_profile:-rom4s} (MM ${base_mm:-?} + SM ${base_sm:-?})"
  echo "Candidate: ${cand_profile:-built} (MM ${cand_mm:-?} + SM ${cand_sm:-?})"
  echo "Tolerance: candidate >= ${COMPARE_MIN_RATIO} x baseline per event metric"
  echo ""
  printf "  %-14s %5s %5s %5s  %-8s %s\n" "metric" "base" "built" "delta" "floor" "status"
  check_event "round_start" "${base_round_start}" "${cand_round_start}"
  check_event "round_end" "${base_round_end}" "${cand_round_end}"
  check_event "player_death" "${base_player_death}" "${cand_player_death}"
  echo ""
  if [[ "${cand_smac_running}" -lt "${base_smac_running}" ]]; then
    echo "FAIL: SMAC running ${cand_smac_running} < baseline ${base_smac_running}"
    fail=1
  else
    echo "OK: SMAC running ${cand_smac_running} >= baseline ${base_smac_running}"
  fi
  if [[ "${cand_smac_failed}" -gt "${base_smac_failed}" ]]; then
    echo "FAIL: SMAC failed ${cand_smac_failed} > baseline ${base_smac_failed}"
    fail=1
  else
    echo "OK: SMAC failed ${cand_smac_failed} <= baseline ${base_smac_failed}"
  fi
  if [[ "${cand_crash}" == "true" ]]; then
    echo "FAIL: candidate has crash markers"
    fail=1
  else
    echo "OK: candidate has no crash markers"
  fi
} | tee "${OUT_TXT}"

if [[ "${fail}" -ne 0 ]]; then
  echo "Comparison FAILED" >&2
  exit 1
fi

echo "Comparison PASSED"
exit 0
