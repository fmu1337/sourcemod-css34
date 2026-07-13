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

# css34: build sourcemod.1.ep1.so as SE_EPISODEONE (like rom4s), not SE_CSS.
# SE_CSS=6 pulls Orange-Box-era assumptions that crash css34 MM when engine
# extensions register SourceHook hooks. GAMEFIX must still be "1.ep1" (not the
# stock EPISODEONE "2.ep1") so we inject SM_CSS34_GAMEFIX_1_EP1 below.
ep1_marker_css = "'ep1':  SDK('HL2SDK', '1.ep1', '6', 'CSS', WinLinux, 'ep1'),"
ep1_marker = "'ep1':  SDK('HL2SDK', '1.ep1', '1', 'EPISODEONE', WinLinux, 'ep1'),"
episode1_anchor = "'episode1':  SDK('HL2SDK', '2.ep1', '1', 'EPISODEONE', WinLinux, 'episode1'),"
if ep1_marker_css in text:
    text = text.replace(ep1_marker_css, ep1_marker, 1)
elif ep1_marker not in text:
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
    insert += """    cxx.cxxflags += ['-Wno-reorder', '-fpermissive', '-Wno-write-strings']  # CSS34 SDK compatibility
"""
if needle not in text:
    raise SystemExit('Failed to locate compiler flags block in AMBuildScript')
text = text.replace(needle, insert, 1)

sp_script = Path(sourcemod_dir) / 'sourcepawn/AMBuildScript'
sp_text = sp_script.read_text()
if compiler_flavor == 'clang' and supports_deprecated_non_prototype and '-Wno-deprecated-non-prototype' not in sp_text:
    sp_text = sp_text.replace(
        "            '-Werror',\n            '-Wno-switch',",
        "            '-Werror',\n            '-Wno-switch',\n            '-Wno-deprecated-non-prototype',  # CSS34 clang compatibility",
    )
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
if old_dynamic not in text:
    raise SystemExit('Failed to locate dynamic_libs block in AMBuildScript')
text = text.replace(old_dynamic, new_dynamic, 1)

# css34/ep1: embed ConVar from static tier1_i486.a (like rom4s). Shared
# vstdlib_i486.so also exports ConVar; if it appears before tier1 on the link
# line, SM imports the engine list and hangs in FindCommand (circular m_pNext).
# Do NOT use --whole-archive on the stock tier1 archive: it embeds nested
# libstdc++.a / libgcc_eh.a and breaks extension links.
# Put tier1 at the front of linkflags (before prepended vstdlib/tier0); leave
# only mathlib in postlink.
old_tier1_variants = [
    (
        "      else:\n"
        "        compiler.postlink += [\n"
        "          compiler.Dep(os.path.join(lib_folder, 'tier1_i486.a')),\n"
        "          compiler.Dep(os.path.join(lib_folder, 'mathlib_i486.a'))\n"
        "        ]"
    ),
    (
        "      else:\n"
        "        # css34: whole-archive tier1 so ConVar/ConCommandBase are not taken from vstdlib\n"
        "        compiler.postlink += [\n"
        "          '-Wl,--whole-archive',\n"
        "          compiler.Dep(os.path.join(lib_folder, 'tier1_i486.a')),\n"
        "          '-Wl,--no-whole-archive',\n"
        "          compiler.Dep(os.path.join(lib_folder, 'mathlib_i486.a'))\n"
        "        ]"
    ),
]
new_tier1 = (
    "      else:\n"
    "        # css34: mathlib only here; tier1 is prepended before vstdlib below\n"
    "        compiler.postlink += [\n"
    "          compiler.Dep(os.path.join(lib_folder, 'mathlib_i486.a'))\n"
    "        ]"
)
replaced_tier1 = False
for old_tier1 in old_tier1_variants:
    if old_tier1 in text:
        text = text.replace(old_tier1, new_tier1, 1)
        replaced_tier1 = True
        break
if not replaced_tier1:
    if new_tier1 not in text:
        raise SystemExit('Failed to locate tier1_i486.a postlink block in AMBuildScript')

tier1_before_vstdlib = (
    "    for library in dynamic_libs:\n"
    "      source_path = os.path.join(lib_folder, library)\n"
    "      output_path = os.path.join(binary.localFolder, library)\n"
    "\n"
    "      def make_linker(source_path, output_path):\n"
    "        def link(context, binary):\n"
    "          cmd_node, (output,) = context.AddSymlink(source_path, output_path)\n"
    "          return output\n"
    "        return link\n"
    "\n"
    "      linker = make_linker(source_path, output_path)\n"
    "      compiler.linkflags[0:0] = [compiler.Dep(library, linker)]\n"
    "\n"
    "    return binary\n"
)
tier1_before_vstdlib_new = (
    "    for library in dynamic_libs:\n"
    "      source_path = os.path.join(lib_folder, library)\n"
    "      output_path = os.path.join(binary.localFolder, library)\n"
    "\n"
    "      def make_linker(source_path, output_path):\n"
    "        def link(context, binary):\n"
    "          cmd_node, (output,) = context.AddSymlink(source_path, output_path)\n"
    "          return output\n"
    "        return link\n"
    "\n"
    "      linker = make_linker(source_path, output_path)\n"
    "      compiler.linkflags[0:0] = [compiler.Dep(library, linker)]\n"
    "\n"
    "    # css34: static tier1 BEFORE shared vstdlib so ConVar is embedded (T),\n"
    "    # not imported from vstdlib (U). Must run after the dynamic_libs prepend.\n"
    "    if builder.target.platform in ['linux', 'mac']:\n"
    "      if not (sdk.name in ['sdk2013', 'bms'] or arch == 'x64'):\n"
    "        compiler.linkflags[0:0] = [\n"
    "          compiler.Dep(os.path.join(lib_folder, 'tier1_i486.a'))\n"
    "        ]\n"
    "\n"
    "    return binary\n"
)
if 'css34: static tier1 BEFORE shared vstdlib' not in text:
    if tier1_before_vstdlib not in text:
        raise SystemExit('Failed to locate dynamic_libs linkflags prepend in AMBuildScript')
    text = text.replace(tier1_before_vstdlib, tier1_before_vstdlib_new, 1)

path.write_text(text)

# css34: force GAMEFIX "1.ep1" for the ep1 SDK binary (SE_EPISODEONE would
# otherwise bake "2.ep1" and load the wrong engine extension set).
text = path.read_text()
marker = "    compiler.defines += ['SOURCE_ENGINE=' + sdk.code]"
insert = """    compiler.defines += ['SOURCE_ENGINE=' + sdk.code]
    # css34: sourcemod.1.ep1.so must advertise gamesuffix 1.ep1
    if sdk.name == 'ep1':
      compiler.defines += ['SM_CSS34_GAMEFIX_1_EP1']"""
if 'SM_CSS34_GAMEFIX_1_EP1' in text:
    print('==> SM_CSS34_GAMEFIX_1_EP1 already in AMBuildScript')
elif marker in text:
    path.write_text(text.replace(marker, insert, 1))
    print('==> Added SM_CSS34_GAMEFIX_1_EP1 define for ep1 SDK')
else:
    raise SystemExit('Failed to locate SOURCE_ENGINE define in AMBuildScript')

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

# MM:S 1.10 for CS:S v34 loads the bridge via legacy CreateInterface (API V1),
# which must open sourcemod.1.ep1.so. Upstream SM removed this export; restore it.
SOURCEMOD_DIR="$sourcemod_dir" python3 - <<'PY'
from pathlib import Path
import os

path = Path(os.environ['SOURCEMOD_DIR']) / 'loader' / 'loader.cpp'
text = path.read_text()
if 'DLL_EXPORT void *CreateInterface(const char *iface, int *ret)' in text:
    print('==> loader CreateInterface already present')
else:
    if '#define FILENAME_1_4_EP1' not in text:
        text = text.replace(
            '#define METAMOD_API_MAJOR\t\t\t2\n',
            '#define METAMOD_API_MAJOR\t\t\t2\n'
            '#define FILENAME_1_4_EP1\t\t\t"sourcemod.1.ep1" PLATFORM_EXT\n',
            1,
        )
        if '#define FILENAME_1_4_EP1' not in text:
            text = text.replace(
                '#define METAMOD_API_MAJOR\t\t\t2\r\n',
                '#define METAMOD_API_MAJOR\t\t\t2\r\n'
                '#define FILENAME_1_4_EP1\t\t\t"sourcemod.1.ep1" PLATFORM_EXT\r\n',
                1,
            )
        if '#define FILENAME_1_4_EP1' not in text:
            raise SystemExit('Failed to insert FILENAME_1_4_EP1 into loader.cpp')

    win_sep = """\t#define PATH_SEP_CHAR\t\t\t"\\\\"
\t#include <Windows.h>
#else"""
    win_sep_new = """\t#define PATH_SEP_CHAR\t\t\t"\\\\"
\tinline bool IsPathSepChar(char c)
\t{
\t\treturn (c == '/' || c == '\\\\');
\t}
\t#include <Windows.h>
#else"""
    if win_sep in text:
        text = text.replace(win_sep, win_sep_new, 1)

    unix_sep = """\ttypedef void *\t\t\t\t\tHINSTANCE;
\t#define PATH_SEP_CHAR\t\t\t"/"
\t#include <dlfcn.h>
#endif"""
    unix_sep_new = """\ttypedef void *\t\t\t\t\tHINSTANCE;
\t#define PATH_SEP_CHAR\t\t\t"/"
\tinline bool IsPathSepChar(char c)
\t{
\t\treturn (c == '/');
\t}
\t#include <dlfcn.h>
#endif"""
    if unix_sep in text:
        text = text.replace(unix_sep, unix_sep_new, 1)

    # Must exist in both #if branches (Windows helper alone is invisible on Linux).
    if text.count('inline bool IsPathSepChar(char c)') < 2:
        raise SystemExit('Failed to insert IsPathSepChar into both loader.cpp branches')

    getfile = r'''
bool GetFileOfAddress(void *pAddr, char *buffer, size_t maxlength)
{
#if defined _MSC_VER
	MEMORY_BASIC_INFORMATION mem;
	if (!VirtualQuery(pAddr, &mem, sizeof(mem)))
		return false;
	if (mem.AllocationBase == NULL)
		return false;
	HMODULE dll = (HMODULE)mem.AllocationBase;
	GetModuleFileName(dll, (LPTSTR)buffer, maxlength);
#else
	Dl_info info;
	if (!dladdr(pAddr, &info))
		return false;
	if (!info.dli_fbase || !info.dli_fname)
		return false;
	const char *dllpath = info.dli_fname;
	snprintf(buffer, maxlength, "%s", dllpath);
#endif
	return true;
}

'''
    if 'bool GetFileOfAddress(' not in text:
        anchor = 'DLL_EXPORT METAMOD_PLUGIN *CreateInterface_MMS('
        if anchor not in text:
            raise SystemExit('Failed to locate CreateInterface_MMS in loader.cpp')
        text = text.replace(anchor, getfile + anchor, 1)

    create = r'''
DLL_EXPORT void *CreateInterface(const char *iface, int *ret)
{
	/**
	 * If a load has already been attempted, bail out immediately.
	 */
	if (load_attempted)
	{
		return NULL;
	}

	if (strcmp(iface, METAMOD_PLAPI_NAME) == 0)
	{
		char thisfile[256];
		char targetfile[256];

		if (!GetFileOfAddress((void *)CreateInterface_MMS, thisfile, sizeof(thisfile)))
		{
			return NULL;
		}

		size_t len = strlen(thisfile);
		for (size_t iter = len - 1; iter < len; iter--)
		{
			if (IsPathSepChar(thisfile[iter]))
			{
				thisfile[iter] = '\0';
				break;
			}
		}

		UTIL_Format(targetfile, sizeof(targetfile), "%s" PATH_SEP_CHAR FILENAME_1_4_EP1, thisfile);

		return _GetPluginPtr(targetfile, METAMOD_FAIL_API_V1);
	}

	return NULL;
}

'''
    unload_anchor = 'DLL_EXPORT void UnloadInterface_MMS()'
    if unload_anchor not in text:
        raise SystemExit('Failed to locate UnloadInterface_MMS in loader.cpp')
    # Insert CreateInterface after UnloadInterface_MMS body.
    end_marker = 'DLL_EXPORT void UnloadInterface_MMS()\n{\n\tif (g_hCore)\n\t{\n\t\tcloselib(g_hCore);\n\t\tg_hCore = NULL;\n\t}\n}\n'
    if end_marker not in text:
        raise SystemExit('Failed to locate UnloadInterface_MMS body in loader.cpp')
    text = text.replace(end_marker, end_marker + create, 1)
    path.write_text(text)
    print('==> Restored legacy CreateInterface in loader.cpp for MM:S 1.10 / EP1')
PY

# Normalize line endings from the upstream SourceMod checkout.
while IFS= read -r -d '' file; do
  sed -i 's/\r$//' "$file"
done < <(find "$sourcemod_dir" -type f \( -name '*.h' -o -name '*.cpp' -o -name 'AMBuildScript' \) -print0)

# CS:S v34 / hl2sdk-ep1 only has VEngineServer021. Upstream SE_CSS shim probes 023/022 first
# and is meant for Orange Box CS:S — drop SE_CSS from that branch for css34 (core + extensions).
for f in \
  "$sourcemod_dir/core/sourcemm_api.cpp" \
  "$sourcemod_dir/public/smsdk_ext.cpp"
do
  if [ -f "$f" ]; then
    sed -i \
      's/#if SOURCE_ENGINE == SE_CSS || SOURCE_ENGINE == SE_DODS || SOURCE_ENGINE == SE_HL2DM || SOURCE_ENGINE == SE_SDK2013$/#if SOURCE_ENGINE == SE_DODS || SOURCE_ENGINE == SE_HL2DM || SOURCE_ENGINE == SE_SDK2013/' \
      "$f"
  fi
done

# Legacy ISmmAPI has no Format(); only used in the OB CSS shim error path above.
if [ -f "$sourcemod_dir/public/smsdk_ext.cpp" ]; then
  sed -i 's/ismm->Format(error, maxlen,/ke::SafeSprintf(error, maxlen,/g' \
    "$sourcemod_dir/public/smsdk_ext.cpp"
fi

# css34: ISmmAPI already uses modern method names with legacy vtable order.
# Disable metamod_wrappers factory renames (they would map GetEngineFactory→engineFactory
# and break compilation). Keep the file for CVAR_INTERFACE_VERSION if included.
wrappers="$sourcemod_dir/public/metamod_wrappers.h"
if [ -f "$wrappers" ] && ! grep -q 'CSS34_NO_FACTORY_RENAME' "$wrappers"; then
  cat > "$wrappers" <<'EOF'
/**
 * css34: Metamod headers use legacy ISmmAPI *vtable order* with modern method
 * names, so factory renames are unnecessary. CSS34_NO_FACTORY_RENAME
 */
#ifndef _INCLUDE_METAMOD_WRAPPERS_H_
#define _INCLUDE_METAMOD_WRAPPERS_H_

#define CVAR_INTERFACE_VERSION	VENGINE_CVAR_INTERFACE_VERSION

#ifndef METAMOD_PLAPI_NAME
#define METAMOD_PLAPI_NAME		PLAPI_NAME
#endif

#endif //_INCLUDE_METAMOD_WRAPPERS_H_
EOF
fi

# Ensure sourcemm_api can see PLAPI helpers; wrappers are now no-op renames.
sourcemm_h="$sourcemod_dir/core/sourcemm_api.h"
if [ -f "$sourcemm_h" ] && ! grep -q 'metamod_wrappers.h' "$sourcemm_h"; then
  sed -i 's|#include <ISmmPlugin.h>|#include <ISmmPlugin.h>\n#include <metamod_wrappers.h>|' "$sourcemm_h"
fi

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

# css34: ep1 binary is SE_EPISODEONE with SM_CSS34_GAMEFIX_1_EP1 so gamesuffix
# is "1.ep1" while engine name stays "original". Keep SE_CSS GAMEFIX/name
# shims as well for any residual SE_CSS compile units.
logic_bridge="$sourcemod_dir/core/logic_bridge.cpp"
if [ -f "$logic_bridge" ]; then
  python3 - <<PY
from pathlib import Path
path = Path("$logic_bridge")
text = path.read_text()
changed = False

# Prefer an explicit css34 override ahead of the SOURCE_ENGINE GAMEFIX ladder.
force_old = '#if SOURCE_ENGINE == SE_LEFT4DEAD\n#define GAMEFIX "2.l4d"'
force_new = '''#if defined(SM_CSS34_GAMEFIX_1_EP1)
#define GAMEFIX "1.ep1"
#elif SOURCE_ENGINE == SE_LEFT4DEAD
#define GAMEFIX "2.l4d"'''
if 'SM_CSS34_GAMEFIX_1_EP1' not in text and force_old in text:
    text = text.replace(force_old, force_new, 1)
    changed = True

# Only the SE_CSS GAMEFIX branch (do not touch the #else "2.ep1" default).
for old, new in (
    ('#elif SOURCE_ENGINE == SE_CSS\n#define GAMEFIX "2.css"',
     '#elif SOURCE_ENGINE == SE_CSS\n#define GAMEFIX "1.ep1"'),
    ('#elif SOURCE_ENGINE == SE_CSS\n#define GAMEFIX "2.ep1"',
     '#elif SOURCE_ENGINE == SE_CSS\n#define GAMEFIX "1.ep1"'),
):
    if old in text:
        text = text.replace(old, new, 1)
        changed = True
        break

old_name = '''#elif SOURCE_ENGINE == SE_CSS
	return "css";
'''
new_name = '''#elif SOURCE_ENGINE == SE_CSS
	/* css34: if compiled as SE_CSS, still report as original EP1 */
	return "original";
'''
if old_name in text:
    text = text.replace(old_name, new_name, 1)
    changed = True

# Repair accidental replacement of the #else EPISODEONE default.
else_bad = '''#else
#define GAMEFIX "1.ep1"
#endif
'''
else_good = '''#else
#define GAMEFIX "2.ep1"
#endif
'''
if else_bad in text and 'SM_CSS34_GAMEFIX_1_EP1' in text:
    text = text.replace(else_bad, else_good, 1)
    changed = True
elif '#elif SOURCE_ENGINE == SE_CSS\n#define GAMEFIX "1.ep1"' in text and else_bad in text:
    text = text.replace(else_bad, else_good, 1)
    changed = True

if changed:
    path.write_text(text)
print('==> GAMEFIX css34 1.ep1 override; GetSourceEngineName original')

# css34: SE_CSS binaries are EP1-era; symbols are exported (like SE_EPISODEONE),
# not hidden like modern OB CSS. Hidden=true makes @gEntList etc. fail.
text = path.read_text()
old_sym = (
    "#if (SOURCE_ENGINE == SE_CSS)            \\\n"
)
new_sym = (
    "#if /* css34 EP1-era */ (0) && (SOURCE_ENGINE == SE_CSS)            \\\n"
)
if old_sym in text and 'css34 EP1-era' not in text:
    path.write_text(text.replace(old_sym, new_sym, 1))
    print('==> SymbolsAreHidden: SE_CSS treated as visible (css34)')

# css34 Metamod implements legacy ISmmPluginManager::Query which always writes
# through the file/status/source outs (reference ABI). Upstream SM 1.11 passes
# NULL for unused outs; that null-deref crashes metamod.1.ep1.so when loading
# any SM extension via LoadMMSPlugin. rom4s passes stack locals — match that.
text = path.read_text()
query_old = '''\tPl_Status status;

\tif (!id || (g_pMMPlugins->Query(id, NULL, &status, NULL) && status < Pl_Paused))
'''
query_new = '''\tPl_Status status;
\tconst char *query_file = nullptr;
\tPluginId query_source = 0;

\t/* css34: never pass NULL outs — legacy Query always stores through them */
\tif (!id || (g_pMMPlugins->Query(id, &query_file, &status, &query_source) && status < Pl_Paused))
'''
if 'css34: never pass NULL outs' in text:
    print('==> LoadMMSPlugin Query NULL-out fix already present')
elif query_old in text:
    path.write_text(text.replace(query_old, query_new, 1))
    print('==> Fixed LoadMMSPlugin Query for css34 legacy PluginManager ABI')
else:
    raise SystemExit('Failed to patch LoadMMSPlugin Query NULL outs for css34')
PY
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


# css34: match rom4s DT_NEEDED — keep static libstdc++, dynamic libgcc_s +
# pthread/rt, and disable HL2 malloc overrides (NO_HOOK_MALLOC).
SOURCEMOD_DIR="$sourcemod_dir" python3 - <<'PYLINK'
from pathlib import Path
import os
path = Path(os.environ['SOURCEMOD_DIR']) / 'AMBuildScript'
text = path.read_text()
# Drop any prior mistaken "remove static-libstdc++" css34 block.
if "css34: match rom4s link" in text:
    import re
    text = re.sub(
        r"\n      # css34: match rom4s link.*?(?=\n    for path in paths:)",
        "\n",
        text,
        count=1,
        flags=re.S,
    )
    path.write_text(text)
    text = path.read_text()

old = """    if builder.target.platform == 'linux':
      if sdk.name in ['csgo', 'blade']:
        compiler.linkflags.remove('-static-libstdc++')
        compiler.defines += ['_GLIBCXX_USE_CXX11_ABI=0']
"""
new = """    if builder.target.platform == 'linux':
      if sdk.name in ['csgo', 'blade']:
        compiler.linkflags.remove('-static-libstdc++')
        compiler.defines += ['_GLIBCXX_USE_CXX11_ABI=0']
      # css34: match rom4s (static libstdc++, dynamic libgcc_s/pthread/rt)
      if sdk.name in ['ep1', 'episode1']:
        if '-static-libgcc' in compiler.linkflags:
          compiler.linkflags.remove('-static-libgcc')
        compiler.defines += ['NO_HOOK_MALLOC', 'NO_MALLOC_OVERRIDE']
        for lib in ('-lpthread', '-lrt', '-lgcc_s'):
          if lib not in compiler.linkflags:
            compiler.linkflags += [lib]
"""
if 'css34: match rom4s (static libstdc++' in text:
    print('==> rom4s link flags already in AMBuildScript')
elif old in text:
    path.write_text(text.replace(old, new, 1))
    print('==> Patched AMBuildScript for rom4s-like link flags')
else:
    raise SystemExit('Failed to patch static-libstdc++ block for css34')
PYLINK

# bintools needs modern SourceHook ProtoInfo/CProtoInfoBuilder; css34 MM requires SH v4
# ISourceHook ABI. Skip bintools until a dual ProtoInfo shim lands — core smoke does not need it.
python3 - <<PY
from pathlib import Path
path = Path("$sourcemod_dir/AMBuildScript")
text = path.read_text()
old = "  'extensions/bintools/AMBuilder',\n"
new = (
    "  # css34: bintools needs modern ProtoInfo; SH v4 headers omit sourcehook_pibuilder.h\n"
    "  # 'extensions/bintools/AMBuilder',\n"
)
if old in text:
    path.write_text(text.replace(old, new, 1))
    print('==> Skipping bintools extension under css34 SourceHook v4 headers')
elif "css34: bintools needs modern ProtoInfo" in text:
    print('==> bintools already skipped for css34')
else:
    raise SystemExit('Failed to locate bintools AMBuilder entry')
PY
