#!/usr/bin/env bash
# Assert SourceMod logs under SM_LOG_DIR contain no error markers.
set -euo pipefail

SM_LOG_DIR="${1:?SM_LOG_DIR is required}"

if [[ ! -d "${SM_LOG_DIR}" ]]; then
  echo "FAIL: SourceMod log directory missing: ${SM_LOG_DIR}" >&2
  exit 1
fi

shopt -s nullglob
log_files=("${SM_LOG_DIR}"/*.log)
shopt -u nullglob

if [[ ${#log_files[@]} -eq 0 ]]; then
  echo "FAIL: no .log files in ${SM_LOG_DIR}" >&2
  exit 1
fi

# SM / extension failures we have seen in CI when boot breaks.
error_pattern='(\[SM\][[:space:]]+(Encountered error|Fatal|Exception|Error))|(Failed to (load|open|create|initialize))|(Could not (load|open|find|initialize))|(Unable to (load|open|find|initialize))|(Plugin file .+ (is invalid|failed))|(Error loading plugin)|(Parse error)|(Native error)|(SQL error)|(Exception reported)'

matches="$(grep -Ehin -- "${error_pattern}" "${log_files[@]}" || true)"
# css34: bintools is not built; splice may still race a stale extensions list entry.
matches="$(printf '%s\n' "${matches}" | grep -v 'Unable to load extension "bintools.ext"' || true)"

matches="$(grep -Ehin -- "${error_pattern}" "${log_files[@]}" || true)"
if [[ -n "${matches}" ]]; then
  echo "FAIL: error markers found in SourceMod logs:" >&2
  echo "${matches}" >&2
  exit 1
fi

echo "OK: no error markers in SourceMod logs (${#log_files[@]} file(s))"
exit 0
