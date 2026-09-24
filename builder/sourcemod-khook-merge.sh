#!/usr/bin/env bash
# Rebuild the css34 merge of SourceMod master into the KHook branch.
#
# The SourceMod KHook port (k/sourcehook_alternative) lags master. Instead of
# forking SourceMod, the builder recreates one fixed merge commit on top of the
# pinned KHook tip:
#   1. files listed in patches/sourcemod-khook-master-merge.take are taken
#      verbatim from the pinned master commit (incl. submodule gitlinks);
#   2. patches/sourcemod-khook-master-merge.patch carries the conflict
#      resolution for the files where both branches changed hook code;
#   3. the tree is committed with fixed metadata, so the resulting SHA is the
#      same on every host and is checked against SOURCEMOD_BUILD_COMMIT.
# Everything goes through the index, so core.autocrlf on Windows is harmless.
#
# Usage: sourcemod-khook-merge.sh <sourcemod dir>
# Env:   SOURCEMOD_MERGE_MASTER (no-op when empty), SOURCEMOD_BUILD_COMMIT
set -euo pipefail

sourcemod_dir="${1:?sourcemod directory required}"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
master="${SOURCEMOD_MERGE_MASTER:-}"
expected="${SOURCEMOD_BUILD_COMMIT:-}"

if [[ -z "$master" ]]; then
  exit 0
fi

take_list="$script_dir/patches/sourcemod-khook-master-merge.take"
resolution="$script_dir/patches/sourcemod-khook-master-merge.patch"
git_sm=(git -C "$sourcemod_dir")

echo "==> Merging SourceMod master ${master:0:10} into $("${git_sm[@]}" rev-parse --short HEAD)"
"${git_sm[@]}" fetch --depth=8192 origin "$master"

take_paths=()
remove_paths=()
while read -r status path; do
  [[ -z "$status" ]] && continue
  if [[ "$status" == D ]]; then
    remove_paths+=("$path")
  else
    take_paths+=("$path")
  fi
done < "$take_list"

"${git_sm[@]}" checkout "$master" -- "${take_paths[@]}"
if [[ ${#remove_paths[@]} -gt 0 ]]; then
  "${git_sm[@]}" rm -q -r --cached --ignore-unmatch -- "${remove_paths[@]}"
fi
"${git_sm[@]}" apply --cached "$resolution"

tree="$("${git_sm[@]}" write-tree)"
parent="$("${git_sm[@]}" rev-parse HEAD)"
commit="$(
  GIT_AUTHOR_NAME="sourcemod-css34" GIT_AUTHOR_EMAIL="builder@sourcemod-css34" \
  GIT_AUTHOR_DATE="2026-09-24T00:00:00+0000" \
  GIT_COMMITTER_NAME="sourcemod-css34" GIT_COMMITTER_EMAIL="builder@sourcemod-css34" \
  GIT_COMMITTER_DATE="2026-09-24T00:00:00+0000" \
  "${git_sm[@]}" commit-tree "$tree" -p "$parent" -p "$master" \
    -m "css34: merge SourceMod master ${master} into k/sourcehook_alternative"
)"
"${git_sm[@]}" reset -q --hard "$commit"

echo "==> SourceMod KHook + master merge commit: $commit"
if [[ -n "$expected" && "$commit" != "$expected" ]]; then
  echo "Merge commit $commit does not match SOURCEMOD_BUILD_COMMIT $expected" >&2
  echo "(the take list / resolution patch no longer reproduce the pinned tree)" >&2
  exit 1
fi
