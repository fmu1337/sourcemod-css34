#!/usr/bin/env bash
set -euo pipefail

DEPS="${1:?deps directory required}"
BUILDER_DIR="${2:?builder directory required}"
BUILD_PLATFORM="${BUILD_PLATFORM:-linux}"
export BUILD_PLATFORM

mkdir -p "$DEPS"

# Fail closed if a downloaded tarball does not match the pinned digest.
# fetch_pinned also serves offline rebuilds from a frozen line's input archive.
# shellcheck source=fetch-pinned.sh
source "$BUILDER_DIR/fetch-pinned.sh"
fetch_verified() { fetch_pinned "$@"; }

# Built prefixes (zlib, OpenSSL, MariaDB Connector/C, MySQL SDK) carry a stamp
# with the digest of every input that decides them (builder/deps_cache.py: build
# image, deps path, these scripts with their version and sha256 pins). A prefix
# is reused only when that stamp matches this build, whether it is left over from
# an earlier build or restored by ci.yml's deps cache; otherwise it is rebuilt.
# Freeze builds (CSS34_OFFLINE, CSS34_SAVE_DOWNLOADS) never reuse.
DEPS_DIGEST=""
deps_digest() {
  if [[ -z "$DEPS_DIGEST" ]]; then
    local image="${CSS34_BUILD_IMAGE:-}"
    # Outside builder/docker/build.sh: tie the stamps to this host's compiler.
    [[ -n "$image" ]] || image="host:$(uname -m):$("${CC:-gcc}" --version 2>/dev/null | head -1)"
    DEPS_DIGEST="$(bash "$BUILDER_DIR/py.sh" "$BUILDER_DIR/deps_cache.py" digest \
      --root "$BUILDER_DIR/.." --image "$image" --deps-dir "$(cd "$DEPS" && pwd)")"
    echo "==> Deps inputs digest ${DEPS_DIGEST}"
  fi
}
deps_reusable() { # PREFIX REQUIRED_FILE...
  deps_digest
  bash "$BUILDER_DIR/py.sh" "$BUILDER_DIR/deps_cache.py" check "$1" "$DEPS_DIGEST" "${@:2}"
}
deps_stamp() { # PREFIX
  deps_digest
  bash "$BUILDER_DIR/py.sh" "$BUILDER_DIR/deps_cache.py" stamp "$1" "$DEPS_DIGEST"
}

# The sm13 MariaDB archive uses zlib. Embed a pinned PIC build so the
# extension has no unversioned compression imports or additional runtime ABI.
install_zlib() {
  local prefix="$DEPS/zlib"
  local tarball="$DEPS/zlib-1.3.1.tar.gz"
  if deps_reusable "$prefix" lib/libz.a include/zlib.h; then
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
  deps_stamp "$prefix"
}

# OpenSSL 3.x's Configure (IPC::Cmd) and Makefile template (Time::Piece) need
# perl modules that CentOS 7 splits out of the image's perl 5.16.3-299.el7_9.
# Extract the matching CentOS 7.9 i386 RPMs (pinned; build time only, nothing is
# installed into the image) and expose them through PERL5LIB for OpenSSL alone.
CSS34_PERL_RPM_BASE="https://vault.centos.org/altarch/7.9.2009"
CSS34_PERL_RPMS=(
  "os perl-ExtUtils-MakeMaker-6.68-3.el7.noarch.rpm d3ae58b2bad3b494352f86e35d098f251ec527cd5a3d66ca820c4898e4c9ec68"
  "os perl-IPC-Cmd-0.80-4.el7.noarch.rpm b47d1612ddc56b12e176de011456c1b141e5661418f2ae6e8340ce652e9d2682"
  "updates perl-Locale-Maketext-Simple-0.21-299.el7_9.noarch.rpm d357914edfc5e38eb99a385b00d0fb43d1c581d9af1d12406c5dbae63542e08e"
  "os perl-Module-Load-0.24-3.el7.noarch.rpm b0dc38a60ddf72cd3d030df03b1497d7e1fe6542491ac91e021b6afbdd642de9"
  "os perl-Module-Load-Conditional-0.54-3.el7.noarch.rpm 3d772781a375a5cecfef82aaed2158a15f2882407317d495fdf19bbf1b4e3118"
  "os perl-Module-Metadata-1.000018-2.el7.noarch.rpm 85c7125288c6cc926e4a5ec009a3f1240c7fdbf4140b4728be2e4860f53cc4a2"
  "os perl-Params-Check-0.38-2.el7.noarch.rpm a9e44da66f5fd0d7076d1c9220ad49559c49251fd2035f3044e9f9ab5b81e849"
  "updates perl-Time-Piece-1.20.1-299.el7_9.i686.rpm 67eb8ee1ea0c2c6e0fd97713cc50e5f5ad12898f4adb0acb79a4156325aa9352"
  "os perl-version-0.99.07-6.el7.i686.rpm 3f38cf841317dbb219f3971be10ced9e5d5d055dda33293d718d79037e7365aa"
)
install_build_perl() {
  local prefix="$DEPS/build-perl"
  local stamp="$prefix/.css34-build-perl-el7.9-v1"
  # Time::Piece and version are XS modules built for exactly this perl.
  local perl_version
  perl_version="$(perl -e 'printf "%vd", $^V')"
  if [[ "$perl_version" != 5.16.3 ]]; then
    echo "FAIL: build image perl is ${perl_version}, the pinned el7 perl modules need 5.16.3" >&2
    exit 1
  fi
  if [[ ! -f "$stamp" ]]; then
    echo "==> Extracting pinned CentOS 7.9 perl modules for the OpenSSL build"
    rm -rf "$prefix"
    mkdir -p "$prefix"
    local entry repo rpm sha
    for entry in "${CSS34_PERL_RPMS[@]}"; do
      read -r repo rpm sha <<< "$entry"
      fetch_verified "$CSS34_PERL_RPM_BASE/$repo/i386/Packages/$rpm" "$DEPS/$rpm" "$sha"
      (cd "$prefix" && rpm2cpio "$DEPS/$rpm" | cpio -idm --quiet)
      rm -f "$DEPS/$rpm"
    done
    touch "$stamp"
  fi
  CSS34_BUILD_PERL5LIB="$prefix/usr/share/perl5/vendor_perl:$prefix/usr/lib/perl5/vendor_perl:$prefix/usr/share/perl5:$prefix/usr/lib/perl5"
  PERL5LIB="$CSS34_BUILD_PERL5LIB" perl -MIPC::Cmd -MTime::Piece -e 1 || {
    echo "FAIL: the extracted perl modules do not load" >&2
    exit 1
  }
}

# Static OpenSSL 3.5 LTS for the MariaDB connector of the sm13 mysql extension
# (CentOS 7 only ships 1.0.2). Linux only: Windows' connector uses Schannel.
OPENSSL_VERSION=3.5.9
install_openssl() {
  local prefix="$DEPS/openssl"
  local tarball="$DEPS/openssl-${OPENSSL_VERSION}.tar.gz"
  local sha="603f5602e2eef00d77fbd429d34dcd5822bb301757a1bc9cdb24c670f1eb859a"
  if deps_reusable "$prefix" lib/libssl.a lib/libcrypto.a include/openssl/opensslv.h; then
    echo "==> OpenSSL ${OPENSSL_VERSION} already built at $prefix"
    return
  fi
  install_build_perl
  echo "==> Building static OpenSSL ${OPENSSL_VERSION}"
  fetch_verified \
    "https://github.com/openssl/openssl/releases/download/openssl-${OPENSSL_VERSION}/openssl-${OPENSSL_VERSION}.tar.gz" \
    "$tarball" "$sha"
  rm -rf "$DEPS/openssl-${OPENSSL_VERSION}" "$prefix"
  tar -C "$DEPS" -xzf "$tarball"
  (
    cd "$DEPS/openssl-${OPENSSL_VERSION}"
    export PERL5LIB="$CSS34_BUILD_PERL5LIB"
    bash "$BUILDER_DIR/py.sh" "$BUILDER_DIR/patches/patch-openssl-getentropy.py" "$PWD"
    ./Configure linux-elf no-shared no-tests no-dso -fPIC --prefix="$prefix" --libdir=lib
    make -j"$(nproc)"
    # Exercise the retained OS entropy path; never accept a seedless build.
    ./apps/openssl rand -hex 32 >/dev/null
    # The libc getentropy probe must be gone (glibc 2.17 has none).
    if nm -A libcrypto.a libssl.a 2>/dev/null | awk '$NF == "getentropy"' | grep -q .; then
      echo "FAIL: OpenSSL still references getentropy" >&2
      exit 1
    fi
    make install_sw
  )
  rm -rf "$DEPS/openssl-${OPENSSL_VERSION}" "$tarball"
  deps_stamp "$prefix"
}

# MariaDB Connector/C (SM 1.13 7461+, --mariadb-path). AlliedModders' Linux
# archive is compiled against Debian 11's OpenSSL 1.1.1 headers: linked with
# OpenSSL 3 it leaves EVP_PKEY_size and SSL_get_peer_certificate undefined (macros
# in 3.x) and passes a 32-bit SSL_CTX_set_options argument (uint64_t in 3.x).
# Build the same 3.4.9 source (MariaDB's signed tarball, identical to the v3.4.9
# tag AlliedModders' v3.4.9-sm.5 builds) with that release's options, against
# the OpenSSL above and the PIC zlib, in this glibc 2.17 image.
install_mariadb_connector_linux() {
  local prefix="$1"
  local src="$DEPS/mariadb-connector-c-${MARIADB_CONNECTOR_VERSION}-src"
  local tarball="$src.tar.gz"
  if deps_reusable "$prefix" lib/libmariadbclient.a include/mariadb/mysql.h; then
    echo "==> MariaDB Connector/C ${MARIADB_CONNECTOR_VERSION} already built at $prefix"
    return
  fi
  echo "==> Building MariaDB Connector/C ${MARIADB_CONNECTOR_VERSION} against OpenSSL ${OPENSSL_VERSION}"
  fetch_verified \
    "https://archive.mariadb.org/connector-c-${MARIADB_CONNECTOR_VERSION}/mariadb-connector-c-${MARIADB_CONNECTOR_VERSION}-src.tar.gz" \
    "$tarball" "a84bba97e59b6a322637a189964d4fd72bd8d92f2d22a9f8d6a5f0657c821e97"
  rm -rf "$src" "$prefix"
  tar -C "$DEPS" -xzf "$tarball"
  cmake -S "$src" -B "$src/build" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_COMPILER="${CC:-gcc}" \
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    -DCMAKE_INSTALL_PREFIX="$prefix" \
    -DINSTALL_LAYOUT=DEFAULT \
    -DINSTALL_LIBDIR=lib \
    -DWITH_UNIT_TESTS=OFF \
    -DWITH_CURL=OFF \
    -DWITH_SSL=OPENSSL \
    -DOPENSSL_ROOT_DIR="$DEPS/openssl" \
    -DOPENSSL_USE_STATIC_LIBS=ON \
    -DWITH_EXTERNAL_ZLIB=ON \
    -DZLIB_ROOT="$DEPS/zlib" \
    -DZLIB_USE_STATIC_LIBS=ON \
    -DCLIENT_PLUGIN_CACHING_SHA2_PASSWORD=STATIC
  # The TLS backend must be the OpenSSL above, not a system copy.
  grep -Fq "OPENSSL_INCLUDE_DIR:PATH=$DEPS/openssl/include" "$src/build/CMakeCache.txt" || {
    echo "FAIL: MariaDB Connector/C did not configure against $DEPS/openssl" >&2
    exit 1
  }
  cmake --build "$src/build" --parallel "$(nproc)" --target mariadbclient
  # Headers only (the Development component also wants the shared library).
  cmake -DCMAKE_INSTALL_PREFIX="$prefix" -DCMAKE_INSTALL_COMPONENT=Development \
    -P "$src/build/include/cmake_install.cmake"
  mkdir -p "$prefix/lib"
  cp "$src/build/libmariadb/libmariadbclient.a" "$prefix/lib/"
  test -f "$prefix/include/mariadb/mysql.h"
  rm -rf "$src" "$tarball"
  deps_stamp "$prefix"
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

# MariaDB Connector/C is only needed when configure.py exposes --mariadb-path (7461+).
# Its Linux build is the only user of OpenSSL: sm12's MySQL 5.6 client bundles
# yaSSL, libpq is built without SSL, Windows' connector uses Schannel.
MARIADB_CONNECTOR_VERSION=3.4.9
MARIADB_CONNECTOR_RELEASE=3.4.9-sm.5
MARIADB_DIR="$DEPS/mariadb-connector-c-${MARIADB_CONNECTOR_VERSION}-x86"
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

if [ "$BUILD_PLATFORM" != "windows" ]; then
  install_zlib
  # builder/run/linux.sh sources this: the static PIC zlib for every line's
  # -lz, OpenSSL only where the MariaDB connector links -lssl/-lcrypto.
  static_include="$DEPS/zlib/include"
  static_lib="$DEPS/zlib/lib"
  if [ "$need_mariadb" = 1 ]; then
    install_openssl
    install_mariadb_connector_linux "$MARIADB_DIR"
    static_include="$DEPS/openssl/include:$static_include"
    static_lib="$DEPS/openssl/lib:$static_lib"
  fi
  rm -f "$DEPS/openssl.env"
  cat > "$DEPS/static-deps.env" <<EOF
export CPATH="$static_include"
export LIBRARY_PATH="$static_lib"
EOF
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
  if ! deps_reusable "$DEPS/mysql-5.5" lib/libmysqlclient_r.a include/mysql.h; then
    fetch_verified \
      "https://cdn.mysql.com/archives/mysql-5.6/mysql-5.6.15-linux-glibc2.5-i686.tar.gz" \
      "$DEPS/mysql.tar.gz" \
      "eddb727dc82a24c8ffe58f6b698d93be905e6912a4fa7ece5fbb526103a8908f"
    tar -C "$DEPS" -xzf "$DEPS/mysql.tar.gz"
    rm -rf "$DEPS/mysql-5.5"
    mv "$DEPS/mysql-5.6.15-linux-glibc2.5-i686" "$DEPS/mysql-5.5"
    rm -f "$DEPS/mysql.tar.gz"
    deps_stamp "$DEPS/mysql-5.5"
  fi
fi

if [ "$need_mariadb" = 1 ] && [ "$BUILD_PLATFORM" = "windows" ]; then
  echo "==> Fetching MariaDB Connector/C ${MARIADB_CONNECTOR_VERSION} (SM 1.13+, Schannel)"
  if [ ! -f "$MARIADB_DIR/lib/mariadbclient.lib" ] && [ ! -f "$MARIADB_DIR/lib/libmariadb.lib" ]; then
    fetch_verified \
      "https://github.com/alliedmodders/mariadb-connector-c/releases/download/v${MARIADB_CONNECTOR_RELEASE}/mariadb-connector-c-${MARIADB_CONNECTOR_VERSION}-windows-x86.zip" \
      "$DEPS/mariadb-connector.zip" \
      "f8bd30653418db166a09f800c685f9cef7c133e2d0aa6a41c14beb6e41e43a23"
    rm -rf "$MARIADB_DIR"
    unzip -q -o "$DEPS/mariadb-connector.zip" -d "$DEPS"
    rm -f "$DEPS/mariadb-connector.zip"
  fi
fi

echo "==> Fetching Metamod:Source"
# MMS_MODE / MMS_DIRNAME / MMS_COMMIT / MMS_BRANCH: the line's primary Metamod
# (resolve-version.sh, via builder/run/*.sh).
: "${MMS_MODE:?MMS_MODE is required (source builder/resolve-version.sh)}"
: "${MMS_DIRNAME:?MMS_DIRNAME is required}" "${MMS_COMMIT:?MMS_COMMIT is required}"
MMS_BRANCH="${MMS_BRANCH:-}"

# The Metamod patch series made for <commit> (builder/patches/series/*/series.json
# with root "metamod"), or nothing.
mm_series_for() {
  local manifest
  for manifest in "$BUILDER_DIR"/patches/series/*/series.json; do
    [[ -f "$manifest" ]] || continue
    if python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if d.get("root") == "metamod" and d.get("commit") == sys.argv[2] else 1)' "$manifest" "$1"; then
      dirname "$manifest"
      return 0
    fi
  done
}

fetch_and_patch_mms() {
  local dirname="$1"
  local mode="$2"
  local branch="$3"
  local commit="$4"

  local series=""
  if [[ "$mode" == 1.12 ]]; then
    series="$(mm_series_for "$commit")"
    [[ -n "$series" ]] || {
      echo "FAIL: no Metamod patch series for $commit (builder/patches/series/MM_*/);" \
        "run builder/scripts/patch-series.sh refresh <MM pin> after a pin bump" >&2
      exit 1
    }
    # Exactly the pinned tree, LF as committed (also on Windows), even in a
    # reused deps directory: the series applies only to that.
    SOURCEMOD_URL="https://github.com/alliedmodders/metamod-source" \
      bash "$BUILDER_DIR/fetch-sourcemod.sh" "$DEPS/$dirname" "$commit" Metamod:Source
  else
    clone_repo "$dirname" "https://github.com/alliedmodders/metamod-source" "$branch" "$commit"
  fi
  echo "==> Metamod:Source (${mode}) in $dirname at $(git -C "$DEPS/$dirname" rev-parse HEAD)"

  case "$mode" in
    1.10)
      MMS_DIR="$DEPS/$dirname" bash "$BUILDER_DIR/patches/apply-mmsource-css34.sh" "$DEPS/$dirname"
      ;;
    1.12)
      # T3.4: the pin's patch series, then the legacy-plugin bridge (our own code).
      bash "$BUILDER_DIR/patches/apply-series.sh" "$series" "$DEPS/$dirname"
      bash "$BUILDER_DIR/patches/apply-mmsource-oldbridge.sh" modern "$DEPS/$dirname"
      ;;
    *)
      echo "Unsupported MMS_MODE=$mode" >&2
      exit 1
      ;;
  esac
}

# The primary Metamod (MMS_*, resolve-version.sh), then the line's
# bridge_metamod from lines.json (the MM 1.10 legacy core of the MM 1.12
# package, legacy-plugin bridge T2.9).
fetch_and_patch_mms "$MMS_DIRNAME" "$MMS_MODE" "$MMS_BRANCH" "$MMS_COMMIT"
mm_inputs="$(bash "$BUILDER_DIR/py.sh" "$BUILDER_DIR/resolve-metamod-pins.py" "${CSS34_LINE:-sm13-latest}")" ||
  { echo "FAIL: cannot resolve the Metamod inputs of ${CSS34_LINE:-sm13-latest}" >&2; exit 1; }
while IFS=$'\t' read -r role dirname mode branch commit rev version; do
  [[ -n "$role" && "$role" != primary ]] || continue
  fetch_and_patch_mms "$dirname" "$mode" "$branch" "$commit"
done <<< "$mm_inputs"

# Pinned 2026-10-20 (episode1 tip). Override only to reproduce another tree.
HL2SDK_EPISODE1_COMMIT="${HL2SDK_EPISODE1_COMMIT:-4b0cde271be6806b95842e78348009712a8b3fbe}"
AMBUILD_COMMIT="${AMBUILD_COMMIT:-01212cb57c96561f664b6dfb2ee10e66de6f81e4}"

echo "==> Fetching HL2SDK episode1 @ ${HL2SDK_EPISODE1_COMMIT}"
rm -rf "$DEPS/hl2sdk-episode1"
clone_repo "hl2sdk-episode1" "https://github.com/alliedmodders/hl2sdk" "" "$HL2SDK_EPISODE1_COMMIT"
if [[ "$(git -C "$DEPS/hl2sdk-episode1" rev-parse HEAD)" != "$HL2SDK_EPISODE1_COMMIT" ]]; then
  echo "FAIL: hl2sdk-episode1 is not ${HL2SDK_EPISODE1_COMMIT}" >&2
  exit 1
fi
patch_episode1_sdk "$DEPS/hl2sdk-episode1"

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
  css34_fetch_build_wheels "$DEPS"
  python3 -m pip install --force-reinstall --no-cache-dir --user --no-index --find-links "$DEPS/wheels" "$DEPS/ambuild"
fi
if ! python -c "import ambuild2" 2>/dev/null && ! python3 -c "import ambuild2" 2>/dev/null; then
  if [ "$BUILD_PLATFORM" = "windows" ]; then
    python -m pip install "$DEPS/ambuild"
  else
    python3 -m pip install --user --no-index --find-links "$DEPS/wheels" "$DEPS/ambuild"
  fi
fi
