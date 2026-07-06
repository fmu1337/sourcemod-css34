#!/usr/bin/env bash
# Verify a css34 package matches the rom4s v1.11.0.6572 layout.
set -euo pipefail

archive="${1:?path to .tar.gz or extracted package root required}"

if [ -f "$archive" ]; then
  work="$(mktemp -d)"
  trap 'rm -rf "$work"' EXIT
  tar -xzf "$archive" -C "$work"
  root="$work"
else
  root="$archive"
fi

sm="$root/addons/sourcemod"
fail=0

check() {
  local rel="$1"
  if [ ! -e "$root/$rel" ]; then
    echo "MISSING: $rel" >&2
    fail=1
  else
    echo "OK: $rel"
  fi
}

echo "==> Verifying css34 package layout"
check "addons/metamod/sourcemod.vdf"
check "addons/sourcemod/bin/sourcemod.1.ep1.so"
check "addons/sourcemod/bin/sourcemod.2.ep1.so"
check "addons/sourcemod/extensions/dbi.mysql.ext.so"
check "addons/sourcemod/extensions/dbi.sqlite.ext.so"
check "addons/sourcemod/extensions/game.cstrike.ext.1.ep1.so"
check "addons/sourcemod/extensions/game.cstrike.ext.2.ep1.so"
check "addons/sourcemod/gamedata/sm-cstrike.games/game.cstrike.txt"
check "cfg/sourcemod/sourcemod.cfg"

if [ -f "$sm/configs/core.cfg" ]; then
  if grep -q '"DisableAutoUpdate"[[:space:]]*"yes"' "$sm/configs/core.cfg"; then
    echo "OK: core.cfg DisableAutoUpdate=yes"
  else
    echo "WARN: core.cfg DisableAutoUpdate is not yes" >&2
  fi
fi

if [ "$fail" -ne 0 ]; then
  echo "==> Verification FAILED" >&2
  exit 1
fi

echo "==> Verification passed"
