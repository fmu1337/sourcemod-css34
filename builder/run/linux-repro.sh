#!/usr/bin/env bash
set -euo pipefail

WDIR="${WDIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
DEPS_DIR="${DEPS_DIR:-$WDIR/deps}"
PACKAGES_DIR="${PACKAGES_DIR:-$WDIR/packages}"
BUILDER_DIR="$WDIR/builder"
SOURCEMOD_DIR="$WDIR/sourcemod"

# shellcheck source=/dev/null
source "$BUILDER_DIR/pins.env"

export PATH="$HOME/.local/bin:$PATH"
export REPRO_BUILD=1
export STRIP_MODE="${STRIP_MODE:-debug}"
export TRANSLATIONS_REF="${TRANSLATIONS_REF:-$SOURCEMOD_COMMIT}"
export ORIGINAL_TRANSLATIONS="${ORIGINAL_TRANSLATIONS:-1}"
export LINUX_SDK_STUB_CC="${LINUX_SDK_STUB_CC:-clang-9}"

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
    libstdc++-9-dev \
    linux-libc-dev
fi

bash "$BUILDER_DIR/install-clang9.sh" "$DEPS_DIR"
# shellcheck source=/dev/null
source "$DEPS_DIR/clang9.env"
export CC="${CC:-clang-9}"
export CXX="${CXX:-clang++-9}"

echo "==> Repro build settings"
echo "    Compiler: $($CC --version | head -1)"
echo "    SourceMod: $SOURCEMOD_COMMIT"
echo "    HL2SDK episode1: ${HL2SDK_EPISODE1_COMMIT:0:12}"
echo "    MMS: ${MMSOURCE_110_COMMIT:0:12}"
echo "    AMBuild: ${AMBUILD_COMMIT:0:12}"
echo "    Translations: ${TRANSLATIONS_REF:0:12}"
echo "    STRIP_MODE: $STRIP_MODE"

echo "==> Initializing SourceMod submodule"
cd "$WDIR"
if [ ! -e "$SOURCEMOD_DIR/.git" ]; then
  git submodule update --init sourcemod
fi
git -C "$SOURCEMOD_DIR" fetch --depth 8192 origin "$SOURCEMOD_COMMIT"
git -C "$SOURCEMOD_DIR" reset --hard "$SOURCEMOD_COMMIT"
git -C "$SOURCEMOD_DIR" submodule update --init --recursive

echo "==> Fetching pinned build dependencies"
bash "$BUILDER_DIR/checkout-deps.sh" "$DEPS_DIR" "$BUILDER_DIR"

python3 -m pip install --upgrade pip --user
python3 -m pip install --user --force-reinstall "$DEPS_DIR/ambuild"

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
echo "==> Repro build complete: $ARTIFACT"

if [ -x "$BUILDER_DIR/compare-release.sh" ]; then
  "$BUILDER_DIR/compare-release.sh" "$ARTIFACT"
fi
