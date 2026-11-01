#!/usr/bin/env bash
# css34 legacy-plugin bridge (T2.9): PLAPI 7-12 Metamod plugins on MM 1.12.
#
#   apply-mmsource-oldbridge.sh legacy <mmsource-1.10 dir>
#     core-legacy (metamod.1.ep1) gets a nested mode and the css34_old_* C API
#     (mm-oldbridge/css34_nested.cpp); the MM 1.10 build also compiles the
#     PLAPI 11 test plugin testing/plugins/css34_legacy_probe (not packaged).
#   apply-mmsource-oldbridge.sh modern <mmsource-1.12 dir>
#     core (metamod.2.ep1) hands PLAPI 7-12 plugins to metamod.1.ep1 from its
#     own bin directory (mm-oldbridge/css34_old_plugins.cpp).
#
# Every edit is anchored and fails closed; re-running is a no-op.
set -euo pipefail

mode="${1:?mode required: legacy | modern}"
mms_dir="${2:?Metamod source directory required}"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd "$script_dir/../.." && pwd)"
PY=(bash "$script_dir/../py.sh")

case "$mode" in
  legacy) [[ -d "$mms_dir/core-legacy" ]] || { echo "FAIL: $mms_dir has no core-legacy" >&2; exit 1; } ;;
  modern) [[ -f "$mms_dir/core/metamod_plugins.cpp" ]] || { echo "FAIL: $mms_dir has no core/metamod_plugins.cpp" >&2; exit 1; } ;;
  *) echo "FAIL: unknown mode $mode" >&2; exit 1 ;;
esac

MODE="$mode" MMS_DIR="$mms_dir" SRC_DIR="$script_dir/mm-oldbridge" REPO_DIR="$repo_dir" "${PY[@]}" - <<'PY'
import os
import shutil
from pathlib import Path

mode = os.environ['MODE']
mms = Path(os.environ['MMS_DIR'])
src = Path(os.environ['SRC_DIR'])
repo = Path(os.environ['REPO_DIR'])


def edit(rel, marker, old, new, count=1):
    path = mms / rel
    text = path.read_text()
    if marker in text:
        print(f'==> {rel}: {marker.strip()} already applied')
        return
    if text.count(old) != count:
        raise SystemExit(f'FAIL: oldbridge anchor not found {text.count(old)}x (want {count}) in {rel}: {old[:60]!r}')
    path.write_text(text.replace(old, new))
    print(f'==> {rel}: applied {marker.strip()}')


def install(source, rel):
    dest = mms / rel
    if dest.exists() and dest.read_bytes() == source.read_bytes():
        print(f'==> {rel} already installed')
        return
    shutil.copyfile(source, dest)
    print(f'==> Installed {rel}')


if mode == 'legacy':
    install(src / 'css34_nested.cpp', 'core-legacy/css34_nested.cpp')
    install(repo / 'testing/plugins/css34_legacy_probe/css34_legacy_probe.cpp',
            'core-legacy/css34_legacy_probe.cpp')
    edit('core-legacy/AMBuilder', "'css34_nested.cpp'",
         "    'vsp_bridge.cpp',\n",
         "    'vsp_bridge.cpp',\n    'css34_nested.cpp',\n")
    edit('core-legacy/AMBuilder', '# css34: PLAPI 11 test plugin',
         "  nodes = builder.Add(binary)\n  MMS.binaries += [nodes]\n",
         "  nodes = builder.Add(binary)\n  MMS.binaries += [nodes]\n\n"
         "  # css34: PLAPI 11 test plugin for the MM 1.12 legacy bridge (never packaged)\n"
         "  probe = MMS.HL2Library(builder, 'css34_legacy_probe', sdk)\n"
         "  probe.sources += ['css34_legacy_probe.cpp']\n"
         "  builder.Add(probe)\n")
    edit('core-legacy/sourcemm.h', 'extern bool g_bCss34Nested;',
         "extern bool g_bGameInit;\n",
         "extern bool g_bGameInit;\n/* css34: hosted by metamod.2.ep1 for PLAPI 7-12 plugins (css34_nested.cpp) */\n"
         "extern bool g_bCss34Nested;\n")
    edit('core-legacy/sourcemm.cpp', '/* css34 nested: the modern core answers',
         "\tif (g_GameDll.pGameClients)\n\t{\n\t\tSH_ADD_HOOK_STATICFUNC(IServerGameClients, ClientCommand",
         "\tif (g_bCss34Nested)\n\t{\n\t\t/* css34 nested: the modern core answers the client meta command */\n\t}\n"
         "\telse if (g_GameDll.pGameClients)\n\t{\n\t\tSH_ADD_HOOK_STATICFUNC(IServerGameClients, ClientCommand")
    edit('core-legacy/sourcemm.cpp', '/* css34 nested: plugins come from the modern core */',
         "bool GameInit_handler()\n{\n",
         "bool GameInit_handler()\n{\n\t/* css34 nested: plugins come from the modern core */\n"
         "\tif (g_bCss34Nested)\n\t{\n\t\tg_bGameInit = true;\n\t\tRETURN_META_VALUE(MRES_IGNORED, true);\n\t}\n\n")
    edit('core-legacy/sourcemm.cpp', '/* css34 nested: no metaplugins.ini reload */',
         "void LevelShutdown_handler(void)\n{\n\tif (!bInFirstLevel)\n",
         "void LevelShutdown_handler(void)\n{\n\t/* css34 nested: no metaplugins.ini reload */\n"
         "\tif (!bInFirstLevel && !g_bCss34Nested)\n")
    edit('core-legacy/concommands.cpp', '/* css34 nested: the modern core owns',
         "bool SMConVarAccessor::RegisterConCommandBase(ConCommandBase *pCommand)\n{\n",
         "extern bool g_bCss34Nested;\n\n"
         "bool SMConVarAccessor::RegisterConCommandBase(ConCommandBase *pCommand)\n{\n"
         "\t/* css34 nested: the modern core owns meta, metamod_version and mm_* */\n"
         "\tif (g_bCss34Nested)\n\t{\n\t\treturn true;\n\t}\n")
    edit('core-legacy/CSmmAPI.cpp', '/* css34 nested: no VSP listener',
         "void CSmmAPI::LoadAsVSP()\n{\n",
         "void CSmmAPI::LoadAsVSP()\n{\n\t/* css34 nested: no VSP listener of its own */\n"
         "\tif (g_bCss34Nested)\n\t{\n\t\treturn;\n\t}\n")
else:
    install(src / 'css34_old_plugins.cpp', 'core/css34_old_plugins.cpp')
    install(src / 'css34_old_plugins.h', 'core/css34_old_plugins.h')
    edit('core/AMBuilder', "'css34_old_plugins.cpp'",
         "    'metamod_plugins.cpp',\n",
         "    'metamod_plugins.cpp',\n    'css34_old_plugins.cpp',\n")
    edit('core/metamod_plugins.cpp', '#include "css34_old_plugins.h"',
         '#include "metamod_util.h"\n',
         '#include "metamod_util.h"\n#include "css34_old_plugins.h"\n')
    edit('core/metamod_plugins.cpp', '/* css34: PLAPI 7-12 plugins run in metamod.1.ep1 */',
         "\t\t\t\tint api = pl->m_API->GetApiVersion();\n\t\t\t\tif (api < PLAPI_MIN_VERSION)\n",
         "\t\t\t\tint api = pl->m_API->GetApiVersion();\n"
         "\t\t\t\tif (css34_IsOldPluginApi(api))\n\t\t\t\t{\n"
         "\t\t\t\t\t/* css34: PLAPI 7-12 plugins run in metamod.1.ep1 */\n"
         "\t\t\t\t\tcss34_LoadOldPlugin(pl, api, error, maxlen, m_AllLoaded);\n\t\t\t\t}\n"
         "\t\t\t\telse if (api < PLAPI_MIN_VERSION)\n")
PY
echo "==> css34 legacy-plugin bridge ($mode) applied to $mms_dir"
