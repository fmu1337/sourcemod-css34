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
# One timestamp for both css34-package.json manifests of this build.
export BUILD_DATE="${BUILD_DATE:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"
export MMS_DIR MMS_GIT_REV CSS34_LINE
export SOURCEMOD_MAJOR MMS_MODE MMS_DIRNAME MMS_COMMIT MMS_BRANCH
export SOURCEMOD_COMMIT SOURCEMOD_GIT_REV SOURCEMOD_DIR WDIR
export PURE_SOURCE_BUILD="${PURE_SOURCE_BUILD:-1}"
if [[ "${PURE_SOURCE_BUILD}" == "1" ]]; then
  export SPLICE_REFERENCE_EXTRAS=0
  export SPLICE_REFERENCE_LOGIC=0
fi

# manylinux2014_i686: devtoolset-10 GCC. build.sh sets SKIP_APT_INSTALL=1.
if [[ -f /opt/rh/devtoolset-10/enable ]]; then
  # shellcheck disable=SC1091
  set +u
  source /opt/rh/devtoolset-10/enable
  set -u
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
    lib32z1-dev \
    libc6-dev-i386 \
    linux-libc-dev \
    libssl-dev:i386
fi

export CC="${CC:-gcc}"
export CXX="${CXX:-g++}"

echo "==> Using compiler: $($CC --version | head -1)"
echo "==> Using C++ compiler: $($CXX --version | head -1)"

echo "==> Initializing SourceMod submodule"
cd "$WDIR"
if [ ! -e "$SOURCEMOD_DIR/.git" ]; then
  git submodule update --init sourcemod
fi
git -C "$SOURCEMOD_DIR" submodule foreach --recursive "git reset --hard && git clean -fd" 2>/dev/null || true
git -C "$SOURCEMOD_DIR" fetch --depth=8192 origin "$SOURCEMOD_COMMIT"
git -C "$SOURCEMOD_DIR" reset --hard "$SOURCEMOD_COMMIT"
git -C "$SOURCEMOD_DIR" submodule update --init --recursive

echo "==> Fetching build dependencies"
bash "$BUILDER_DIR/checkout-deps.sh" "$DEPS_DIR" "$BUILDER_DIR"
if [[ -f "$DEPS_DIR/openssl.env" ]]; then
  # shellcheck disable=SC1091
  source "$DEPS_DIR/openssl.env"
  echo "==> OpenSSL: CPATH=${CPATH:-} LIBRARY_PATH=${LIBRARY_PATH:-}"
fi
chmod +x "$BUILDER_DIR/py.sh" "$BUILDER_DIR/build-metamod.sh" "$BUILDER_DIR/package-metamod.sh" \
  "$BUILDER_DIR/write-build-stamps.sh" 2>/dev/null || true

python3 -m pip install --upgrade pip --user
chmod +x "$BUILDER_DIR/patches/patch-ambuild-py312.sh" 2>/dev/null || true
bash "$BUILDER_DIR/patches/patch-ambuild-py312.sh" "$DEPS_DIR/ambuild"
python3 -m pip install --force-reinstall --no-cache-dir --user "$DEPS_DIR/ambuild" 2>/dev/null || true
# Ensure Python 3.12 site-packages stay patched after reinstall.
bash "$BUILDER_DIR/patches/patch-ambuild-py312.sh" "$(python3 -c 'import ambuild2, pathlib; print(pathlib.Path(ambuild2.__file__).parent.parent)')" 2>/dev/null || true

echo "==> Writing CSS34 build stamp headers (pre-Metamod)"
WDIR="$WDIR" DEPS_DIR="$DEPS_DIR" SOURCEMOD_DIR="$SOURCEMOD_DIR" \
  SOURCEMOD_COMMIT="$SOURCEMOD_COMMIT" MMS_COMMIT="$MMS_COMMIT" MMS_DIR="$MMS_DIR" \
  bash "$BUILDER_DIR/write-build-stamps.sh"

build_and_package_mm() {
  local mm_dir="$1"
  local mm_mode="$2"
  local mm_dirname="$3"
  local mm_rev="$4"
  local mm_commit="$5"

  echo "==> Building Metamod:Source (css34 episode1, ${mm_mode}) in ${mm_dir}"
  WDIR="$WDIR" DEPS_DIR="$DEPS_DIR" BUILDER_DIR="$BUILDER_DIR" \
    CC="$CC" CXX="$CXX" \
    SOURCEMOD_MAJOR="$SOURCEMOD_MAJOR" MMS_DIR="$mm_dir" \
    MMS_MODE="$mm_mode" MMS_DIRNAME="$mm_dirname" MMS_GIT_REV="$mm_rev" MMS_COMMIT="$mm_commit" \
    bash "$BUILDER_DIR/build-metamod.sh"

  # css34 legacy-plugin bridge (T2.9): sm11's MM 1.12 package also ships the
  # MM 1.10 legacy core; metamod.2.ep1 loads it for PLAPI 7-12 plugins. The
  # PLAPI 11 test plugin goes to packages/test-plugins (never released).
  local mm_bin="$mm_dir/build/package/addons/metamod/bin"
  if [[ "${SM11_DUAL_MM:-0}" == 1 && "$mm_mode" == 1.10 ]]; then
    local probe
    probe="$(find "$mm_dir/build" -name 'css34_legacy_probe.so' -print -quit)"
    [[ -n "$probe" ]] || { echo "FAIL: css34_legacy_probe.so was not built in $mm_dir/build" >&2; exit 1; }
    mkdir -p "$PACKAGES_DIR/test-plugins"
    cp -f "$probe" "$PACKAGES_DIR/test-plugins/"
    SM11_LEGACY_CORE="$mm_bin/metamod.1.ep1.so"
  elif [[ "${SM11_DUAL_MM:-0}" == 1 && "$mm_mode" == 1.12 ]]; then
    [[ -f "${SM11_LEGACY_CORE:-}" ]] || { echo "FAIL: the MM 1.10 legacy core must be built before MM 1.12" >&2; exit 1; }
    cp -f "$SM11_LEGACY_CORE" "$mm_bin/"
    echo "==> Added $(basename "$SM11_LEGACY_CORE") to the MM 1.12 package (legacy-plugin bridge)"
  fi

  local mm_art
  mm_art="$(
    MMS_DIR="$mm_dir" MMS_GIT_REV="$mm_rev" MMS_COMMIT="$mm_commit" \
      bash "$BUILDER_DIR/package-metamod.sh" \
      "$mm_dir/build/package" \
      "$PACKAGES_DIR" \
      "$mm_dir"
  )"
  echo "==> Metamod package: $mm_art"
}

if [[ "${SOURCEMOD_MAJOR:-11}" -eq 11 || "${CSS34_LINE:-}" == sm11* ]]; then
  SM11_DUAL_MM=1
  mm_inputs="$(bash "$BUILDER_DIR/py.sh" "$BUILDER_DIR/resolve-metamod-pins.py" "${CSS34_LINE:-sm11-oldstable}")"
  MM_LEGACY_DIR=""
  MM_MODERN_DIR=""
  while IFS=$'\t' read -r role dirname mode branch commit rev version; do
    build_and_package_mm "$DEPS_DIR/$dirname" "$mode" "$dirname" "$rev" "$commit"
    case "$mode" in
      1.10) [[ -z "$MM_LEGACY_DIR" ]] || { echo "FAIL: two MM 1.10 inputs for ${CSS34_LINE:-sm11}" >&2; exit 1; }
            MM_LEGACY_DIR="$DEPS_DIR/$dirname" ;;
      1.12) [[ -z "$MM_MODERN_DIR" ]] || { echo "FAIL: two MM 1.12 inputs for ${CSS34_LINE:-sm11}" >&2; exit 1; }
            MM_MODERN_DIR="$DEPS_DIR/$dirname" ;;
    esac
  done <<< "$mm_inputs"
  # Dual-core SM 1.11: 1.ep1 builds against MM 1.10 legacy headers, 2.ep1 against MM 1.12.
  if [[ -z "$MM_LEGACY_DIR" || -z "$MM_MODERN_DIR" ]]; then
    echo "FAIL: SM 1.11 needs one MM 1.10 and one MM 1.12 input (got legacy='${MM_LEGACY_DIR}' modern='${MM_MODERN_DIR}')" >&2
    exit 1
  fi
  if [[ ! -d "$MM_LEGACY_DIR/core-css34legacy" || ! -d "$MM_MODERN_DIR/core" ]]; then
    echo "FAIL: missing $MM_LEGACY_DIR/core-css34legacy or $MM_MODERN_DIR/core" >&2
    exit 1
  fi
  export CSS34_MMS_LEGACY_CORE="$MM_LEGACY_DIR/core-css34legacy"
else
  build_and_package_mm "$MMS_DIR" "$MMS_MODE" "$MMS_DIRNAME" "${MMS_GIT_REV:-}" "${MMS_COMMIT:-}"
fi

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

# shellcheck source=../db-configure-args.sh
source "$BUILDER_DIR/db-configure-args.sh"
mapfile -t DB_PATH_ARGS < <(db_configure_args "$DEPS_DIR" "$SOURCEMOD_DIR")

CONFIGURE_ARGS=(
  --enable-optimize
  --hl2sdk-root="$DEPS_DIR"
  --mms-path="$MMS_DIR"
  "${DB_PATH_ARGS[@]}"
  --sdks=episode1
)
if [ "$SOURCEMOD_MAJOR" -ge 12 ]; then
  CONFIGURE_ARGS+=(--targets=x86)
elif [ "$SOURCEMOD_MAJOR" -lt 12 ]; then
  # SM 1.11 css34 builds dual 1.ep1 (MM 1.10) + 2.ep1 (MM 1.12) cores; --mms-path is the
  # MM 1.12 input resolved from lines.json above, never a silent fallback to MM 1.10.
  CONFIGURE_ARGS=(
    --enable-optimize
    --hl2sdk-root="$DEPS_DIR"
    --mms-path="$MM_MODERN_DIR"
    "${DB_PATH_ARGS[@]}"
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

echo "==> Build complete: $ARTIFACT"
