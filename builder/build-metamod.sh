#!/usr/bin/env bash
# Build Metamod:Source for CS:S v34.
# SM 1.11 path: mmsource-1.10 → metamod.1.ep1 (legacy Core / SH v4)
# SM 1.12 path: mmsource-1.12 → metamod.2.ep1 (modern Core / SH v5)
set -euo pipefail

WDIR="${WDIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
DEPS_DIR="${DEPS_DIR:-$WDIR/deps}"
BUILDER_DIR="${BUILDER_DIR:-$WDIR/builder}"
BUILD_PLATFORM="${BUILD_PLATFORM:-linux}"
SOURCEMOD_MAJOR="${SOURCEMOD_MAJOR:-11}"

if [ -z "${MMS_DIR:-}" ]; then
  if [ "$SOURCEMOD_MAJOR" -ge 12 ] && [ -d "$DEPS_DIR/mmsource-1.12" ]; then
    MMS_DIR="$DEPS_DIR/mmsource-1.12"
  else
    MMS_DIR="$DEPS_DIR/mmsource-1.10"
  fi
fi

export PATH="${HOME}/.local/bin:${PATH}"

if [[ ! -f "$MMS_DIR/core/ISmmAPI.h" ]]; then
  echo "Missing $MMS_DIR — run checkout-deps.sh first" >&2
  exit 1
fi

product="$(tr -d '\r\n' < "$MMS_DIR/product.version" 2>/dev/null || echo "")"
mm_major="${product%%.*}"
if [[ "$product" == 1.12* ]] || [[ "$(basename "$MMS_DIR")" == "mmsource-1.12" ]]; then
  MM_EXT="2.ep1"
  MM_MODE="1.12"
else
  MM_EXT="1.ep1"
  MM_MODE="1.10"
fi

if [[ "$MM_MODE" == "1.10" ]]; then
  # Headers must already be css34-patched (checkout-deps applies apply-mmsource-css34.sh).
  if ! grep -q 'SH_IFACE_VERSION 4' "$MMS_DIR/core/sourcehook/sourcehook.h" 2>/dev/null; then
    echo "==> Applying css34 Metamod header patches before build"
    BUILD_PLATFORM="$BUILD_PLATFORM" MMS_DIR="$MMS_DIR" \
      bash "$BUILDER_DIR/patches/apply-mmsource-css34.sh" "$MMS_DIR"
  fi
else
  if [ ! -f "$MMS_DIR/hl2sdk-manifests/SdkHelpers.ambuild" ]; then
    echo "==> Initializing Metamod 1.12 submodules"
    git -C "$MMS_DIR" submodule update --init --recursive
  fi
  bash "$BUILDER_DIR/patches/apply-mmsource-v112.sh" "$MMS_DIR"
fi

if [[ "$BUILD_PLATFORM" != "windows" && "${USE_CLANG9:-1}" == "1" && -f "$DEPS_DIR/clang9.env" ]]; then
  # shellcheck source=/dev/null
  source "$DEPS_DIR/clang9.env"
  export CC="${CC:-clang-9}"
  export CXX="${CXX:-clang++-9}"
fi

if [[ "$BUILD_PLATFORM" == "windows" ]]; then
  MM_BIN="$MMS_DIR/build/package/addons/metamod/bin/metamod.${MM_EXT}.dll"
  PY=(python)
  echo "==> Building Metamod:Source (${MM_MODE} episode1 → metamod.${MM_EXT}.dll)"
else
  MM_BIN="$MMS_DIR/build/package/addons/metamod/bin/metamod.${MM_EXT}.so"
  PY=(python3)
  echo "==> Building Metamod:Source (${MM_MODE} episode1 → metamod.${MM_EXT}.so)"
  echo "    CC=${CC:-} CXX=${CXX:-}"
fi
echo "    MMS_DIR=$MMS_DIR"
echo "    BUILD_PLATFORM=$BUILD_PLATFORM"

cd "$MMS_DIR"
rm -rf build obj-*
mkdir -p build
cd build

CONFIGURE_ARGS=(
  --enable-optimize
  --hl2sdk-root="$DEPS_DIR"
  --sdks=episode1
)
if [[ "$MM_MODE" == "1.12" ]]; then
  CONFIGURE_ARGS+=(--targets=x86)
fi

"${PY[@]}" ../configure.py "${CONFIGURE_ARGS[@]}"

ambuild

if [[ ! -f "$MM_BIN" ]]; then
  echo "Build finished but $MM_BIN was not found" >&2
  exit 1
fi

echo "==> Metamod build complete: $MM_BIN"
