#!/usr/bin/env bash
# Print latest AlliedMods git tips (rev-list count + full SHA) for daily bump checks.
set -euo pipefail

cache="${TMPDIR:-/tmp}/css34-upstream-tips"
mkdir -p "$cache"

fetch_tip() {
  local name="$1"
  local url="$2"
  local ref="$3"
  local dir="$cache/$name"

  if [[ ! -d "$dir/.git" ]]; then
    git clone --quiet --filter=blob:none --no-checkout "$url" "$dir"
  fi
  git -C "$dir" fetch --quiet --depth 1 origin "$ref"
  local sha
  sha="$(git -C "$dir" rev-parse "FETCH_HEAD")"
  local count
  count="$(git -C "$dir" rev-list --count "$sha")"
  printf '%s %s %s\n' "$name" "$count" "$sha"
}

# shellcheck source=/dev/null
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/versions.env"

echo "==> Upstream tips (AlliedMods git)"
read -r _ sm12_up _ < <(fetch_tip sourcemod-112 https://github.com/alliedmodders/sourcemod.git 1.12-dev)
read -r _ sm13_up _ < <(fetch_tip sourcemod-113 https://github.com/alliedmodders/sourcemod.git master)
read -r _ mm112_up _ < <(fetch_tip mmsource-112 https://github.com/alliedmodders/metamod-source.git 1.12-dev)

echo "sm12-latest upstream: git${sm12_up} (pinned: git${SM_LATEST_REV})"
echo "sm13-latest upstream: git${sm13_up} (pinned: git${SM_LATEST_13_REV})"
echo "MM 1.12 upstream:     git${mm112_up} (pinned: git$(git -C "$cache/mmsource-112" rev-list --count "${MM_112_COMMIT}" 2>/dev/null || echo '?'))"

needs_bump=0
if [[ "$sm12_up" != "$SM_LATEST_REV" ]]; then
  echo "ACTION: sm12-latest bump available (${SM_LATEST_REV} -> ${sm12_up})"
  needs_bump=1
fi
if [[ "$sm13_up" != "$SM_LATEST_13_REV" ]]; then
  echo "ACTION: sm13-latest bump available (${SM_LATEST_13_REV} -> ${sm13_up})"
  needs_bump=1
fi
mm_pinned_count="$(git -C "$cache/mmsource-112" rev-list --count "$MM_112_COMMIT")"
if [[ "$mm112_up" != "$mm_pinned_count" ]]; then
  echo "ACTION: MM 1.12 bump available (git${mm_pinned_count} -> git${mm112_up})"
  needs_bump=1
fi

if [[ "$needs_bump" -eq 0 ]]; then
  echo "OK: pins match upstream tips"
else
  exit 2
fi
