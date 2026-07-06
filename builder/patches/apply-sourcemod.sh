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

BUILD_PLATFORM="${BUILD_PLATFORM:-linux}"

# Clang 15+ understands -Wno-deprecated-non-prototype; older distro clang does not.
# Probe with -Werror because SourceMod builds with -Werror and unknown -Wno-* is fatal then.
supports_deprecated_non_prototype=0
supports_reorder_ctor=0
compiler_flavor="gcc"
compiler="${CC:-gcc-9}"

if [ "$BUILD_PLATFORM" = "windows" ]; then
  compiler_flavor="msvc"
else
  case "$(basename "$compiler")" in
    clang*) compiler_flavor="clang" ;;
  esac
  if echo 'int main(void){return 0;}' | "$compiler" -m32 -Werror -Wno-deprecated-non-prototype -x c - -c -o /dev/null 2>/dev/null; then
    supports_deprecated_non_prototype=1
  fi
  if echo 'int main(void){return 0;}' | "$compiler" -m32 -Werror -Wno-reorder-ctor -x c - -c -o /dev/null 2>/dev/null; then
    supports_reorder_ctor=1
  fi
fi

SOURCEMOD_DIR="$sourcemod_dir" \
SUPPORTS_WNO_DEPRECATED_NON_PROTOTYPE="$supports_deprecated_non_prototype" \
SUPPORTS_WNO_REORDER_CTOR="$supports_reorder_ctor" \
COMPILER_FLAVOR="$compiler_flavor" \
python3 - <<'PY'
from pathlib import Path
import os

sourcemod_dir = os.environ['SOURCEMOD_DIR']
supports_deprecated_non_prototype = os.environ.get('SUPPORTS_WNO_DEPRECATED_NON_PROTOTYPE') == '1'
supports_reorder_ctor = os.environ.get('SUPPORTS_WNO_REORDER_CTOR') == '1'
compiler_flavor = os.environ.get('COMPILER_FLAVOR', 'gcc')

path = Path(sourcemod_dir) / 'AMBuildScript'
text = path.read_text()

ep1_marker = "'ep1':  SDK('HL2SDK', '1.ep1', '6', 'CSS', WinLinux, 'ep1'),"
episode1_anchor = "'episode1':  SDK('HL2SDK', '2.ep1', '1', 'EPISODEONE', WinLinux, 'episode1'),"
if ep1_marker not in text:
    if episode1_anchor not in text:
        raise SystemExit('Failed to locate episode1 SDK anchor in AMBuildScript')
    text = text.replace(episode1_anchor, episode1_anchor + "\n  " + ep1_marker, 1)

path_block_old = """    if sdk.name == 'episode1' or sdk.name == 'darkm':
      paths.append(['public', 'dlls'])
      paths.append(['game_shared'])"""
path_block_new = """    if sdk.name in ['episode1', 'darkm']:
      paths.append(['public', 'dlls'])
      paths.append(['game_shared'])
    elif sdk.name == 'ep1':
      paths.append(['public', 'game', 'server'])
      paths.append(['public', 'toolframework'])
      paths.append(['game', 'shared'])
      paths.append(['common'])"""
if path_block_old in text:
    text = text.replace(path_block_old, path_block_new, 1)
elif """    if sdk.name in ['episode1', 'darkm', 'ep1']:
      paths.append(['public', 'dlls'])
      paths.append(['game_shared'])""" in text:
    text = text.replace(
        """    if sdk.name in ['episode1', 'darkm', 'ep1']:
      paths.append(['public', 'dlls'])
      paths.append(['game_shared'])""",
        path_block_new,
        1,
    )
elif path_block_new not in text:
    raise SystemExit('Failed to patch SDK include paths in AMBuildScript')

lib_block_old = "      if sdk.name == 'episode1':\n        lib_folder = os.path.join(sdk.path, 'linux_sdk')"
lib_block_new = "      if sdk.name in ['episode1', 'ep1']:\n        lib_folder = os.path.join(sdk.path, 'linux_sdk')"
if lib_block_old in text:
    text = text.replace(lib_block_old, lib_block_new, 1)

gcc_flags_old = "      '-Wno-array-bounds',\n      '-msse',"
gcc_flags_new = """      '-Wno-array-bounds',
      '-Wno-stringop-overflow',
      '-Wno-error=stringop-overflow',
      '-Wno-stringop-truncation',
      '-Wno-error=stringop-truncation',
      '-Wno-format-truncation',
      '-Wno-error=format-truncation',
      '-msse',"""
if compiler_flavor == 'clang' and gcc_flags_new in text:
    text = text.replace(gcc_flags_new, gcc_flags_old, 1)
elif compiler_flavor == 'gcc' and gcc_flags_old in text and gcc_flags_new not in text:
    text = text.replace(gcc_flags_old, gcc_flags_new, 1)

needle = "      '-fvisibility=hidden',\n    ]\n"
insert = """      '-fvisibility=hidden',
    ]
"""
if compiler_flavor == 'clang':
    insert += """    cxx.cflags += ['-Wno-nonportable-include-path', '-Wno-macro-redefined', '-Wno-writable-strings']  # CSS34 SDK compatibility
    cxx.cxxflags += ['-Wno-reorder', '-Wno-attributes', '-fpermissive']  # CSS34 SDK compatibility
"""
    if supports_reorder_ctor:
        insert += "    cxx.cxxflags += ['-Wno-reorder-ctor']  # CSS34 clang compatibility\n"
    if supports_deprecated_non_prototype:
        insert += "    cxx.cflags += ['-Wno-deprecated-non-prototype']  # CSS34 clang compatibility\n"
elif compiler_flavor == 'gcc':
    insert += """    cxx.cxxflags += ['-Wno-reorder', '-fpermissive', '-Wno-write-strings', '-Wno-sign-compare']  # CSS34 SDK compatibility
"""
if needle not in text:
    raise SystemExit('Failed to locate compiler flags block in AMBuildScript')
text = text.replace(needle, insert, 1)

sp_script = Path(sourcemod_dir) / 'sourcepawn/AMBuildScript'
sp_text = sp_script.read_text()
sp_patch = "            '-Werror',\n            '-Wno-switch',"
sp_replacements = []
if compiler_flavor == 'clang' and supports_deprecated_non_prototype and '-Wno-deprecated-non-prototype' not in sp_text:
    sp_replacements.append("            '-Wno-deprecated-non-prototype',  # CSS34 clang compatibility")
if '-Wno-sign-compare' not in sp_text:
    sp_replacements.append("            '-Wno-sign-compare',  # CSS34 gcc compatibility")
if sp_replacements and sp_patch in sp_text:
    sp_text = sp_text.replace(sp_patch, sp_patch + "\n" + "\n".join(sp_replacements), 1)
if "'-std=c++17', '-Wno-sign-compare'" not in sp_text and "cxx.cxxflags += ['-std=c++17']" in sp_text:
    sp_text = sp_text.replace(
        "cxx.cxxflags += ['-std=c++17']",
        "cxx.cxxflags += ['-std=c++17', '-Wno-sign-compare']  # CSS34 gcc compatibility",
        1,
    )
elif "'-std=c++14', '-Wno-sign-compare'" not in sp_text and "cxx.cxxflags += ['-std=c++14']" in sp_text:
    sp_text = sp_text.replace(
        "cxx.cxxflags += ['-std=c++14']",
        "cxx.cxxflags += ['-std=c++14', '-Wno-sign-compare']  # CSS34 gcc compatibility",
        1,
    )
sp_orig = sp_script.read_text()
if sp_text != sp_orig:
    sp_script.write_text(sp_text)

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
if "elif sdk.name == 'css':" in text and "tier0_i486.so" in text:
    pass
elif old_dynamic in text:
    text = text.replace(old_dynamic, new_dynamic, 1)
else:
    raise SystemExit('Failed to locate dynamic_libs block in AMBuildScript')

path.write_text(text)

cstrike_ambuild = Path(sourcemod_dir) / 'extensions/cstrike/AMBuilder'
if cstrike_ambuild.exists():
    cstrike_text = cstrike_ambuild.read_text()
    if "for sdk_name in ['ep1', 'episode1', 'css', 'csgo']:" not in cstrike_text:
        cstrike_text = cstrike_text.replace(
            "for sdk_name in ['css', 'csgo']:",
            "for sdk_name in ['ep1', 'episode1', 'css', 'csgo']:",
            1,
        )
        cstrike_ambuild.write_text(cstrike_text)

for rel in ('extensions/cstrike/forwards.cpp', 'extensions/cstrike/natives.cpp'):
    cstrike_src = Path(sourcemod_dir) / rel
    if cstrike_src.exists():
        cstrike_code = cstrike_src.read_text()
        cstrike_code = cstrike_code.replace(
            '#if SOURCE_ENGINE == SE_CSS',
            '#if SOURCE_ENGINE == SE_CSS || SOURCE_ENGINE == SE_EPISODEONE',
        )
        cstrike_src.write_text(cstrike_code)
PY

ambuild_script="$sourcemod_dir/AMBuildScript"
if grep -q "CSS34 SDK compatibility" "$ambuild_script" && ! grep -q "'-Wno-sign-compare']  # CSS34 SDK compatibility" "$ambuild_script"; then
  sed -i "s/'-Wno-write-strings']  # CSS34 SDK compatibility/'-Wno-write-strings', '-Wno-sign-compare']  # CSS34 SDK compatibility/" "$ambuild_script"
fi

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
text = text.replace(
    "#if SOURCE_ENGINE < SE_ORANGEBOX\n\t\treturn pContext->ThrowNativeError(\"Cannot set %s. Setting string_t values not supported on this game.\", prop);\n#else\n\t\t*(string_t *) ((intptr_t) pEntity + offset) = g_HL2.AllocPooledString(src);",
    "#if SOURCE_ENGINE < SE_ORANGEBOX || SOURCE_ENGINE == SE_CSS\n\t\treturn pContext->ThrowNativeError(\"Cannot set %s. Setting string_t values not supported on this game.\", prop);\n#else\n\t\t*(string_t *) ((intptr_t) pEntity + offset) = g_HL2.AllocPooledString(src);",
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
        if old not in text:
            raise SystemExit('Failed to patch tools/buildbot/Versioning for submodule git metadata')
        versioning.write_text(text.replace(old, new, 1))
PY

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"$script_dir/apply-api-compat.sh" "$sourcemod_dir"
