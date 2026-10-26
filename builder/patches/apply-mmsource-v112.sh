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

# Manifests can add flags GCC 10 does not know (hl2sdk-manifests ebd6e10).
"${PY[@]}" "$script_dir/manifest_flag_guard.py" \
  "$mms_dir/hl2sdk-manifests/SdkHelpers.ambuild"

# Detached MMS_COMMIT checkout stores a raw SHA in .git/HEAD (no "ref: ...").
MMS_DIR="$mms_dir" "${PY[@]}" - <<'PYVER'
from pathlib import Path
import os

path = Path(os.environ['MMS_DIR']) / 'support/buildbot/Versioning'
if not path.exists():
    raise SystemExit('FAIL: support/buildbot/Versioning missing in MM')
text = path.read_text()
if 'css34: detached HEAD' in text or 'head_contents = fp.read().strip()' in text:
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
        raise SystemExit('FAIL: MM Versioning detached-HEAD pattern not found in support/buildbot/Versioning')
    else:
        path.write_text(text.replace(old, new, 1))
        print('==> Patched MM Versioning for detached MMS_COMMIT checkouts')
PYVER

# css34: lines.json MMS_GIT_REV (shallow clone cannot count commits).
"${PY[@]}" "$script_dir/pin-generate-headers.py" \
  "$mms_dir/support/buildbot/generate_headers.py" \
  --env MMS_GIT_REV

# Print CSS34 pack commit from `meta version`.
MMS_DIR="$mms_dir" "${PY[@]}" - <<'PYCONS'
from pathlib import Path
import os

def patch_console(rel: str) -> None:
    path = Path(os.environ['MMS_DIR']) / rel
    if not path.exists():
        raise SystemExit(f'FAIL: {rel} missing in MM')
    text = path.read_text()
    if 'CSS34 pack:' in text:
        print(f'==> {rel}: meta version already prints CSS34 pack commit')
        return

    # MM 1.12: versionlib.h + CONMSG / METAMOD_BUILD_SHA
    # MM 2.0:  metamod_version.h + CMDMSG / METAMOD_SHA (no versionlib.h)
    if '#include <versionlib.h>' in text:
        text = text.replace(
            '#include <versionlib.h>',
            '#include <versionlib.h>\n#include <css34_build_stamp.h>',
            1,
        )
    elif '#include "metamod_version.h"' in text:
        text = text.replace(
            '#include "metamod_version.h"',
            '#include "metamod_version.h"\n#include <css34_build_stamp.h>',
            1,
        )
    elif '#include <metamod_version.h>' in text:
        text = text.replace(
            '#include <metamod_version.h>',
            '#include <metamod_version.h>\n#include <css34_build_stamp.h>',
            1,
        )
    else:
        raise SystemExit(f'FAIL: no version header include found in {rel}')

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
        # MM 2.0 ReplyVersion (CMDMSG + METAMOD_SHA)
        (
            '''\tCMDMSG(client, "    Built from: https://github.com/alliedmodders/metamod-source/commit/%s\\n", METAMOD_SHA);
\tCMDMSG(client, "    Build ID: %s:%s\\n", METAMOD_LOCAL_REV, METAMOD_SHA);
''',
            '''\tCMDMSG(client, "    Built from: https://github.com/alliedmodders/metamod-source/commit/%s\\n", METAMOD_SHA);
\tCMDMSG(client, "    CSS34 pack: https://github.com/fmu1337/sourcemod-css34/commit/%s\\n", CSS34_PACK_COMMIT);
\tCMDMSG(client, "    Build ID: %s:%s\\n", METAMOD_LOCAL_REV, METAMOD_SHA);
''',
        ),
    ):
        if old in text:
            path.write_text(text.replace(old, new, 1))
            print(f'==> Patched {rel} to print CSS34 pack commit')
            return
    raise SystemExit(f'FAIL: Built from block not found in {rel}')

patch_console('core/metamod_console.cpp')
PYCONS

# Linux episode1: NO_HOOK_MALLOC must survive SdkHelpers (css34 glibc).
MMS_DIR="$mms_dir" "${PY[@]}" - <<'PYSDK'
from pathlib import Path
import json, os
man = Path(os.environ['MMS_DIR']) / 'hl2sdk-manifests/manifests/episode1.json'
if not man.exists():
    raise SystemExit('FAIL: episode1.json missing in MM hl2sdk-manifests')
data = json.loads(man.read_text())
linux = data.setdefault('linux', {})
defs = linux.setdefault('defines', [])
changed = False
for d in ('NO_HOOK_MALLOC', 'NO_MALLOC_OVERRIDE'):
    if d not in defs:
        defs.append(d)
        changed = True
if '_GLIBCXX_USE_CXX11_ABI=0' in defs:
    defs.remove('_GLIBCXX_USE_CXX11_ABI=0')
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

# css34: GCC 10 -Werror (metamod.cpp format truncation) and hidden static libstdc++.
# libgcc_s stays dynamic. Cores keep tier1 exports (--exclude-libs is not ALL).
MMS_DIR="$mms_dir" "${PY[@]}" - <<'PYSTD'
from pathlib import Path
import os
path = Path(os.environ['MMS_DIR']) / 'AMBuildScript'
text = path.read_text()
old = """      if cxx.family == 'gcc':
        cxx.linkflags += ['-static-libgcc']
      elif cxx.family == 'clang':
        cxx.linkflags += ['-lgcc_eh']
      cxx.linkflags += ['-static-libstdc++']
"""
new = """      if cxx.family == 'gcc':
        # css34: libgcc_s stays dynamic; hide static libstdc++ (GCC 10 / glibc 2.17)
        cxx.linkflags += ['-lgcc_s']
        cxx.cxxflags += ['-Wno-format-truncation', '-Wno-stringop-truncation', '-Wno-volatile']
      elif cxx.family == 'clang':
        cxx.linkflags += ['-lgcc_eh']
      cxx.linkflags += ['-static-libstdc++', '-Wl,--exclude-libs=libstdc++.a:libsupc++.a']
"""
if 'css34: libgcc_s stays dynamic' in text:
    print('==> MM 1.12 libstdc++ link flags already patched')
elif old not in text:
    raise SystemExit('FAIL: MM 1.12 static-libgcc anchor not found in AMBuildScript')
else:
    path.write_text(text.replace(old, new, 1))
    print('==> Patched MM 1.12 link flags (static libstdc++, dynamic libgcc_s)')
PYSTD

# episode1 SDK: MemAllocScratch lives in tier0/mem.h but the Source1 provider
# never includes it (newer SDKs pull it transitively). Without the include,
# metamod.2.ep1 fails to compile.
# MM 1.12: core/provider/provider_ep2.cpp
# MM 2.0+:  core/provider/source/provider_source.cpp
MMS_DIR="$mms_dir" "${PY[@]}" - <<'PYMEM'
from pathlib import Path
import os

root = Path(os.environ['MMS_DIR'])
candidates = [
    root / 'core/provider/provider_ep2.cpp',
    root / 'core/provider/source/provider_source.cpp',
]
path = next((p for p in candidates if p.is_file()), None)
if path is None:
    raise SystemExit(
        'Failed to locate provider_ep2.cpp / provider_source.cpp for mem.h patch'
    )
text = path.read_text()
rel = path.relative_to(root)
if 'tier0/mem.h' in text:
    print(f'==> {rel} already includes tier0/mem.h')
else:
    needles = [
        '#include <tier1/KeyValues.h>\n',
        '#include "KeyValues.h"\n',
        '#include <KeyValues.h>\n',
    ]
    needle = next((n for n in needles if n in text), None)
    if needle is None:
        raise SystemExit(f'Failed to locate KeyValues include in {rel}')
    path.write_text(text.replace(
        needle,
        needle + '#include <tier0/mem.h>  /* css34 episode1: MemAllocScratch */\n',
        1,
    ))
    print(f'==> Patched {rel} to include tier0/mem.h for episode1')
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
