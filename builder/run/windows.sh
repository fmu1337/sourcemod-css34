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

export BUILD_PLATFORM=windows
export SOURCEMOD_MAJOR MMS_MODE MMS_DIR MMS_DIRNAME MMS_COMMIT MMS_BRANCH MMS_GIT_REV
export SOURCEMOD_COMMIT SOURCEMOD_GIT_REV SOURCEMOD_DIR WDIR
export PURE_SOURCE_BUILD="${PURE_SOURCE_BUILD:-1}"
# One timestamp for both css34-package.json manifests of this build.
export BUILD_DATE="${BUILD_DATE:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"

if ! command -v cl >/dev/null 2>&1; then
  echo "MSVC compiler (cl.exe) not found. Run inside a Visual Studio Developer shell." >&2
  exit 1
fi

# shellcheck source=../windows-toolchain.env
source "$BUILDER_DIR/windows-toolchain.env"
msvc_toolset="${VCToolsVersion:-${VCTOOLSVERSION:-}}"
windows_sdk="${WindowsSDKVersion:-${WINDOWSSDKVERSION:-}}"
windows_sdk="${windows_sdk//\\/}"
windows_sdk="${windows_sdk%/}"
sdk_prefix="${WINDOWS_SDK_PIN%.*}"
if [[ "$msvc_toolset" != "${MSVC_TOOLSET_PREFIX}".* ]]; then
  echo "FAIL: MSVC toolset '${msvc_toolset:-unset}' is not ${MSVC_TOOLSET_PREFIX}.* (vcvars -vcvars_ver=${MSVC_TOOLSET_PREFIX})" >&2
  exit 1
fi
if [[ "$windows_sdk" != "$WINDOWS_SDK_PIN" && "$windows_sdk" != "${sdk_prefix}".* ]]; then
  echo "FAIL: Windows SDK '${windows_sdk:-unset}' is not ${WINDOWS_SDK_PIN}" >&2
  exit 1
fi
export MSVC_TOOLSET="$msvc_toolset"
export WINDOWS_SDK="$windows_sdk"
echo "==> MSVC toolset ${MSVC_TOOLSET}, Windows SDK ${WINDOWS_SDK}"

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
chmod +x "$BUILDER_DIR/py.sh" "$BUILDER_DIR/build-metamod.sh" "$BUILDER_DIR/write-build-stamps.sh" \
  "$BUILDER_DIR/write-package-manifest.sh" "$BUILDER_DIR"/patches/*.sh 2>/dev/null || true

python -m pip install --upgrade pip
python -m pip install "$DEPS_DIR/ambuild"

# RootConsoleMenu.cpp / Metamod versioning include css34_build_stamp.h.
echo "==> Writing CSS34 build stamp headers (pre-Metamod)"
WDIR="$WDIR" DEPS_DIR="$DEPS_DIR" SOURCEMOD_DIR="$SOURCEMOD_DIR" \
  SOURCEMOD_COMMIT="$SOURCEMOD_COMMIT" MMS_COMMIT="$MMS_COMMIT" MMS_DIR="$MMS_DIR" \
  bash "$BUILDER_DIR/write-build-stamps.sh"

mkdir -p "$PACKAGES_DIR"

build_and_package_mm_win() {
  local mm_dir="$1"
  local mm_mode="$2"
  local mm_dirname="$3"
  local mm_rev="$4"
  local mm_commit="$5"

  echo "==> Building Metamod:Source (${mm_mode} episode1, Windows) in ${mm_dir}"
  WDIR="$WDIR" DEPS_DIR="$DEPS_DIR" BUILDER_DIR="$BUILDER_DIR" \
    BUILD_PLATFORM=windows SOURCEMOD_MAJOR="$SOURCEMOD_MAJOR" MMS_DIR="$mm_dir" \
    MMS_MODE="$mm_mode" MMS_DIRNAME="$mm_dirname" MMS_GIT_REV="$mm_rev" MMS_COMMIT="$mm_commit" \
    bash "$BUILDER_DIR/build-metamod.sh"

  local mm_art
  mm_art="$(
    MMS_DIR="$mm_dir" MMS_GIT_REV="$mm_rev" MMS_COMMIT="$mm_commit" \
      powershell -NoProfile -ExecutionPolicy Bypass \
      -File "$BUILDER_DIR/package-metamod-windows.ps1" \
      -PackageDir "$mm_dir/build/package" \
      -OutputDir "$PACKAGES_DIR" \
      -MmsDir "$mm_dir" | tail -n1 | tr -d '\r'
  )"
  cp -f "$mm_art" "$WDIR/$(basename "$mm_art")"
  echo "==> Metamod package: $mm_art"
}

if [[ "${SOURCEMOD_MAJOR:-11}" -eq 11 || "${CSS34_LINE:-}" == sm11* ]]; then
  mm_inputs="$(bash "$BUILDER_DIR/py.sh" "$BUILDER_DIR/resolve-metamod-pins.py" "${CSS34_LINE:-sm11-oldstable}")"
  while IFS=$'\t' read -r role dirname mode branch commit rev version; do
    build_and_package_mm_win "$DEPS_DIR/$dirname" "$mode" "$dirname" "$rev" "$commit"
  done <<< "$mm_inputs"
else
  build_and_package_mm_win "$MMS_DIR" "$MMS_MODE" "$MMS_DIRNAME" "${MMS_GIT_REV:-}" "${MMS_COMMIT:-}"
fi

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
  CONFIGURE_ARGS=(
    --enable-optimize
    --hl2sdk-root="$DEPS_DIR"
    --mms-path="$MMS_DIR"
    "${DB_PATH_ARGS[@]}"
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
    -SourceModDir "$SOURCEMOD_DIR" | tail -n1 | tr -d '\r'
)"

cp -f "$ARTIFACT" "$WDIR/$(basename "$ARTIFACT")"
echo "==> Build complete: $ARTIFACT"
