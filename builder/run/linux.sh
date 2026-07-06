#!/usr/bin/env bash
set -euo pipefail

WDIR="${WDIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
DEPS_DIR="${DEPS_DIR:-$WDIR/deps}"
PACKAGES_DIR="${PACKAGES_DIR:-$WDIR/packages}"
BUILDER_DIR="$WDIR/builder"
SOURCEMOD_DIR="$WDIR/sourcemod"
SOURCEMOD_COMMIT="${SOURCEMOD_COMMIT:-832519ab647cdecb85763918dbfed1cb5e79c6cb}"
SOURCEMOD_GIT_REV="${SOURCEMOD_GIT_REV:-6572}"

export CC="${CC:-gcc-9}"
export CXX="${CXX:-g++-9}"
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
    lib32stdc++6 \
    lib32z1-dev \
    libc6-dev-i386 \
    linux-libc-dev
fi

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

python3 -m pip install --upgrade pip --user
python3 -m pip install --user "$DEPS_DIR/ambuild" 2>/dev/null || true

echo "==> Applying CS:S v34 compatibility patches"
"$BUILDER_DIR/patches/apply-sourcemod.sh" "$SOURCEMOD_DIR"

echo "==> Configuring SourceMod (ep1 + episode1, like original release)"
cd "$SOURCEMOD_DIR"
rm -rf build obj-*
mkdir -p build
cd build

python3 ../configure.py \
  --enable-optimize \
  --disable-auto-versioning \
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
    "$SOURCEMOD_DIR"
)"

ln -sfn "$ARTIFACT" "$WDIR/$(basename "$ARTIFACT")"
echo "==> Build complete: $ARTIFACT"
