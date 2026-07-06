#!/usr/bin/env bash
set -euo pipefail

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
  python3 - <<'PY'
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

SDK_DIR="$sdk_dir" python3 - <<'PY'
from pathlib import Path
sdk = Path(__import__('os').environ['SDK_DIR'])

for rel in ('public/minmax.h', 'public/tier0/basetypes.h'):
    path = sdk / rel
    text = path.read_text(encoding='latin-1')
    if '#if !defined(__cplusplus)\n#ifndef min' in text:
        continue
    text = text.replace(
        '#ifndef min\n#define min(a,b)  (((a) < (b)) ? (a) : (b))\n#endif\n#ifndef max\n#define max(a,b)  (((a) > (b)) ? (a) : (b))\n#endif',
        '#if !defined(__cplusplus)\n#ifndef min\n#define min(a,b)  (((a) < (b)) ? (a) : (b))\n#endif\n#ifndef max\n#define max(a,b)  (((a) > (b)) ? (a) : (b))\n#endif\n#endif',
    )
    text = text.replace(
        '#ifndef min\n\t#define min(a,b)  (((a) < (b)) ? (a) : (b))\n#endif\n\n#ifndef max\n\t#define max(a,b)  (((a) > (b)) ? (a) : (b))\n#endif',
        '#if !defined(__cplusplus)\n#ifndef min\n\t#define min(a,b)  (((a) < (b)) ? (a) : (b))\n#endif\n\n#ifndef max\n\t#define max(a,b)  (((a) > (b)) ? (a) : (b))\n#endif\n#endif',
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

SDK_DIR="$sdk_dir" python3 - <<'PY'
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

SDK_DIR="$sdk_dir" python3 - <<'PY'
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

SDK_DIR="$sdk_dir" python3 - <<'PY'
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

SDK_DIR="$sdk_dir" python3 - <<'PY'
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

SDK_DIR="$sdk_dir" python3 - <<'PY'
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

# Link-time stubs: tier0/vstdlib come from the game at runtime, not from the SDK repo.
if [ "${BUILD_PLATFORM:-linux}" != "windows" ]; then
  mkdir -p "$sdk_dir/linux_sdk"
  stub_cc="${LINUX_SDK_STUB_CC:-gcc}"
  for lib in tier0_i486 vstdlib_i486; do
    if [ ! -f "$sdk_dir/linux_sdk/${lib}.so" ]; then
      echo "void ${lib}_stub(void){}" | "$stub_cc" -m32 -shared -fPIC -x c - -o "$sdk_dir/linux_sdk/${lib}.so"
    fi
  done
fi
