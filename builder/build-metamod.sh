#!/usr/bin/env bash
# Build Metamod:Source 1.10.x (episode1 / metamod.1.ep1) from patched mmsource headers.
set -euo pipefail

WDIR="${WDIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
DEPS_DIR="${DEPS_DIR:-$WDIR/deps}"
MMS_DIR="${MMS_DIR:-$DEPS_DIR/mmsource-1.10}"
BUILDER_DIR="${BUILDER_DIR:-$WDIR/builder}"

export PATH="${HOME}/.local/bin:${PATH}"

if [[ ! -f "$MMS_DIR/core/ISmmAPI.h" ]]; then
  echo "Missing $MMS_DIR — run checkout-deps.sh first" >&2
  exit 1
fi

# Headers must already be css34-patched (checkout-deps applies apply-mmsource-css34.sh).
if ! grep -q 'SH_IFACE_VERSION 4' "$MMS_DIR/core/sourcehook/sourcehook.h" 2>/dev/null; then
  echo "==> Applying css34 Metamod header patches before build"
  MMS_DIR="$MMS_DIR" bash "$BUILDER_DIR/patches/apply-mmsource-css34.sh" "$MMS_DIR"
fi

if [[ "${USE_CLANG9:-1}" == "1" && -f "$DEPS_DIR/clang9.env" ]]; then
  # shellcheck source=/dev/null
  source "$DEPS_DIR/clang9.env"
  export CC="${CC:-clang-9}"
  export CXX="${CXX:-clang++-9}"
fi

echo "==> Building Metamod:Source (episode1 → metamod.1.ep1.so)"
echo "    MMS_DIR=$MMS_DIR"
echo "    CC=$CC CXX=$CXX"

cd "$MMS_DIR"
rm -rf build obj-*
mkdir -p build
cd build

python3 ../configure.py \
  --enable-optimize \
  --hl2sdk-root="$DEPS_DIR" \
  --sdks=episode1

ambuild

MM_SO="$MMS_DIR/build/package/addons/metamod/bin/metamod.1.ep1.so"
if [[ ! -f "$MM_SO" ]]; then
  echo "Build finished but $MM_SO was not found" >&2
  exit 1
fi

echo "==> Metamod build complete: $MM_SO"
