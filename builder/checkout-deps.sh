#!/usr/bin/env bash
set -euo pipefail

DEPS="${1:?deps directory required}"
BUILDER_DIR="${2:?builder directory required}"
BUILD_PLATFORM="${BUILD_PLATFORM:-linux}"
export BUILD_PLATFORM

mkdir -p "$DEPS"

# Fail closed if a downloaded tarball does not match the pinned digest.
fetch_verified() {
  local url="$1"
  local dest="$2"
  local expect="$3"
  local got
  curl -fsSL --retry 3 --retry-delay 2 -o "$dest" "$url"
  got="$(sha256sum "$dest" | awk '{print $1}')"
  if [[ "$got" != "$expect" ]]; then
    echo "FAIL: sha256 mismatch for ${dest}" >&2
    echo "  url:      ${url}" >&2
    echo "  expected: ${expect}" >&2
    echo "  got:      ${got}" >&2
    rm -f "$dest"
    exit 1
  fi
}

# The sm13 MariaDB archive uses zlib. Embed a pinned PIC build so the
# extension has no unversioned compression imports or additional runtime ABI.
install_zlib() {
  local prefix="$DEPS/zlib"
  local stamp="$prefix/.css34-zlib-1.3.1-pic"
  local tarball="$DEPS/zlib-1.3.1.tar.gz"
  if [[ -f "$stamp" && -f "$prefix/lib/libz.a" ]]; then
    echo "==> Static PIC zlib 1.3.1 already built at $prefix"
    return
  fi
  fetch_verified \
    "https://github.com/madler/zlib/releases/download/v1.3.1/zlib-1.3.1.tar.gz" \
    "$tarball" "9a93b2b7dfdac77ceba5a558a580e74667dd6fede4585b91eefb60f03b72df23"
  rm -rf "$DEPS/zlib-1.3.1" "$prefix"
  tar -C "$DEPS" -xzf "$tarball"
  (
    cd "$DEPS/zlib-1.3.1"
    CFLAGS="${CFLAGS:-} -O2 -fPIC" ./configure --static --prefix="$prefix"
    make -j"$(nproc)"
    make check
    make install
  )
  rm -rf "$DEPS/zlib-1.3.1" "$tarball"
  touch "$stamp"
}

# Static OpenSSL 1.1.1w. CentOS 7 only ships 1.0.2, and the MariaDB connector
# links -lssl/-lcrypto. OpenSSL 3.x needs perl modules this image does not have.
install_openssl_111w() {
  local prefix="$DEPS/openssl"
  local stamp="$prefix/.css34-openssl-1.1.1w-linux-syscall-v1"
  local tarball="$DEPS/openssl-1.1.1w.tar.gz"
  local sha="cf3098950cb4d853ad95c0841f1f9c6d3dc102dccfcacd521d93925208b76ac8"
  if [[ -f "$stamp" && -f "$prefix/lib/libssl.a" && -f "$prefix/lib/libcrypto.a" ]]; then
    echo "==> OpenSSL 1.1.1w already built at $prefix"
  else
    echo "==> Building static OpenSSL 1.1.1w"
    fetch_verified "https://www.openssl.org/source/openssl-1.1.1w.tar.gz" "$tarball" "$sha"
    rm -rf "$DEPS/openssl-1.1.1w" "$prefix"
    tar -C "$DEPS" -xzf "$tarball"
    (
      cd "$DEPS/openssl-1.1.1w"
      bash "$BUILDER_DIR/py.sh" "$BUILDER_DIR/patches/patch-openssl-getentropy.py" "$PWD"
      ./Configure linux-elf no-shared no-tests no-dso -fPIC --prefix="$prefix"
      make -j"$(nproc)"
      # Exercise the retained OS entropy path; never accept a seedless build.
      ./apps/openssl rand -hex 32 >/dev/null
      make install_sw
    )
    rm -rf "$DEPS/openssl-1.1.1w" "$tarball"
    touch "$stamp"
  fi
  cat > "$DEPS/openssl.env" <<EOF
export CPATH="$prefix/include:$DEPS/zlib/include"
export LIBRARY_PATH="$prefix/lib:$DEPS/zlib/lib"
EOF
}

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

if [ "$BUILD_PLATFORM" != "windows" ]; then
  install_zlib
  install_openssl_111w
fi

echo "==> Fetching MySQL client SDK"
if [ "$BUILD_PLATFORM" = "windows" ]; then
  if [ ! -f "$DEPS/mysql-5.5/lib/mysqlclient.lib" ] && [ ! -f "$DEPS/mysql-5.5/lib/libmysql.lib" ]; then
    fetch_verified \
      "https://cdn.mysql.com/archives/mysql-5.5/mysql-5.5.54-win32.zip" \
      "$DEPS/mysql.zip" \
      "385e6e14bc5a0a2af423228ab3f248035b17ff569e8ca2599be4ba7fff67c750"
    rm -rf "$DEPS/mysql-5.5"
    unzip -q -o "$DEPS/mysql.zip" -d "$DEPS"
    mv "$DEPS/mysql-5.5.54-win32" "$DEPS/mysql-5.5"
    rm -f "$DEPS/mysql.zip"
  fi
else
  if [ ! -f "$DEPS/mysql-5.5/lib/libmysqlclient_r.a" ]; then
    fetch_verified \
      "https://cdn.mysql.com/archives/mysql-5.6/mysql-5.6.15-linux-glibc2.5-i686.tar.gz" \
      "$DEPS/mysql.tar.gz" \
      "eddb727dc82a24c8ffe58f6b698d93be905e6912a4fa7ece5fbb526103a8908f"
    tar -C "$DEPS" -xzf "$DEPS/mysql.tar.gz"
    rm -rf "$DEPS/mysql-5.5"
    mv "$DEPS/mysql-5.6.15-linux-glibc2.5-i686" "$DEPS/mysql-5.5"
    rm -f "$DEPS/mysql.tar.gz"
  fi
fi

# MariaDB Connector/C is only needed when configure.py exposes --mariadb-path (7461+).
MARIADB_CONNECTOR_VERSION="${MARIADB_CONNECTOR_VERSION:-3.4.9}"
MARIADB_CONNECTOR_RELEASE="${MARIADB_CONNECTOR_RELEASE:-3.4.9-sm.5}"
need_mariadb=0
sm_configure=""
for candidate in "${SOURCEMOD_DIR:-}" "${WDIR:-}/sourcemod"; do
  if [ -n "$candidate" ] && [ -f "$candidate/configure.py" ]; then
    sm_configure="$candidate/configure.py"
    break
  fi
done
if [ -n "$sm_configure" ] && grep -q 'mariadb-path' "$sm_configure"; then
  need_mariadb=1
fi
if [ "$need_mariadb" = 1 ]; then
  echo "==> Fetching MariaDB Connector/C ${MARIADB_CONNECTOR_VERSION} (SM 1.13+)"
  MARIADB_DIR="$DEPS/mariadb-connector-c-${MARIADB_CONNECTOR_VERSION}-x86"
  if [ "$BUILD_PLATFORM" = "windows" ]; then
    if [ ! -f "$MARIADB_DIR/lib/mariadbclient.lib" ] && [ ! -f "$MARIADB_DIR/lib/libmariadb.lib" ]; then
      fetch_verified \
        "https://github.com/alliedmodders/mariadb-connector-c/releases/download/v${MARIADB_CONNECTOR_RELEASE}/mariadb-connector-c-${MARIADB_CONNECTOR_VERSION}-windows-x86.zip" \
        "$DEPS/mariadb-connector.zip" \
        "f8bd30653418db166a09f800c685f9cef7c133e2d0aa6a41c14beb6e41e43a23"
      rm -rf "$MARIADB_DIR"
      unzip -q -o "$DEPS/mariadb-connector.zip" -d "$DEPS"
      rm -f "$DEPS/mariadb-connector.zip"
    fi
  elif [ ! -f "$MARIADB_DIR/lib/libmariadbclient.a" ]; then
    fetch_verified \
      "https://github.com/alliedmodders/mariadb-connector-c/releases/download/v${MARIADB_CONNECTOR_RELEASE}/mariadb-connector-c-${MARIADB_CONNECTOR_VERSION}-linux-x86.tar.gz" \
      "$DEPS/mariadb-connector.tar.gz" \
      "147d96bd4fb3579acd99e6a8eed327f58c3b0c05544decb0d98ce434f3826ee6"
    tar -C "$DEPS" -xzf "$DEPS/mariadb-connector.tar.gz"
    rm -f "$DEPS/mariadb-connector.tar.gz"
  fi
fi

echo "==> Fetching Metamod:Source"
# MMS_MODE / MMS_DIRNAME / MMS_COMMIT come from resolve-version.sh (or env).
MMS_MODE="${MMS_MODE:-}"
MMS_DIRNAME="${MMS_DIRNAME:-}"
MMS_COMMIT="${MMS_COMMIT:-}"
MMS_BRANCH="${MMS_BRANCH:-}"

if [[ -z "$MMS_MODE" || -z "$MMS_DIRNAME" || -z "$MMS_COMMIT" ]]; then
  if [ "${SOURCEMOD_MAJOR:-11}" -ge 12 ]; then
    MMS_COMMIT="${MMS_COMMIT:-cb47755826fad1483291e5dc00222aa64303d12f}"
    MMS_BRANCH="${MMS_BRANCH:-1.12-dev}"
    MMS_DIRNAME="${MMS_DIRNAME:-mmsource-1.12}"
    MMS_MODE="${MMS_MODE:-1.12}"
  else
    MMS_COMMIT="${MMS_COMMIT:-80e8ff0be3b62386bbd6f937e97b819ef8be6dd2}"
    MMS_BRANCH="${MMS_BRANCH:-1.10-dev}"
    MMS_DIRNAME="${MMS_DIRNAME:-mmsource-1.10}"
    MMS_MODE="${MMS_MODE:-1.10}"
  fi
fi

clone_repo "$MMS_DIRNAME" "https://github.com/alliedmodders/metamod-source" "$MMS_BRANCH" "$MMS_COMMIT"
echo "==> Metamod:Source (${MMS_MODE}) at $(git -C "$DEPS/$MMS_DIRNAME" rev-parse HEAD)"

case "$MMS_MODE" in
  1.10)
    MMS_DIR="$DEPS/$MMS_DIRNAME" bash "$BUILDER_DIR/patches/apply-mmsource-css34.sh" "$DEPS/$MMS_DIRNAME"
    ;;
  1.11)
    bash "$BUILDER_DIR/patches/apply-mmsource-v111.sh" "$DEPS/$MMS_DIRNAME"
    ;;
  1.12|2.0)
    git -C "$DEPS/$MMS_DIRNAME" submodule update --init --recursive
    bash "$BUILDER_DIR/patches/apply-mmsource-v112.sh" "$DEPS/$MMS_DIRNAME"
    ;;
  *)
    echo "Unsupported MMS_MODE=$MMS_MODE" >&2
    exit 1
    ;;
esac

# Pinned 2026-10-20 (episode1 / ep1c tips). Override only to reproduce another tree.
HL2SDK_EPISODE1_COMMIT="${HL2SDK_EPISODE1_COMMIT:-4b0cde271be6806b95842e78348009712a8b3fbe}"
HL2SDK_EP1C_COMMIT="${HL2SDK_EP1C_COMMIT:-fd7c497104abcc3537c6732465ad8c623e2c40aa}"
AMBUILD_COMMIT="${AMBUILD_COMMIT:-01212cb57c96561f664b6dfb2ee10e66de6f81e4}"

echo "==> Fetching HL2SDK episode1 @ ${HL2SDK_EPISODE1_COMMIT}"
rm -rf "$DEPS/hl2sdk-episode1"
clone_repo "hl2sdk-episode1" "https://github.com/alliedmodders/hl2sdk" "" "$HL2SDK_EPISODE1_COMMIT"
if [[ "$(git -C "$DEPS/hl2sdk-episode1" rev-parse HEAD)" != "$HL2SDK_EPISODE1_COMMIT" ]]; then
  echo "FAIL: hl2sdk-episode1 is not ${HL2SDK_EPISODE1_COMMIT}" >&2
  exit 1
fi
patch_episode1_sdk "$DEPS/hl2sdk-episode1"

echo "==> Fetching rom4s/hl2sdk-ep1c @ ${HL2SDK_EP1C_COMMIT} as hl2sdk-ep1"
rm -rf "$DEPS/hl2sdk-ep1"
clone_repo "hl2sdk-ep1" "https://github.com/rom4s/hl2sdk-ep1c" "" "$HL2SDK_EP1C_COMMIT"
if [[ "$(git -C "$DEPS/hl2sdk-ep1" rev-parse HEAD)" != "$HL2SDK_EP1C_COMMIT" ]]; then
  echo "FAIL: hl2sdk-ep1c is not ${HL2SDK_EP1C_COMMIT}" >&2
  exit 1
fi
# ep1c does not ship tier0/vstdlib; use episode1's real .so so the linker records DT_NEEDED.
export HL2SDK_EPISODE1_LINUX_SDK="$DEPS/hl2sdk-episode1/linux_sdk"
"$BUILDER_DIR/patches/apply-hl2sdk-ep1c.sh" "$DEPS/hl2sdk-ep1"

echo "==> Fetching AMBuild @ ${AMBUILD_COMMIT}"
# Tag 2.2 is too old for current hl2sdk-manifests. One SHA serves every line.
if [[ "$(git -C "$DEPS/ambuild" rev-parse HEAD 2>/dev/null || true)" != "$AMBUILD_COMMIT" ]]; then
  rm -rf "$DEPS/ambuild"
  clone_repo "ambuild" "https://github.com/alliedmodders/ambuild" "" "$AMBUILD_COMMIT"
fi
if [[ "$(git -C "$DEPS/ambuild" rev-parse HEAD)" != "$AMBUILD_COMMIT" ]]; then
  echo "FAIL: AMBuild is not ${AMBUILD_COMMIT}" >&2
  exit 1
fi
if [ "$BUILD_PLATFORM" = "windows" ]; then
  python -m pip install --force-reinstall --no-cache-dir "$DEPS/ambuild"
else
  python3 -m pip install --force-reinstall --no-cache-dir --user "$DEPS/ambuild"
fi
if ! python -c "import ambuild2" 2>/dev/null && ! python3 -c "import ambuild2" 2>/dev/null; then
  if [ "$BUILD_PLATFORM" = "windows" ]; then
    python -m pip install "$DEPS/ambuild"
  else
    python3 -m pip install --user "$DEPS/ambuild"
  fi
fi
