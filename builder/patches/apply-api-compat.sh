#!/usr/bin/env bash
set -euo pipefail

sourcemod_dir="${1:?sourcemod directory required}"

cstrike_inc="$sourcemod_dir/plugins/include/cstrike.inc"
if [ -f "$cstrike_inc" ]; then
  sed -i 's/forward Action CS_OnCSWeaponDrop(int client, int weaponIndex, bool donated);/forward Action CS_OnCSWeaponDrop(int client, int weaponIndex, bool donated=false);/' "$cstrike_inc"
fi

sdktools_inc="$sourcemod_dir/plugins/include/sdktools_functions.inc"
if [ -f "$sdktools_inc" ] && ! grep -q 'stock void SetCollisionGroup' "$sdktools_inc"; then
  python3 - "$sdktools_inc" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text()
needle = "native void SetEntityCollisionGroup(int entity, int collisionGroup);"
insert = """native void SetEntityCollisionGroup(int entity, int collisionGroup);

/**
 * @deprecated Use SetEntityCollisionGroup instead.
 */
#pragma deprecated Use SetEntityCollisionGroup instead
stock void SetCollisionGroup(int entity, int collisionGroup)
{
\tSetEntityCollisionGroup(entity, collisionGroup);
}"""
if needle not in text:
    raise SystemExit('SetEntityCollisionGroup native not found in sdktools_functions.inc')
path.write_text(text.replace(needle, insert, 1))
PY
fi
