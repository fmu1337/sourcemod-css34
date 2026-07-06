#!/usr/bin/env bash
# Generate hl2sdk-ep1c patch diff: pristine rom4s @ pins.env vs apply-hl2sdk-ep1c.sh
set -euo pipefail

BUILDER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$BUILDER_DIR/pins.env"

OUT_DIR="${1:-/tmp/sdk-patch-diff}"
PRISTINE="$OUT_DIR/pristine"
PATCHED="$OUT_DIR/patched"
PATCH_FILE="$OUT_DIR/hl2sdk-ep1c.patch"

mkdir -p "$OUT_DIR"
rm -rf "$PRISTINE" "$PATCHED"

echo "==> Cloning rom4s/hl2sdk-ep1c @ ${HL2SDK_EP1C_COMMIT:0:12}"
git clone --quiet https://github.com/rom4s/hl2sdk-ep1c "$PRISTINE"
git -C "$PRISTINE" fetch --depth 1 origin "$HL2SDK_EP1C_COMMIT"
git -C "$PRISTINE" checkout --detach "$HL2SDK_EP1C_COMMIT" >/dev/null

cp -a "$PRISTINE" "$PATCHED"
LINUX_SDK_STUB_CC="${LINUX_SDK_STUB_CC:-gcc}" BUILD_PLATFORM=linux \
  bash "$BUILDER_DIR/patches/apply-hl2sdk-ep1c.sh" "$PATCHED"

diff -ruN "$PRISTINE" "$PATCHED" >"$PATCH_FILE" || true

python3 - <<PY
from pathlib import Path
pristine, patched = Path("$PRISTINE"), Path("$PATCHED")
mods, adds, links = [], [], 0
for p in patched.rglob('*'):
    rel = p.relative_to(patched)
    if p.is_symlink():
        links += 1
        continue
    if not p.is_file():
        continue
    op = pristine / rel
    if not op.exists():
        adds.append(str(rel))
    elif p.read_bytes() != op.read_bytes():
        mods.append(str(rel))
print(f"Symlinks created: {links}")
print(f"Files added: {len(adds)}")
for a in adds:
    print(f"  + {a}")
print(f"Files modified: {len(mods)}")
for m in mods:
    print(f"  ~ {m}")
print(f"Unified diff: $PATCH_FILE ({Path('$PATCH_FILE').stat().st_size} bytes)")
PY
