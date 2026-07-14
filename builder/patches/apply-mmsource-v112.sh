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
  echo "hl2sdk-manifests missing in $mms_dir — run git submodule update --init --recursive" >&2
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
if 'css34: full commit SHA' in text or 'longhash' in text:
    print('==> MM generate_headers already prefers full SHA or uses longhash')
else:
    old = '""".format(tag, shorthash, major, minor, release, count))'
    new = '""".format(tag, longhash, major, minor, release, count))'
    if old in text:
        text = text.replace(
            '  with open(os.path.join(OutputFolder, \'metamod_version_auto.h\'), \'w\') as fp:\n',
            '  # css34: full commit SHA for meta version Built from\n'
            '  with open(os.path.join(OutputFolder, \'metamod_version_auto.h\'), \'w\') as fp:\n',
            1,
        )
        text = text.replace(old, new, 1)
        path.write_text(text)
        print('==> Patched MM generate_headers.py to emit full commit SHA')
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

echo "==> Metamod 1.12+ css34 light patches applied"
