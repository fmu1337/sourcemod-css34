#!/usr/bin/env bash
set -euo pipefail

WDIR="${WDIR:-$(pwd)}"
DEPS="$WDIR/deps"
BUILD="$WDIR/build"
SM_DIR="$WDIR/sourcemod"

export WDIR

export CC="${CC:-gcc-9}"
export CXX="${CXX:-g++-9}"
export PATH="$HOME/.local/bin:$PATH"

echo "Building SourceMod CSS v34 from $WDIR"

git -C "$SM_DIR" submodule update --init --recursive

bash "$WDIR/builder/checkout-deps.sh" "$DEPS"
python3 "$WDIR/builder/patch-ambuild.py" "$SM_DIR/AMBuildScript"

rm -rf "$BUILD"
mkdir -p "$BUILD/OUTPUT"
cd "$BUILD/OUTPUT"

python3 "$SM_DIR/configure.py" \
  --enable-optimize \
  --disable-auto-versioning \
  --hl2sdk-root="$DEPS" \
  --mms-path="$DEPS/mmsource-1.10" \
  --mysql-path="$DEPS/mysql-5.5" \
  --sdks=ep1,episode1 \
  --target-arch=x86

ambuild

bash "$WDIR/builder/package.sh" "$BUILD/OUTPUT/package" "$WDIR/packages"
