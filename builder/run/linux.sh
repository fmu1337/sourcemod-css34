#!/usr/bin/env bash
set -euo pipefail

WDIR="${WDIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
DEPS_DIR="${DEPS_DIR:-$WDIR/deps}"
PACKAGES_DIR="${PACKAGES_DIR:-$WDIR/packages}"
BUILDER_DIR="$WDIR/builder"
SOURCEMOD_DIR="$WDIR/sourcemod"

# shellcheck source=resolve-version.sh
source "$BUILDER_DIR/resolve-version.sh"

export PATH="$HOME/.local/bin:$PATH"

if [ "${SKIP_APT_INSTALL:-0}" != "1" ]; then
  echo "==> Installing Linux build dependencies"
  export DEBIAN_FRONTEND=noninteractive
  sudo dpkg --add-architecture i386 2>/dev/null || true
  sudo apt-get update -qq
  sudo apt-get install -y -qq \
    curl \
    git \
    python3 \
    python3-pip \
    g++-9-multilib \
    gcc-9-multilib \
    lib32stdc++-9-dev \
    lib32stdc++6 \
    lib32z1-dev \
    libc6-dev-i386 \
    linux-libc-dev
fi

# rom4s SM 1.11.0.6572 was built with clang-9; gcc-9 produces a core that
# loads alone but SIGSEGVs inside css34 metamod when engine extensions
# register SourceHook hooks (FastDelegate / HookMan ABI drift).
USE_CLANG9="${USE_CLANG9:-1}"
if [ "$USE_CLANG9" = "1" ]; then
  echo "==> Installing/using clang-9 (rom4s-compatible toolchain)"
  bash "$BUILDER_DIR/install-clang9.sh" "$DEPS_DIR"
  bash "$BUILDER_DIR/install-clang10.sh" "$DEPS_DIR"
  # shellcheck source=/dev/null
  source "$DEPS_DIR/clang9.env"
  # shellcheck source=/dev/null
  source "$DEPS_DIR/clang10.env"
  export CC="${CC:-clang-9}"
  export CXX="${CXX:-clang++-9}"
  # Prefer clang-9 wrappers even if a parent env exported gcc-9.
  case "$CC" in
    gcc*|g++*) export CC=clang-9 ;;
  esac
  case "$CXX" in
    g++*|gcc*) export CXX=clang++-9 ;;
  esac
else
  export CC="${CC:-gcc-9}"
  export CXX="${CXX:-g++-9}"
fi

echo "==> Profile: ${SOURCEMOD_PROFILE:-stable} (SourceMod 1.11.0-git${SOURCEMOD_GIT_REV})"
echo "==> Using compiler: $($CC --version | head -1)"
echo "==> Using C++ compiler: $($CXX --version | head -1)"

echo "==> Initializing SourceMod submodule"
cd "$WDIR"
if [ ! -e "$SOURCEMOD_DIR/.git" ]; then
  git submodule update --init sourcemod
fi
git -C "$SOURCEMOD_DIR" fetch --depth=8192 origin "$SOURCEMOD_COMMIT"
git -C "$SOURCEMOD_DIR" reset --hard "$SOURCEMOD_COMMIT"
git -C "$SOURCEMOD_DIR" submodule update --init --recursive

echo "==> Fetching build dependencies"
bash "$BUILDER_DIR/checkout-deps.sh" "$DEPS_DIR" "$BUILDER_DIR"
chmod +x "$BUILDER_DIR/py.sh" 2>/dev/null || true

python3 -m pip install --upgrade pip --user
chmod +x "$BUILDER_DIR/patches/patch-ambuild-linker.sh" 2>/dev/null || true
bash "$BUILDER_DIR/patches/patch-ambuild-linker.sh" "$DEPS_DIR/ambuild"
python3 -m pip install --force-reinstall --no-cache-dir --user "$DEPS_DIR/ambuild" 2>/dev/null || true

echo "==> Applying CS:S v34 compatibility patches"
"$BUILDER_DIR/patches/apply-sourcemod.sh" "$SOURCEMOD_DIR"

echo "==> Configuring SourceMod (ep1 + episode1, like original release)"
cd "$SOURCEMOD_DIR"
rm -rf build obj-*
mkdir -p build
cd build

python3 ../configure.py \
  --enable-optimize \
  --hl2sdk-root="$DEPS_DIR" \
  --mms-path="$DEPS_DIR/mmsource-1.10" \
  --mysql-path="$DEPS_DIR/mysql-5.5" \
  --sdks=ep1,episode1

echo "==> Building SourceMod"
ambuild

PACKAGE_DIR="$SOURCEMOD_DIR/build/package"
if [ ! -d "$PACKAGE_DIR/addons/sourcemod" ]; then
  echo "Build finished but package directory was not found." >&2
  exit 1
fi

mkdir -p "$PACKAGES_DIR"
ARTIFACT="$(
  SOURCEMOD_GIT_REV="$SOURCEMOD_GIT_REV" bash "$BUILDER_DIR/package.sh" \
    "$PACKAGE_DIR" \
    "$PACKAGES_DIR" \
    "$SOURCEMOD_DIR" \
    "$BUILDER_DIR" \
    "$DEPS_DIR"
)"

ln -sfn "$ARTIFACT" "$WDIR/$(basename "$ARTIFACT")"
echo "==> Build complete: $ARTIFACT"
