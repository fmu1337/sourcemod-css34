#!/usr/bin/env bash
set -euo pipefail

# Checkout build dependencies for SourceMod CSS v34.

DEPS="${1:?deps directory required}"
mkdir -p "$DEPS"
cd "$DEPS"

clone_repo() {
  local name="$1"
  local url="$2"
  local branch="${3:-}"

  if [ ! -d "$name/.git" ]; then
    if [ -n "$branch" ]; then
      git clone --depth 1 --branch "$branch" "$url" "$name"
    else
      git clone --depth 1 "$url" "$name"
    fi
  fi
}

if [ ! -d "mysql-5.5" ]; then
  curl -fsSL -o mysql.tar.gz \
    https://cdn.mysql.com/archives/mysql-5.6/mysql-5.6.15-linux-glibc2.5-i686.tar.gz
  tar xzf mysql.tar.gz
  mv mysql-5.6.15-linux-glibc2.5-i686 mysql-5.5
  rm mysql.tar.gz
fi

clone_repo "mmsource-1.10" "https://github.com/alliedmodders/metamod-source" "1.10-dev"
clone_repo "hl2sdk-ep1c" "https://github.com/rom4s/hl2sdk-ep1c"
clone_repo "hl2sdk-episode1" "https://github.com/alliedmodders/hl2sdk" "episode1"

patch_hl2sdk() {
  local sdk_dir="$1"
  local platform_h="$sdk_dir/public/tier0/platform.h"

  if [ -f "$platform_h" ] && grep -q '#include <new.h>' "$platform_h"; then
    sed -i 's|#include <new.h>|#if defined(_WIN32)\n#include <new.h>\n#else\n#include <new>\n#endif|' "$platform_h"
  fi
}

fix_appframework_case() {
  local sdk_dir="$1/appframework"
  [ -d "$sdk_dir" ] || return 0

  ln -sfn iappsystem.h "$sdk_dir/IAppSystem.h" 2>/dev/null || true
  ln -sfn iappsystemgroup.h "$sdk_dir/IAppSystemGroup.h" 2>/dev/null || true
  ln -sfn appframework.h "$sdk_dir/AppFramework.h" 2>/dev/null || true
}

patch_hl2sdk "hl2sdk-ep1c"
fix_appframework_case "hl2sdk-ep1c/public"

if [ ! -e "hl2sdk-ep1" ]; then
  cp -a hl2sdk-episode1 hl2sdk-ep1
fi

if ! python3 -c "import ambuild2" 2>/dev/null; then
  clone_repo "ambuild" "https://github.com/alliedmodders/ambuild" "master"
  python3 -m pip install --user ./ambuild
fi
