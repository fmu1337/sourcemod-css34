#!/usr/bin/env bash
# CS:S v34 Metamod:Source 1.10.6 uses the PLAPI 11 / core-legacy ABI and
# SourceHook iface v4. Upstream mmsource 1.10-dev defaults to core/ (SH v5 /
# modern ISmmAPI), which produces plugins that crash inside css34 MM when
# registering hooks (HookManPubFunc / AddHook ABI mismatch → null call).
#
# We:
#  1) Replace core/sourcehook with core-legacy (SH_IFACE_VERSION 4)
#  2) Keep legacy ISmmAPI *vtable order* (and PLAPI 11) but rename methods to
#     modern SourceMod-facing names so SM compiles without metamod_wrappers.h
#     macros that break Valve IConCommandBaseAccessor::RegisterConCommandBase.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Always invoke via bash so a missing +x bit cannot break CI checkouts.
PY=(bash "$script_dir/../py.sh")

mms_dir="${1:?mmsource directory required}"
core_dir="$mms_dir/core"
legacy_dir="$mms_dir/core-legacy"
ext_h="$core_dir/ISmmPluginExt.h"

if [ ! -d "$core_dir" ]; then
  echo "Missing Metamod core dir: $core_dir" >&2
  exit 1
fi

# --- SourceHook v4 (required by css34 metamod.1.ep1.so) ---
if [ -d "$legacy_dir/sourcehook" ]; then
  echo "==> Installing core-legacy SourceHook (SH_IFACE_VERSION 4) into core/"
  rm -rf "$core_dir/sourcehook"
  cp -a "$legacy_dir/sourcehook" "$core_dir/sourcehook"
  # loader/AMBuilder also looks for $mms_root/sourcehook
  if [ "${BUILD_PLATFORM:-linux}" = "windows" ]; then
    rm -rf "$mms_dir/sourcehook"
    cp -a "$core_dir/sourcehook" "$mms_dir/sourcehook"
  else
    ln -sfn core/sourcehook "$mms_dir/sourcehook"
  fi
  if ! grep -q 'SH_IFACE_VERSION 4' "$core_dir/sourcehook/sourcehook.h"; then
    echo "Expected SH_IFACE_VERSION 4 after core-legacy sourcehook install" >&2
    exit 1
  fi
  # SourceMod 1.11 uses SH_DECL_EXTERN* (modern-only). Emit v4-ABI equivalents
  # (AddHook has no AddHookMode; VP hooks use separate FHVPAdd).
  export MMS_CSS34_SH_H="$core_dir/sourcehook/sourcehook.h"
  export MMS_CSS34_ROOT="$mms_dir"
  "${PY[@]}" "$script_dir/gen-sh-decl-extern-v4.py"

  # bintools uses modern PassInfo/ProtoInfo; omit legacy ProtoInfo when the shim is active.
  export MMS_CSS34_SH_H
  export MMS_PATCH_DIR="$script_dir"
  "${PY[@]}" - <<'PY'
from pathlib import Path
import os

path = Path(os.environ['MMS_CSS34_SH_H'])
text = path.read_text()
marker = 'SOURCEMOD_BINTOOLS_PROTO_SHIM'
if marker in text:
    print('==> sourcehook.h ProtoInfo shim guard already present')
else:
    old = """\tstruct ProtoInfo
\t{
\t\tProtoInfo(int rtsz, int nop, const int *p) : beginningNull(0), retTypeSize(rtsz), numOfParams(nop), params(p)
\t\t{
\t\t}
\t\tint beginningNull;\t\t//!< To distinguish from old protos (which never begin with 0)
\t\tint retTypeSize;\t\t//!< 0 if void
\t\tint numOfParams;\t\t//!< number of parameters
\t\tconst int *params;\t\t//!< params[0]=0 (or -1 for vararg), params[1]=size of first param, ...
\t};"""
    new = """#ifndef SOURCEMOD_BINTOOLS_PROTO_SHIM
\tstruct ProtoInfo
\t{
\t\tProtoInfo(int rtsz, int nop, const int *p) : beginningNull(0), retTypeSize(rtsz), numOfParams(nop), params(p)
\t\t{
\t\t}
\t\tint beginningNull;\t\t//!< To distinguish from old protos (which never begin with 0)
\t\tint retTypeSize;\t\t//!< 0 if void
\t\tint numOfParams;\t\t//!< number of parameters
\t\tconst int *params;\t\t//!< params[0]=0 (or -1 for vararg), params[1]=size of first param, ...
\t};
#endif // !SOURCEMOD_BINTOOLS_PROTO_SHIM"""
    if old not in text:
        raise SystemExit('Failed to locate legacy ProtoInfo in sourcehook.h')
    path.write_text(text.replace(old, new, 1))
    print('==> Wrapped legacy ProtoInfo for bintools shim in sourcehook.h')

shim_src = Path(os.environ['MMS_PATCH_DIR']) / 'sourcehook-pibuilder-shim.h'
shim_dst = path.parent / 'sourcehook_pibuilder.h'
shim_dst.write_text(shim_src.read_text())
print(f'==> Installed {shim_dst.name} for css34 bintools builds')
PY
else
  echo "Missing $legacy_dir/sourcehook — cannot target css34 Metamod" >&2
  exit 1
fi

MMS_LEGACY_SHA="${MMS_LEGACY_SHA:-a112f84e1fe9659918300c65102ad97cdc5b106d}"
tmpdir="$(mktemp -d)"
cleanup() { rm -rf "$tmpdir"; }
trap cleanup EXIT

echo "==> Fetching Metamod core-legacy ISmm headers (${MMS_LEGACY_SHA})"
curl -fsSL -o "$tmpdir/ISmmAPI.h" \
  "https://raw.githubusercontent.com/alliedmodders/metamod-source/${MMS_LEGACY_SHA}/core-legacy/ISmmAPI.h"
curl -fsSL -o "$tmpdir/ISmmPlugin.h" \
  "https://raw.githubusercontent.com/alliedmodders/metamod-source/${MMS_LEGACY_SHA}/core-legacy/ISmmPlugin.h"

export MMS_CORE_DIR="$core_dir"
export MMS_TMPDIR="$tmpdir"
"${PY[@]}" - <<'PY'
from pathlib import Path
import os
import re

core = Path(os.environ['MMS_CORE_DIR'])
tmpdir = Path(os.environ['MMS_TMPDIR'])

def strip_old_gcc_guard(text: str) -> str:
    return re.sub(
        r'#if defined __GNUC__\n#if \(\(__GNUC__ == 3\).*?#endif //__GNUC__\n',
        '',
        text,
        count=1,
        flags=re.S,
    )

def wrap_sourcemm(text: str, usings: list) -> str:
    text = strip_old_gcc_guard(text)
    if 'namespace SourceMM' in text:
        return text
    m = re.search(r'#ifndef\s+\w+\n#define\s+\w+\n', text)
    if not m:
        raise SystemExit('Could not find include guard start')
    endif = text.rfind('#endif')
    if endif < 0:
        raise SystemExit('Could not find include guard end')
    head, body, tail = text[:m.end()], text[m.end():endif], text[endif:]
    preamble, decls = [], []
    for line in body.splitlines(True):
        stripped = line.lstrip()
        if stripped.startswith('#include'):
            preamble.append(line)
        else:
            decls.append(line)
    using_lines = ''.join(f'using SourceMM::{name};\n' for name in usings)
    return (
        head + ''.join(preamble) + '\nnamespace SourceMM {\n'
        + ''.join(decls) + '\n} // namespace SourceMM\n\n'
        + using_lines + '\n' + tail
    )

# Modern names, legacy slot order.
api_renames = [
    ('engineFactory', 'GetEngineFactory'),
    ('physicsFactory', 'GetPhysicsFactory'),
    ('fileSystemFactory', 'GetFileSystemFactory'),
    ('serverFactory', 'GetServerFactory'),
    ('pGlobals', 'GetCGlobals'),
    ('RegisterConCmdBase', 'RegisterConCommandBase'),
    ('UnregisterConCmdBase', 'UnregisterConCommandBase'),
]

api = (tmpdir / 'ISmmAPI.h').read_text()
for old, new in api_renames:
    # Only rename method declarations / references that are the identifier.
    api = re.sub(rf'\b{old}\b', new, api)

# META_REG* macros in legacy ISmmPlugin still say RegisterConCmdBase — fix after wrap.
plugin = (tmpdir / 'ISmmPlugin.h').read_text()
plugin = plugin.replace('RegisterConCmdBase', 'RegisterConCommandBase')
plugin = plugin.replace('UnregisterConCmdBase', 'UnregisterConCommandBase')

api = wrap_sourcemm(api, ['ISmmAPI'])
plugin = wrap_sourcemm(plugin, ['ISmmPlugin', 'IMetamodListener'])

# Legacy headers only export with default visibility on GCC 4.x; gcc-9 needs >= 4.
plugin = plugin.replace(
    '#if (__GNUC__ == 4) && (__GNUC_MINOR__ >= 1)',
    '#if (__GNUC__ >= 4)',
)

if 'GetEngineFactory' not in api or 'SetLastMetaReturn' not in api:
    raise SystemExit('ISmmAPI rename/wrap failed sanity check')
if 'PLAPI_VERSION' not in plugin:
    raise SystemExit('ISmmPlugin missing PLAPI_VERSION')
if '#if (__GNUC__ >= 4)' not in plugin:
    raise SystemExit('Failed to patch SMM_API visibility for modern GCC')

(core / 'ISmmAPI.h').write_text(api)
(core / 'ISmmPlugin.h').write_text(plugin)
print('==> Installed legacy-layout ISmmAPI/ISmmPlugin with modern method names')
PY

# Ext.h: define METAMOD_PLAPI_VERSION=11 so smsdk_ext takes the modern-name code path
# against our renamed legacy-layout ISmmAPI. GetApiVersion still returns PLAPI_VERSION (11)
# from ISmmPlugin.h.
if [ -f "$ext_h" ]; then
  "${PY[@]}" - <<'PY'
from pathlib import Path
import os
import re
path = Path(os.environ['MMS_CORE_DIR']) / 'ISmmPluginExt.h'
text = path.read_text()
if re.search(r'^#define METAMOD_PLAPI_VERSION\s+11\b', text, re.M):
    print('==> ISmmPluginExt.h already has METAMOD_PLAPI_VERSION 11')
elif 'css34 uses PLAPI_VERSION 11' in text or 'METAMOD_PLAPI_VERSION omitted' in text:
    text2 = re.sub(
        r'/\* METAMOD_PLAPI_VERSION omitted:.*? \*/',
        '#define METAMOD_PLAPI_VERSION\t\t\t11\t\t\t\t/**< css34 Metamod max API */',
        text,
        count=1,
        flags=re.S,
    )
    path.write_text(text2)
    print('==> Restored METAMOD_PLAPI_VERSION 11 in ISmmPluginExt.h')
else:
    text2, n = re.subn(
        r'^#define METAMOD_PLAPI_VERSION\s+\d+.*$',
        '#define METAMOD_PLAPI_VERSION\t\t\t11\t\t\t\t/**< css34 Metamod max API */',
        text,
        count=1,
        flags=re.M,
    )
    if n != 1:
        raise SystemExit('Failed to pin METAMOD_PLAPI_VERSION in ISmmPluginExt.h')
    path.write_text(text2)
    print('==> Pinned METAMOD_PLAPI_VERSION to 11 in ISmmPluginExt.h')
PY
fi

# css34: stamp full upstream SHA into metamod_version_auto.h and print CSS34 pack
# commit from `meta version`.
MMS_DIR="$mms_dir" "${PY[@]}" - <<'PYHDR'
from pathlib import Path
import os
path = Path(os.environ['MMS_DIR']) / 'support/buildbot/generate_headers.py'
text = path.read_text()
# Use full 40-char SHA for Built from / Build ID.
old = '""".format(tag, shorthash, major, minor, release, count))'
new = '""".format(tag, longhash, major, minor, release, count))'
if 'css34: full commit SHA' in text:
    print('==> MM generate_headers already uses full SHA')
elif old in text:
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
    raise SystemExit('Failed to patch MM generate_headers.py for full SHA')
PYHDR

MMS_DIR="$mms_dir" "${PY[@]}" - <<'PYCONS'
from pathlib import Path
import os
path = Path(os.environ['MMS_DIR']) / 'core/metamod_console.cpp'
text = path.read_text()
if 'CSS34 pack:' in text:
    print('==> meta version already prints CSS34 pack commit')
else:
    if '#include <versionlib.h>' not in text:
        raise SystemExit('Failed to locate versionlib.h include in metamod_console.cpp')
    text = text.replace(
        '#include <versionlib.h>',
        '#include <versionlib.h>\n#include <css34_build_stamp.h>',
        1,
    )
    old = '''\t\t\tCONMSG("Built from: https://github.com/alliedmodders/metamod-source/commit/%s\\n", METAMOD_BUILD_SHA);
#endif
\t\t\tCONMSG("Build ID: %s:%s\\n", METAMOD_BUILD_LOCAL_REV, METAMOD_BUILD_SHA);
'''
    new = '''\t\t\tCONMSG("Built from: https://github.com/alliedmodders/metamod-source/commit/%s\\n", METAMOD_BUILD_SHA);
#endif
\t\t\tCONMSG("CSS34 pack: https://github.com/fmu1337/sourcemod-css34/commit/%s\\n", CSS34_PACK_COMMIT);
\t\t\tCONMSG("Build ID: %s:%s\\n", METAMOD_BUILD_LOCAL_REV, METAMOD_BUILD_SHA);
'''
    if old not in text:
        raise SystemExit('Failed to locate Built from block in metamod_console.cpp')
    path.write_text(text.replace(old, new, 1))
    print('==> Patched meta version to print CSS34 pack commit')
PYCONS
