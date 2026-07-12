#!/usr/bin/env bash
set -euo pipefail

artifact="${1:?built tarball required}"
original_url="${ORIGINAL_RELEASE_URL:-https://github.com/rom4s/sourcemod-css34/releases/download/v1.11.0.6572/sourcemod-1.11.0-git6572-css34-linux.tar.gz}"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

orig_dir="$tmpdir/original"
built_dir="$tmpdir/built"
orig_tar="$tmpdir/original.tar.gz"

echo "==> Comparing against original rom4s release"
curl -fsSL -o "$orig_tar" "$original_url"
mkdir -p "$orig_dir" "$built_dir"
tar -xzf "$orig_tar" -C "$orig_dir"
tar -xzf "$artifact" -C "$built_dir"

ORIG_DIR="$orig_dir" BUILT_DIR="$built_dir" EXP7_VARIANT="${EXP7_VARIANT:-}" python3 - <<'PY'
import hashlib
import os
import re
import subprocess
from pathlib import Path

orig = Path(os.environ['ORIG_DIR'])
built = Path(os.environ['BUILT_DIR'])

SIMPLE_EXTENSIONS = [
    'addons/sourcemod/extensions/bintools.ext.so',
    'addons/sourcemod/extensions/geoip.ext.so',
    'addons/sourcemod/extensions/regex.ext.so',
    'addons/sourcemod/extensions/topmenus.ext.so',
    'addons/sourcemod/extensions/updater.ext.so',
    'addons/sourcemod/extensions/dbi.sqlite.ext.so',
    'addons/sourcemod/extensions/dbi.mysql.ext.so',
]

SDK_MODULES = [
    'addons/sourcemod/bin/sourcemod.1.ep1.so',
    'addons/sourcemod/bin/sourcemod.2.ep1.so',
    'addons/sourcemod/extensions/sdkhooks.ext.1.ep1.so',
    'addons/sourcemod/extensions/sdkhooks.ext.2.ep1.so',
    'addons/sourcemod/extensions/sdktools.ext.1.ep1.so',
    'addons/sourcemod/extensions/sdktools.ext.2.ep1.so',
    'addons/sourcemod/extensions/game.cstrike.ext.1.ep1.so',
    'addons/sourcemod/extensions/game.cstrike.ext.2.ep1.so',
]

def read_comment_strings(path):
    try:
        out = subprocess.check_output(['readelf', '-p', '.comment', str(path)], text=True, stderr=subprocess.DEVNULL)
    except (subprocess.CalledProcessError, FileNotFoundError):
        return []
    strings = []
    for line in out.splitlines():
        m = re.search(r'\]\s+(.*)$', line)
        if m:
            strings.append(m.group(1).strip())
    return strings

def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open('rb') as fp:
        for chunk in iter(lambda: fp.read(1 << 20), b''):
            h.update(chunk)
    return h.hexdigest()

def rel_files(root: Path):
    return {str(p.relative_to(root)): p for p in root.rglob('*') if p.is_file()}

orig_files = rel_files(orig)
built_files = rel_files(built)
all_paths = sorted(set(orig_files) | set(built_files))

so_same = so_diff = so_size_same = 0
text_same = text_diff = 0
missing = 0

print('\n=== Native modules (.so) ===')
for rel in all_paths:
    if not rel.endswith('.so'):
        continue
    o = orig_files.get(rel)
    b = built_files.get(rel)
    if o is None or b is None:
        missing += 1
        print(f'MISSING  {rel}')
        continue
    oh, bh = sha256(o), sha256(b)
    osz, bsz = o.stat().st_size, b.stat().st_size
    if oh == bh:
        so_same += 1
        print(f'MATCH    {rel} ({osz} bytes)')
    else:
        so_diff += 1
        delta = bsz - osz
        sign = '+' if delta >= 0 else ''
        tag = 'SIZE' if osz == bsz else 'DIFF'
        if osz == bsz:
            so_size_same += 1
        print(f'{tag:5}    {rel}: orig={osz} built={bsz} ({sign}{delta})')

print('\n=== Summary ===')
print(f'.so files: {so_same} byte-match, {so_size_same} size-match only, {so_diff - so_size_same} size-differ, {missing} missing')

for rel in all_paths:
    if rel.endswith('.so'):
        continue
    o = orig_files.get(rel)
    b = built_files.get(rel)
    if o is None or b is None:
        continue
    if sha256(o) == sha256(b):
        text_same += 1
    else:
        text_diff += 1

print(f'other files: {text_same} match, {text_diff} differ')

print('\n=== .comment section (simple extensions) ===')
gcc_target = 'GCC: (Ubuntu 9.3.0-11ubuntu0~14.04) 9.3.0'
clang_target = 'clang version 9.0.1'
comment_match = comment_diff = 0
for rel in SIMPLE_EXTENSIONS:
    o = orig / rel
    b = built / rel
    if not o.is_file() or not b.is_file():
        print(f'MISSING  {rel}')
        continue
    os_ = read_comment_strings(o)
    bs = read_comment_strings(b)
    og = next((s for s in os_ if s.startswith('GCC:')), None)
    bg = next((s for s in bs if s.startswith('GCC:')), None)
    oc = next((s for s in os_ if s.startswith('clang')), None)
    bc = next((s for s in bs if s.startswith('clang')), None)
    gcc_ok = bg == gcc_target
    clang_ok = bc == clang_target
    extra_orig = sorted(set(os_) - set(bs))
    extra_built = sorted(set(bs) - set(os_))
    if os_ == bs:
        comment_match += 1
        tag = 'MATCH'
    else:
        comment_diff += 1
        tag = 'DIFF'
    print(f'{tag:5}    {rel}')
    print(f'         gcc:  orig={og!r}')
    print(f'               built={bg!r} {"OK" if gcc_ok else "MISMATCH"}')
    print(f'         clang: orig={oc!r} built={bc!r} {"OK" if clang_ok else "MISMATCH"}')
    if extra_orig:
        print(f'         only in orig: {extra_orig[:3]}{"..." if len(extra_orig) > 3 else ""}')
    if extra_built:
        print(f'         only in built: {extra_built[:3]}{"..." if len(extra_built) > 3 else ""}')

print(f'\n.comment: {comment_match} exact-match, {comment_diff} differ (of {len(SIMPLE_EXTENSIONS)} simple extensions)')

variant = os.environ.get('EXP7_VARIANT', '')
if variant:
    print(f'\n=== SDK module sizes (EXP7_VARIANT={variant}) ===')
    for rel in SDK_MODULES:
        o = orig / rel
        b = built / rel
        if not o.is_file() or not b.is_file():
            continue
        osz, bsz = o.stat().st_size, b.stat().st_size
        delta = bsz - osz
        sign = '+' if delta >= 0 else ''
        print(f'  {rel}: orig={osz} built={bsz} ({sign}{delta})')
PY
