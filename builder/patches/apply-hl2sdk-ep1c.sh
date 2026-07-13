#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Always invoke via bash so a missing +x bit cannot break CI checkouts.
PY=(bash "$script_dir/../py.sh")

sdk_dir="${1:?hl2sdk directory required}"

apply_sed() {
  local file="$1"
  local expr="$2"
  sed -i "$expr" "$sdk_dir/$file"
}

if [ ! -e "$sdk_dir/public/SoundEmitterSystem" ] && [ -d "$sdk_dir/public/soundemittersystem" ]; then
  ln -s soundemittersystem "$sdk_dir/public/SoundEmitterSystem"
fi

create_include_symlinks() {
  "${PY[@]}" - <<'PY'
import os, re
sdk = os.environ['SDK_DIR']
public = os.path.join(sdk, 'public')

def find_case_insensitive(root, rel):
    parts = rel.split('/')
    cur = root
    for part in parts:
        if not os.path.isdir(cur):
            return None
        match = None
        for entry in os.listdir(cur):
            if entry.lower() == part.lower():
                match = entry
                break
        if match is None:
            return None
        cur = os.path.join(cur, match)
    return cur

for dirpath, _, files in os.walk(sdk):
    for fname in files:
        if not fname.endswith(('.h', '.cpp', '.c', '.inc')):
            continue
        path = os.path.join(dirpath, fname)
        try:
            text = open(path, errors='ignore').read()
        except OSError:
            continue
        for match in re.finditer(r'#include\s*[<"]([^">]+)[">]', text):
            inc = match.group(1)
            if inc.startswith('../'):
                continue
            if not any(c.isupper() for c in inc):
                continue
            direct = os.path.join(public, inc)
            if os.path.exists(direct):
                continue
            target = find_case_insensitive(public, inc)
            if target is None:
                target = find_case_insensitive(sdk, inc)
            if target is None:
                continue
            rel_target = os.path.relpath(target, os.path.dirname(direct))
            os.makedirs(os.path.dirname(direct), exist_ok=True)
            if os.path.lexists(direct):
                continue
            os.symlink(rel_target, direct)
            print(f'linked {inc} -> {target}')
PY
}

SDK_DIR="$sdk_dir" create_include_symlinks

# Modern Linux/clang compatibility fixes for rom4s/hl2sdk-ep1c.
apply_sed public/tier0/wchartypes.h \
  's/#ifndef _WCHAR_T_DEFINED/#if !defined(_WCHAR_T_DEFINED) \&\& !defined(GNUC)/'

apply_sed public/bitmap/imageformat.h \
  's/#pragma warning(disable : 4514)/#ifdef _MSC_VER\n#pragma warning(disable : 4514)\n#endif/'

SDK_DIR="$sdk_dir" "${PY[@]}" - <<'PY'
from pathlib import Path
sdk = Path(__import__('os').environ['SDK_DIR'])

for rel in ('public/minmax.h', 'public/tier0/basetypes.h'):
    path = sdk / rel
    text = path.read_text(encoding='latin-1')
    if '#if !defined(__cplusplus)\n#ifndef min' in text:
        continue
    if '#if !defined(__cplusplus) || defined(_MSC_VER)\n#ifndef min' in text:
        continue
    text = text.replace(
        '#ifndef min\n#define min(a,b)  (((a) < (b)) ? (a) : (b))\n#endif\n#ifndef max\n#define max(a,b)  (((a) > (b)) ? (a) : (b))\n#endif',
        '#if !defined(__cplusplus) || defined(_MSC_VER)\n#ifndef min\n#define min(a,b)  (((a) < (b)) ? (a) : (b))\n#endif\n#ifndef max\n#define max(a,b)  (((a) > (b)) ? (a) : (b))\n#endif\n#endif',
    )
    text = text.replace(
        '#ifndef min\n\t#define min(a,b)  (((a) < (b)) ? (a) : (b))\n#endif\n\n#ifndef max\n\t#define max(a,b)  (((a) > (b)) ? (a) : (b))\n#endif',
        '#if !defined(__cplusplus) || defined(_MSC_VER)\n#ifndef min\n\t#define min(a,b)  (((a) < (b)) ? (a) : (b))\n#endif\n\n#ifndef max\n\t#define max(a,b)  (((a) > (b)) ? (a) : (b))\n#endif\n#endif',
    )
    path.write_text(text, encoding='latin-1')

path = sdk / 'public/mathlib/math_base.h'
text = path.read_text(encoding='latin-1')
marker = '#include "minmax.h"\n'
insert = marker + '\n#if defined(__cplusplus) && !defined(_MSC_VER)\ntemplate<typename T> inline T min(T a, T b) { return a < b ? a : b; }\ntemplate<typename T> inline T max(T a, T b) { return a > b ? a : b; }\n#endif\n'
if 'template<typename T> inline T min(T a, T b)' not in text and marker in text:
    text = text.replace(marker, insert, 1)
    path.write_text(text, encoding='latin-1')
elif 'template<typename T> inline T min(T a, T b)' in text:
    text = text.replace(
        '#if defined(__cplusplus)\ntemplate<typename T> inline T min(T a, T b)',
        '#if defined(__cplusplus) && !defined(_MSC_VER)\ntemplate<typename T> inline T min(T a, T b)',
    )
    path.write_text(text, encoding='latin-1')
PY

apply_sed public/networkvar.h \
  's/#pragma warning( disable : 4284 )/#ifdef _MSC_VER\n#pragma warning( disable : 4284 )\n#endif/'

apply_sed public/tier0/platform.h \
  's/#include <new.h>/#if defined(_WIN32)\n#include <new.h>\n#else\n#include <new>\n#endif/'

apply_sed public/tier0/platform.h \
  's/#if !defined( _WIN64 )/#if defined(_MSC_VER) \&\& !defined( _WIN64 )/'

apply_sed public/tier0/platform.h \
  's/#define LITTLE_ENDIAN 1/#define VALVE_LITTLE_ENDIAN 1/'

apply_sed public/tier0/platform.h \
  's/#if defined(LITTLE_ENDIAN)/#if defined(VALVE_LITTLE_ENDIAN)/'

apply_sed public/tier0/platform.h \
  's/PLATFORM_INTERFACE const CPUInformation\& GetCPUInformation();/PLATFORM_INTERFACE const CPUInformation* GetCPUInformation();/'

apply_sed public/tier0/fasttimer.h \
  's/const CPUInformation\& pi = GetCPUInformation();/const CPUInformation\& pi = *GetCPUInformation();/'

apply_sed public/icvar.h \
  's|"appframework/IAppSystem.h"|"appframework/iappsystem.h"|'

if [ ! -f "$sdk_dir/common/userid.h" ]; then
  curl -sL "https://raw.githubusercontent.com/alliedmodders/hl2sdk/css/common/userid.h" \
    -o "$sdk_dir/common/userid.h"
fi
if [ ! -f "$sdk_dir/common/steamcommon.h" ]; then
  curl -sL "https://raw.githubusercontent.com/alliedmodders/hl2sdk/css/common/steamcommon.h" \
    -o "$sdk_dir/common/steamcommon.h"
fi
if [ ! -e "$sdk_dir/public/userid.h" ]; then
  ln -sf ../common/userid.h "$sdk_dir/public/userid.h"
fi
if [ ! -e "$sdk_dir/public/steamcommon.h" ]; then
  ln -sf ../common/steamcommon.h "$sdk_dir/public/steamcommon.h"
fi

SDK_DIR="$sdk_dir" "${PY[@]}" - <<'PY'
from pathlib import Path
path = Path(__import__('os').environ['SDK_DIR']) / 'public/tier0/memalloc.h'
text = path.read_text(encoding='latin-1')
if '#endif !STEAM && NO_MALLOC_OVERRIDE' in text:
    text = text.replace('#endif !STEAM && NO_MALLOC_OVERRIDE', '#endif /* !STEAM && NO_MALLOC_OVERRIDE */')
    path.write_text(text, encoding='latin-1')
PY

apply_sed public/mathlib/math_base.h \
  's/template<> FORCEINLINE_MATH/template<> inline/g'

apply_sed public/mathlib/math_base.h \
  's/template<> FORCEINLINE QAngle/template<> inline QAngle/g'

apply_sed public/tier1/utlmemory.h \
  's/#pragma warning (disable:4100)/#ifdef _MSC_VER\n#pragma warning (disable:4100)/'

apply_sed public/tier1/utlmemory.h \
  's/#pragma warning (disable:4514)/#pragma warning (disable:4514)\n#endif/'

apply_sed public/tier1/utlmemory.h \
  's/\tValidateGrowSize();/\tthis->ValidateGrowSize();/g'

apply_sed public/tier1/utlmemory.h \
  's/if ( IsExternallyAllocated() )/if ( this->IsExternallyAllocated() )/g'

apply_sed public/tier1/utlmemory.h \
  's/if ( !IsExternallyAllocated() )/if ( !this->IsExternallyAllocated() )/g'

apply_sed public/edict.h \
  's|"engine/ICollideable.h"|"engine/icollideable.h"|'

SDK_DIR="$sdk_dir" "${PY[@]}" - <<'PY'
from pathlib import Path
path = Path(__import__('os').environ['SDK_DIR']) / 'public/tier0/threadtools.h'
text = path.read_text(encoding='latin-1')
# Undo accidental double-patching from re-running this script.
text = text.replace('this->this->', 'this->')
replacements = [
    ('return Get();', 'return this->Get();'),
    ('T i = Get();', 'T i = this->Get();'),
    ('Set( ++i )', 'this->Set( ++i )'),
    ('Set( --i )', 'this->Set( --i )'),
    ('Set( i + 1 )', 'this->Set( i + 1 )'),
    ('Set( i - 1 )', 'this->Set( i - 1 )'),
]
for old, new in replacements:
    if new not in text:
        text = text.replace(old, new)
path.write_text(text, encoding='latin-1')
PY

SDK_DIR="$sdk_dir" "${PY[@]}" - <<'PY'
from pathlib import Path
path = Path(__import__('os').environ['SDK_DIR']) / 'public/dt_common.h'
text = path.read_text(encoding='latin-1')
if 'SPROP_VARINT' not in text:
    needle = '#define SPROP_COLLAPSIBLE\t\t(1<<12)\t// Set automatically if it\'s a datatable with an offset of 0 that doesn\'t change the pointer'
    insert = needle + '\n#ifndef SPROP_VARINT\n#define SPROP_VARINT 0\n#endif'
    if needle not in text:
        raise SystemExit('dt_common.h patch point not found')
    text = text.replace(needle, insert, 1)
    path.write_text(text, encoding='latin-1')
PY

SDK_DIR="$sdk_dir" "${PY[@]}" - <<'PY'
from pathlib import Path
path = Path(__import__('os').environ['SDK_DIR']) / 'public/tier0/platform.h'
text = path.read_text(encoding='latin-1')
if '#ifndef MIN' in text:
    import re
    text = re.sub(r'\n#ifndef MIN\n#define MIN\(a,b\).*?#endif\n#ifndef MAX\n#define MAX\(a,b\).*?#endif', '', text, count=1, flags=re.S)
    path.write_text(text, encoding='latin-1')
PY

apply_sed public/tier1/keyvalues.h \
  's|"Color.h"|"color.h"|'

apply_sed public/engine/iserverplugin.h \
  's|"KeyValues.h"|"tier1/keyvalues.h"|'

apply_sed public/toolframework/itoolentity.h \
  's|"Color.h"|"color.h"|'

SDK_DIR="$sdk_dir" "${PY[@]}" - <<'PY'
from pathlib import Path
import re

path = Path(__import__('os').environ['SDK_DIR']) / 'public/networkvar.h'
text = path.read_text(encoding='latin-1')

# Clang requires explicit this-> for dependent base calls in templates.
text = re.sub(
    r'^(\s+)NetworkStateChanged\(\);\s*$',
    r'\1this->NetworkStateChanged();',
    text,
    flags=re.M,
)
path.write_text(text, encoding='latin-1')
PY

sound_emitter="$sdk_dir/public/soundemittersystem/isoundemittersystembase.h"
if ! grep -q 'interval.h' "$sound_emitter"; then
  sed -i '/#include "appframework\/IAppSystem.h"/a #include "interval.h"' "$sound_emitter"
fi

sed -i 's/bool CSoundParametersInternal::operator ==/bool operator ==/' "$sound_emitter"

# glibc/gcc already provide offsetof; ep1c redefines it on Linux.
datamap_h="$sdk_dir/public/datamap.h"
if [ -f "$datamap_h" ] && grep -q '#define offsetof(s,m)' "$datamap_h"; then
  sed -i 's/#if !defined(offsetof) || defined(_LINUX)/#if 0 \/* CSS34: use system offsetof *\//' "$datamap_h"
fi

utlvector_h="$sdk_dir/public/tier1/utlvector.h"
if [ -f "$utlvector_h" ] && grep -q 'swap( m_Size, vec.m_Size );' "$utlvector_h"; then
  sed -i 's/\tswap( m_Size/\tstd::swap( m_Size/g' "$utlvector_h"
  sed -i 's/\tswap( m_pElements/\tstd::swap( m_pElements/g' "$utlvector_h"
fi

utlmemory_h="$sdk_dir/public/tier1/utlmemory.h"
if [ -f "$utlmemory_h" ] && grep -q 'swap( m_nGrowSize, mem.m_nGrowSize );' "$utlmemory_h"; then
  sed -i 's/\tswap( m_nGrowSize/\tstd::swap( m_nGrowSize/g' "$utlmemory_h"
  sed -i 's/\tswap( m_pMemory/\tstd::swap( m_pMemory/g' "$utlmemory_h"
  sed -i 's/\tswap( m_nAllocationCount/\tstd::swap( m_nAllocationCount/g' "$utlmemory_h"
fi

math_base_h="$sdk_dir/public/mathlib/math_base.h"
if [ -f "$math_base_h" ] && grep -q 'FORCEINLINE_TEMPLATE void swap( T& x, T& y )' "$math_base_h"; then
  sed -i '/\/\/ Swap two of anything\./,/^}$/c\
// Swap template removed for CSS34 gcc compatibility (conflicts with std::swap).' "$math_base_h"
fi

# CS:S v34 exposes ServerGameDLL006 (same as alliedmodders episode1). ep1c still ships 005.
eiface="$sdk_dir/public/eiface.h"
if [ -f "$eiface" ] && grep -q 'INTERFACEVERSION_SERVERGAMEDLL.*"ServerGameDLL005"' "$eiface"; then
  if ! grep -q 'INTERFACEVERSION_SERVERGAMEDLL_VERSION_5' "$eiface"; then
    sed -i 's|#define INTERFACEVERSION_SERVERGAMEDLL_VERSION_4\t"ServerGameDLL004"|#define INTERFACEVERSION_SERVERGAMEDLL_VERSION_4\t"ServerGameDLL004"\n#define INTERFACEVERSION_SERVERGAMEDLL_VERSION_5\t"ServerGameDLL005"|' "$eiface"
  fi
  sed -i 's|#define INTERFACEVERSION_SERVERGAMEDLL\t\t\t\t"ServerGameDLL005"|#define INTERFACEVERSION_SERVERGAMEDLL\t\t\t\t"ServerGameDLL006"|' "$eiface"
  echo "==> Bumped INTERFACEVERSION_SERVERGAMEDLL to ServerGameDLL006"
fi

# CS:S v34 engine actually has QueryCvar APIs (StartQueryCvarValue /
# OnQueryCvarValueFinished) matching alliedmodders episode1. Stock hl2sdk-ep1
# omits them, so SE_EPISODEONE SourceHook decls fail to compile and SE_CSS
# builds skip the hooks — both leave sourcemod.1.ep1.so ABI-mismatched vs
# rom4s and crash metamod when engine extensions register hooks.
SDK_DIR="$sdk_dir" "${PY[@]}" - <<'PY'
from pathlib import Path
import os

sdk = Path(os.environ['SDK_DIR'])
plugin = sdk / 'public/engine/iserverplugin.h'
eiface = sdk / 'public/eiface.h'

if plugin.exists():
    text = plugin.read_text(encoding='latin-1')
    if 'QueryCvarCookie_t' not in text:
        old = '''} PLUGIN_RESULT;


#define INTERFACEVERSION_ISERVERPLUGINCALLBACKS\t"ISERVERPLUGINCALLBACKS001"
'''
        new = '''} PLUGIN_RESULT;

typedef enum
{
\teQueryCvarValueStatus_ValueIntact=0,\t// It got the value fine.
\teQueryCvarValueStatus_CvarNotFound=1,
\teQueryCvarValueStatus_NotACvar=2,\t\t// There's a ConCommand, but it's not a ConVar.
\teQueryCvarValueStatus_CvarProtected=3\t// The cvar was marked with FCVAR_SERVER_CAN_NOT_QUERY, so the server is not allowed to have its value.
} EQueryCvarValueStatus;

typedef int QueryCvarCookie_t;

#define InvalidQueryCvarCookie -1
#define INTERFACEVERSION_ISERVERPLUGINCALLBACKS_VERSION_1\t"ISERVERPLUGINCALLBACKS001"
#define INTERFACEVERSION_ISERVERPLUGINCALLBACKS\t\t\t\t"ISERVERPLUGINCALLBACKS002"
'''
        if old not in text:
            raise SystemExit('Failed to locate ISERVERPLUGINCALLBACKS version marker in iserverplugin.h')
        text = text.replace(old, new, 1)

        old = '''\t// A user has had their network id setup and validated 
\tvirtual PLUGIN_RESULT\tNetworkIDValidated( const char *pszUserName, const char *pszNetworkID ) = 0;
};
'''
        new = '''\t// A user has had their network id setup and validated 
\tvirtual PLUGIN_RESULT\tNetworkIDValidated( const char *pszUserName, const char *pszNetworkID ) = 0;
\t
\t// This is called when a query from IServerPluginHelpers::StartQueryCvarValue is finished.
\t// iCookie is the value returned by IServerPluginHelpers::StartQueryCvarValue.
\t// Added with version 2 of the interface.
\tvirtual void OnQueryCvarValueFinished( QueryCvarCookie_t iCookie, edict_t *pPlayerEntity, EQueryCvarValueStatus eStatus, const char *pCvarName, const char *pCvarValue )
\t{
\t}
};
'''
        if old not in text:
            raise SystemExit('Failed to locate NetworkIDValidated tail in iserverplugin.h')
        text = text.replace(old, new, 1)

        old = '''\tvirtual void CreateMessage( edict_t *pEntity, DIALOG_TYPE type, KeyValues *data, IServerPluginCallbacks *plugin ) = 0;
\tvirtual void ClientCommand( edict_t *pEntity, const char *cmd ) = 0;
};
'''
        new = '''\tvirtual void CreateMessage( edict_t *pEntity, DIALOG_TYPE type, KeyValues *data, IServerPluginCallbacks *plugin ) = 0;
\tvirtual void ClientCommand( edict_t *pEntity, const char *cmd ) = 0;

\t// Call this to find out the value of a cvar on the client.
\t//
\t// It is an asynchronous query, and it will call IServerPluginCallbacks::OnQueryCvarValueFinished when
\t// the value comes in from the client.
\t//
\t// Store the return value if you want to match this specific query to the OnQueryCvarValueFinished call.
\t// Returns InvalidQueryCvarCookie if the entity is invalid.
\tvirtual QueryCvarCookie_t StartQueryCvarValue( edict_t *pEntity, const char *pName ) = 0;
};
'''
        if old not in text:
            raise SystemExit('Failed to locate IServerPluginHelpers tail in iserverplugin.h')
        text = text.replace(old, new, 1)
        plugin.write_text(text, encoding='latin-1')
        print('==> Added QueryCvar APIs to iserverplugin.h (ISERVERPLUGINCALLBACKS002)')

if eiface.exists():
    text = eiface.read_text(encoding='latin-1')
    changed = False
    if 'virtual QueryCvarCookie_t StartQueryCvarValue(' not in text:
        old = '''\tvirtual IChangeInfoAccessor *GetChangeAccessor( const edict_t *pEdict ) = 0;\t
};
'''
        # tolerate both tab-space variants after GetChangeAccessor
        if old not in text:
            old = '''\tvirtual IChangeInfoAccessor *GetChangeAccessor( const edict_t *pEdict ) = 0;
};
'''
        new = '''\tvirtual IChangeInfoAccessor *GetChangeAccessor( const edict_t *pEdict ) = 0;
\t
\t// Call this to find out the value of a cvar on the client.
\t//
\t// It is an asynchronous query, and it will call IServerGameDLL::OnQueryCvarValueFinished when 
\t// the value comes in from the client.
\t//
\t// Store the return value if you want to match this specific query to the OnQueryCvarValueFinished call.
\t// Returns InvalidQueryCvarCookie if the entity is invalid.
\tvirtual QueryCvarCookie_t StartQueryCvarValue( edict_t *pPlayerEntity, const char *pName ) = 0;
};
'''
        if old not in text:
            raise SystemExit('Failed to locate IVEngineServer GetChangeAccessor tail in eiface.h')
        text = text.replace(old, new, 1)
        changed = True

    # Note: StartQueryCvarValue comments mention OnQueryCvarValueFinished — check the method itself.
    if 'virtual void OnQueryCvarValueFinished(' not in text:
        old = '''\tvirtual void\t\t\tGetSaveCommentEx( char *comment, int maxlength, float flMinutes, float flSeconds  ) = 0;
#ifdef _XBOX
\tvirtual void\t\t\tGetTitleName( const char *pMapName, char* pTitleBuff, int titleBuffSize ) = 0;
#endif
};
'''
        new = '''\tvirtual void\t\t\tGetSaveCommentEx( char *comment, int maxlength, float flMinutes, float flSeconds  ) = 0;
#ifdef _XBOX
\tvirtual void\t\t\tGetTitleName( const char *pMapName, char* pTitleBuff, int titleBuffSize ) = 0;
#endif

\t// * This function is new with version 6 of the interface.
\t//
\t// This is called when a query from IVEngineServer::StartQueryCvarValue is finished.
\t// iCookie is the value returned by IVEngineServer::StartQueryCvarValue.
\t// Added with version 2 of the interface.
\tvirtual void OnQueryCvarValueFinished( QueryCvarCookie_t iCookie, edict_t *pPlayerEntity, EQueryCvarValueStatus eStatus, const char *pCvarName, const char *pCvarValue )
\t{
\t}
};
'''
        if old not in text:
            raise SystemExit('Failed to locate IServerGameDLL GetSaveCommentEx tail in eiface.h')
        text = text.replace(old, new, 1)
        changed = True

    if changed:
        eiface.write_text(text, encoding='latin-1')
        print('==> Added QueryCvar APIs to eiface.h (ServerGameDLL006 / VEngineServer)')
PY

# Link against real game tier0/vstdlib so DT_NEEDED is recorded (--as-needed drops empty stubs).
# Prefer HL2SDK_EPISODE1_LINUX_SDK (alliedmodders episode1 ships the libs); fall back to stubs only as last resort.
if [ "${BUILD_PLATFORM:-linux}" != "windows" ]; then
  mkdir -p "$sdk_dir/linux_sdk"
  episode1_linux_sdk="${HL2SDK_EPISODE1_LINUX_SDK:-}"
  stub_cc="${LINUX_SDK_STUB_CC:-gcc}"
  for lib in tier0_i486.so vstdlib_i486.so; do
    dest="$sdk_dir/linux_sdk/${lib}"
    if [ -n "$episode1_linux_sdk" ] && [ -f "$episode1_linux_sdk/${lib}" ]; then
      cp -f "$episode1_linux_sdk/${lib}" "$dest"
      echo "==> Installed link lib ${lib} from episode1 linux_sdk"
    elif [ ! -f "$dest" ]; then
      echo "WARNING: ${lib} missing; creating empty stub (DT_NEEDED may be dropped)" >&2
      echo "void ${lib%.*}_stub(void){}" | "$stub_cc" -m32 -shared -fPIC -x c - -o "$dest"
    fi
  done
fi
