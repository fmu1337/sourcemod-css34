#!/usr/bin/env bash
set -euo pipefail

sourcemod_dir="${1:?sourcemod directory required}"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PY=(bash "$script_dir/../py.sh")

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

# MM 1.10 core-legacy SourceHook (SH v4) has SH_DECL_MANUALHOOK* but not
# SH_DECL_MANUALEXTERN*. SM ≥6970 dropped the `#if defined` guards around
# TakeDamage/DropWeapon SH_MCALL paths that 6572 kept. Restore guards and use
# the BinTools VCall path when MANUALEXTERN is unavailable.
SOURCEMOD_DIR="$sourcemod_dir" "${PY[@]}" - <<'PY'
from pathlib import Path
import os

path = Path(os.environ['SOURCEMOD_DIR']) / 'extensions/sdkhooks/natives.cpp'
if not path.exists():
    raise SystemExit(0)
text = path.read_text()
if 'css34: MANUALEXTERN guard for MM 1.10 / SH v4' in text:
    print('==> sdkhooks MANUALEXTERN guards already present')
    raise SystemExit(0)

old_decl = """SH_DECL_MANUALEXTERN1(OnTakeDamage, int, CTakeDamageInfoHack &);
SH_DECL_MANUALEXTERN3_void(Weapon_Drop, CBaseCombatWeapon *, const Vector *, const Vector *);
"""
new_decl = """/* css34: MANUALEXTERN guard for MM 1.10 / SH v4 (core-legacy has no MANUALEXTERN) */
#if defined SH_DECL_MANUALEXTERN1
SH_DECL_MANUALEXTERN1(OnTakeDamage, int, CTakeDamageInfoHack &);
SH_DECL_MANUALEXTERN3_void(Weapon_Drop, CBaseCombatWeapon *, const Vector *, const Vector *);
#endif
"""
if old_decl not in text:
    raise SystemExit('Failed to locate unguarded SH_DECL_MANUALEXTERN decls in sdkhooks/natives.cpp')
text = text.replace(old_decl, new_decl, 1)

# Prefer SH_MCALL only when MANUALEXTERN exists; otherwise always BinTools.
old_td = """\tif (params[0] < 9 || params[9] != 0)
\t{
\t\tSH_MCALL(pVictim, OnTakeDamage)((CTakeDamageInfoHack&)info);
\t}
\telse
\t{"""
new_td = """\tif ((params[0] < 9 || params[9] != 0)
#if defined SH_DECL_MANUALEXTERN1
\t\t)
\t{
\t\tSH_MCALL(pVictim, OnTakeDamage)((CTakeDamageInfoHack&)info);
\t}
\telse
\t{
#else
\t\t|| true)
\t{
\t\t/* css34: no MANUALEXTERN — always BinTools VCall on SH v4 */
#endif"""
if old_td not in text:
    raise SystemExit('Failed to locate TakeDamage SH_MCALL branch in sdkhooks/natives.cpp')
text = text.replace(old_td, new_td, 1)

old_dw_early = """\tif (addr != pContext->GetNullRef(SP_NULL_VECTOR))
\t{
\t\tvecTarget = Vector(
\t\t\tsp_ctof(addr[0]),
\t\t\tsp_ctof(addr[1]),
\t\t\tsp_ctof(addr[2]));
\t}
\telse
\t{
\t\tSH_MCALL(pPlayer, Weapon_Drop)((CBaseCombatWeapon *)pWeapon, NULL, NULL);
\t\treturn 0;
\t}

\tVector vecVelocity;
\tVector *pVecVelocity = nullptr;"""
new_dw_early = """\tVector *pVecTarget = &vecTarget;
\tif (addr != pContext->GetNullRef(SP_NULL_VECTOR))
\t{
\t\tvecTarget = Vector(
\t\t\tsp_ctof(addr[0]),
\t\t\tsp_ctof(addr[1]),
\t\t\tsp_ctof(addr[2]));
\t}
\telse
\t{
#if defined SH_DECL_MANUALEXTERN1
\t\tSH_MCALL(pPlayer, Weapon_Drop)((CBaseCombatWeapon *)pWeapon, NULL, NULL);
\t\treturn 0;
#else
\t\t/* css34: no MANUALEXTERN — BinTools with NULL target */
\t\tpVecTarget = nullptr;
#endif
\t}

\tVector vecVelocity;
\tVector *pVecVelocity = nullptr;"""
if old_dw_early not in text:
    raise SystemExit('Failed to locate DropWeapon null-target SH_MCALL in sdkhooks/natives.cpp')
text = text.replace(old_dw_early, new_dw_early, 1)

old_dw = """\tif (params[0] < 5 || params[5] != 0)
\t{
\t\tSH_MCALL(pPlayer, Weapon_Drop)((CBaseCombatWeapon*)pWeapon, &vecTarget, pVecVelocity);
\t}
\telse
\t{"""
new_dw = """\tif ((params[0] < 5 || params[5] != 0)
#if defined SH_DECL_MANUALEXTERN1
\t\t)
\t{
\t\tSH_MCALL(pPlayer, Weapon_Drop)((CBaseCombatWeapon*)pWeapon, pVecTarget, pVecVelocity);
\t}
\telse
\t{
#else
\t\t|| true)
\t{
\t\t/* css34: no MANUALEXTERN — always BinTools VCall on SH v4 */
#endif"""
if old_dw not in text:
    raise SystemExit('Failed to locate DropWeapon SH_MCALL branch in sdkhooks/natives.cpp')
text = text.replace(old_dw, new_dw, 1)

old_dw_exec = "pCall->Execute(ArgBuffer<CBaseEntity *, CBaseEntity *, Vector *, Vector *>(pPlayer, pWeapon, &vecTarget, pVecVelocity), nullptr);"
new_dw_exec = "pCall->Execute(ArgBuffer<CBaseEntity *, CBaseEntity *, Vector *, Vector *>(pPlayer, pWeapon, pVecTarget, pVecVelocity), nullptr);"
if old_dw_exec not in text:
    raise SystemExit('Failed to locate DropWeapon BinTools Execute in sdkhooks/natives.cpp')
text = text.replace(old_dw_exec, new_dw_exec, 1)

path.write_text(text)
print('==> Restored sdkhooks MANUALEXTERN guards for MM 1.10 / SH v4')
PY
