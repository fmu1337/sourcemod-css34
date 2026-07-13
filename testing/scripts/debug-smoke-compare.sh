#!/usr/bin/env bash
# Compare built vs rom4s logic: boot trace + gdb snapshot side by side.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WAIT_SECS="${WAIT_SECS:-60}"
SCRIPT="${ROOT}/testing/scripts/debug-smoke-hang.sh"

for mode in built rom4s; do
  OUT="/tmp/smoke-compare-${mode}-$$"
  mkdir -p "${OUT}"
  echo "===== ${mode} ====="
  SERVER_DIR="${SERVER_DIR:-${ROOT}/.ci-server}" \
    LOGIC_MODE="${mode}" WAIT_SECS="${WAIT_SECS}" OUT_DIR="${OUT}" PORT="$((27020 + RANDOM % 100))" \
    "${SCRIPT}" || true
  echo
done

echo "=== boot trace diff (last 30 lines each) ==="
for mode in built rom4s; do
  echo "--- ${mode} ---"
  f="/tmp/smoke-compare-${mode}-$$/boot-trace.log"
  if [[ -f "$f" ]]; then tail -30 "$f"; else echo "(missing)"; fi
done
