#!/usr/bin/env bash
# Check out SourceMod at the line's pinned commit (T3.3: no git submodule; the
# pin lives in builder/lines.json, resolved by resolve-version.sh).
#
#   builder/fetch-sourcemod.sh <sourcemod dir> <commit>
#
# Reuses an existing checkout (including an old submodule checkout) and leaves
# exactly the pinned tree: tracked files reset, untracked files removed, nested
# submodules (amtl, sourcepawn, ...) initialized at the commits it pins. Offline
# rebuilds rewrite the URL to the input archive's mirror (builder/docker/build.sh).
set -euo pipefail

dir="${1:?sourcemod directory required}"
commit="${2:?SourceMod commit required}"
url="${SOURCEMOD_URL:-https://github.com/alliedmodders/sourcemod}"

[[ "$commit" =~ ^[0-9a-f]{40}$ ]] || { echo "FAIL: SourceMod commit must be a full SHA: $commit" >&2; exit 1; }

if [[ ! -e "$dir/.git" ]]; then
  mkdir -p "$dir"
  git init -q "$dir"
fi
if git -C "$dir" remote get-url origin >/dev/null 2>&1; then
  git -C "$dir" remote set-url origin "$url"
else
  git -C "$dir" remote add origin "$url"
fi

# No on-demand recursive fetch: in a reused checkout it also fetches nested
# submodule commits named anywhere in the newly fetched history, and one that
# upstream no longer has (sourcepawn's mimalloc) fails the whole update.
# `submodule update --recursive` fetches each pinned nested commit itself.
git_sm() { git -c fetch.recurseSubmodules=false -C "$dir" "$@"; }

git_sm submodule foreach --quiet --recursive "git reset -q --hard && git clean -fdxq" 2>/dev/null || true
# Deep enough for the revision count AMBuild's Versioning reads.
git_sm fetch --depth=8192 origin "$commit"
git_sm checkout -q --force --detach "$commit"
git_sm clean -fdxq
git_sm submodule update --init --recursive

head="$(git -C "$dir" rev-parse HEAD)"
[[ "$head" == "$commit" ]] || { echo "FAIL: SourceMod is at $head, expected $commit" >&2; exit 1; }
echo "==> SourceMod ${commit:0:12} in $dir"
