#!/usr/bin/env bash
# T2.3 acceptance on the SM 1.11 dual-core build log:
#   - ep1 (1.ep1 core) compiles against MM 1.10 core-css34legacy,
#   - episode1 (2.ep1 core) compiles against the MM 1.12 input from lines.json,
#   - no patcher printed WARN (fail-closed patching).
#
# Usage: check-sm11-build-log.sh <build.log> [line]
set -euo pipefail

log="${1:?build log path required}"
line="${2:-sm11-oldstable}"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fail=0

[[ -f "${log}" ]] || { echo "FAIL: build log not found: ${log}" >&2; exit 1; }

legacy_dir=""
modern_dir=""
while IFS=$'\t' read -r role dirname mode _branch _commit _rev _version; do
  case "${mode}" in
    1.10) legacy_dir="${dirname}" ;;
    1.12) modern_dir="${dirname}" ;;
  esac
done < <(bash "${root}/builder/py.sh" "${root}/builder/resolve-metamod-pins.py" "${line}")
if [[ -z "${legacy_dir}" || -z "${modern_dir}" ]]; then
  echo "FAIL: ${line} does not resolve to one MM 1.10 and one MM 1.12 input" >&2
  exit 1
fi

require_line() {
  local pattern="$1" label="$2"
  if grep -Eq -- "${pattern}" "${log}"; then
    echo "OK: ${label}"
  else
    echo "FAIL: ${label} (no line matching: ${pattern})" >&2
    fail=1
  fi
}
require_line "==> Using Metamod core-css34legacy include path for ep1: .*/${legacy_dir}/core-css34legacy\$" \
  "ep1 includes ${legacy_dir}/core-css34legacy"
require_line "==> Using Metamod core include path for episode1: .*/${modern_dir}/core\$" \
  "episode1 includes ${modern_dir}/core"

# Any other include root for episode1 means 2.ep1 was built against the wrong Metamod.
if grep -E -- '==> Using Metamod core include path for episode1: ' "${log}" \
    | grep -Ev -- "/${modern_dir}/core\$" | grep -q .; then
  echo "FAIL: episode1 also built against another Metamod root:" >&2
  grep -E -- '==> Using Metamod core include path for episode1: ' "${log}" \
    | grep -Ev -- "/${modern_dir}/core\$" | sort -u >&2
  fail=1
fi

# Patchers print "WARN: ..." on a skipped anchor; pip's "WARNING:" is not ours.
warn_lines="$(grep -E -- '(^|[^A-Za-z])WARN:' "${log}" || true)"
if [[ -n "${warn_lines}" ]]; then
  echo "FAIL: $(grep -c . <<<"${warn_lines}") WARN line(s) in the ${line} build log:" >&2
  sort -u <<<"${warn_lines}" | head -n 20 >&2
  fail=1
else
  echo "OK: 0 WARN lines in the ${line} build log"
fi

exit "${fail}"
