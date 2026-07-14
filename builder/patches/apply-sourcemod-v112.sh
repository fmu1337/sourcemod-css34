#!/usr/bin/env bash
# CS:S v34 compatibility for SourceMod 1.12+ (hl2sdk-manifests / AMBuild 2.2).
# Pairs with Metamod:Source 1.12 (PLAPI 16 / modern Core / metamod.2.ep1).
# Primary binary: sourcemod.2.ep1.so (SE_EPISODEONE / gamesuffix 2.ep1).
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PY=(bash "$script_dir/../py.sh")

sourcemod_dir="${1:?sourcemod directory required}"
builder_dir="$(cd "$script_dir/.." && pwd)"

echo "==> Applying SourceMod 1.12+ css34 patches (Metamod 1.12 / 2.ep1)"

# --- manifests ---
manifests_dir="$sourcemod_dir/hl2sdk-manifests/manifests"
if [ ! -d "$manifests_dir" ]; then
  echo "hl2sdk-manifests missing; is this SourceMod 1.12+?" >&2
  exit 1
fi

# Ensure episode1 linux defines match css34 (ABI0 + no HL2 malloc hooks).
SOURCEMOD_DIR="$sourcemod_dir" "${PY[@]}" - <<'PYMAN'
from pathlib import Path
import json, os
man = Path(os.environ['SOURCEMOD_DIR']) / 'hl2sdk-manifests/manifests/episode1.json'
data = json.loads(man.read_text())
linux = data.setdefault('linux', {})
defs = linux.setdefault('defines', [])
changed = False
for d in ('NO_HOOK_MALLOC', 'NO_MALLOC_OVERRIDE', '_GLIBCXX_USE_CXX11_ABI=0'):
    if d not in defs:
        defs.append(d)
        changed = True
if changed:
    man.write_text(json.dumps(data, indent=4) + '\n')
    print('==> Patched SM episode1.json linux defines for css34')
else:
    print('==> SM episode1.json linux defines already ok')
PYMAN

# --- AMBuildScript / SdkHelpers (1.12 structure) ---
SOURCEMOD_DIR="$sourcemod_dir" "${PY[@]}" - <<'PY'
from pathlib import Path
import os

sm = Path(os.environ['SOURCEMOD_DIR'])
ambuild = sm / 'AMBuildScript'
text = ambuild.read_text()

# css34: for episode1 (and optional ep1) embed ConVar from static tier1 before
# shared vstdlib, and record pthread/rt DT_NEEDED on older glibc.
needle = "    SdkHelpers.configureCxx(context, binary, sdk)\n\n    return binary"
insert = """    SdkHelpers.configureCxx(context, binary, sdk)

    # css34: episode1 → sourcemod.2.ep1.so (Metamod 1.12); optional ep1 → 1.ep1
    if sdk.get('name') in ('ep1', 'episode1'):
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
if 'css34: episode1 → sourcemod.2.ep1.so' not in text and 'SM_CSS34_GAMEFIX_1_EP1' not in text:
    if needle not in text:
        raise SystemExit('Failed to locate ConfigureForHL2 SdkHelpers.configureCxx return')
    text = text.replace(needle, insert, 1)
    print('==> Patched ConfigureForHL2 for episode1 tier1-before-vstdlib')
elif 'css34: episode1 → sourcemod.2.ep1.so' in text:
    print('==> ConfigureForHL2 episode1 css34 link already patched')
else:
    # Older patch only covered ep1 — widen to episode1.
    if "if sdk.get('name') == 'ep1':" in text and "in ('ep1', 'episode1')" not in text:
        text = text.replace(
            "    # css34: sourcemod.1.ep1.so / extensions must advertise gamesuffix 1.ep1\n"
            "    if sdk.get('name') == 'ep1':\n"
            "      compiler.defines += ['SM_CSS34_GAMEFIX_1_EP1']\n",
            "    # css34: episode1 → sourcemod.2.ep1.so (Metamod 1.12); optional ep1 → 1.ep1\n"
            "    if sdk.get('name') in ('ep1', 'episode1'):\n"
            "      if sdk.get('name') == 'ep1':\n"
            "        compiler.defines += ['SM_CSS34_GAMEFIX_1_EP1']\n",
            1,
        )
        print('==> Widened ConfigureForHL2 css34 link patch to episode1')
    else:
        print('==> ConfigureForHL2 css34 link patch present')

# ExtLibrary pthread/rt + leave META_NO_HL2SDK happy against Metamod 1.12 headers
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
        print('==> WARN: ExtLibrary pattern not found (continuing)')
    else:
        text = text.replace(old_ext, new_ext, 1)
        print('==> Patched ExtLibrary for pthread/rt')
else:
    print('==> ExtLibrary already patched')

# Force link via C++ driver (AMBuild master defaults to raw `ld`, which rejects
# -static-libstdc++ and other gcc/clang driver flags used by SourceMod).
if "css34: link via C++ driver" not in text:
    detect_anchor = "    if not self.all_targets:\n        raise Exception('No suitable C/C++ compiler was found.')\n"
    detect_insert = detect_anchor + """
    # css34: link via C++ driver (AMBuild tip uses raw ld by default)
    for _cxx in self.all_targets:
      _cxx.linker_argv = list(_cxx.cxx_argv)
"""
    if detect_anchor not in text:
        raise SystemExit('Failed to locate DetectCxx all_targets guard')
    text = text.replace(detect_anchor, detect_insert, 1)
    print('==> Forced linker_argv to C++ driver')
else:
    print('==> linker_argv already forced to C++ driver')

# Global CXX11 ABI + SDK warning suppressions for clang/gcc on episode1
if "CSS34 SDK compatibility" not in text:
    marker = "    if have_gcc:\n      cxx.cflags += ['-mfpmath=sse']\n      cxx.cflags += ['-Wno-maybe-uninitialized']\n"
    extra = marker + """    # CSS34 SDK compatibility
    cxx.cxxflags += ['-Wno-reorder', '-fpermissive', '-Wno-write-strings', '-Wno-sign-compare', '-Wno-ignored-attributes']
    if have_gcc:
      cxx.cflags += [
        '-Wno-stringop-overflow', '-Wno-error=stringop-overflow',
        '-Wno-stringop-truncation', '-Wno-error=stringop-truncation',
        '-Wno-format-truncation', '-Wno-error=format-truncation',
      ]
    cxx.defines += ['_GLIBCXX_USE_CXX11_ABI=0']
"""
    if marker not in text:
        alt = "    have_gcc = cxx.family == 'gcc'\n"
        if alt not in text:
            raise SystemExit('Failed to locate configure_gcc warning block')
        text = text.replace(
            alt,
            alt + "    # CSS34 SDK compatibility (early)\n"
                 "    cxx.cxxflags += ['-Wno-reorder', '-fpermissive', '-Wno-write-strings', '-Wno-sign-compare', '-Wno-ignored-attributes']\n"
                 "    if cxx.family == 'gcc':\n"
                 "      cxx.cflags += ['-Wno-stringop-overflow', '-Wno-error=stringop-overflow', '-Wno-stringop-truncation', '-Wno-error=stringop-truncation', '-Wno-format-truncation', '-Wno-error=format-truncation']\n"
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

# cstrike: build for episode1 (Metamod 1.12 path)
cstrike = sm / 'extensions/cstrike/AMBuilder'
if cstrike.exists():
    ct = cstrike.read_text()
    if "['episode1', 'css', 'csgo']" not in ct and "['ep1', 'episode1'" not in ct:
        ct = ct.replace(
            "for sdk_name in ['css', 'csgo']:",
            "for sdk_name in ['episode1', 'css', 'csgo']:",
            1,
        )
        cstrike.write_text(ct)
        print('==> cstrike AMBuilder includes episode1')
    else:
        print('==> cstrike AMBuilder already includes episode1')

for rel in ('extensions/cstrike/forwards.cpp', 'extensions/cstrike/natives.cpp'):
    p = sm / rel
    if p.exists():
        p.write_text(p.read_text().replace(
            '#if SOURCE_ENGINE == SE_CSS',
            '#if SOURCE_ENGINE == SE_CSS || SOURCE_ENGINE == SE_EPISODEONE',
        ))

# cstrike GetPlayerVarAddressOrError: FindInDataMap returns incomplete typedescription_t on EP1
natives = sm / 'extensions/cstrike/natives.cpp'
if natives.exists():
    text = natives.read_text()
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
        natives.write_text(text.replace(old_block, new_block, 1))
        print('==> Patched cstrike natives FindDataMapInfo')
    elif 'FindDataMapInfo(pMap, pszBaseVar' in text:
        print('==> cstrike natives FindDataMapInfo already patched')
    else:
        print('==> WARN: cstrike natives FindInDataMap block not found')

# bundled curl fortify noise on gcc only (clang-9 rejects -Wno-stringop-*)
curl_ambuild = sm / 'extensions/curl/curl-src/lib/AMBuilder'
if curl_ambuild.exists() and 'stringop-truncation' not in curl_ambuild.read_text():
    ct = curl_ambuild.read_text()
    ct = ct.replace(
        "binary.compiler.defines += ['_GNU_SOURCE']",
        "binary.compiler.defines += ['_GNU_SOURCE']\n"
        "    if binary.compiler.family == 'gcc':\n"
        "      binary.compiler.cflags += ['-Wno-stringop-truncation', '-Wno-error=stringop-truncation']",
        1,
    )
    curl_ambuild.write_text(ct)
    print('==> Patched bundled libcurl for stringop-truncation (gcc)')

# shell.cpp sign-compare
shell = sm / 'sourcepawn/vm/shell/shell.cpp'
if shell.exists() and 'if (index > params[0])' in shell.read_text():
    shell.write_text(shell.read_text().replace(
        'if (index > params[0])',
        'if (index > (size_t)params[0])',
    ))

# MMS headers used by SM 1.12 may lack PVKII/MCV constants when building against older trees
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

# --- Source-level patches ---
while IFS= read -r -d '' file; do
  sed -i 's/\r$//' "$file"
done < <(find "$sourcemod_dir" -type f \( -name '*.h' -o -name '*.cpp' -o -name 'AMBuildScript' -o -name 'AMBuilder' \) -print0)

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

echo "==> SourceMod 1.12+ css34 patches applied (Metamod 1.12 / 2.ep1)"
