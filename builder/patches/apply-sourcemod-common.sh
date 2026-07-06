#!/usr/bin/env bash
# Shared CS:S v34 source-level compatibility patches (all SourceMod versions).
set -euo pipefail

sourcemod_dir="${1:?sourcemod directory required}"

# Normalize line endings from the upstream SourceMod checkout.
while IFS= read -r -d '' file; do
  sed -i 's/\r$//' "$file"
done < <(find "$sourcemod_dir" -type f \( -name '*.h' -o -name '*.cpp' -o -name 'AMBuildScript' -o -name 'AMBuilder' \) -print0)

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
if [ -f "$compat_wrappers" ] && ! grep -q 'SE_DARKMESSIAH || SOURCE_ENGINE == SE_CSS' "$compat_wrappers"; then
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
    if not path.exists():
        continue
    text = path.read_text().replace(css_line, "")
    path.write_text(text)

path = Path(sourcemod_dir) / 'extensions/sdktools/vhelpers.cpp'
if path.exists():
    text = path.read_text()
    text = text.replace(
        "#if SOURCE_ENGINE < SE_ORANGEBOX\n\t\tCBaseEntity *pWorldEntity = nullptr;",
        "#if SOURCE_ENGINE < SE_ORANGEBOX || SOURCE_ENGINE == SE_CSS\n\t\tCBaseEntity *pWorldEntity = nullptr;",
    )
    path.write_text(text)

# Pre-Orange Box EmitSound hooks (14 params, no iSpecialDSP).
for rel in ('extensions/sdktools/vsound.cpp', 'extensions/sdktools/vsound.h'):
    path = Path(sourcemod_dir) / rel
    if path.exists():
        path.write_text(path.read_text().replace('SOURCE_ENGINE == SE_CSS || ', ''))

path = Path(sourcemod_dir) / 'extensions/sdkhooks/takedamageinfohack.h'
if path.exists():
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
if path.exists():
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
if path.exists():
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
if path.exists():
    text = path.read_text()
    text = text.replace('MIN(maxBytes, datalen)', '(maxBytes < datalen ? maxBytes : datalen)')
    path.write_text(text)

path = Path(sourcemod_dir) / 'core/MenuStyle_Base.cpp'
if path.exists():
    text = path.read_text()
    text = text.replace('MIN(GetItemCount(), 255)', '(GetItemCount() < 255 ? GetItemCount() : 255)')
    text = text.replace('MIN(length, stop)', '(length < stop ? length : stop)')
    text = text.replace('MIN(length, 255)', '(length < 255 ? length : 255)')
    path.write_text(text)

# Pre-Orange Box CS:S v34 has no FL_EP2V_UNKNOWN (conflicts with FL_WATERJUMP).
path = Path(sourcemod_dir) / 'core/smn_entities.cpp'
if path.exists():
    text = path.read_text()
    text = text.replace(
        '|| SOURCE_ENGINE == SE_BMS || SOURCE_ENGINE == SE_CSS || SOURCE_ENGINE == SE_TF2',
        '|| SOURCE_ENGINE == SE_BMS || SOURCE_ENGINE == SE_TF2',
    )
    text = text.replace(
        "#if SOURCE_ENGINE < SE_ORANGEBOX\n\t\treturn pContext->ThrowNativeError(\"Cannot set %s. Setting string_t values not supported on this game.\", prop);\n#else\n\t\t*(string_t *) ((intptr_t) pEntity + offset) = g_HL2.AllocPooledString(src);",
        "#if SOURCE_ENGINE < SE_ORANGEBOX || SOURCE_ENGINE == SE_CSS\n\t\treturn pContext->ThrowNativeError(\"Cannot set %s. Setting string_t values not supported on this game.\", prop);\n#else\n\t\t*(string_t *) ((intptr_t) pEntity + offset) = g_HL2.AllocPooledString(src);",
    )
    path.write_text(text)

path = Path(sourcemod_dir) / 'core/PlayerManager.cpp'
if path.exists():
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
if path.exists():
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
if path.exists():
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
if path.exists():
    text = path.read_text()
    text = text.replace(
        '#if SOURCE_ENGINE < SE_ORANGEBOX\n  float flOldValue = atof(oldValue);',
        '#if SOURCE_ENGINE < SE_ORANGEBOX || SOURCE_ENGINE == SE_CSS\n  float flOldValue = atof(oldValue);',
    )
    path.write_text(text)

versioning = Path(sourcemod_dir) / 'tools/buildbot/Versioning'
if versioning.exists():
    text = versioning.read_text()
    marker = 'def _resolve_git_head_path(source_path):'
    if marker not in text:
        old = """with open(os.path.join(builder.sourcePath, '.git', 'HEAD')) as fp:
  head_contents = fp.read().strip()
  if re.search('^[a-fA-F0-9]{40}$', head_contents):
    git_head_path = os.path.join(builder.sourcePath, '.git', 'HEAD')
  else:
    git_state = head_contents.split(':')[1].strip()
    git_head_path = os.path.join(builder.sourcePath, '.git', git_state)
    if not os.path.exists(git_head_path):
      git_head_path = os.path.join(builder.sourcePath, '.git', 'HEAD')
"""
        new = """def _resolve_git_head_path(source_path):
  git_meta = os.path.join(source_path, '.git')
  if os.path.isfile(git_meta):
    with open(git_meta) as meta_fp:
      gitdir_line = meta_fp.read().strip()
    if gitdir_line.startswith('gitdir: '):
      git_dir = gitdir_line[8:]
      if not os.path.isabs(git_dir):
        git_dir = os.path.normpath(os.path.join(source_path, git_dir))
    else:
      git_dir = git_meta
  else:
    git_dir = git_meta
  return os.path.join(git_dir, 'HEAD')

git_head_path = _resolve_git_head_path(builder.sourcePath)
with open(git_head_path) as fp:
  head_contents = fp.read().strip()
  if re.search('^[a-fA-F0-9]{40}$', head_contents):
    pass
  else:
    git_state = head_contents.split(':')[1].strip()
    candidate = os.path.join(os.path.dirname(git_head_path), git_state)
    if os.path.exists(candidate):
      git_head_path = candidate
"""
        if old in text:
            versioning.write_text(text.replace(old, new, 1))
PY

# cstrike extension: treat Episode One SDK like CSS for shared code paths.
for rel in extensions/cstrike/forwards.cpp extensions/cstrike/natives.cpp; do
    cstrike_src="$sourcemod_dir/$rel"
    if [ -f "$cstrike_src" ]; then
        sed -i \
            's/#if SOURCE_ENGINE == SE_CSS$/#if SOURCE_ENGINE == SE_CSS || SOURCE_ENGINE == SE_EPISODEONE/g' \
            "$cstrike_src"
    fi
done
