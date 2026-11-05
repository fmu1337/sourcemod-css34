#!/usr/bin/env bash
# Build the third-party Socket extension (JoinedSenses/sm-ext-socket, "Socket (3.0.2)")
# against a line's SourceMod tree. Runs inside the release image (manylinux2014 i686,
# devtoolset-10 GCC 10.2.1, glibc 2.17) through builder/third-party/build.sh, after
# builder/docker/build.sh left the line's patched tree in sourcemod/ and its package
# build (spcomp) in sourcemod/build/package.
#
# Output (never part of the SourceMod package):
#   packages/third-party/socket-<ver>-git<rev>-<line>-linux.tar.gz
#       addons/sourcemod/extensions/socket.ext.so
#       addons/sourcemod/scripting/include/socket.inc
#       addons/sourcemod/licenses/socket/{LICENSE,css34-socket.json}
#   packages/third-party/socket-<ver>-git<rev>-<line>-linux.json  (same manifest)
#   packages/test-plugins/css34_socket_probe.smx                   (never released)
#
# Changes to upstream, all made here so the pinned source stays verifiable:
#   - sdk/smsdk_ext.h / .cpp come from the line's sourcemod/public (upstream ships
#     an old smsdk_ext.cpp; its smsdk_config.h is kept), so the extension API matches.
#   - boost::thread / mutex / shared_mutex and their locks become C++17 std::
#     types, so no boost library is compiled or linked; asio stays header-only.
set -euo pipefail

WDIR="${WDIR:-/workspace}"
DEPS_DIR="${DEPS_DIR:-$WDIR/deps}"
PACKAGES_DIR="${PACKAGES_DIR:-$WDIR/packages}"
SOURCEMOD_DIR="${SOURCEMOD_DIR:-$WDIR/sourcemod}"
CSS34_LINE="${CSS34_LINE:?CSS34_LINE is required}"
SOURCEMOD_COMMIT="${SOURCEMOD_COMMIT:?SOURCEMOD_COMMIT is required (builder/resolve-version.sh)}"
CXX="${CXX:-g++}"

# shellcheck source=../fetch-pinned.sh
source "$WDIR/builder/fetch-pinned.sh"
# shellcheck source=socket.env
source "$WDIR/builder/third-party/socket.env"

die() { echo "FAIL: $*" >&2; exit 1; }

case " ${SOCKET_LINES} " in
  *" ${CSS34_LINE} "*) ;;
  *) die "the Socket extension is built for: ${SOCKET_LINES} (not ${CSS34_LINE})" ;;
esac

# Same toolchain as the release packages (builder/docker/build.sh checks these too).
gcc_line="$("$CXX" --version | head -1)"
[[ "$gcc_line" == *"10.2.1"* ]] || die "expected devtoolset-10 GCC 10.2.1, got: ${gcc_line}"
[[ "$(uname -m)" == i686 && "$("$CXX" -dumpmachine)" == i686-* ]] ||
  die "must build for i686 (uname=$(uname -m) dumpmachine=$("$CXX" -dumpmachine))"

# The line's SourceMod tree, at its pin with the patch series applied.
[[ -f "$SOURCEMOD_DIR/public/smsdk_ext.cpp" ]] ||
  die "$SOURCEMOD_DIR has no public/smsdk_ext.cpp: run builder/docker/build.sh for ${CSS34_LINE} first"
sm_head="$(git -C "$SOURCEMOD_DIR" rev-parse HEAD)"
[[ "$sm_head" == "$SOURCEMOD_COMMIT" ]] ||
  die "$SOURCEMOD_DIR is at ${sm_head}, ${CSS34_LINE} pins ${SOURCEMOD_COMMIT}"
sm_tree="$(git -C "$SOURCEMOD_DIR" write-tree)"
SM_PACKAGE_DIR="$SOURCEMOD_DIR/build/package/addons/sourcemod"
SPCOMP="$SM_PACKAGE_DIR/scripting/spcomp"
[[ -x "$SPCOMP" ]] || die "no $SPCOMP: run builder/docker/build.sh for ${CSS34_LINE} first"
ext_api="$(sed -nE 's/^#define[[:space:]]+SMINTERFACE_EXTENSIONAPI_VERSION[[:space:]]+([0-9]+).*/\1/p' \
  "$SOURCEMOD_DIR/public/IExtensionSys.h")"
[[ -n "$ext_api" ]] || die "cannot read SMINTERFACE_EXTENSIONAPI_VERSION"

# boost headers (pinned tarball; only boost/ is extracted).
BOOST_DIR="$DEPS_DIR/boost_${SOCKET_BOOST_VERSION//./_}"
if [[ ! -f "$BOOST_DIR/.css34-${SOCKET_BOOST_SHA256}" ]]; then
  echo "==> boost ${SOCKET_BOOST_VERSION} headers" >&2
  rm -rf "$BOOST_DIR" "$BOOST_DIR.tar.bz2"
  mkdir -p "$DEPS_DIR"
  fetch_pinned "$SOCKET_BOOST_URL" "$BOOST_DIR.tar.bz2" "$SOCKET_BOOST_SHA256"
  tar -xjf "$BOOST_DIR.tar.bz2" -C "$DEPS_DIR" "boost_${SOCKET_BOOST_VERSION//./_}/boost"
  rm -f "$BOOST_DIR.tar.bz2"
  touch "$BOOST_DIR/.css34-${SOCKET_BOOST_SHA256}"
fi

# Upstream source at the pinned commit, verified by its tree hash.
SRC="$DEPS_DIR/sm-ext-socket"
echo "==> ${SOCKET_REPO} ${SOCKET_COMMIT}" >&2
rm -rf "$SRC"
git init -q "$SRC"
git -C "$SRC" fetch -q --depth 1 "$SOCKET_REPO" "$SOCKET_COMMIT"
git -C "$SRC" checkout -q --detach FETCH_HEAD
[[ "$(git -C "$SRC" rev-parse HEAD)" == "$SOCKET_COMMIT" ]] || die "fetched the wrong commit"
tree_sha="$(cd "$SRC" && git ls-files -z | LC_ALL=C sort -z | xargs -0 sha256sum | sha256sum | awk '{print $1}')"
[[ "$tree_sha" == "$SOCKET_TREE_SHA256" ]] ||
  die "source tree sha256 ${tree_sha}, expected ${SOCKET_TREE_SHA256}"
grep -Fq "#define SMEXT_CONF_VERSION		\"${SOCKET_VERSION}\"" "$SRC/sdk/smsdk_config.h" ||
  die "sdk/smsdk_config.h does not declare version ${SOCKET_VERSION}"

# Extension API of this line: its own smsdk_ext.h / .cpp.
cp -f "$SOURCEMOD_DIR/public/smsdk_ext.h" "$SOURCEMOD_DIR/public/smsdk_ext.cpp" "$SRC/sdk/"

# boost threads and locks -> C++17.
(
  cd "$SRC"
  sed -i -E \
    -e 's@#include <boost/thread\.hpp>@#include <thread>\n#include <mutex>\n#include <shared_mutex>@' \
    -e '/#include <boost\/thread\/shared_mutex\.hpp>/d' \
    -e 's/boost::mutex::scoped_lock/std::unique_lock<std::mutex>/g' \
    -e 's/boost::(thread|mutex|shared_mutex|shared_lock|unique_lock)\b/std::\1/g' \
    ./*.cpp ./*.h
  if grep -nE 'boost::(thread|mutex|shared_mutex|shared_lock|unique_lock|this_thread)|boost/thread' ./*.cpp ./*.h; then
    die "boost thread types left after the C++17 rewrite"
  fi
)

echo "==> Compiling socket.ext.so (${CSS34_LINE}, extension API ${ext_api})" >&2
OBJ="$SRC/build"
mkdir -p "$OBJ"
CXXFLAGS=(
  -std=c++17 -O2 -fPIC -pipe -m32 -msse -mfpmath=sse
  -fvisibility=hidden -fvisibility-inlines-hidden -fno-strict-aliasing
  -Wall -Wno-unused -Wno-switch -Wno-deprecated-declarations
  -DLINUX -D_LINUX -DPOSIX -DGNUC -DCOMPILER_GCC -DHAVE_STDINT_H -DNDEBUG
  -DBOOST_BIND_GLOBAL_PLACEHOLDERS -DBOOST_ASIO_NO_TS_EXECUTORS
  -DBOOST_ERROR_CODE_HEADER_ONLY -DBOOST_SYSTEM_NO_DEPRECATED
  -I"$SRC" -I"$SRC/sdk"
  -I"$SOURCEMOD_DIR/public" -I"$SOURCEMOD_DIR/public/extensions"
  -I"$SOURCEMOD_DIR/sourcepawn/include"
  -I"$SOURCEMOD_DIR/public/amtl" -I"$SOURCEMOD_DIR/public/amtl/amtl"
  -isystem "$BOOST_DIR"
)
objs=()
for src in Extension.cpp Socket.cpp SocketHandler.cpp Callback.cpp CallbackHandler.cpp sdk/smsdk_ext.cpp; do
  obj="$OBJ/$(basename "${src%.cpp}").o"
  "$CXX" "${CXXFLAGS[@]}" -c "$SRC/$src" -o "$obj"
  objs+=("$obj")
done
# Static libstdc++/libgcc (srcds runs on glibc 2.17+ systems with any libstdc++);
# --exclude-libs keeps their symbols out of the dynamic table; -z defs proves
# that nothing outside libc/libpthread is imported.
"$CXX" -m32 -shared -o "$OBJ/socket.ext.so" "${objs[@]}" \
  -static-libstdc++ -static-libgcc -Wl,--exclude-libs,ALL -Wl,-z,defs -Wl,--as-needed \
  -lpthread -lm

echo "==> Compiling css34_socket_probe.smx" >&2
mkdir -p "$PACKAGES_DIR/test-plugins"
"$SPCOMP" -i"$SM_PACKAGE_DIR/scripting/include" -i"$SRC/scripting/include" \
  -o"$PACKAGES_DIR/test-plugins/css34_socket_probe.smx" \
  "$WDIR/testing/plugins/css34_socket_probe.sp"

asset="$(socket_asset_name "$CSS34_LINE")"
STAGE="$OBJ/stage"
rm -rf "$STAGE"
mkdir -p "$STAGE/addons/sourcemod/extensions" "$STAGE/addons/sourcemod/scripting/include" \
  "$STAGE/addons/sourcemod/licenses/socket"
install -m 0755 "$OBJ/socket.ext.so" "$STAGE/addons/sourcemod/extensions/socket.ext.so"
install -m 0644 "$SRC/scripting/include/socket.inc" "$STAGE/addons/sourcemod/scripting/include/socket.inc"
install -m 0644 "$SRC/LICENSE" "$STAGE/addons/sourcemod/licenses/socket/LICENSE"
manifest="$STAGE/addons/sourcemod/licenses/socket/css34-socket.json"
python3 - "$manifest" <<PY
import json, sys
json.dump({
    "name": "Socket",
    "version": "${SOCKET_VERSION}",
    "source": "${SOCKET_REPO}",
    "source_commit": "${SOCKET_COMMIT}",
    "source_tree_sha256": "${SOCKET_TREE_SHA256}",
    "boost": "${SOCKET_BOOST_VERSION}",
    "boost_sha256": "${SOCKET_BOOST_SHA256}",
    "line": "${CSS34_LINE}",
    "sm_commit": "${SOURCEMOD_COMMIT}",
    "sm_tree": "${sm_tree}",
    "extension_api": int("${ext_api}"),
    "compiler": "${gcc_line}",
    "css34_pack_commit": "$(git -C "$WDIR" rev-parse HEAD 2>/dev/null || echo unknown)",
}, open(sys.argv[1], "w"), indent=2, sort_keys=True)
PY
mkdir -p "$PACKAGES_DIR/third-party"
cp -f "$manifest" "$PACKAGES_DIR/third-party/${asset%.tar.gz}.json"
# Reproducible archive: fixed owner, order and mtime.
tar --sort=name --owner=0 --group=0 --numeric-owner --mtime='@0' \
  -C "$STAGE" -czf "$PACKAGES_DIR/third-party/${asset}" addons
echo "==> Built ${PACKAGES_DIR}/third-party/${asset}" >&2
