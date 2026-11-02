#!/usr/bin/env bash
set -euo pipefail

WDIR="${WDIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
DEPS_DIR="${DEPS_DIR:-$WDIR/deps}"
PACKAGES_DIR="${PACKAGES_DIR:-$WDIR/packages}"
BUILDER_DIR="$WDIR/builder"
SOURCEMOD_DIR="$WDIR/sourcemod"

# shellcheck source=../resolve-version.sh
source "$BUILDER_DIR/resolve-version.sh"
css34_require_buildable
MMS_DIR="${MMS_DIR:-$DEPS_DIR/$MMS_DIRNAME}"

export BUILD_PLATFORM=windows
export SOURCEMOD_MAJOR MMS_MODE MMS_DIR MMS_DIRNAME MMS_COMMIT MMS_BRANCH MMS_GIT_REV
export SOURCEMOD_COMMIT SOURCEMOD_GIT_REV SOURCEMOD_DIR WDIR
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

echo "==> Fetching SourceMod at the pinned commit"
cd "$WDIR"
bash "$BUILDER_DIR/fetch-sourcemod.sh" "$SOURCEMOD_DIR" "$SOURCEMOD_COMMIT"

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
  local mm_role="${6:-primary}"

  echo "==> Building Metamod:Source (${mm_mode} episode1, Windows) in ${mm_dir}"
  WDIR="$WDIR" DEPS_DIR="$DEPS_DIR" BUILDER_DIR="$BUILDER_DIR" \
    BUILD_PLATFORM=windows SOURCEMOD_MAJOR="$SOURCEMOD_MAJOR" MMS_DIR="$mm_dir" \
    MMS_MODE="$mm_mode" MMS_DIRNAME="$mm_dirname" MMS_GIT_REV="$mm_rev" MMS_COMMIT="$mm_commit" \
    bash "$BUILDER_DIR/build-metamod.sh"

  # css34 legacy-plugin bridge (T2.9): the MM 1.12 package also ships the line's
  # MM 1.10 legacy core (bridge_metamod); metamod.2.ep1 loads it for PLAPI 7-12
  # plugins. The PLAPI 11 test plugin goes to packages/test-plugins (never released).
  local mm_bin="$mm_dir/build/package/addons/metamod/bin"
  if [[ "$mm_mode" == 1.10 ]]; then
    local probe
    probe="$(find "$mm_dir/build" -name 'css34_legacy_probe.dll' -print -quit)"
    [[ -n "$probe" ]] || { echo "FAIL: css34_legacy_probe.dll was not built in $mm_dir/build" >&2; exit 1; }
    mkdir -p "$PACKAGES_DIR/test-plugins"
    cp -f "$probe" "$PACKAGES_DIR/test-plugins/"
    LEGACY_CORE="$mm_bin/metamod.1.ep1.dll"
  elif [[ "$mm_mode" == 1.12 && -n "${LEGACY_CORE:-}" ]]; then
    [[ -f "$LEGACY_CORE" ]] || { echo "FAIL: missing the MM 1.10 legacy core $LEGACY_CORE" >&2; exit 1; }
    cp -f "$LEGACY_CORE" "$mm_bin/"
    echo "==> Added $(basename "$LEGACY_CORE") to the MM 1.12 package (legacy-plugin bridge)"
  fi
  if [[ "$mm_role" == bridge ]]; then
    echo "==> MM ${mm_mode} built for the legacy-plugin bridge only; not packaged"
    return 0
  fi

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

# Every Metamod build of the line, MM 1.10 first: the primary (MMS_*,
# resolve-version.sh) and lines.json's bridge_metamod (only its metamod.1.ep1
# goes into the MM 1.12 package: legacy-plugin bridge, T2.9).
mm_extra="$(bash "$BUILDER_DIR/py.sh" "$BUILDER_DIR/resolve-metamod-pins.py" "${CSS34_LINE:-sm13-latest}")" ||
  { echo "FAIL: cannot resolve the Metamod inputs of ${CSS34_LINE:-sm13-latest}" >&2; exit 1; }
mm_inputs="$(
  {
    printf 'primary\t%s\t%s\t%s\t%s\t%s\t-\n' "$MMS_DIRNAME" "$MMS_MODE" "$MMS_BRANCH" "$MMS_COMMIT" "${MMS_GIT_REV:--}"
    awk -F'\t' '$1 != "primary"' <<< "$mm_extra"
  } | sort -t$'\t' -k3,3
)"
LEGACY_CORE=""
while IFS=$'\t' read -r role dirname mode branch commit rev version; do
  [[ "$rev" != - ]] || rev=""
  build_and_package_mm_win "$DEPS_DIR/$dirname" "$mode" "$dirname" "$rev" "$commit" "$role"
done <<< "$mm_inputs"

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
  --targets=x86
)

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
