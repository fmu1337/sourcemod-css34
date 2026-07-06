#!/usr/bin/env bash
set -euo pipefail

WDIR="${WDIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
DEPS_DIR="${DEPS_DIR:-$WDIR/deps}"
BUILDER_DIR="$WDIR/builder"
SOURCEMOD_DIR="$WDIR/sourcemod"
ENABLE_MYSQL="${ENABLE_MYSQL:-0}"
MYSQL_PATH="${MYSQL_PATH:-$DEPS_DIR/mysql-5.5}"
MYSQL_ARCHIVE_URL="${MYSQL_ARCHIVE_URL:-https://cdn.mysql.com/archives/mysql-5.6/mysql-5.6.15-linux-glibc2.5-i686.tar.gz}"
MYSQL_ARCHIVE_DIR="${MYSQL_ARCHIVE_DIR:-mysql-5.6.15-linux-glibc2.5-i686}"

fetch_mysql_client() {
  if [ -f "$MYSQL_PATH/lib/libmysqlclient_r.a" ] && [ -f "$MYSQL_PATH/include/mysql.h" ]; then
    echo "==> Using existing MySQL client SDK at $MYSQL_PATH"
    return 0
  fi

  echo "==> Fetching 32-bit MySQL client SDK (~280 MB)"
  local archive="$DEPS_DIR/mysql-client-i686.tar.gz"
  mkdir -p "$DEPS_DIR"
  curl -fsSL "$MYSQL_ARCHIVE_URL" -o "$archive"
  rm -rf "$DEPS_DIR/$MYSQL_ARCHIVE_DIR"
  tar -C "$DEPS_DIR" -xzf "$archive"
  rm -f "$archive"
  rm -rf "$MYSQL_PATH"
  mv "$DEPS_DIR/$MYSQL_ARCHIVE_DIR" "$MYSQL_PATH"
}

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

if [ "$ENABLE_MYSQL" = "1" ] || [ "$ENABLE_MYSQL" = "true" ] || [ "$ENABLE_MYSQL" = "yes" ]; then
  fetch_mysql_client
fi

python3 -m pip install --upgrade pip
python3 -m pip install --user "$DEPS_DIR/ambuild"
export PATH="$HOME/.local/bin:$PATH"
export CC=clang
export CXX=clang++

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

configure_args=(
  -s css
  --enable-optimize
  --disable-auto-versioning
)

if [ "$ENABLE_MYSQL" = "1" ] || [ "$ENABLE_MYSQL" = "true" ] || [ "$ENABLE_MYSQL" = "yes" ]; then
  configure_args+=(--mysql-path="$MYSQL_PATH")
  echo "==> MySQL extension enabled (dbi.mysql.ext.so)"
else
  configure_args+=(--no-mysql)
  echo "==> MySQL extension disabled (set ENABLE_MYSQL=1 to build dbi.mysql.ext.so)"
fi

python3 ../configure.py "${configure_args[@]}"

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
