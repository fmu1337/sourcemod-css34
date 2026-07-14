#!/usr/bin/env bash
set -euo pipefail

WDIR="${WDIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
DEPS_DIR="${DEPS_DIR:-$WDIR/deps}"
PACKAGES_DIR="${PACKAGES_DIR:-$WDIR/packages}"
BUILDER_DIR="$WDIR/builder"
SOURCEMOD_DIR="$WDIR/sourcemod"
SOURCEMOD_COMMIT="${SOURCEMOD_COMMIT:-bd1bde7def4c1e3e584c320dfb2ac974eb4d7433}"
SOURCEMOD_GIT_REV="${SOURCEMOD_GIT_REV:-7394}"
SOURCEMOD_MAJOR="${SOURCEMOD_MAJOR:-13}"
if [ "$SOURCEMOD_MAJOR" -ge 12 ]; then
  MMS_COMMIT="${MMS_COMMIT:-364cb6c26f66f7d9254d95a2fc533eac3557166b}"
  MMS_DIR="${MMS_DIR:-$DEPS_DIR/mmsource-1.12}"
else
  MMS_COMMIT="${MMS_COMMIT:-80e8ff0be3b62386bbd6f937e97b819ef8be6dd2}"
  MMS_DIR="${MMS_DIR:-$DEPS_DIR/mmsource-1.10}"
fi

export BUILD_PLATFORM=windows
export SOURCEMOD_MAJOR

if ! command -v cl >/dev/null 2>&1; then
  echo "MSVC compiler (cl.exe) not found. Run inside a Visual Studio Developer shell." >&2
  exit 1
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
chmod +x "$BUILDER_DIR/py.sh" "$BUILDER_DIR/build-metamod.sh" "$BUILDER_DIR/write-build-stamps.sh" \
  "$BUILDER_DIR"/patches/*.sh 2>/dev/null || true

python -m pip install --upgrade pip
python -m pip install "$DEPS_DIR/ambuild"

# RootConsoleMenu.cpp / Metamod versioning include css34_build_stamp.h.
echo "==> Writing CSS34 build stamp headers (pre-Metamod)"
WDIR="$WDIR" DEPS_DIR="$DEPS_DIR" SOURCEMOD_DIR="$SOURCEMOD_DIR" \
  SOURCEMOD_COMMIT="$SOURCEMOD_COMMIT" MMS_COMMIT="$MMS_COMMIT" MMS_DIR="$MMS_DIR" \
  bash "$BUILDER_DIR/write-build-stamps.sh"

echo "==> Building Metamod:Source (css34 episode1, Windows)"
WDIR="$WDIR" DEPS_DIR="$DEPS_DIR" BUILDER_DIR="$BUILDER_DIR" \
  BUILD_PLATFORM=windows SOURCEMOD_MAJOR="$SOURCEMOD_MAJOR" MMS_DIR="$MMS_DIR" \
  bash "$BUILDER_DIR/build-metamod.sh"

mkdir -p "$PACKAGES_DIR"
MM_ARTIFACT="$(
  powershell -NoProfile -ExecutionPolicy Bypass \
    -File "$BUILDER_DIR/package-metamod-windows.ps1" \
    -PackageDir "$MMS_DIR/build/package" \
    -OutputDir "$PACKAGES_DIR" \
    -MmsDir "$MMS_DIR"
)"
cp -f "$MM_ARTIFACT" "$WDIR/$(basename "$MM_ARTIFACT")"
echo "==> Metamod package: $MM_ARTIFACT"

echo "==> Applying CS:S v34 compatibility patches"
bash "$BUILDER_DIR/patches/apply-sourcemod.sh" "$SOURCEMOD_DIR"

echo "==> Writing CSS34 build stamp headers (pre-SourceMod)"
WDIR="$WDIR" DEPS_DIR="$DEPS_DIR" SOURCEMOD_DIR="$SOURCEMOD_DIR" \
  SOURCEMOD_COMMIT="$SOURCEMOD_COMMIT" MMS_COMMIT="$MMS_COMMIT" MMS_DIR="$MMS_DIR" \
  bash "$BUILDER_DIR/write-build-stamps.sh"

echo "==> Configuring SourceMod (episode1 / 2.ep1 with Metamod 1.12, Windows)"
cd "$SOURCEMOD_DIR"
rm -rf build obj-*
mkdir -p build
cd build

CONFIGURE_ARGS=(
  --enable-optimize
  --hl2sdk-root="$DEPS_DIR"
  --mms-path="$MMS_DIR"
  --mysql-path="$DEPS_DIR/mysql-5.5"
  --sdks=episode1
)
if [ "$SOURCEMOD_MAJOR" -ge 12 ]; then
  CONFIGURE_ARGS+=(--targets=x86)
elif [ "$SOURCEMOD_MAJOR" -lt 12 ]; then
  CONFIGURE_ARGS=(
    --enable-optimize
    --hl2sdk-root="$DEPS_DIR"
    --mms-path="$MMS_DIR"
    --mysql-path="$DEPS_DIR/mysql-5.5"
    --sdks=ep1,episode1
  )
fi

python ../configure.py "${CONFIGURE_ARGS[@]}"

echo "==> Building SourceMod"
ambuild

PACKAGE_DIR="$SOURCEMOD_DIR/build/package"
if [ ! -d "$PACKAGE_DIR/addons/sourcemod" ]; then
  echo "Build finished but package directory was not found." >&2
  exit 1
fi

bash "$BUILDER_DIR/prepare-package.sh" \
  "$PACKAGE_DIR" \
  "$SOURCEMOD_DIR" \
  "$BUILDER_DIR" \
  "$DEPS_DIR"

ARTIFACT="$(
  SOURCEMOD_GIT_REV="$SOURCEMOD_GIT_REV" powershell -NoProfile -ExecutionPolicy Bypass \
    -File "$BUILDER_DIR/package-windows.ps1" \
    -PackageDir "$PACKAGE_DIR" \
    -OutputDir "$PACKAGES_DIR" \
    -SourceModDir "$SOURCEMOD_DIR"
)"

cp -f "$ARTIFACT" "$WDIR/$(basename "$ARTIFACT")"
echo "==> Build complete: $ARTIFACT"
