#!/usr/bin/env bash
set -euo pipefail

sourcemod_dir="${1:?sourcemod directory required}"
ambuild_script="$sourcemod_dir/AMBuildScript"

if grep -q "CSS34 SDK compatibility" "$ambuild_script"; then
  sed -i '/CSS34 SDK compatibility/d' "$ambuild_script"
fi
if grep -q "CSS34 clang compatibility" "$ambuild_script"; then
  sed -i '/CSS34 clang compatibility/d' "$ambuild_script"
fi

sp_ambuild_script="$sourcemod_dir/sourcepawn/AMBuildScript"
if [ -f "$sp_ambuild_script" ] && grep -q "CSS34 clang compatibility" "$sp_ambuild_script"; then
  sed -i '/CSS34 clang compatibility/d' "$sp_ambuild_script"
fi

# Clang 15+ understands -Wno-deprecated-non-prototype; older distro clang does not.
# Probe with -Werror because SourceMod builds with -Werror and unknown -Wno-* is fatal then.
supports_deprecated_non_prototype=0
compiler="${CC:-clang}"
if echo 'int main(void){return 0;}' | "$compiler" -m32 -Werror -Wno-deprecated-non-prototype -x c - -c -o /dev/null 2>/dev/null; then
  supports_deprecated_non_prototype=1
fi

SOURCEMOD_DIR="$sourcemod_dir" SUPPORTS_WNO_DEPRECATED_NON_PROTOTYPE="$supports_deprecated_non_prototype" python3 - <<'PY'
from pathlib import Path
import os

sourcemod_dir = os.environ['SOURCEMOD_DIR']
supports_deprecated_non_prototype = os.environ.get('SUPPORTS_WNO_DEPRECATED_NON_PROTOTYPE') == '1'

path = Path(sourcemod_dir) / 'AMBuildScript'
text = path.read_text()

needle = "      '-fvisibility=hidden',\n    ]\n"
insert = """      '-fvisibility=hidden',
    ]
    cxx.cflags += ['-Wno-nonportable-include-path', '-Wno-macro-redefined', '-Wno-writable-strings']  # CSS34 SDK compatibility
    cxx.cxxflags += ['-Wno-reorder', '-Wno-reorder-ctor', '-Wno-attributes', '-fpermissive']  # CSS34 SDK compatibility
"""
if supports_deprecated_non_prototype:
    insert += "    cxx.cflags += ['-Wno-deprecated-non-prototype']  # CSS34 clang compatibility\n"
if needle not in text:
    raise SystemExit('Failed to locate compiler flags block in AMBuildScript')
text = text.replace(needle, insert, 1)

sp_script = Path(sourcemod_dir) / 'sourcepawn/AMBuildScript'
sp_text = sp_script.read_text()
if supports_deprecated_non_prototype and '-Wno-deprecated-non-prototype' not in sp_text:
    sp_text = sp_text.replace(
        "            '-Werror',\n            '-Wno-switch',",
        "            '-Werror',\n            '-Wno-switch',\n            '-Wno-deprecated-non-prototype',  # CSS34 clang compatibility",
    )
    sp_script.write_text(sp_text)

# CS:S v34 ships the Episode One SDK layout (linux_sdk/, tier0_i486.so).
text = text.replace(
    "      if sdk.name == 'episode1':\n        lib_folder = os.path.join(sdk.path, 'linux_sdk')",
    "      if sdk.name in ['episode1', 'css']:\n        lib_folder = os.path.join(sdk.path, 'linux_sdk')",
)

old_dynamic = (
    "      if sdk.name in ['css', 'hl2dm', 'dods', 'tf2', 'sdk2013', 'bms', 'nucleardawn', 'l4d2', 'insurgency', 'doi']:\n"
    "        dynamic_libs = ['libtier0_srv.so', 'libvstdlib_srv.so']"
)
new_dynamic = (
    "      if sdk.name in ['hl2dm', 'dods', 'tf2', 'sdk2013', 'bms', 'nucleardawn', 'l4d2', 'insurgency', 'doi']:\n"
    "        dynamic_libs = ['libtier0_srv.so', 'libvstdlib_srv.so']\n"
    "      elif sdk.name == 'css':\n"
    "        dynamic_libs = ['tier0_i486.so', 'vstdlib_i486.so']"
)
if old_dynamic not in text:
    raise SystemExit('Failed to locate dynamic_libs block in AMBuildScript')
text = text.replace(old_dynamic, new_dynamic, 1)

path.write_text(text)
PY

# Normalize line endings from the upstream SourceMod checkout.
while IFS= read -r -d '' file; do
  sed -i 's/\r$//' "$file"
done < <(find "$sourcemod_dir" -type f \( -name '*.h' -o -name '*.cpp' -o -name 'AMBuildScript' \) -print0)

# CS:S v34 is pre-Orange Box (Episode One SDK). Disable Orange Box-only code paths.
while IFS= read -r -d '' file; do
  if grep -q 'SOURCE_ENGINE >= SE_ORANGEBOX && SOURCE_ENGINE != SE_CSS' "$file"; then
    continue
  fi
  sed -i \
    -e 's/#if SOURCE_ENGINE >= SE_ORANGEBOX$/#if SOURCE_ENGINE >= SE_ORANGEBOX \&\& SOURCE_ENGINE != SE_CSS/g' \
    -e 's/#elif SOURCE_ENGINE >= SE_ORANGEBOX$/#elif SOURCE_ENGINE >= SE_ORANGEBOX \&\& SOURCE_ENGINE != SE_CSS/g' \
    "$file"
done < <(find "$sourcemod_dir" -type f \( -name '*.h' -o -name '*.cpp' \) -print0)

# Pre-Orange Box CS:S v34 uses SE_CSS=6 but lacks post-Episode-One APIs (SE_EYE+).
while IFS= read -r -d '' file; do
  if grep -q 'SOURCE_ENGINE >= SE_EYE && SOURCE_ENGINE != SE_CSS' "$file"; then
    continue
  fi
  sed -i \
    -e 's/#if SOURCE_ENGINE >= SE_EYE$/#if SOURCE_ENGINE >= SE_EYE \&\& SOURCE_ENGINE != SE_CSS/g' \
    -e 's/#elif SOURCE_ENGINE > SE_EYE \/\//#elif SOURCE_ENGINE > SE_EYE \&\& SOURCE_ENGINE != SE_CSS \/\//g' \
    "$file"
done < <(find "$sourcemod_dir" -type f \( -name '*.h' -o -name '*.cpp' \) -print0)

# Pre-Orange Box CS:S v34 lacks QueryCvar APIs guarded by != SE_DARKMESSIAH.
while IFS= read -r -d '' file; do
  sed -i 's/#if SOURCE_ENGINE != SE_DARKMESSIAH$/#if SOURCE_ENGINE != SE_DARKMESSIAH \&\& SOURCE_ENGINE != SE_CSS/g' "$file"
done < <(find "$sourcemod_dir/core" -type f \( -name 'GameHooks.*' -o -name 'ConVarManager.*' -o -name 'logic_bridge.cpp' \) -print0)

# Pre-Orange Box CS:S v34 has no QueryCvar API in the engine SDK.
compat_wrappers="$sourcemod_dir/public/compat_wrappers.h"
if ! grep -q 'SE_DARKMESSIAH || SOURCE_ENGINE == SE_CSS' "$compat_wrappers"; then
  sed -i 's/#if SOURCE_ENGINE == SE_DARKMESSIAH$/#if SOURCE_ENGINE == SE_DARKMESSIAH || SOURCE_ENGINE == SE_CSS/' "$compat_wrappers"
fi

# Episode One SDK uses legacy CON_COMMAND macros without a CCommand parameter.
while IFS= read -r -d '' file; do
  sed -i 's/#if SOURCE_ENGINE <= SE_DARKMESSIAH$/#if SOURCE_ENGINE <= SE_DARKMESSIAH || SOURCE_ENGINE == SE_CSS/g' "$file"
done < <(find "$sourcemod_dir" -type f \( -name '*.h' -o -name '*.cpp' \) -print0)

while IFS= read -r -d '' file; do
  sed -i 's/#if SOURCE_ENGINE <= SE_DARKMESSIAH || SOURCE_ENGINE == SE_CSS || SOURCE_ENGINE == SE_CSS/#if SOURCE_ENGINE <= SE_DARKMESSIAH || SOURCE_ENGINE == SE_CSS/g' "$file"
done < <(find "$sourcemod_dir" -type f \( -name '*.h' -o -name '*.cpp' \) -print0)

while IFS= read -r -d '' file; do
  sed -i 's/#if SOURCE_ENGINE <= SE_DARKMESSIAH$/#if SOURCE_ENGINE <= SE_DARKMESSIAH || SOURCE_ENGINE == SE_CSS/g' "$file"
done < <(find "$sourcemod_dir/extensions/sdktools" -type f \( -name 'vhelpers.cpp' -o -name 'tempents.cpp' \) -print0)

SOURCEMOD_DIR="$sourcemod_dir" python3 - <<'PY'
import os
from pathlib import Path

sourcemod_dir = os.environ['SOURCEMOD_DIR']
css_line = "\t|| SOURCE_ENGINE == SE_CSS     \\\n"

for rel in (
    'extensions/sdktools/vhelpers.cpp',
    'extensions/sdktools/vglobals.cpp',
    'extensions/sdktools/vnatives.cpp',
    'extensions/sdktools/tempents.cpp',
):
    path = Path(sourcemod_dir) / rel
    text = path.read_text().replace(css_line, "")
    path.write_text(text)

path = Path(sourcemod_dir) / 'extensions/sdktools/vhelpers.cpp'
text = path.read_text()
text = text.replace(
    "#if SOURCE_ENGINE < SE_ORANGEBOX\n\t\tCBaseEntity *pWorldEntity = nullptr;",
    "#if SOURCE_ENGINE < SE_ORANGEBOX || SOURCE_ENGINE == SE_CSS\n\t\tCBaseEntity *pWorldEntity = nullptr;",
)
path.write_text(text)

# Pre-Orange Box EmitSound hooks (14 params, no iSpecialDSP).
for rel in ('extensions/sdktools/vsound.cpp', 'extensions/sdktools/vsound.h'):
    path = Path(sourcemod_dir) / rel
    path.write_text(path.read_text().replace('SOURCE_ENGINE == SE_CSS || ', ''))

path = Path(sourcemod_dir) / 'extensions/sdkhooks/takedamageinfohack.h'
text = path.read_text()
text = text.replace(
    '#if SOURCE_ENGINE >= SE_ORANGEBOX && SOURCE_ENGINE != SE_LEFT4DEAD',
    '#if SOURCE_ENGINE >= SE_ORANGEBOX && SOURCE_ENGINE != SE_CSS && SOURCE_ENGINE != SE_LEFT4DEAD',
)
text = text.replace(
    '#if SOURCE_ENGINE < SE_ORANGEBOX\n\tinline int GetDamageCustom()',
    '#if SOURCE_ENGINE < SE_ORANGEBOX || SOURCE_ENGINE == SE_CSS\n\tinline int GetDamageCustom()',
)
path.write_text(text)

path = Path(sourcemod_dir) / 'extensions/sdkhooks/takedamageinfohack.cpp'
text = path.read_text()
text = text.replace(
    '#if SOURCE_ENGINE >= SE_ORANGEBOX && SOURCE_ENGINE != SE_LEFT4DEAD',
    '#if SOURCE_ENGINE >= SE_ORANGEBOX && SOURCE_ENGINE != SE_CSS && SOURCE_ENGINE != SE_LEFT4DEAD',
)
text = text.replace(
    "#if SOURCE_ENGINE < SE_ORANGEBOX\n\tm_iCustomKillType = 0;\n#else\n\tm_iDamageCustom = 0;\n#endif",
    "#if SOURCE_ENGINE < SE_ORANGEBOX || SOURCE_ENGINE == SE_CSS\n\tm_iCustomKillType = 0;\n#elif SOURCE_ENGINE >= SE_ORANGEBOX\n\tm_iDamageCustom = 0;\n#endif",
)
text = text.replace('SOURCE_ENGINE == SE_CSS || ', '')
path.write_text(text)

path = Path(sourcemod_dir) / 'extensions/cstrike/natives.cpp'
text = path.read_text()
old_block = """\t\tdatamap_t *pMap = gamehelpers->GetDataMap(pPlayerEntity);
\t\ttypedescription_t *td = gamehelpers->FindInDataMap(pMap, pszBaseVar);
\t\tif (td)
\t\t{
#if SOURCE_ENGINE >= SE_LEFT4DEAD
\t\t\tinterimOffset = td->fieldOffset;
#else
\t\t\tinterimOffset = td->fieldOffset[TD_OFFSET_NORMAL];
#endif
\t\t}"""
new_block = """\t\tdatamap_t *pMap = gamehelpers->GetDataMap(pPlayerEntity);
\t\tsm_datatable_info_t datamapInfo;
\t\tif (gamehelpers->FindDataMapInfo(pMap, pszBaseVar, &datamapInfo))
\t\t{
\t\t\tinterimOffset = datamapInfo.actual_offset;
\t\t}"""
if old_block in text:
    text = text.replace(old_block, new_block, 1)
    path.write_text(text)

path = Path(sourcemod_dir) / 'extensions/sdktools/vstringtable.cpp'
text = path.read_text()
text = text.replace('MIN(maxBytes, datalen)', '(maxBytes < datalen ? maxBytes : datalen)')
path.write_text(text)

path = Path(sourcemod_dir) / 'core/MenuStyle_Base.cpp'
text = path.read_text()
text = text.replace('MIN(GetItemCount(), 255)', '(GetItemCount() < 255 ? GetItemCount() : 255)')
text = text.replace('MIN(length, stop)', '(length < stop ? length : stop)')
text = text.replace('MIN(length, 255)', '(length < 255 ? length : 255)')
path.write_text(text)

# Pre-Orange Box CS:S v34 has no FL_EP2V_UNKNOWN (conflicts with FL_WATERJUMP).
path = Path(sourcemod_dir) / 'core/smn_entities.cpp'
text = path.read_text()
text = text.replace(
    '|| SOURCE_ENGINE == SE_BMS || SOURCE_ENGINE == SE_CSS || SOURCE_ENGINE == SE_TF2',
    '|| SOURCE_ENGINE == SE_BMS || SOURCE_ENGINE == SE_TF2',
)
path.write_text(text)

path = Path(sourcemod_dir) / 'core/PlayerManager.cpp'
text = path.read_text()
text = text.replace(
    '#if SOURCE_ENGINE == SE_EPISODEONE || SOURCE_ENGINE == SE_DARKMESSIAH',
    '#if SOURCE_ENGINE == SE_EPISODEONE || SOURCE_ENGINE == SE_DARKMESSIAH || SOURCE_ENGINE == SE_CSS',
)
text = text.replace(
    '\t|| SOURCE_ENGINE == SE_CSS   \\\n',
    '',
)
text = text.replace(
    '#if SOURCE_ENGINE < SE_ORANGEBOX\n\tconst char *pAuth = GetAuthString();',
    '#if SOURCE_ENGINE < SE_ORANGEBOX || SOURCE_ENGINE == SE_CSS\n\tconst char *pAuth = GetAuthString();',
)
text = text.replace('k_steamIDNil', 'CSteamID()')
text = text.replace('k_unSteamUserDesktopInstance', '1')
path.write_text(text)

path = Path(sourcemod_dir) / 'core/HalfLife2.h'
text = path.read_text()
text = text.replace(
    '|| SOURCE_ENGINE == SE_DODS || SOURCE_ENGINE == SE_CSS || SOURCE_ENGINE == SE_TF2',
    '|| SOURCE_ENGINE == SE_DODS || SOURCE_ENGINE == SE_TF2',
)
text = text.replace(
    '#if SOURCE_ENGINE <= SE_DARKMESSIAH\n\tchar cmd[300];',
    '#if SOURCE_ENGINE <= SE_DARKMESSIAH || SOURCE_ENGINE == SE_CSS\n\tchar cmd[300];',
)
path.write_text(text)

path = Path(sourcemod_dir) / 'core/HalfLife2.cpp'
text = path.read_text()
text = text.replace('\t|| SOURCE_ENGINE == SE_CSS     \\\n', '')
text = text.replace(
    '#elif SOURCE_ENGINE == SE_TF2 || SOURCE_ENGINE == SE_CSS || SOURCE_ENGINE == SE_DODS',
    '#elif SOURCE_ENGINE == SE_TF2 || SOURCE_ENGINE == SE_DODS',
)
text = text.replace(
    '#if SOURCE_ENGINE < SE_ORANGEBOX\n\tCBaseEntity* pEntity = nullptr;',
    '#if SOURCE_ENGINE < SE_ORANGEBOX || SOURCE_ENGINE == SE_CSS\n\tCBaseEntity* pEntity = nullptr;',
)
text = text.replace(
    '#if SOURCE_ENGINE < SE_ORANGEBOX\n\tstatic int iFuncOffset;',
    '#if SOURCE_ENGINE < SE_ORANGEBOX || SOURCE_ENGINE == SE_CSS\n\tstatic int iFuncOffset;',
)
text = text.replace(
    '#if SOURCE_ENGINE <= SE_DARKMESSIAH\n\tke::SafeStrcpy(info.cmd',
    '#if SOURCE_ENGINE <= SE_DARKMESSIAH || SOURCE_ENGINE == SE_CSS\n\tke::SafeStrcpy(info.cmd',
)
text = text.replace(
    '#if SOURCE_ENGINE < SE_ORANGEBOX\nclass VKeyValuesSS_Helper',
    '#if SOURCE_ENGINE < SE_ORANGEBOX || SOURCE_ENGINE == SE_CSS\nclass VKeyValuesSS_Helper',
)
text = text.replace('\t|| SOURCE_ENGINE == SE_CSS         \\\n', '')
path.write_text(text)

path = Path(sourcemod_dir) / 'core/GameHooks.cpp'
text = path.read_text()
text = text.replace(
    '#if SOURCE_ENGINE < SE_ORANGEBOX\n  float flOldValue = atof(oldValue);',
    '#if SOURCE_ENGINE < SE_ORANGEBOX || SOURCE_ENGINE == SE_CSS\n  float flOldValue = atof(oldValue);',
)
path.write_text(text)
PY
