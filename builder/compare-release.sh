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

ORIG_DIR="$orig_dir" BUILT_DIR="$built_dir" python3 - <<'PY'
import hashlib
import os
from pathlib import Path

orig = Path(os.environ['ORIG_DIR'])
built = Path(os.environ['BUILT_DIR'])

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
PY
