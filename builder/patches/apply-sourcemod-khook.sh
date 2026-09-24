#!/usr/bin/env bash
# CS:S v34 patches for the SourceMod KHook port (k/sourcehook_alternative)
# built against Metamod:Source 2.0 git1450+ (SourceHook removed, KHook only).
# Called at the start of apply-sourcemod-v112.sh; no-op on SourceHook trees.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PY=(bash "$script_dir/../py.sh")

sourcemod_dir="${1:?sourcemod directory required}"

if ! grep -q "'khook'" "$sourcemod_dir/AMBuildScript" 2>/dev/null; then
  echo "==> SourceMod tree does not build against KHook; skipping KHook patches"
  exit 0
fi

echo "==> Applying SourceMod KHook css34 patches (Metamod 2.0 KHook)"

# KHook 96f3c61 (2026-09-03) renamed the untyped KHook::GetContext() to
# GetContextPtr() and made GetContext<T>() a template. The SM KHook branch
# still calls the old spelling.
SOURCEMOD_DIR="$sourcemod_dir" "${PY[@]}" - <<'PY'
from pathlib import Path
import os, re

root = Path(os.environ['SOURCEMOD_DIR'])
pattern = re.compile(r'KHook::GetContext\(\)')
changed = []
for sub in ('core', 'extensions', 'public'):
    for path in (root / sub).rglob('*'):
        if not path.is_file() or path.suffix not in ('.h', '.hpp', '.cpp'):
            continue
        data = path.read_bytes()
        if b'KHook::GetContext()' not in data:
            continue
        text = data.decode('utf-8', errors='surrogateescape')
        path.write_bytes(pattern.sub('KHook::GetContextPtr()', text).encode('utf-8', errors='surrogateescape'))
        changed.append(str(path.relative_to(root)))
if changed:
    print('==> KHook GetContext() -> GetContextPtr(): ' + ', '.join(sorted(changed)))
else:
    print('==> KHook GetContextPtr() already in use')
PY

# SDKTools output.cpp: the Windows x86 definition of Hook_FireOutput lacks the
# EntityOutputManager:: qualifier, so MSVC builds a free function and the
# member stays unresolved (LNK2019). Linux takes the other #if branch.
SOURCEMOD_DIR="$sourcemod_dir" "${PY[@]}" - <<'PY'
from pathlib import Path
import os

path = Path(os.environ['SOURCEMOD_DIR']) / 'extensions/sdktools/output.cpp'
old = b'KHook::Return<void> Hook_FireOutput(CBaseEntity* this_ptr, int what'
new = b'KHook::Return<void> EntityOutputManager::Hook_FireOutput(CBaseEntity* this_ptr, int what'
data = path.read_bytes() if path.is_file() else b''
if old in data:
    path.write_bytes(data.replace(old, new, 1))
    print('==> SDKTools Hook_FireOutput: added EntityOutputManager:: (Windows x86)')
else:
    print('==> SDKTools Hook_FireOutput already qualified')
PY

# The KHook branch disables cstrike (SourceHook LevelInit hook + CDetour) and
# mysql in AMBuildScript. Port cstrike to KHook::Virtual / KHook::Member and
# re-enable both. The patch is written against LF sources (upstream cstrike
# files are CRLF).
patch_file="$script_dir/sourcemod-khook-css34.patch"
mapfile -t patched_files < <(sed -n 's#^+++ b/##p' "$patch_file")
for rel in "${patched_files[@]}"; do
  [ -f "$sourcemod_dir/$rel" ] && sed -i 's/\r$//' "$sourcemod_dir/$rel"
done
if git -C "$sourcemod_dir" apply --reverse --check "$patch_file" >/dev/null 2>&1; then
  echo "==> cstrike KHook port already applied"
else
  git -C "$sourcemod_dir" apply "$patch_file"
  echo "==> Applied cstrike KHook port + re-enabled cstrike/mysql"
fi

echo "==> SourceMod KHook css34 patches applied"
