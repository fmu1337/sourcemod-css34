#!/usr/bin/env bash
# Fail when commit SHAs leak back into workflows or builder fallbacks.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

failures=0
note_fail() {
  echo "FAIL: $*" >&2
  failures=$((failures + 1))
}

if grep -R -E -n '[0-9a-f]{40}' .github/workflows; then
  note_fail ".github/workflows still embeds a full commit SHA; load builder/generated/ci-matrix.json"
fi

for file in builder/checkout-deps.sh builder/write-build-stamps.sh testing/scripts/smoke-test.sh; do
  if grep -E -n '[0-9a-f]{40}' "$file"; then
    note_fail "${file} still has a hardcoded commit fallback"
  fi
done

python3 - "$repo_root/testing/versions/matrix.json" <<'PY'
import json, sys
path = sys.argv[1]
with open(path) as handle:
    data = json.load(handle)
removed = [key for key in ("lines", "releases", "metamod_pins") if key in data]
if removed:
    print("FAIL: matrix.json still has pin copies: " + ", ".join(removed), file=sys.stderr)
    sys.exit(1)
for key in ("compatibility", "reference"):
    if key not in data or not data[key]:
        print("FAIL: matrix.json missing historical " + key, file=sys.stderr)
        sys.exit(1)
print("OK: testing/versions/matrix.json is history/compatibility only")
PY

if [[ "$failures" -gt 0 ]]; then
  echo "==> ${failures} pin consistency error(s)" >&2
  exit 1
fi

echo "==> Workflows and fallbacks have no copied commit pins"
