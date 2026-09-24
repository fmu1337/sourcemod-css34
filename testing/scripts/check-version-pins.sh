#!/usr/bin/env bash
# Fail when version pins drift across builder/versions.env, matrix.json, CI, and fallbacks.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

# shellcheck source=/dev/null
source "$repo_root/builder/versions.env"

failures=0
note_fail() {
  echo "FAIL: $*" >&2
  failures=$((failures + 1))
}

expect_file_contains() {
  local file="$1"
  local needle="$2"
  local label="$3"
  if ! grep -Fq "$needle" "$file"; then
    note_fail "${label}: ${file} missing '${needle}'"
  fi
}

sm12_rev="$SM_LATEST_REV"
sm12_commit="$SM_LATEST_COMMIT"
sm13_rev="$SM_LATEST_13_REV"
sm13_commit="$SM_LATEST_13_COMMIT"
mm112_commit="$MM_112_COMMIT"

sm12_tag="1.12.0.${sm12_rev}-mm1.12.0"
sm13_tag="1.13.0.${sm13_rev}-mm1.12.0"

echo "==> Pin source: builder/versions.env"
echo "    sm12-latest SM ${sm12_rev} (${sm12_commit:0:12})"
echo "    sm13-latest SM ${sm13_rev} (${sm13_commit:0:12})"
echo "    MM 1.12 (${mm112_commit:0:12})"

# matrix.json lines must match versions.env
python3 - "$repo_root/testing/versions/matrix.json" "$sm12_rev" "$sm12_commit" "$mm112_commit" \
  "$sm13_rev" "$sm13_commit" <<'PY'
import json, sys
path, sm12_rev, sm12_commit, mm_commit, sm13_rev, sm13_commit = sys.argv[1:7]
with open(path) as f:
    data = json.load(f)
lines = data["lines"]
checks = [
    ("sm12-latest", f"1.12.0.{sm12_rev}", sm12_commit, mm_commit),
    ("sm13-latest", f"1.13.0.{sm13_rev}", sm13_commit, mm_commit),
    ("sm13-dev", "1.13.0.7404", "cdedec7606f1ee9bf3685b2cce3620fbec90efa8", mm_commit),
]
for line, expect_sm, commit, mm in checks:
    row = lines[line]
    if row["sourcemod"] != expect_sm:
        print(f"FAIL: matrix lines.{line}.sourcemod = {row['sourcemod']} (expected {expect_sm})", file=sys.stderr)
        sys.exit(1)
    if row["sourcemod_commit"] != commit:
        print(f"FAIL: matrix lines.{line}.sourcemod_commit mismatch", file=sys.stderr)
        sys.exit(1)
    if row["metamod_commit"] != mm:
        print(f"FAIL: matrix lines.{line}.metamod_commit mismatch", file=sys.stderr)
        sys.exit(1)

releases = data["releases"]
sm12_key = f"1.12.0.{sm12_rev}-mm1.12.0"
sm13_key = f"1.13.0.{sm13_rev}-mm1.12.0"
if sm12_key not in releases:
    print(f"FAIL: matrix releases missing '{sm12_key}' (stale release key still present?)", file=sys.stderr)
    sys.exit(1)
if sm13_key not in releases:
    print(f"FAIL: matrix releases missing '{sm13_key}'", file=sys.stderr)
    sys.exit(1)
if releases[sm12_key]["sourcemod"] != f"1.12.0-git{sm12_rev}":
    print("FAIL: matrix releases sm12-latest sourcemod string mismatch", file=sys.stderr)
    sys.exit(1)
if releases[sm13_key]["sourcemod"] != f"1.13.0-git{sm13_rev}":
    print("FAIL: matrix releases sm13-latest sourcemod string mismatch", file=sys.stderr)
    sys.exit(1)
print("OK: testing/versions/matrix.json")
PY

# CI workflow matrices (test-server.yml embeds commit SHAs)
ci_matrix="$repo_root/.github/workflows/test-server.yml"
expect_file_contains "$ci_matrix" "$sm12_commit" "test-server.yml sm12 commit"
expect_file_contains "$ci_matrix" "$sm13_commit" "test-server.yml sm13-latest commit"
expect_file_contains "$ci_matrix" "$mm112_commit" "test-server.yml MM 1.12 commit"
expect_file_contains "$ci_matrix" "1.12.0.${sm12_rev}" "test-server.yml sm12 version string"
expect_file_contains "$ci_matrix" "1.13.0.${sm13_rev}" "test-server.yml sm13-latest version string"

# release.yml maps tags only (no commit SHAs)
expect_file_contains "$repo_root/.github/workflows/release.yml" "${sm12_tag})" "release.yml sm12 tag mapping"
expect_file_contains "$repo_root/.github/workflows/release.yml" "${sm13_tag})" "release.yml sm13-latest tag mapping"

# Local build fallbacks (Jules often forgets these)
expect_file_contains "$repo_root/builder/checkout-deps.sh" "$mm112_commit" "checkout-deps.sh MM fallback"
expect_file_contains "$repo_root/builder/write-build-stamps.sh" "$mm112_commit" "write-build-stamps.sh MM fallback"

if [[ "$failures" -gt 0 ]]; then
  echo "==> ${failures} pin consistency error(s). See docs/JULES_DAILY_VERSION_BUMP.md" >&2
  exit 1
fi

echo "==> All version pins consistent"
