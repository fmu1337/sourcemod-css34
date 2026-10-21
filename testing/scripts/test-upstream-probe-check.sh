#!/usr/bin/env bash
# Show that check-upstream-probe.sh fails when a counter is wrong.
# Each case is the log line a deliberately broken probe would emit.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CHECK="${ROOT}/testing/scripts/check-upstream-probe.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT

good='L 00/00/0000 - 00:00:00: [css34_upstream_probe] round=4 sound_first=1 sound_second=1 sound_saw=1 sound_bad=0 output_fresh=2 output_stale=0 output_miss=0 output_maps=1 userid_ok=3 userid_bad=0'

write_log() {
  printf '%s\n' "$1" > "${tmp}/probe.log"
}

expect_fail() {
  local name="$1"
  local version="$2"
  local body="$3"
  write_log "${body}"
  local out
  if out="$("${CHECK}" --sm-version "${version}" "${tmp}/probe.log" 2>&1)"; then
    echo "FAIL: ${name} was accepted" >&2
    printf '%s\n' "${out}" >&2
    exit 1
  fi
  if ! grep -q '^FAIL:' <<<"${out}"; then
    echo "FAIL: ${name} did not print FAIL:" >&2
    printf '%s\n' "${out}" >&2
    exit 1
  fi
  echo "OK: broken case rejected: ${name}"
  printf '%s\n' "${out}" | grep '^FAIL:' | head -n 2
}

expect_pass() {
  local name="$1"
  local version="$2"
  local body="$3"
  write_log "${body}"
  "${CHECK}" --sm-version "${version}" "${tmp}/probe.log" >/dev/null
  echo "OK: accepted: ${name}"
}

expect_pass "sm13 chain" "1.13.0.7478" "${good}"
expect_pass "sm12 without chain" "1.12.0.7257" \
  'L 00/00/0000 - 00:00:00: [css34_upstream_probe] round=4 sound_first=1 sound_second=0 sound_saw=0 sound_bad=0 output_fresh=2 output_stale=0 output_miss=0 output_maps=1 userid_ok=3 userid_bad=0'

expect_fail "sound chain missing on 1.13.0.7478" "1.13.0.7478" \
  'L 00/00/0000 - 00:00:00: [css34_upstream_probe] round=4 sound_first=1 sound_second=0 sound_saw=0 sound_bad=0 output_fresh=2 output_stale=0 output_miss=0 output_maps=1 userid_ok=3 userid_bad=0'

expect_fail "sound edits dropped" "1.13.0.7478" \
  'L 00/00/0000 - 00:00:00: [css34_upstream_probe] round=4 sound_first=1 sound_second=1 sound_saw=0 sound_bad=1 output_fresh=2 output_stale=0 output_miss=0 output_maps=1 userid_ok=3 userid_bad=0'

expect_fail "stale entity output hook" "1.12.0.7257" \
  'L 00/00/0000 - 00:00:00: [css34_upstream_probe] round=4 sound_first=1 sound_second=0 sound_saw=0 sound_bad=0 output_fresh=2 output_stale=1 output_miss=0 output_maps=1 userid_ok=3 userid_bad=0'

expect_fail "userid lookup" "1.12.0.7256" \
  'L 00/00/0000 - 00:00:00: [css34_upstream_probe] round=4 sound_first=1 sound_second=0 sound_saw=0 sound_bad=0 output_fresh=2 output_stale=0 output_miss=0 output_maps=1 userid_ok=0 userid_bad=1'

expect_fail "missing probe line" "1.13.0.7478" \
  'L 00/00/0000 - 00:00:00: [css34_dhooks_probe] round=1 available=1'

echo "upstream probe checker fixtures passed"
