#!/usr/bin/env bash
# Fail when generated pin copies drift, or a commit SHA is copied back into a workflow
# or a builder script.
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

# The builder takes every SourceMod / Metamod pin from resolve-version.sh and
# resolve-metamod-pins.py: a pinned commit in a builder script is a stale copy.
for pin in "$SM_LATEST_COMMIT" "$SM_LATEST_13_COMMIT" "$MM_112_COMMIT" "$MM_110_COMMIT"; do
  if grep -R -F -n "$pin" builder --include='*.sh' --include='*.ps1'; then
    note_fail "builder scripts copy pinned commit ${pin:0:12}; read it from builder/versions.env"
  fi
done

if [[ "$failures" -gt 0 ]]; then
  echo "==> ${failures} pin consistency error(s). See docs/MAINTAINING.md" >&2
  exit 1
fi

echo "==> Generated matrices and tag map match; no pin copies in workflows or builder scripts"
