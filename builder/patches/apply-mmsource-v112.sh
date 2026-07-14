#!/usr/bin/env bash
# Light CS:S v34 patches for Metamod:Source 1.12+ (modern Core / SH v5 / 2.ep1).
# Unlike apply-mmsource-css34.sh this does NOT transplant core-legacy / PLAPI 11.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PY=(bash "$script_dir/../py.sh")

mms_dir="${1:?mmsource directory required}"

if [ ! -f "$mms_dir/core/ISmmAPI.h" ]; then
  echo "Missing Metamod core: $mms_dir/core/ISmmAPI.h" >&2
  exit 1
fi

if [ ! -f "$mms_dir/hl2sdk-manifests/SdkHelpers.ambuild" ]; then
  echo "hl2sdk-manifests missing in $mms_dir - run git submodule update --init --recursive" >&2
  exit 1
fi

echo "==> Applying Metamod 1.12+ css34 light patches"

# Detached MMS_COMMIT checkout stores a raw SHA in .git/HEAD (no "ref: ...").
MMS_DIR="$mms_dir" "${PY[@]}" - <<'PYVER'
from pathlib import Path
import os

path = Path(os.environ['MMS_DIR']) / 'support/buildbot/Versioning'
if not path.exists():
    print('==> WARN: support/buildbot/Versioning missing')
    raise SystemExit(0)
text = path.read_text()
if 'css34: detached HEAD' in text:
    print('==> MM Versioning already handles detached HEAD')
else:
    old = """with open(os.path.join(builder.sourcePath, '.git', 'HEAD')) as fp:
 git_state = fp.read().strip().split(':')[1].strip()

git_head_path = os.path.join(builder.sourcePath, '.git', git_state)
if not os.path.exists(git_head_path):
  git_head_path = os.path.join(builder.sourcePath, '.git', 'HEAD')
"""
    new = """# css34: detached HEAD / MMS_COMMIT pin stores raw SHA in .git/HEAD
import re
with open(os.path.join(builder.sourcePath, '.git', 'HEAD')) as fp:
  head_contents = fp.read().strip()
if re.search('^[a-fA-F0-9]{40}$', head_contents):
  git_head_path = os.path.join(builder.sourcePath, '.git', 'HEAD')
else:
  git_state = head_contents.split(':')[1].strip()
  git_head_path = os.path.join(builder.sourcePath, '.git', git_state)
  if not os.path.exists(git_head_path):
    git_head_path = os.path.join(builder.sourcePath, '.git', 'HEAD')
"""
    if old not in text:
        # Best-effort: 1.12 Versioning may already be submodule-aware.
        print('==> WARN: MM Versioning detached-HEAD pattern not found (continuing)')
    else:
        path.write_text(text.replace(old, new, 1))
        print('==> Patched MM Versioning for detached MMS_COMMIT checkouts')
PYVER

# Prefer full upstream SHA in metamod_version_auto.h when the generator uses shorthash.
MMS_DIR="$mms_dir" "${PY[@]}" - <<'PYHDR'
from pathlib import Path
import os
path = Path(os.environ['MMS_DIR']) / 'support/buildbot/generate_headers.py'
if not path.exists():
    print('==> WARN: generate_headers.py missing')
    raise SystemExit(0)
text = path.read_text()
if 'css34: full commit SHA' in text:
    print('==> MM generate_headers already prefers full SHA')
else:
    # Note: file already mentions longhash in get_git_version(); only CSET format matters.
    old = '""".format(tag, shorthash, major, minor, release, fullstring, count))'
    new = '""".format(tag, longhash, major, minor, release, fullstring, count))'
    # MM 1.12 may omit fullstring in the format call:
    old_alt = '""".format(tag, shorthash, major, minor, release, count))'
    new_alt = '""".format(tag, longhash, major, minor, release, count))'
    if old in text:
        text = text.replace(
            '  with open(os.path.join(OutputFolder, \'metamod_version_auto.h\'), \'w\') as fp:\n',
            '  # css34: full commit SHA for meta version Built from\n'
            '  with open(os.path.join(OutputFolder, \'metamod_version_auto.h\'), \'w\') as fp:\n',
            1,
        )
        path.write_text(text.replace(old, new, 1))
        print('==> Patched MM generate_headers.py to emit full commit SHA')
    elif old_alt in text:
        text = text.replace(
            '  with open(os.path.join(OutputFolder, \'metamod_version_auto.h\'), \'w\') as fp:\n',
            '  # css34: full commit SHA for meta version Built from\n'
            '  with open(os.path.join(OutputFolder, \'metamod_version_auto.h\'), \'w\') as fp:\n',
            1,
        )
        path.write_text(text.replace(old_alt, new_alt, 1))
        print('==> Patched MM generate_headers.py to emit full commit SHA (alt)')
    else:
        print('==> WARN: generate_headers.py SHA format unchanged (continuing)')
PYHDR

# Print CSS34 pack commit from `meta version`.
MMS_DIR="$mms_dir" "${PY[@]}" - <<'PYCONS'
from pathlib import Path
import os

def patch_console(rel: str) -> None:
    path = Path(os.environ['MMS_DIR']) / rel
    if not path.exists():
        print(f'==> WARN: {rel} missing')
        return
    text = path.read_text()
    if 'CSS34 pack:' in text:
        print(f'==> {rel}: meta version already prints CSS34 pack commit')
        return
    if '#include <versionlib.h>' not in text:
        print(f'==> WARN: versionlib.h include missing in {rel}')
        return
    text = text.replace(
        '#include <versionlib.h>',
        '#include <versionlib.h>\n#include <css34_build_stamp.h>',
        1,
    )
    for old, new in (
        (
            '''\t\t\tCONMSG("Built from: https://github.com/alliedmodders/metamod-source/commit/%s\\n", METAMOD_BUILD_SHA);
#endif
\t\t\tCONMSG("Build ID: %s:%s\\n", METAMOD_BUILD_LOCAL_REV, METAMOD_BUILD_SHA);
''',
            '''\t\t\tCONMSG("Built from: https://github.com/alliedmodders/metamod-source/commit/%s\\n", METAMOD_BUILD_SHA);
#endif
\t\t\tCONMSG("CSS34 pack: https://github.com/fmu1337/sourcemod-css34/commit/%s\\n", CSS34_PACK_COMMIT);
\t\t\tCONMSG("Build ID: %s:%s\\n", METAMOD_BUILD_LOCAL_REV, METAMOD_BUILD_SHA);
''',
        ),
        (
            '''\t\tCONMSG("Built from: https://github.com/alliedmodders/metamod-source/commit/%s\\n", METAMOD_BUILD_SHA);
#endif
\t\tCONMSG("Build ID: %s:%s\\n", METAMOD_BUILD_LOCAL_REV, METAMOD_BUILD_SHA);
''',
            '''\t\tCONMSG("Built from: https://github.com/alliedmodders/metamod-source/commit/%s\\n", METAMOD_BUILD_SHA);
#endif
\t\tCONMSG("CSS34 pack: https://github.com/fmu1337/sourcemod-css34/commit/%s\\n", CSS34_PACK_COMMIT);
\t\tCONMSG("Build ID: %s:%s\\n", METAMOD_BUILD_LOCAL_REV, METAMOD_BUILD_SHA);
''',
        ),
    ):
        if old in text:
            path.write_text(text.replace(old, new, 1))
            print(f'==> Patched {rel} to print CSS34 pack commit')
            return
    print(f'==> WARN: Built from block not found in {rel}')

patch_console('core/metamod_console.cpp')
PYCONS

# Linux episode1: ensure CXX11 ABI=0 + NO_HOOK_MALLOC survive SdkHelpers (css34 glibc).
MMS_DIR="$mms_dir" "${PY[@]}" - <<'PYSDK'
from pathlib import Path
import json, os
man = Path(os.environ['MMS_DIR']) / 'hl2sdk-manifests/manifests/episode1.json'
if not man.exists():
    print('==> WARN: episode1.json missing in MM hl2sdk-manifests')
    raise SystemExit(0)
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
    print('==> Patched MM episode1.json linux defines for css34')
else:
    print('==> MM episode1.json linux defines already ok')
PYSDK

# Force link via C++ driver (AMBuild tip detects raw `ld` into linker_argv).
MMS_DIR="$mms_dir" "${PY[@]}" - <<'PYLINK'
from pathlib import Path
import os
path = Path(os.environ['MMS_DIR']) / 'AMBuildScript'
text = path.read_text()
if 'css34: link via C++ driver' in text:
    print('==> MM linker_argv already forced to C++ driver')
else:
    detect_anchor = "    if not self.all_targets:\n        raise Exception('No suitable C/C++ compiler was found.')\n"
    detect_insert = detect_anchor + """
    # css34: link via C++ driver (AMBuild tip detects raw ld into linker_argv)
    for _cxx in self.all_targets:
      _cxx.linker_argv = list(_cxx.cxx_argv)
"""
    if detect_anchor not in text:
        raise SystemExit('Failed to locate DetectCxx all_targets guard in MM AMBuildScript')
    path.write_text(text.replace(detect_anchor, detect_insert, 1))
    print('==> Forced MM linker_argv to C++ driver')
PYLINK

# episode1 SDK: MemAllocScratch lives in tier0/mem.h but provider_ep2.cpp never includes it
# (newer SDKS pull it transitively). Without the include, metamod.2.ep1 fails to compile.
MMS_DIR="$mms_dir" "${PY[@]}" - <<'PYMEM'
from pathlib import Path
import os
path = Path(os.environ['MMS_DIR']) / 'core/provider/provider_ep2.cpp'
text = path.read_text()
if 'tier0/mem.h' in text:
    print('==> provider_ep2.cpp already includes tier0/mem.h')
else:
    needle = '#include <tier1/KeyValues.h>\n'
    if needle not in text:
        raise SystemExit('Failed to locate KeyValues include in provider_ep2.cpp')
    path.write_text(text.replace(
        needle,
        needle + '#include <tier0/mem.h>  /* css34 episode1: MemAllocScratch */\n',
        1,
    ))
    print('==> Patched provider_ep2.cpp to include tier0/mem.h for episode1')
PYMEM

# css34: SdkHelpers puts dynamic vstdlib/tier0 BEFORE static tier1_i486.a (postlink).
# That imports ConVar from vstdlib and hangs srcds during GameDLLInit (same fix as SM core).
MMS_DIR="$mms_dir" "${PY[@]}" - <<'PYTIER1'
from pathlib import Path
import os

path = Path(os.environ['MMS_DIR']) / 'AMBuildScript'
text = path.read_text()
if 'css34: episode1 tier1 before vstdlib' in text:
    print('==> MM HL2Library tier1-before-vstdlib already patched')
else:
    needle = "    SdkHelpers.configureCxx(context, binary, sdk)\n\n    return binary"
    insert = """    SdkHelpers.configureCxx(context, binary, sdk)

    # css34: episode1 tier1 before vstdlib so ConVar is embedded, not imported
    if sdk.get('name') == 'episode1' and cxx.target.platform == 'linux':
      import os as _os
      tier1 = _os.path.join(sdk['path'], 'linux_sdk', 'tier1_i486.a')
      if _os.path.isfile(tier1):
        # Drop copy that configureCxx placed in postlink; put it first in linkflags.
        cxx.postlink = [x for x in cxx.postlink if x != tier1]
        if tier1 not in cxx.linkflags:
          cxx.linkflags[0:0] = [tier1]
      for flag in ('-Wl,--no-as-needed', '-lpthread', '-lrt', '-lgcc_s'):
        if flag not in cxx.linkflags:
          cxx.linkflags += [flag]

    return binary"""
    if needle not in text:
        raise SystemExit('Failed to locate HL2Library configureCxx return in MM AMBuildScript')
    path.write_text(text.replace(needle, insert, 1), encoding='utf-8')
    print('==> Patched MM HL2Library for episode1 tier1-before-vstdlib')
PYTIER1

echo "==> Metamod 1.12+ css34 light patches applied"
