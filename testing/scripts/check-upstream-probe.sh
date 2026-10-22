#!/usr/bin/env bash
# Require css34_upstream_probe counters from a botplay log.
# A missing line, a bad counter, or a sound-hook chain miss on a build that
# contains #2586 is a failure. There is no WARN path.
set -euo pipefail

# #2586 is SM 1.13.0.7475 (2ed5b865). 1.12-dev through 7257 does not have it.
SOUND_CHAIN_MAJOR=13
SOUND_CHAIN_REV=7475

usage() {
  echo "usage: $0 --sm-version <1.major.0.rev> <log> [log...]" >&2
  exit 2
}

sm_version=""
logs=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --sm-version)
      sm_version="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      ;;
    *)
      logs+=("$1")
      shift
      ;;
  esac
done

if [[ -z "${sm_version}" || ${#logs[@]} -eq 0 ]]; then
  usage
fi

if [[ ! "${sm_version}" =~ ^1\.([0-9]+)\.0\.([0-9]+)$ ]]; then
  echo "FAIL: upstream probe: SM version '${sm_version}' is not 1.<major>.0.<rev>" >&2
  exit 1
fi
sm_major="${BASH_REMATCH[1]}"
sm_rev="${BASH_REMATCH[2]}"

require_chain=0
if [[ "${sm_major}" -gt "${SOUND_CHAIN_MAJOR}" ]] || {
  [[ "${sm_major}" -eq "${SOUND_CHAIN_MAJOR}" ]] && [[ "${sm_rev}" -ge "${SOUND_CHAIN_REV}" ]]
}; then
  require_chain=1
fi

line="$(grep -h '\[css34_upstream_probe\] round=' "${logs[@]}" 2>/dev/null | tail -n1 || true)"
if [[ -z "${line}" ]]; then
  echo "FAIL: no [css34_upstream_probe] round= line in SM logs" >&2
  exit 1
fi

field() {
  local v
  v="$(printf '%s\n' "${line}" | grep -Eo " $1=[0-9]+" | grep -Eo '[0-9]+' | tail -n1 || true)"
  echo "${v:-0}"
}

failed=0
require_min() {
  local label="$1" got="$2" min="$3"
  if [[ "${got}" -lt "${min}" ]]; then
    echo "FAIL: ${label} (${got} < ${min})" >&2
    failed=1
  else
    echo "OK: ${label} (${got} >= ${min})"
  fi
}
require_zero() {
  local label="$1" got="$2"
  if [[ "${got}" -ne 0 ]]; then
    echo "FAIL: ${label} (${got} > 0)" >&2
    failed=1
  else
    echo "OK: ${label} (0)"
  fi
}

require_min "upstream userid lookup hits" "$(field userid_ok)" 1
require_zero "upstream userid lookup failures" "$(field userid_bad)"
require_min "upstream entity output hook hits" "$(field output_fresh)" 1
require_min "upstream entity output map changes" "$(field output_maps)" 1
require_zero "upstream stale entity output hooks" "$(field output_stale)"
require_zero "upstream entity output misses" "$(field output_miss)"
require_min "upstream sound hook hits" "$(field sound_first)" 1
require_zero "upstream sound hook failures" "$(field sound_bad)"

sound_second="$(field sound_second)"
sound_saw="$(field sound_saw)"
if [[ "${require_chain}" -eq 1 ]]; then
  require_min "upstream sound Plugin_Changed chain" "${sound_second}" 1
  require_min "upstream sound Plugin_Changed edits visible" "${sound_saw}" 1
elif [[ "${sound_second}" -ge 1 ]]; then
  require_min "upstream sound Plugin_Changed edits visible" "${sound_saw}" 1
  echo "OK: sound Plugin_Changed chain ran (build ${sm_version} is below 1.${SOUND_CHAIN_MAJOR}.0.${SOUND_CHAIN_REV}; chain not required)"
else
  echo "OK: sound Plugin_Changed chain not required on ${sm_version} (fix is 1.${SOUND_CHAIN_MAJOR}.0.${SOUND_CHAIN_REV}+); second hook did not run"
fi

if [[ "${failed}" -ne 0 ]]; then
  echo "FAIL: upstream probe line: ${line}" >&2
  exit 1
fi

echo "OK: upstream probe (${sm_version})"
exit 0
