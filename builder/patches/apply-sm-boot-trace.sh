#!/usr/bin/env bash
# Inject SM_BOOT_TRACE probes into SourceMod core/logic for hang diagnosis.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
sourcemod_dir="${1:?sourcemod directory required}"
trace_header="$script_dir/sm-boot-trace.h"
marker="CSS34 SM_BOOT_TRACE"

if [[ ! -f "$trace_header" ]]; then
  echo "missing $trace_header" >&2
  exit 1
fi

cp -f "$trace_header" "$sourcemod_dir/core/sm-boot-trace.h"

apply_once() {
  local file="$1"
  local needle="$2"
  if [[ ! -f "$file" ]]; then
    echo "skip missing $file" >&2
    return 0
  fi
  if grep -q "$marker" "$file"; then
    echo "==> boot trace already in $(basename "$file")"
    return 0
  fi
  if ! grep -q "$needle" "$file"; then
    echo "needle not found in $file: $needle" >&2
    exit 1
  fi
}

PY=(bash "$script_dir/../py.sh")
SOURCEMOD_DIR="$sourcemod_dir" MARKER="$marker" "${PY[@]}" - <<'PY'
from pathlib import Path
import os

sm = Path(os.environ['SOURCEMOD_DIR'])
marker = os.environ['MARKER']

def ensure_include(text: str) -> str:
    inc = '#include "sm-boot-trace.h"\n'
    if inc in text:
        return text
    # After last #include block in first 80 lines.
    lines = text.splitlines(keepends=True)
    last_inc = 0
    for i, line in enumerate(lines[:80]):
        if line.startswith('#include'):
            last_inc = i
    if last_inc:
        lines.insert(last_inc + 1, inc)
    else:
        lines.insert(0, inc)
    return ''.join(lines)

def patch_file(rel: str, edits):
    path = sm / rel
    if not path.exists():
        print(f'skip missing {rel}')
        return
    text = path.read_text()
    if marker in text:
        print(f'==> boot trace already in {rel}')
        return
    for old, new, label in edits:
        if old not in text:
            raise SystemExit(f'{rel}: anchor not found for {label}')
        text = text.replace(old, new, 1)
    text = ensure_include(text)
    path.write_text(text)
    print(f'==> patched boot trace in {rel}')

patch_file('core/logic_bridge.cpp', [
    (
        '\tlogic_ = ke::SharedLib::Open(file, myerror, sizeof(myerror));\n\tif (!logic_) {',
        f'\tsm_boot_trace("{marker} LoadBridge: before dlopen");\n'
        '\tlogic_ = ke::SharedLib::Open(file, myerror, sizeof(myerror));\n'
        f'\tsm_boot_trace("{marker} LoadBridge: after dlopen");\n'
        '\tif (!logic_) {',
        'LoadBridge dlopen',
    ),
    (
        '\tlogic_init_ = llf(SM_LOGIC_MAGIC);\n\tif (!logic_init_) {',
        f'\tsm_boot_trace("{marker} LoadBridge: before logic_load");\n'
        '\tlogic_init_ = llf(SM_LOGIC_MAGIC);\n'
        f'\tsm_boot_trace("{marker} LoadBridge: after logic_load");\n'
        '\tif (!logic_init_) {',
        'LoadBridge logic_load',
    ),
    (
        'void CoreProviderImpl::InitializeBridge()\n{',
        'void CoreProviderImpl::InitializeBridge()\n{\n'
        f'\tsm_boot_trace("{marker} InitializeBridge: enter");',
        'InitializeBridge enter',
    ),
    (
        '\tlogic_init_(this, &logicore);\n\n\t// Join logic\'s SMGlobalClass instances.',
        f'\tsm_boot_trace("{marker} InitializeBridge: before logic_init_");\n'
        '\tlogic_init_(this, &logicore);\n'
        f'\tsm_boot_trace("{marker} InitializeBridge: after logic_init_");\n\n'
        '\t// Join logic\'s SMGlobalClass instances.',
        'InitializeBridge logic_init_',
    ),
    (
        '\trootmenu = logicore.rootmenu;\n}',
        '\trootmenu = logicore.rootmenu;\n'
        f'\tsm_boot_trace("{marker} InitializeBridge: leave");\n'
        '}',
        'InitializeBridge leave',
    ),
])

patch_file('core/sourcemod.cpp', [
    (
        '\tif (!sCoreProviderImpl.LoadBridge(error, maxlength))\n\t{\n\t\treturn false;\n\t}',
        f'\tsm_boot_trace("{marker} InitializeSourceMod: before LoadBridge");\n'
        '\tif (!sCoreProviderImpl.LoadBridge(error, maxlength))\n\t{\n'
        f'\t\tsm_boot_trace("{marker} InitializeSourceMod: LoadBridge failed");\n'
        '\t\treturn false;\n\t}\n'
        f'\tsm_boot_trace("{marker} InitializeSourceMod: LoadBridge ok");',
        'InitializeSourceMod LoadBridge',
    ),
    (
        '\tif (!late)\n\t{\n\t\tStartSourceMod(false);\n\t}',
        f'\tsm_boot_tracef("{marker} InitializeSourceMod: before StartSourceMod late=%d", (int)late);\n'
        '\tif (!late)\n\t{\n\t\tStartSourceMod(false);\n\t}\n'
        f'\tsm_boot_trace("{marker} InitializeSourceMod: after StartSourceMod call");',
        'InitializeSourceMod StartSourceMod',
    ),
    (
        'void SourceModBase::StartSourceMod(bool late)\n{',
        'void SourceModBase::StartSourceMod(bool late)\n{\n'
        f'\tsm_boot_tracef("{marker} StartSourceMod: enter late=%d loaded=%d", (int)late, (int)g_Loaded);',
        'StartSourceMod enter',
    ),
    (
        '\tsCoreProviderImpl.InitializeBridge();\n\n\t/* Initialize CoreConfig',
        f'\tsm_boot_trace("{marker} StartSourceMod: before InitializeBridge");\n'
        '\tsCoreProviderImpl.InitializeBridge();\n'
        f'\tsm_boot_trace("{marker} StartSourceMod: after InitializeBridge");\n\n'
        '\t/* Initialize CoreConfig',
        'StartSourceMod InitializeBridge',
    ),
    (
        '\tg_CoreConfig.Initialize();\n\n\t/* Notify! */\n\tSMGlobalClass *pBase = SMGlobalClass::head;\n\twhile (pBase)\n\t{\n\t\tpBase->OnSourceModStartup(false);',
        f'\tsm_boot_trace("{marker} StartSourceMod: before CoreConfig.Initialize");\n'
        '\tg_CoreConfig.Initialize();\n'
        f'\tsm_boot_trace("{marker} StartSourceMod: after CoreConfig.Initialize");\n\n'
        '\t/* Notify! */\n\tSMGlobalClass *pBase = SMGlobalClass::head;\n'
        f'\tsm_boot_trace("{marker} StartSourceMod: OnSourceModStartup loop");\n'
        '\twhile (pBase)\n\t{\n\t\tpBase->OnSourceModStartup(false);',
        'StartSourceMod CoreConfig',
    ),
    (
        '\tsCoreProviderImpl.InitializeHooks();\n\n\t/* Notify! */\n\tpBase = SMGlobalClass::head;\n\twhile (pBase)\n\t{\n\t\tpBase->OnSourceModAllInitialized();',
        f'\tsm_boot_trace("{marker} StartSourceMod: before InitializeHooks");\n'
        '\tsCoreProviderImpl.InitializeHooks();\n'
        f'\tsm_boot_trace("{marker} StartSourceMod: after InitializeHooks");\n\n'
        '\t/* Notify! */\n\tpBase = SMGlobalClass::head;\n'
        f'\tsm_boot_trace("{marker} StartSourceMod: OnSourceModAllInitialized loop");\n'
        '\twhile (pBase)\n\t{\n\t\tpBase->OnSourceModAllInitialized();',
        'StartSourceMod InitializeHooks',
    ),
    (
        '\tg_Loaded = true;\n\n\t/* Initialize VSP stuff */',
        f'\tsm_boot_trace("{marker} StartSourceMod: OnSourceModAllInitialized_Post loop done");\n'
        '\tg_Loaded = true;\n'
        f'\tsm_boot_trace("{marker} StartSourceMod: g_Loaded=true");\n\n'
        '\t/* Initialize VSP stuff */',
        'StartSourceMod g_Loaded',
    ),
    (
        '\tSH_ADD_HOOK(IServerGameDLL, Think, gamedll, SH_MEMBER(logicore.callbacks, &IProviderCallbacks::OnThink), false);\n}',
        f'\tsm_boot_trace("{marker} StartSourceMod: leave");\n'
        '\tSH_ADD_HOOK(IServerGameDLL, Think, gamedll, SH_MEMBER(logicore.callbacks, &IProviderCallbacks::OnThink), false);\n}',
        'StartSourceMod leave',
    ),
    (
        'bool SourceModBase::LevelInit(char const *pMapName, char const *pMapEntities, char const *pOldLevel, char const *pLandmarkName, bool loadGame, bool background)\n{',
        'bool SourceModBase::LevelInit(char const *pMapName, char const *pMapEntities, char const *pOldLevel, char const *pLandmarkName, bool loadGame, bool background)\n{\n'
        f'\tsm_boot_tracef("{marker} LevelInit: enter map=%s loaded=%d", pMapName ? pMapName : "(null)", (int)g_Loaded);',
        'LevelInit enter',
    ),
    (
        '\t/* Notify! */\n\tSMGlobalClass *pBase = SMGlobalClass::head;\n\twhile (pBase)\n\t{\n\t\tpBase->OnSourceModLevelChange(pMapName);',
        f'\tsm_boot_trace("{marker} LevelInit: OnSourceModLevelChange loop");\n'
        '\t/* Notify! */\n\tSMGlobalClass *pBase = SMGlobalClass::head;\n'
        '\tunsigned level_cb = 0;\n'
        '\twhile (pBase)\n\t{\n'
        f'\t\tsm_boot_tracef("{marker} LevelInit: OnSourceModLevelChange cb=%u ptr=%p", level_cb++, (void*)pBase);\n'
        '\t\tpBase->OnSourceModLevelChange(pMapName);',
        'LevelInit OnSourceModLevelChange',
    ),
    (
        '\tDoGlobalPluginLoads();\n\n\tm_IsMapLoading = false;',
        f'\tsm_boot_trace("{marker} LevelInit: before DoGlobalPluginLoads");\n'
        '\tDoGlobalPluginLoads();\n'
        f'\tsm_boot_trace("{marker} LevelInit: after DoGlobalPluginLoads");\n\n'
        '\tm_IsMapLoading = false;',
        'LevelInit DoGlobalPluginLoads',
    ),
])

patch_file('core/logic/common_logic.cpp', [
    (
        'static void logic_init(CoreProvider* core, sm_logic_t* _logic)\n{',
        'static void logic_init(CoreProvider* core, sm_logic_t* _logic)\n{\n'
        f'\tsm_boot_trace("{marker} logic_init: enter");',
        'logic_init enter',
    ),
    (
        '\t_logic->core_ident = g_pCoreIdent;\n}',
        '\t_logic->core_ident = g_pCoreIdent;\n'
        f'\tsm_boot_trace("{marker} logic_init: leave");\n'
        '}',
        'logic_init leave',
    ),
    (
        '\tif (magic != SM_LOGIC_MAGIC)\n\t{\n\t\treturn NULL;\n\t}',
        f'\tsm_boot_tracef("{marker} logic_load: magic=0x%x", magic);\n'
        '\tif (magic != SM_LOGIC_MAGIC)\n\t{\n\t\treturn NULL;\n\t}',
        'logic_load magic',
    ),
])

patch_file('core/logic/Logger.cpp', [
    (
        'void Logger::OnSourceModLevelChange(const char *mapName)\n{\n\t_MapChange(mapName);\n}',
        'void Logger::OnSourceModLevelChange(const char *mapName)\n{\n'
        f'\tsm_boot_tracef("{marker} Logger::OnSourceModLevelChange map=%s", mapName ? mapName : "(null)");\n'
        '\t_MapChange(mapName);\n'
        f'\tsm_boot_trace("{marker} Logger::OnSourceModLevelChange done");\n'
        '}',
        'Logger OnSourceModLevelChange',
    ),
    (
        'void Logger::_MapChange(const char *mapname)\n{\n\tm_CurrentMapName = mapname;',
        'void Logger::_MapChange(const char *mapname)\n{\n'
        f'\tsm_boot_tracef("{marker} Logger::_MapChange map=%s", mapname ? mapname : "(null)");\n'
        '\tm_CurrentMapName = mapname;',
        'Logger _MapChange',
    ),
    (
        '\t/* CSS34 LOGGER_MAPCHANGE_FIX: log first mapchange even when daily log path is new */\n'
        '\tif (m_NormalFileName.compare(buff))\n\t{\n\t\t_CloseNormal();\n\t\tm_NormalFileName = buff;\n\t}\n'
        '\tif (bLevelChange)\n\t{\n\t\tLogMessage("-------- Mapchange to %s --------", m_CurrentMapName.c_str());\n\t}',
        '\t/* CSS34 LOGGER_MAPCHANGE_FIX: log first mapchange even when daily log path is new */\n'
        '\tif (m_NormalFileName.compare(buff))\n\t{\n\t\t_CloseNormal();\n\t\tm_NormalFileName = buff;\n\t}\n'
        '\tif (bLevelChange)\n\t{\n'
        f'\t\tsm_boot_trace("{marker} Logger::_UpdateFiles: mapchange LogMessage");\n'
        '\t\tLogMessage("-------- Mapchange to %s --------", m_CurrentMapName.c_str());\n\t}',
        'Logger _UpdateFiles mapchange trace',
    ),
    (
        '\tif (pFile == NULL)\n\t{\n\t\t_LogFatalOpen(m_NormalFileName);\n\t\treturn pFile;\n\t}',
        f'\tif (pFile == NULL)\n\t{{\n\t\tsm_boot_tracef("{marker} Logger::_OpenNormal: fopen failed for %s", m_NormalFileName.c_str());\n\t\t_LogFatalOpen(m_NormalFileName);\n\t\treturn pFile;\n\t}}',
        'Logger _OpenNormal fopen',
    ),
])
PY

# Enable SM_BOOT_TRACE define in core + logic builds via AMBuildScript / logic AMBuilder.
SOURCEMOD_DIR="$sourcemod_dir" MARKER="$marker" "${PY[@]}" - <<'PY'
from pathlib import Path
import os

sm = Path(os.environ['SOURCEMOD_DIR'])
marker = os.environ['MARKER']

ambuild = sm / 'AMBuildScript'
text = ambuild.read_text()
trace_define = "      'SM_BOOT_TRACE',  # css34 boot trace\n"
if "'SM_BOOT_TRACE'" in text:
    print('==> AMBuildScript SM_BOOT_TRACE already set')
else:
    anchor = "      'SOURCEMOD_BUILD',\n"
    if anchor not in text:
        raise SystemExit('AMBuildScript SOURCEMOD_BUILD anchor missing')
    text = text.replace(anchor, anchor + trace_define, 1)
    ambuild.write_text(text)
    print('==> AMBuildScript: added SM_BOOT_TRACE define')

logic_amb = sm / 'core' / 'logic' / 'AMBuilder'
if logic_amb.exists():
    ltext = logic_amb.read_text()
    if "'SM_BOOT_TRACE'" in ltext:
        print('==> logic AMBuilder SM_BOOT_TRACE already set')
    elif "'NO_MALLOC_OVERRIDE'" in ltext:
        ltext = ltext.replace("'NO_MALLOC_OVERRIDE',", "'NO_MALLOC_OVERRIDE',\n    'SM_BOOT_TRACE',", 1)
        logic_amb.write_text(ltext)
        print('==> logic AMBuilder: added SM_BOOT_TRACE to defines')
    else:
        la = "    'SM_LOGIC'\n  ]"
        if la not in ltext:
            print('==> logic AMBuilder: defer SM_BOOT_TRACE until css34 defines applied')
        else:
            ltext = ltext.replace(la, "    'SM_LOGIC',\n    'SM_BOOT_TRACE',\n  ]", 1)
            logic_amb.write_text(ltext)
            print('==> logic AMBuilder: added SM_BOOT_TRACE to base defines')

logic_amb = sm / 'core' / 'logic' / 'AMBuilder'
if logic_amb.exists():
    ltext = logic_amb.read_text()
    inc = "    os.path.join(builder.sourcePath, 'core'),\n"
    if inc in ltext:
        print('==> logic AMBuilder core include already set')
    else:
        anchor = "    builder.sourcePath,\n"
        if anchor not in ltext:
            raise SystemExit('logic AMBuilder sourcePath anchor missing')
        ltext = ltext.replace(anchor, anchor + inc, 1)
        logic_amb.write_text(ltext)
        print('==> logic AMBuilder: added core/ include for sm-boot-trace.h')
PY

echo "==> SM boot trace applied ($marker)"
