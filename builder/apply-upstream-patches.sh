#!/usr/bin/env bash
# Apply optional patches after apply-sourcemod.sh (API + toolchain for newer upstream).
set -euo pipefail

sourcemod_dir="${1:?sourcemod directory required}"
git_rev="${2:?git rev required}"
builder_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

need_toolchain=0
need_api=0

case "${SOURCEMOD_TOOLCHAIN_PATCHES:-auto}" in
  0) ;;
  1) need_toolchain=1 ;;
  auto)
    if [ "$git_rev" -ge 6800 ] 2>/dev/null; then
      need_toolchain=1
    fi
    ;;
esac

case "${SOURCEMOD_API_PATCHES:-auto}" in
  0) ;;
  1) need_api=1 ;;
  auto)
    if [ "$git_rev" -ge 6800 ] 2>/dev/null; then
      need_api=1
    fi
    ;;
esac

if [ "$need_toolchain" -eq 1 ]; then
  echo "==> Applying toolchain patches (upstream >= 6800)"
  "$builder_dir/patches/apply-toolchain.sh" "$sourcemod_dir"
fi

if [ "$need_api" -eq 1 ]; then
  echo "==> Applying API compatibility patches (upstream >= 6800)"
  "$builder_dir/patches/apply-api-compat.sh" "$sourcemod_dir"
fi
