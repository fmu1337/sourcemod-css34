#!/usr/bin/env bash
# CS:S v34 compatibility for SourceMod 1.12+ (hl2sdk-manifests / AMBuild 2.2).
# Keeps MMS 1.10.7 css34 ABI; ep1 binary is SE_EPISODEONE + gamesuffix 1.ep1.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PY=(bash "$script_dir/../py.sh")

sourcemod_dir="${1:?sourcemod directory required}"
builder_dir="$(cd "$script_dir/.." && pwd)"

echo "==> Applying SourceMod 1.12+ css34 patches"

# --- manifests ---
manifests_dir="$sourcemod_dir/hl2sdk-manifests/manifests"
if [ ! -d "$manifests_dir" ]; then
  echo "hl2sdk-manifests missing; is this SourceMod 1.12+?" >&2
  exit 1
fi
cp -f "$builder_dir/assets/hl2sdk-manifests/ep1.json" "$manifests_dir/ep1.json"
echo "==> Installed ep1.json (SE_EPISODEONE / extension 1.ep1)"

# --- AMBuildScript / SdkHelpers (1.12 structure) ---
SOURCEMOD_DIR="$sourcemod_dir" "${PY[@]}" - <<'PY'
from pathlib import Path
import os

sm = Path(os.environ['SOURCEMOD_DIR'])
ambuild = sm / 'AMBuildScript'
text = ambuild.read_text()

# SM_CSS34_GAMEFIX_1_EP1 for ep1 sdk binaries
needle = "    SdkHelpers.configureCxx(context, binary, sdk)\n\n    return binary"
insert = """    SdkHelpers.configureCxx(context, binary, sdk)

    # css34: sourcemod.1.ep1.so / extensions must advertise gamesuffix 1.ep1
    if sdk.get('name') == 'ep1':
      compiler.defines += ['SM_CSS34_GAMEFIX_1_EP1']
      # Static tier1 BEFORE shared vstdlib so ConVar is embedded, not imported.
      if compiler.target.platform == 'linux':
        tier1 = os.path.join(sdk['path'], 'linux_sdk', 'tier1_i486.a')
        if os.path.isfile(tier1):
          compiler.linkflags[0:0] = [tier1]
        for flag in ('-Wl,--no-as-needed', '-lpthread', '-lrt', '-lgcc_s'):
          if flag not in compiler.linkflags:
            compiler.linkflags += [flag]

    return binary"""
if 'SM_CSS34_GAMEFIX_1_EP1' not in text:
    if needle not in text:
        raise SystemExit('Failed to locate ConfigureForHL2 SdkHelpers.configureCxx return')
    text = text.replace(needle, insert, 1)
    print('==> Patched ConfigureForHL2 for GAMEFIX + tier1-before-vstdlib')
else:
    print('==> ConfigureForHL2 already has SM_CSS34_GAMEFIX_1_EP1')

# ExtLibrary pthread/rt
old_ext = """  def ExtLibrary(self, context, compiler, name):
    binary = self.Library(context, compiler, name)
    SetArchFlags(compiler)
    self.ConfigureForExtension(context, binary.compiler)
    return binary
"""
new_ext = """  def ExtLibrary(self, context, compiler, name):
    binary = self.Library(context, compiler, name)
    SetArchFlags(compiler)
    self.ConfigureForExtension(context, binary.compiler)
    # css34: pthread/rt DT_NEEDED on pre-2.34 glibc
    if compiler.target.platform == 'linux':
      for flag in ('-Wl,--no-as-needed', '-lpthread', '-lrt'):
        if flag not in binary.compiler.linkflags:
          binary.compiler.linkflags += [flag]
    return binary
"""
if 'css34: pthread/rt DT_NEEDED on pre-2.34' not in text:
    if old_ext not in text:
        raise SystemExit('Failed to locate ExtLibrary in AMBuildScript')
    text = text.replace(old_ext, new_ext, 1)
    print('==> Patched ExtLibrary for pthread/rt')
else:
    print('==> ExtLibrary already patched')

# Global CXX11 ABI + SDK warning suppressions for clang/gcc on ep1c
cfg = """  def configure_gcc(self, cxx):
"""
# inject after cflags list creation in configure_gcc
if "CSS34 SDK compatibility" not in text:
    marker = "    if have_gcc:\n      cxx.cflags += ['-mfpmath=sse']\n      cxx.cflags += ['-Wno-maybe-uninitialized']\n"
    extra = marker + """    # CSS34 SDK compatibility
    cxx.cxxflags += ['-Wno-reorder', '-fpermissive', '-Wno-write-strings', '-Wno-sign-compare', '-Wno-ignored-attributes']
    cxx.cflags += [
      '-Wno-stringop-overflow', '-Wno-error=stringop-overflow',
      '-Wno-stringop-truncation', '-Wno-error=stringop-truncation',
      '-Wno-format-truncation', '-Wno-error=format-truncation',
      '-Wno-ignored-attributes',
    ]
    cxx.defines += ['_GLIBCXX_USE_CXX11_ABI=0']
"""
    if marker not in text:
        # clang-only path may differ; insert before "have_gcc = "
        alt = "    have_gcc = cxx.family == 'gcc'\n"
        if alt not in text:
            raise SystemExit('Failed to locate configure_gcc warning block')
        text = text.replace(
            alt,
            alt + "    # CSS34 SDK compatibility (early)\n"
                 "    cxx.cxxflags += ['-Wno-reorder', '-fpermissive', '-Wno-write-strings', '-Wno-sign-compare', '-Wno-ignored-attributes']\n"
                 "    cxx.cflags += ['-Wno-stringop-overflow', '-Wno-error=stringop-overflow', '-Wno-stringop-truncation', '-Wno-error=stringop-truncation', '-Wno-format-truncation', '-Wno-error=format-truncation', '-Wno-ignored-attributes']\n"
                 "    if '_GLIBCXX_USE_CXX11_ABI=0' not in cxx.defines:\n"
                 "      cxx.defines += ['_GLIBCXX_USE_CXX11_ABI=0']\n",
            1,
        )
        print('==> Injected CSS34 compiler flags (alt path)')
    else:
        text = text.replace(marker, extra, 1)
        print('==> Injected CSS34 compiler flags')
else:
    print('==> CSS34 compiler flags already present')

ambuild.write_text(text)

# SourcePawn sign-compare under -Werror on gcc-9
sp = sm / 'sourcepawn/AMBuildScript'
if sp.exists():
    sp_text = sp.read_text()
    if 'CSS34 sign-compare' not in sp_text:
        sp_text = sp_text.replace(
            "'-Werror',\n",
            "'-Werror',\n            '-Wno-sign-compare',  # CSS34 sign-compare\n",
            1,
        )
        if "cxx.cxxflags += ['-std=c++17']" in sp_text and "CSS34 sign-compare" not in sp_text.split("cxx.cxxflags")[1][:200]:
            sp_text = sp_text.replace(
                "cxx.cxxflags += ['-std=c++17']\n",
                "cxx.cxxflags += ['-std=c++17']\n        cxx.cxxflags += ['-Wno-sign-compare']  # CSS34 sign-compare\n",
                1,
            )
        sp.write_text(sp_text)
        print('==> Patched sourcepawn AMBuildScript for sign-compare')

# cstrike: build for ep1 + episode1
cstrike = sm / 'extensions/cstrike/AMBuilder'
if cstrike.exists():
    ct = cstrike.read_text()
    if "['ep1', 'episode1'" not in ct:
        ct = ct.replace(
            "for sdk_name in ['css', 'csgo']:",
            "for sdk_name in ['ep1', 'episode1', 'css', 'csgo']:",
            1,
        )
        cstrike.write_text(ct)
        print('==> cstrike AMBuilder includes ep1, episode1')

for rel in ('extensions/cstrike/forwards.cpp', 'extensions/cstrike/natives.cpp'):
    p = sm / rel
    if p.exists():
        p.write_text(p.read_text().replace(
            '#if SOURCE_ENGINE == SE_CSS',
            '#if SOURCE_ENGINE == SE_CSS || SOURCE_ENGINE == SE_EPISODEONE',
        ))

# bundled curl fortify noise on gcc-9
curl_ambuild = sm / 'extensions/curl/curl-src/lib/AMBuilder'
if curl_ambuild.exists() and 'stringop-truncation' not in curl_ambuild.read_text():
    ct = curl_ambuild.read_text()
    ct = ct.replace(
        "binary.compiler.defines += ['_GNU_SOURCE']",
        "binary.compiler.defines += ['_GNU_SOURCE']\n"
        "    binary.compiler.cflags += ['-Wno-stringop-truncation', '-Wno-error=stringop-truncation']",
        1,
    )
    curl_ambuild.write_text(ct)
    print('==> Patched bundled libcurl for stringop-truncation')

# shell.cpp sign-compare
shell = sm / 'sourcepawn/vm/shell/shell.cpp'
if shell.exists() and 'if (index > params[0])' in shell.read_text():
    shell.write_text(shell.read_text().replace(
        'if (index > params[0])',
        'if (index > (size_t)params[0])',
    ))

# MMS headers used by SM 1.12 may lack PVKII/MCV constants
for rel in ('core/smn_halflife.cpp', 'loader/loader.cpp'):
    p = sm / rel
    if p.exists() and 'ifndef SOURCE_ENGINE_PVKII' not in p.read_text():
        p.write_text(
            '#ifndef SOURCE_ENGINE_PVKII\n'
            '#define SOURCE_ENGINE_PVKII 25\n'
            '#endif\n'
            '#ifndef SOURCE_ENGINE_MCV\n'
            '#define SOURCE_ENGINE_MCV 26\n'
            '#endif\n'
            + p.read_text()
        )
        print(f'==> Added PVKII/MCV defines to {rel}')
PY

# --- CreateInterface for MMS 1.10 V1 load path (same as 1.11 css34) ---
SOURCEMOD_DIR="$sourcemod_dir" "${PY[@]}" - <<'PY'
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
    end_marker = 'DLL_EXPORT void UnloadInterface_MMS()\n{\n\tif (g_hCore)\n\t{\n\t\tcloselib(g_hCore);\n\t\tg_hCore = NULL;\n\t}\n}\n'
    if end_marker not in text:
        raise SystemExit('Failed to locate UnloadInterface_MMS body in loader.cpp')
    text = text.replace(end_marker, end_marker + create, 1)
    path.write_text(text)
    print('==> Restored CreateInterface for MMS 1.10 V1 load')
PY

# --- Source-level patches (shared with 1.11 spirit; ep1 is SE_EPISODEONE) ---
while IFS= read -r -d '' file; do
  sed -i 's/\r$//' "$file"
done < <(find "$sourcemod_dir" -type f \( -name '*.h' -o -name '*.cpp' -o -name 'AMBuildScript' -o -name 'AMBuilder' \) -print0)

# GAMEFIX / logic_bridge css34 overrides
logic_bridge="$sourcemod_dir/core/logic_bridge.cpp"
if [ -f "$logic_bridge" ]; then
  LOGIC_BRIDGE="$logic_bridge" "${PY[@]}" - <<'PY'
from pathlib import Path
import os
path = Path(os.environ['LOGIC_BRIDGE'])
text = path.read_text()
changed = False
force_old = '#if SOURCE_ENGINE == SE_LEFT4DEAD\n#define GAMEFIX "2.l4d"'
force_new = '''#if defined(SM_CSS34_GAMEFIX_1_EP1)
#define GAMEFIX "1.ep1"
#elif SOURCE_ENGINE == SE_LEFT4DEAD
#define GAMEFIX "2.l4d"'''
if 'SM_CSS34_GAMEFIX_1_EP1' not in text and force_old in text:
    text = text.replace(force_old, force_new, 1)
    changed = True
if changed:
    path.write_text(text)
    print('==> GAMEFIX SM_CSS34_GAMEFIX_1_EP1 override')
else:
    print('==> GAMEFIX patch skipped or already applied')
PY
fi

# LoadMMSPlugin Query null-out fix (MMS 1.10 css34)
if [ -f "$logic_bridge" ]; then
  LOGIC_BRIDGE="$logic_bridge" "${PY[@]}" - <<'PY'
from pathlib import Path
import os
path = Path(os.environ['LOGIC_BRIDGE'])
text = path.read_text()
query_old = '''\tPl_Status status;

\tif (!id || (g_pMMPlugins->Query(id, NULL, &status, NULL) && status < Pl_Paused))
'''
query_new = '''\tPl_Status status;
\tconst char *query_file = nullptr;
\tPluginId query_source = 0;

\tif (!id || (g_pMMPlugins->Query(id, &query_file, &status, &query_source) && status < Pl_Paused))
'''
if query_old in text:
    path.write_text(text.replace(query_old, query_new, 1))
    print('==> Patched LoadMMSPlugin Query for css34 MMS')
elif 'query_file' in text:
    print('==> LoadMMSPlugin Query already patched')
else:
    # try alternate formatting from 1.12
    alt_old = 'g_pMMPlugins->Query(id, NULL, &status, NULL)'
    alt_new = 'g_pMMPlugins->Query(id, &query_file, &status, &query_source)'
    if alt_old in text and 'query_file' not in text:
        text = text.replace(
            '\tPl_Status status;\n',
            '\tPl_Status status;\n\tconst char *query_file = nullptr;\n\tPluginId query_source = 0;\n',
            1,
        )
        text = text.replace(alt_old, alt_new, 1)
        path.write_text(text)
        print('==> Patched LoadMMSPlugin Query (alt)')
    else:
        print('==> WARN: LoadMMSPlugin Query pattern not found')
PY
fi

# Episode One CON_COMMAND / pre-OB guards (SE_CSS leftovers still matter for some units)
while IFS= read -r -d '' file; do
  sed -i 's/#if SOURCE_ENGINE <= SE_DARKMESSIAH$/#if SOURCE_ENGINE <= SE_DARKMESSIAH || SOURCE_ENGINE == SE_CSS/g' "$file"
done < <(find "$sourcemod_dir" -type f \( -name '*.h' -o -name '*.cpp' \) -print0)

while IFS= read -r -d '' file; do
  sed -i 's/#if SOURCE_ENGINE <= SE_DARKMESSIAH || SOURCE_ENGINE == SE_CSS || SOURCE_ENGINE == SE_CSS/#if SOURCE_ENGINE <= SE_DARKMESSIAH || SOURCE_ENGINE == SE_CSS/g' "$file"
done < <(find "$sourcemod_dir" -type f \( -name '*.h' -o -name '*.cpp' \) -print0)

# MIN macros
for rel in extensions/sdktools/vstringtable.cpp core/MenuStyle_Base.cpp; do
  f="$sourcemod_dir/$rel"
  if [ -f "$f" ]; then
    sed -i \
      -e 's/MIN(maxBytes, datalen)/(maxBytes < datalen ? maxBytes : datalen)/g' \
      -e 's/MIN(GetItemCount(), 255)/(GetItemCount() < 255 ? GetItemCount() : 255)/g' \
      -e 's/MIN(length, stop)/(length < stop ? length : stop)/g' \
      -e 's/MIN(length, 255)/(length < 255 ? length : 255)/g' \
      "$f"
  fi
done

# Versioning submodule HEAD
versioning="$sourcemod_dir/tools/buildbot/Versioning"
if [ -f "$versioning" ] && ! grep -q '_resolve_git_head_path' "$versioning"; then
  SOURCEMOD_DIR="$sourcemod_dir" "${PY[@]}" - <<'PY'
from pathlib import Path
import os
versioning = Path(os.environ['SOURCEMOD_DIR']) / 'tools/buildbot/Versioning'
text = versioning.read_text()
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
    print('==> Patched Versioning for submodule gitdir')
else:
    print('==> Versioning already patched or layout changed')
PY
fi

# Optional logger / boot-trace (best-effort; may no-op on 1.12)
bash "$script_dir/apply-logger-mapchange-fix.sh" "$sourcemod_dir" || \
  echo "==> WARN: apply-logger-mapchange-fix.sh failed (continuing)"
bash "$script_dir/apply-sm-boot-trace.sh" "$sourcemod_dir" || \
  echo "==> WARN: apply-sm-boot-trace.sh failed (continuing)"

# sm version CSS34 pack line
SOURCEMOD_DIR="$sourcemod_dir" "${PY[@]}" - <<'PYVER'
from pathlib import Path
import os
path = Path(os.environ['SOURCEMOD_DIR']) / 'core/logic/RootConsoleMenu.cpp'
text = path.read_text()
if 'CSS34 pack:' in text:
    print('==> sm version already prints CSS34 pack commit')
else:
    if '#include <sourcemod_version.h>' not in text:
        print('==> WARN: sourcemod_version.h include missing')
    else:
        text = text.replace(
            '#include <sourcemod_version.h>',
            '#include <sourcemod_version.h>\n#include <css34_build_stamp.h>',
            1,
        )
        old = '''#if defined(SM_GENERATED_BUILD)
\t\tConsolePrint("    Built from: https://github.com/alliedmodders/sourcemod/commit/%s", SOURCEMOD_SHA);
\t\tConsolePrint("    Build ID: %s:%s", SOURCEMOD_LOCAL_REV, SOURCEMOD_SHA);
#endif
'''
        new = '''#if defined(SM_GENERATED_BUILD)
\t\tConsolePrint("    Built from: https://github.com/alliedmodders/sourcemod/commit/%s", SOURCEMOD_SHA);
\t\tConsolePrint("    CSS34 pack: https://github.com/fmu1337/sourcemod-css34/commit/%s", CSS34_PACK_COMMIT);
\t\tConsolePrint("    Build ID: %s:%s", SOURCEMOD_LOCAL_REV, SOURCEMOD_SHA);
#endif
'''
        if old in text:
            path.write_text(text.replace(old, new, 1))
            print('==> Patched sm version CSS34 pack line')
        else:
            print('==> WARN: Built from block not found for CSS34 pack')
PYVER

echo "==> SourceMod 1.12+ css34 patches applied"
