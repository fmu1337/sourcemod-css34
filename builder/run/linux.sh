#!/usr/bin/env bash
set -euo pipefail

WDIR="${WDIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
DEPS_DIR="${DEPS_DIR:-$WDIR/deps}"
PACKAGES_DIR="${PACKAGES_DIR:-$WDIR/packages}"
BUILDER_DIR="$WDIR/builder"
SOURCEMOD_DIR="$WDIR/sourcemod"

# shellcheck source=../resolve-version.sh
source "$BUILDER_DIR/resolve-version.sh"
MMS_DIR="${MMS_DIR:-$DEPS_DIR/$MMS_DIRNAME}"

export PATH="$HOME/.local/bin:$PATH"
export SOURCEMOD_MAJOR MMS_MODE MMS_DIRNAME MMS_COMMIT MMS_BRANCH
export SOURCEMOD_COMMIT SOURCEMOD_GIT_REV
export PURE_SOURCE_BUILD="${PURE_SOURCE_BUILD:-1}"
if [[ "${PURE_SOURCE_BUILD}" == "1" ]]; then
  export SPLICE_REFERENCE_EXTRAS=0
  export SPLICE_REFERENCE_LOGIC=0
fi

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
chmod +x "$BUILDER_DIR/py.sh" "$BUILDER_DIR/build-metamod.sh" "$BUILDER_DIR/package-metamod.sh" \
  "$BUILDER_DIR/write-build-stamps.sh" 2>/dev/null || true

python3 -m pip install --upgrade pip --user
chmod +x "$BUILDER_DIR/patches/patch-ambuild-linker.sh" "$BUILDER_DIR/patches/patch-ambuild-py312.sh" 2>/dev/null || true
bash "$BUILDER_DIR/patches/patch-ambuild-linker.sh" "$DEPS_DIR/ambuild"
bash "$BUILDER_DIR/patches/patch-ambuild-py312.sh" "$DEPS_DIR/ambuild"
python3 -m pip install --force-reinstall --no-cache-dir --user "$DEPS_DIR/ambuild" 2>/dev/null || true
# Ensure Python 3.12 site-packages stay patched after reinstall.
bash "$BUILDER_DIR/patches/patch-ambuild-py312.sh" "$(python3 -c 'import ambuild2, pathlib; print(pathlib.Path(ambuild2.__file__).parent.parent)')" 2>/dev/null || true

echo "==> Writing CSS34 build stamp headers (pre-Metamod)"
WDIR="$WDIR" DEPS_DIR="$DEPS_DIR" SOURCEMOD_DIR="$SOURCEMOD_DIR" \
  SOURCEMOD_COMMIT="$SOURCEMOD_COMMIT" MMS_COMMIT="$MMS_COMMIT" MMS_DIR="$MMS_DIR" \
  bash "$BUILDER_DIR/write-build-stamps.sh"

echo "==> Building Metamod:Source (css34 episode1, ${MMS_MODE})"
WDIR="$WDIR" DEPS_DIR="$DEPS_DIR" BUILDER_DIR="$BUILDER_DIR" \
  CC="$CC" CXX="$CXX" USE_CLANG9="$USE_CLANG9" \
  SOURCEMOD_MAJOR="$SOURCEMOD_MAJOR" MMS_DIR="$MMS_DIR" \
  MMS_MODE="$MMS_MODE" MMS_DIRNAME="$MMS_DIRNAME" \
  bash "$BUILDER_DIR/build-metamod.sh"

MM_ARTIFACT="$(
  bash "$BUILDER_DIR/package-metamod.sh" \
    "$MMS_DIR/build/package" \
    "$PACKAGES_DIR" \
    "$MMS_DIR"
)"
ln -sfn "$MM_ARTIFACT" "$WDIR/$(basename "$MM_ARTIFACT")"
echo "==> Metamod package: $MM_ARTIFACT"

echo "==> Applying CS:S v34 compatibility patches"
"$BUILDER_DIR/patches/apply-sourcemod.sh" "$SOURCEMOD_DIR"

echo "==> Writing CSS34 build stamp headers (pre-SourceMod)"
WDIR="$WDIR" DEPS_DIR="$DEPS_DIR" SOURCEMOD_DIR="$SOURCEMOD_DIR" \
  SOURCEMOD_COMMIT="$SOURCEMOD_COMMIT" MMS_COMMIT="$MMS_COMMIT" MMS_DIR="$MMS_DIR" \
  bash "$BUILDER_DIR/write-build-stamps.sh"

echo "==> Configuring SourceMod (episode1 / 2.ep1 with Metamod 1.12)"
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
  # SM 1.11 css34 still builds dual 1.ep1 + 2.ep1 cores against MM 1.10.
  CONFIGURE_ARGS=(
    --enable-optimize
    --hl2sdk-root="$DEPS_DIR"
    --mms-path="$MMS_DIR"
    --mysql-path="$DEPS_DIR/mysql-5.5"
    --sdks=ep1,episode1
  )
fi

python3 ../configure.py "${CONFIGURE_ARGS[@]}"

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
