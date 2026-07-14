#!/usr/bin/env bash
set -euo pipefail

DEPS="${1:?deps directory required}"
BUILDER_DIR="${2:?builder directory required}"
BUILD_PLATFORM="${BUILD_PLATFORM:-linux}"
export BUILD_PLATFORM

mkdir -p "$DEPS"

clone_repo() {
  local name="$1"
  local url="$2"
  local branch="${3:-}"
  local commit="${4:-}"

  if [ -d "$DEPS/$name/.git" ]; then
    if [ -n "$commit" ]; then
      echo "==> Pinning $name to $commit"
      git -C "$DEPS/$name" fetch --depth 1 origin "$commit"
      git -C "$DEPS/$name" checkout --force "$commit"
    fi
    return 0
  fi

  if [ -n "$commit" ]; then
    git clone --depth 1 "$url" "$DEPS/$name"
    git -C "$DEPS/$name" fetch --depth 1 origin "$commit"
    git -C "$DEPS/$name" checkout --force "$commit"
  elif [ -n "$branch" ]; then
    git clone --depth 1 --branch "$branch" "$url" "$DEPS/$name"
  else
    git clone --depth 1 "$url" "$DEPS/$name"
  fi
}

patch_episode1_sdk() {
  local sdk_dir="$1"
  local platform_h="$sdk_dir/public/tier0/platform.h"

  if [ -f "$platform_h" ] && grep -q '#include <new.h>' "$platform_h"; then
    sed -i 's|#include <new.h>|#if defined(_WIN32)\n#include <new.h>\n#else\n#include <new>\n#endif|' "$platform_h"
  fi

  # alliedmodders/hl2sdk episode1 already ships mixed-case headers; only
  # create symlinks when lowercase sources exist (rom4s-style SDK layouts).
  local appframework="$sdk_dir/public/appframework"
  if [ -d "$appframework" ]; then
    if [ -f "$appframework/iappsystem.h" ] && [ ! -f "$appframework/IAppSystem.h" ]; then
      ln -sfn iappsystem.h "$appframework/IAppSystem.h"
    fi
    if [ -f "$appframework/iappsystemgroup.h" ] && [ ! -f "$appframework/IAppSystemGroup.h" ]; then
      ln -sfn iappsystemgroup.h "$appframework/IAppSystemGroup.h"
    fi
    if [ -f "$appframework/appframework.h" ] && [ ! -f "$appframework/AppFramework.h" ]; then
      ln -sfn appframework.h "$appframework/AppFramework.h"
    fi
  fi
}

echo "==> Fetching MySQL client SDK"
if [ "$BUILD_PLATFORM" = "windows" ]; then
  if [ ! -f "$DEPS/mysql-5.5/lib/mysqlclient.lib" ] && [ ! -f "$DEPS/mysql-5.5/lib/libmysql.lib" ]; then
    curl -fsSL -o "$DEPS/mysql.zip" \
      https://cdn.mysql.com/archives/mysql-5.5/mysql-5.5.54-win32.zip
    rm -rf "$DEPS/mysql-5.5"
    unzip -q -o "$DEPS/mysql.zip" -d "$DEPS"
    mv "$DEPS/mysql-5.5.54-win32" "$DEPS/mysql-5.5"
    rm -f "$DEPS/mysql.zip"
  fi
else
  if [ ! -f "$DEPS/mysql-5.5/lib/libmysqlclient_r.a" ]; then
    curl -fsSL -o "$DEPS/mysql.tar.gz" \
      https://cdn.mysql.com/archives/mysql-5.6/mysql-5.6.15-linux-glibc2.5-i686.tar.gz
    tar -C "$DEPS" -xzf "$DEPS/mysql.tar.gz"
    rm -rf "$DEPS/mysql-5.5"
    mv "$DEPS/mysql-5.6.15-linux-glibc2.5-i686" "$DEPS/mysql-5.5"
    rm -f "$DEPS/mysql.tar.gz"
  fi
fi

echo "==> Fetching Metamod:Source"
if [ "${SOURCEMOD_MAJOR:-11}" -ge 12 ]; then
  # SourceMod 1.12 expects Metamod 1.12 (PLAPI 16 / modern Core / metamod.2.ep1).
  MMS_COMMIT="${MMS_COMMIT:-364cb6c26f66f7d9254d95a2fc533eac3557166b}"
  clone_repo "mmsource-1.12" "https://github.com/alliedmodders/metamod-source" "1.12-dev" "$MMS_COMMIT"
  echo "==> Metamod:Source at $(git -C "$DEPS/mmsource-1.12" rev-parse HEAD)"
  git -C "$DEPS/mmsource-1.12" submodule update --init --recursive
  bash "$BUILDER_DIR/patches/apply-mmsource-v112.sh" "$DEPS/mmsource-1.12"
else
  # SourceMod 1.11 css34: keep legacy metamod.1.ep1 / SH v4 / PLAPI 11.
  MMS_COMMIT="${MMS_COMMIT:-80e8ff0be3b62386bbd6f937e97b819ef8be6dd2}"
  clone_repo "mmsource-1.10" "https://github.com/alliedmodders/metamod-source" "1.10-dev" "$MMS_COMMIT"
  echo "==> Metamod:Source at $(git -C "$DEPS/mmsource-1.10" rev-parse HEAD)"
  bash "$BUILDER_DIR/patches/apply-mmsource-css34.sh" "$DEPS/mmsource-1.10"
fi

echo "==> Fetching HL2SDK episode1"
rm -rf "$DEPS/hl2sdk-episode1"
clone_repo "hl2sdk-episode1" "https://github.com/alliedmodders/hl2sdk" "episode1"
patch_episode1_sdk "$DEPS/hl2sdk-episode1"

echo "==> Fetching rom4s/hl2sdk-ep1c as hl2sdk-ep1"
rm -rf "$DEPS/hl2sdk-ep1"
git clone --depth 1 https://github.com/rom4s/hl2sdk-ep1c "$DEPS/hl2sdk-ep1"
# ep1c does not ship tier0/vstdlib; use episode1's real .so so the linker records DT_NEEDED.
export HL2SDK_EPISODE1_LINUX_SDK="$DEPS/hl2sdk-episode1/linux_sdk"
"$BUILDER_DIR/patches/apply-hl2sdk-ep1c.sh" "$DEPS/hl2sdk-ep1"

echo "==> Fetching AMBuild"
AMBUILD_TAG="${AMBUILD_TAG:-}"
AMBUILD_REF="${AMBUILD_REF:-}"
if [ "${SOURCEMOD_MAJOR:-11}" -ge 12 ]; then
  # Tag 2.2 is too old for current hl2sdk-manifests (addConfigureFile); use main tip.
  AMBUILD_REF="${AMBUILD_REF:-master}"
fi
if [ -n "$AMBUILD_REF" ]; then
  echo "==> Pinning AMBuild to $AMBUILD_REF (SourceMod ${SOURCEMOD_MAJOR})"
  rm -rf "$DEPS/ambuild"
  git clone --depth 1 --branch "$AMBUILD_REF" https://github.com/alliedmodders/ambuild "$DEPS/ambuild"
  if [ "$BUILD_PLATFORM" = "windows" ]; then
    python -m pip install --force-reinstall --no-cache-dir "$DEPS/ambuild"
  else
    python3 -m pip install --force-reinstall --no-cache-dir --user "$DEPS/ambuild"
  fi
elif [ -n "$AMBUILD_TAG" ]; then
  echo "==> Pinning AMBuild to tag $AMBUILD_TAG (SourceMod ${SOURCEMOD_MAJOR})"
  rm -rf "$DEPS/ambuild"
  git clone --depth 1 --branch "$AMBUILD_TAG" https://github.com/alliedmodders/ambuild "$DEPS/ambuild"
  if [ "$BUILD_PLATFORM" = "windows" ]; then
    python -m pip install --force-reinstall --no-cache-dir "$DEPS/ambuild"
  else
    python3 -m pip install --force-reinstall --no-cache-dir --user "$DEPS/ambuild"
  fi
elif [ ! -d "$DEPS/ambuild/.git" ]; then
  clone_repo "ambuild" "https://github.com/alliedmodders/ambuild"
fi
if ! python -c "import ambuild2" 2>/dev/null && ! python3 -c "import ambuild2" 2>/dev/null; then
  if [ "$BUILD_PLATFORM" = "windows" ]; then
    python -m pip install "$DEPS/ambuild"
  else
    python3 -m pip install --user "$DEPS/ambuild"
  fi
fi
