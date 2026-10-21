#!/usr/bin/env bash
# Fail when generated pin copies drift, or a commit SHA is copied back into a workflow.
# MM fallback SHAs in the builder scripts stay until a later change removes them.
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
  if ! grep -Fq -- "$needle" "$file"; then
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

matrix="$repo_root/builder/generated/ci-matrix.json"
expect_file_contains "$matrix" "$sm12_commit" "ci-matrix.json sm12 commit"
expect_file_contains "$matrix" "$sm13_commit" "ci-matrix.json sm13-latest commit"
expect_file_contains "$matrix" "$mm112_commit" "ci-matrix.json MM 1.12 commit"
expect_file_contains "$matrix" "1.12.0.${sm12_rev}" "ci-matrix.json sm12 version string"
expect_file_contains "$matrix" "1.13.0.${sm13_rev}" "ci-matrix.json sm13-latest version string"

tag_map="$repo_root/builder/generated/tag-map.sh"
expect_file_contains "$tag_map" "${sm12_tag})" "tag-map.sh sm12 tag"
expect_file_contains "$tag_map" "${sm13_tag})" "tag-map.sh sm13-latest tag"

# Workflows load matrices at runtime. A full SHA here is a second pin copy.
if grep -R -E -n '[0-9a-f]{40}' .github/workflows; then
  note_fail ".github/workflows still embeds a full commit SHA; generate the matrix from lines.json"
fi

# Local build fallbacks are still hand-written (not part of the generated matrix).
expect_file_contains "$repo_root/builder/checkout-deps.sh" "$mm112_commit" "checkout-deps.sh MM fallback"
expect_file_contains "$repo_root/builder/write-build-stamps.sh" "$mm112_commit" "write-build-stamps.sh MM fallback"

if [[ "$failures" -gt 0 ]]; then
  echo "==> ${failures} pin consistency error(s). See docs/JULES_DAILY_VERSION_BUMP.md" >&2
  exit 1
fi

echo "==> Generated matrices, tag map, and MM fallbacks match"
echo "OK: testing/versions/matrix.json is historical and is not a pin source"
