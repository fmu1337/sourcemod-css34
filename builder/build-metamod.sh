#!/usr/bin/env bash
# Build Metamod:Source for CS:S v34 (MMS_DIR / MMS_MODE from builder/run/*.sh):
#   MM 1.10 -> metamod.1.ep1 (legacy core / SourceHook v4): the legacy-plugin
#              bridge core inside the MM 1.12 package (T2.9)
#   MM 1.12 -> metamod.2.ep1 (modern core / SourceHook v5)
set -euo pipefail

WDIR="${WDIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
DEPS_DIR="${DEPS_DIR:-$WDIR/deps}"
BUILDER_DIR="${BUILDER_DIR:-$WDIR/builder}"
BUILD_PLATFORM="${BUILD_PLATFORM:-linux}"
: "${MMS_DIR:?MMS_DIR is required}" "${MMS_MODE:?MMS_MODE is required (1.10 or 1.12)}"

export PATH="${HOME}/.local/bin:${PATH}"

if [[ ! -f "$MMS_DIR/core/ISmmAPI.h" ]]; then
  echo "Missing $MMS_DIR — run checkout-deps.sh first" >&2
  exit 1
fi

case "$MMS_MODE" in
  1.10)
    MM_EXT="1.ep1"
    # Headers must already be css34-patched (checkout-deps applies apply-mmsource-css34.sh).
    if ! grep -q 'SH_IFACE_VERSION 4' "$MMS_DIR/core-css34legacy/sourcehook/sourcehook.h" 2>/dev/null; then
      echo "==> Applying css34 Metamod header patches before build"
      BUILD_PLATFORM="$BUILD_PLATFORM" MMS_DIR="$MMS_DIR" \
        bash "$BUILDER_DIR/patches/apply-mmsource-css34.sh" "$MMS_DIR"
    fi
    ;;
  1.12)
    MM_EXT="2.ep1"
    if [ ! -f "$MMS_DIR/hl2sdk-manifests/SdkHelpers.ambuild" ]; then
      echo "==> Initializing Metamod ${MMS_MODE} submodules"
      git -C "$MMS_DIR" submodule update --init --recursive
    fi
    bash "$BUILDER_DIR/patches/apply-mmsource-v112.sh" "$MMS_DIR"
    ;;
  *)
    echo "Unsupported MMS_MODE=$MMS_MODE (MM 2.0 builds live on the archive/khook branch)" >&2
    exit 1
    ;;
esac

if [[ "$BUILD_PLATFORM" == "windows" ]]; then
  MM_BIN="$MMS_DIR/build/package/addons/metamod/bin/metamod.${MM_EXT}.dll"
  PY=(python)
  echo "==> Building Metamod:Source (${MMS_MODE} episode1 → metamod.${MM_EXT}.dll)"
else
  MM_BIN="$MMS_DIR/build/package/addons/metamod/bin/metamod.${MM_EXT}.so"
  PY=(python3)
  echo "==> Building Metamod:Source (${MMS_MODE} episode1 → metamod.${MM_EXT}.so)"
  echo "    CC=${CC:-} CXX=${CXX:-}"
fi
echo "    MMS_DIR=$MMS_DIR"
echo "    MMS_GIT_REV=${MMS_GIT_REV:-<unset>}"
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
if [[ "$MMS_MODE" == "1.12" ]]; then
  CONFIGURE_ARGS+=(--targets=x86)
fi

"${PY[@]}" ../configure.py "${CONFIGURE_ARGS[@]}"

ambuild

if [[ ! -f "$MM_BIN" ]]; then
  echo "Build finished but $MM_BIN was not found" >&2
  exit 1
fi

echo "==> Metamod build complete: $MM_BIN"
