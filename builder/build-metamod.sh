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
MMS_MODE="${MMS_MODE:-}"
MMS_DIRNAME="${MMS_DIRNAME:-}"

if [ -z "${MMS_DIR:-}" ]; then
  if [ -n "$MMS_DIRNAME" ] && [ -d "$DEPS_DIR/$MMS_DIRNAME" ]; then
    MMS_DIR="$DEPS_DIR/$MMS_DIRNAME"
  elif [ "$SOURCEMOD_MAJOR" -ge 12 ] && [ -d "$DEPS_DIR/mmsource-1.12" ]; then
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
if [[ -z "$MMS_MODE" ]]; then
  case "$product" in
    2.*|2) MMS_MODE=2.0 ;;
    1.12*) MMS_MODE=1.12 ;;
    1.11*) MMS_MODE=1.11 ;;
    *)     MMS_MODE=1.10 ;;
  esac
  case "$(basename "$MMS_DIR")" in
    mmsource-2.0) MMS_MODE=2.0 ;;
    mmsource-1.12) MMS_MODE=1.12 ;;
    mmsource-1.11) MMS_MODE=1.11 ;;
    mmsource-1.10) MMS_MODE=1.10 ;;
  esac
fi

case "$MMS_MODE" in
  1.10)
    MM_EXT="1.ep1"
    ;;
  1.11|1.12|2.0)
    MM_EXT="2.ep1"
    ;;
  *)
    echo "Unsupported MMS_MODE=$MMS_MODE" >&2
    exit 1
    ;;
esac

if [[ "$MMS_MODE" == "1.10" ]]; then
  # Headers must already be css34-patched (checkout-deps applies apply-mmsource-css34.sh).
  if ! grep -q 'SH_IFACE_VERSION 4' "$MMS_DIR/core/sourcehook/sourcehook.h" 2>/dev/null; then
    echo "==> Applying css34 Metamod header patches before build"
    BUILD_PLATFORM="$BUILD_PLATFORM" MMS_DIR="$MMS_DIR" \
      bash "$BUILDER_DIR/patches/apply-mmsource-css34.sh" "$MMS_DIR"
  fi
elif [[ "$MMS_MODE" == "1.11" ]]; then
  bash "$BUILDER_DIR/patches/apply-mmsource-v111.sh" "$MMS_DIR"
else
  if [ ! -f "$MMS_DIR/hl2sdk-manifests/SdkHelpers.ambuild" ]; then
    echo "==> Initializing Metamod ${MMS_MODE} submodules"
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
  echo "==> Building Metamod:Source (${MMS_MODE} episode1 → metamod.${MM_EXT}.dll)"
else
  MM_BIN="$MMS_DIR/build/package/addons/metamod/bin/metamod.${MM_EXT}.so"
  PY=(python3)
  echo "==> Building Metamod:Source (${MMS_MODE} episode1 → metamod.${MM_EXT}.so)"
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
if [[ "$MMS_MODE" == "1.12" || "$MMS_MODE" == "2.0" ]]; then
  CONFIGURE_ARGS+=(--targets=x86)
fi

"${PY[@]}" ../configure.py "${CONFIGURE_ARGS[@]}"

ambuild

if [[ ! -f "$MM_BIN" ]]; then
  echo "Build finished but $MM_BIN was not found" >&2
  exit 1
fi

echo "==> Metamod build complete: $MM_BIN"
