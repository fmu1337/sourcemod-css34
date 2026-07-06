#!/usr/bin/env bash
set -euo pipefail

WDIR="${WDIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
DEPS_DIR="${DEPS_DIR:-$WDIR/deps}"
BUILDER_DIR="$WDIR/builder"
SOURCEMOD_DIR="$WDIR/sourcemod"

echo "==> Installing Linux build dependencies"
export DEBIAN_FRONTEND=noninteractive
sudo apt-get update -qq
sudo apt-get install -y -qq \
  git \
  python3 \
  python3-pip \
  clang \
  gcc-multilib \
  g++-multilib \
  lib32stdc++6 \
  lib32z1-dev \
  libc6-dev-i386

echo "==> Initializing submodules"
cd "$WDIR"
git submodule foreach --recursive 'git checkout -- . >/dev/null 2>&1 || true; git clean -fd >/dev/null 2>&1 || true'
git submodule update --init --recursive --force

echo "==> Fetching build dependencies"
mkdir -p "$DEPS_DIR"
rm -rf "$DEPS_DIR/hl2sdk-css"
git clone --depth 1 https://github.com/rom4s/hl2sdk-ep1c "$DEPS_DIR/hl2sdk-css"
if [ ! -d "$DEPS_DIR/mmsource-1.10" ]; then
  git clone --depth 1 https://github.com/alliedmodders/metamod-source "$DEPS_DIR/mmsource-1.10"
fi
if [ ! -d "$DEPS_DIR/ambuild" ]; then
  git clone --depth 1 https://github.com/alliedmodders/ambuild "$DEPS_DIR/ambuild"
fi

python3 -m pip install --upgrade pip
python3 -m pip install --user "$DEPS_DIR/ambuild"
export PATH="$HOME/.local/bin:$PATH"

echo "==> Applying CS:S v34 compatibility patches"
"$BUILDER_DIR/patches/apply-hl2sdk-ep1c.sh" "$DEPS_DIR/hl2sdk-css"
"$BUILDER_DIR/patches/apply-sourcemod.sh" "$SOURCEMOD_DIR"

echo "==> Configuring SourceMod"
cd "$SOURCEMOD_DIR"
rm -rf build obj-*
mkdir -p build
cd build

export HL2SDKCSS="$DEPS_DIR/hl2sdk-css"
export MMSOURCE110="$DEPS_DIR/mmsource-1.10"
export CC=clang
export CXX=clang++

python3 ../configure.py \
  -s css \
  --enable-optimize \
  --no-mysql \
  --disable-auto-versioning

echo "==> Building SourceMod"
ambuild

PACKAGE_DIR="$SOURCEMOD_DIR/build/package"
if [ ! -d "$PACKAGE_DIR/addons/sourcemod" ]; then
  echo "Build finished but package directory was not found." >&2
  exit 1
fi

GIT_REV="$(git -C "$SOURCEMOD_DIR" rev-list --count HEAD 2>/dev/null || echo 0)"
ARTIFACT="$WDIR/sourcemod-css34-linux.tar.gz"
tar -C "$PACKAGE_DIR" -czf "$ARTIFACT" addons cfg

echo "==> Build complete: $ARTIFACT (git$GIT_REV)"
