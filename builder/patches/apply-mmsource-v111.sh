#!/usr/bin/env bash
# Light CS:S v34 patches for Metamod:Source 1.11-dev (metamod.2.ep1, no hl2sdk-manifests).
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PY=(bash "$script_dir/../py.sh")

mms_dir="${1:?mmsource directory required}"

if [ ! -f "$mms_dir/core/ISmmAPI.h" ]; then
  echo "Missing Metamod core: $mms_dir/core/ISmmAPI.h" >&2
  exit 1
fi

echo "==> Applying Metamod 1.11 css34 light patches"

# Detached MMS_COMMIT checkout may store a raw SHA in .git/HEAD.
MMS_DIR="$mms_dir" "${PY[@]}" - <<'PYVER'
from pathlib import Path
import os
import re

path = Path(os.environ['MMS_DIR']) / 'support/buildbot/Versioning'
if not path.exists():
    print('==> WARN: support/buildbot/Versioning missing')
    raise SystemExit(0)
text = path.read_text()
if 'css34: detached HEAD' in text:
    print('==> MM 1.11 Versioning already handles detached HEAD')
    raise SystemExit(0)
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
    print('==> WARN: MM 1.11 Versioning detached-HEAD pattern not found (continuing)')
else:
    path.write_text(text.replace(old, new, 1))
    print('==> Patched MM 1.11 Versioning for detached MMS_COMMIT checkouts')
PYVER

echo "==> Metamod 1.11 css34 patches applied"
