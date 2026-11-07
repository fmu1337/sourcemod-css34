#!/usr/bin/env bash
# Build the third-party AntiDLL extension + handler plugin (JDW1337/AntiDLL) for
# CS:S v34 (episode1 / "original" engine, Linux x86) in two variants:
#   sm13: against this line's SourceMod tree (extension API of the line, CDetour on
#         SourceMod's safetyhook), AntiDLL.ext.2.ep1.so, plugin by the line's spcomp
#   sm17: against the SourceMod 1.7 SDK (API 8, ISourceMod 13; CDetour on asm.c) and
#         Metamod 1.10 core-legacy, AntiDLL.ext.1.ep1.so, plugin by spcomp 1.7.3
# builder/run/linux.sh runs it after `ambuild` for the lines in ANTIDLL_LINES
# (builder/third-party/antidll.env), inside the release image (manylinux2014 i686,
# devtoolset-10 GCC 10.2.1, glibc 2.17). Output, never part of the SM package:
#   packages/antidll/antidll-<ver>-{sm13,sm17}-css34-linux.tar.gz   (cstrike/ layout)
#
# Changes to upstream, all made here so the pinned source stays verifiable: none to
# the code. The release binaries (1.4) were built against SM 1.10, which SM 1.13
# rejects ("Extension version is too old to load") and SM 1.7 cannot serve
# ("Could not find interface: ISourceMod"); rebuilding against each SDK is the fix.
set -euo pipefail

WDIR="${WDIR:-/workspace}"
DEPS_DIR="${DEPS_DIR:-$WDIR/deps}"
PACKAGES_DIR="${PACKAGES_DIR:-$WDIR/packages}"
SOURCEMOD_DIR="${SOURCEMOD_DIR:-$WDIR/sourcemod}"
CSS34_LINE="${CSS34_LINE:?CSS34_LINE is required}"
SOURCEMOD_COMMIT="${SOURCEMOD_COMMIT:?SOURCEMOD_COMMIT is required (builder/resolve-version.sh)}"
MMS_DIR="${MMS_DIR:?MMS_DIR is required (Metamod tree of the line)}"
SM_PACKAGE_DIR="${SM_PACKAGE_DIR:-$SOURCEMOD_DIR/build/package}/addons/sourcemod"
HL2SDK="${HL2SDK:-$DEPS_DIR/hl2sdk-episode1}"
CC="${CC:-gcc}"
CXX="${CXX:-g++}"

# shellcheck source=../fetch-pinned.sh
source "$WDIR/builder/fetch-pinned.sh"
# shellcheck source=antidll.env
source "$WDIR/builder/third-party/antidll.env"
# shellcheck source=../versions.env
source "$WDIR/builder/versions.env"

die() { echo "FAIL: $*" >&2; exit 1; }

case " ${ANTIDLL_LINES} " in
  *" ${CSS34_LINE} "*) ;;
  *) die "AntiDLL is built for: ${ANTIDLL_LINES} (not ${CSS34_LINE})" ;;
esac

gcc_line="$("$CXX" --version | head -1)"
[[ "$gcc_line" == *"10.2.1"* ]] || die "expected devtoolset-10 GCC 10.2.1, got: ${gcc_line}"
[[ "$(uname -m)" == i686 && "$("$CXX" -dumpmachine)" == i686-* ]] ||
  die "must build for i686 (uname=$(uname -m) dumpmachine=$("$CXX" -dumpmachine))"
[[ -f "$HL2SDK/public/iclient.h" && -f "$HL2SDK/linux_sdk/tier0_i486.so" ]] ||
  die "no episode1 SDK at $HL2SDK"
sm_head="$(git -C "$SOURCEMOD_DIR" rev-parse HEAD)"
[[ "$sm_head" == "$SOURCEMOD_COMMIT" ]] ||
  die "$SOURCEMOD_DIR is at ${sm_head}, ${CSS34_LINE} pins ${SOURCEMOD_COMMIT}"
SPCOMP13="$SM_PACKAGE_DIR/scripting/spcomp"
[[ -x "$SPCOMP13" ]] || die "no $SPCOMP13: run after the SourceMod build (builder/run/linux.sh)"

# git clone of REPO at COMMIT (shallow), origin set for builder/freeze mirrors.
clone_at() { # DIR REPO COMMIT
  rm -rf "$1"
  git init -q "$1"
  git -C "$1" remote add origin "$2"
  git -C "$1" fetch -q --depth 1 origin "$3"
  git -C "$1" -c advice.detachedHead=false checkout -q --detach FETCH_HEAD
  [[ "$(git -C "$1" rev-parse HEAD)" == "$3" ]] || die "$2: fetched the wrong commit"
}

SRC="$DEPS_DIR/antidll"
echo "==> ${ANTIDLL_REPO} ${ANTIDLL_COMMIT}" >&2
clone_at "$SRC" "$ANTIDLL_REPO" "$ANTIDLL_COMMIT"
git -C "$SRC" ls-files -z | LC_ALL=C sort -z >"$DEPS_DIR/antidll-files.z"
ad_tree_sha="$(cd "$SRC" && xargs -0 sha256sum <"$DEPS_DIR/antidll-files.z" | sha256sum | awk '{print $1}')"
echo "==> AntiDLL source tree sha256 ${ad_tree_sha}" >&2
if [[ "$ad_tree_sha" != "$ANTIDLL_TREE_SHA256" ]]; then
  die "AntiDLL source tree sha256 ${ad_tree_sha}, expected ${ANTIDLL_TREE_SHA256}"
fi
grep -Fq "#define SMEXT_CONF_VERSION		\"${ANTIDLL_VERSION}\"" "$SRC/smsdk_config.h" ||
  die "smsdk_config.h does not declare version ${ANTIDLL_VERSION}"

SM17="$DEPS_DIR/sourcemod-1.7-sdk"
echo "==> SourceMod 1.7 SDK ${ANTIDLL_SM17_COMMIT}" >&2
clone_at "$SM17" "$ANTIDLL_SM17_REPO" "$ANTIDLL_SM17_COMMIT"
MM110="$DEPS_DIR/antidll-mmsource-1.10"
echo "==> Metamod:Source 1.10 ${MM_110_COMMIT}" >&2
clone_at "$MM110" "https://github.com/alliedmodders/metamod-source" "$MM_110_COMMIT"
SM17_PKG="$DEPS_DIR/sourcemod-1.7.3-linux"
if [[ ! -f "$SM17_PKG/.css34-${ANTIDLL_SM17_PKG_SHA256}" ]]; then
  rm -rf "$SM17_PKG"; mkdir -p "$SM17_PKG"
  fetch_pinned "$ANTIDLL_SM17_PKG_URL" "$SM17_PKG.tar.gz" "$ANTIDLL_SM17_PKG_SHA256"
  tar -xzf "$SM17_PKG.tar.gz" -C "$SM17_PKG" addons/sourcemod/scripting
  rm -f "$SM17_PKG.tar.gz"
  touch "$SM17_PKG/.css34-${ANTIDLL_SM17_PKG_SHA256}"
fi
SPCOMP17="$SM17_PKG/addons/sourcemod/scripting/spcomp"

# -DSE_<NAME>=<code> for every engine: SourceMod headers compare SOURCE_ENGINE
# against them, and an undefined SE_* would silently be 0.
se_defines_13() {
  python3 - "$SOURCEMOD_DIR/hl2sdk-manifests/manifests" <<'PY'
import json, pathlib, sys
for m in sorted(pathlib.Path(sys.argv[1]).glob("*.json")):
    d = json.loads(m.read_text())
    if "define" in d and "code" in d:
        print("-DSE_{}={}".format(d["define"], d["code"]))
PY
}
se_defines_17() {
  python3 - "$SM17/AMBuildScript" <<'PY'
import re, sys
for code, define in re.findall(r"SDK\('[^']*',\s*'[^']*',\s*'(\d+)',\s*'(\w+)'", open(sys.argv[1]).read()):
    print("-DSE_{}={}".format(define, code))
PY
}

COMMON=(
  -m32 -O2 -pipe -fPIC -msse -mfpmath=sse -mstackrealign
  -fno-strict-aliasing -fvisibility=hidden -Wall -Wno-unused -Wno-switch
  -Wno-array-bounds -Wno-unknown-pragmas -Wno-narrowing -Wno-unused-result
  -Dstricmp=strcasecmp -D_stricmp=strcasecmp -D_snprintf=snprintf -D_vsnprintf=vsnprintf
  -DHAVE_STDINT_H -DGNUC -DLINUX -D_LINUX -DPOSIX -DCOMPILER_GCC -DNDEBUG
  -DSOURCE_ENGINE=1 -DGAME_DLL
  -I"$SRC"
)
for p in public public/engine public/mathlib public/vstdlib public/tier0 public/tier1 \
         public/toolframework public/dlls game_shared; do
  COMMON+=(-I"$HL2SDK/$p")
done
CXXONLY=(
  -fvisibility-inlines-hidden -fno-threadsafe-statics -Wno-non-virtual-dtor
  -Wno-overloaded-virtual -Wno-delete-non-virtual-dtor -Wno-class-memaccess
  -Wno-packed-not-aligned -Wno-deprecated-declarations -Wno-register
)

# Link: static libstdc++/libgcc, only GetSMExtAPI and the Metamod entry (CreateInterface_MMS on
# MM 1.12 headers, CreateInterface on 1.10 core-legacy) of an SMEXT_CONF_METAMOD extension) exported, everything resolved
# against libc/libm/libdl/libpthread and the server's tier0/vstdlib (-z defs).
link_ext() { # OUT OBJ...
  local out="$1"; shift
  printf '{\n  global: GetSMExtAPI; CreateInterface; CreateInterface_MMS;\n  local: *;\n};\n' >"$(dirname "$out")/exports.map"
  "$CXX" -m32 -shared -o "$out" "$@" \
    -static-libstdc++ -static-libgcc -Wl,--exclude-libs,ALL \
    -Wl,--version-script="$(dirname "$out")/exports.map" -Wl,-z,defs \
    -Wl,--as-needed -L"$HL2SDK/linux_sdk" -l:tier0_i486.so -l:vstdlib_i486.so \
    -ldl -lpthread -lm
}

# ELF rules of testing/scripts/check-third-party.sh for a standalone .so.
check_elf() { # SO
  local so="$1"
  readelf -h "$so" | grep -q 'Machine:.*80386' || die "$so is not i386"
  if readelf -d "$so" | grep -E 'NEEDED.*(libstdc\+\+|libgcc_s)'; then die "$so needs libstdc++/libgcc_s"; fi
  if readelf -d "$so" | grep -q TEXTREL; then die "$so has DT_TEXTREL"; fi
  local exports
  exports="$(readelf -W --dyn-syms "$so" | awk '$5=="GLOBAL" && $7!="UND" {print $8}' | sed 's/@.*//' | sort -u | tr '\n' ' ')"
  [[ "$exports" == "CreateInterface GetSMExtAPI " || "$exports" == "CreateInterface_MMS GetSMExtAPI " ]] ||
    die "$so exports [${exports}], want GetSMExtAPI + the Metamod entry (CreateInterface or CreateInterface_MMS)"
  local maxg
  maxg="$(readelf -W --dyn-syms "$so" | grep -o 'GLIBC_[0-9.]*' | sed 's/GLIBC_//' | sort -V | tail -1)"
  [[ "$(printf '%s\n2.17\n' "$maxg" | sort -V | tail -1)" == 2.17 ]] || die "$so needs GLIBC_${maxg} > 2.17"
  if readelf -W --dyn-syms "$so" | grep -E 'GLIBCXX_|CXXABI_'; then die "$so imports libstdc++ symbols"; fi
  echo "OK: $(basename "$so"): i386, exports [${exports% }] only, glibc <= 2.17, needs: $(readelf -d "$so" | grep NEEDED | grep -o '\[.*\]' | tr '\n' ' ')" >&2
}

api_of() { sed -nE 's/^[[:space:]]*#define[[:space:]]+SMINTERFACE_EXTENSIONAPI_VERSION[[:space:]]+([0-9]+).*/\1/p' "$1/public/IExtensionSys.h"; }

OUT="$DEPS_DIR/antidll-build"
rm -rf "$OUT"; mkdir -p "$OUT/sm13" "$OUT/sm17"

# ---- sm13: this line's SourceMod ----
safetyhook="$(find "$SOURCEMOD_DIR/build" -name 'libsafetyhook.a' -o -name 'safetyhook.a' | head -1)"
[[ -n "$safetyhook" ]] || die "no safetyhook static library under $SOURCEMOD_DIR/build"
mapfile -t SE13 < <(se_defines_13)
[[ "${#SE13[@]}" -gt 10 ]] || die "cannot read SE_* codes from hl2sdk-manifests"
api13="$(api_of "$SOURCEMOD_DIR")"
echo "==> Compiling AntiDLL.ext.2.ep1.so (${CSS34_LINE}, extension API ${api13})" >&2
F13=(
  "${COMMON[@]}" "${SE13[@]}" -D_FILE_OFFSET_BITS=64 -DRAD_TELEMETRY_DISABLED
  -I"$SOURCEMOD_DIR/public" -I"$SOURCEMOD_DIR/public/extensions"
  -I"$SOURCEMOD_DIR/sourcepawn/include" -I"$SOURCEMOD_DIR/public/amtl/amtl"
  -I"$SOURCEMOD_DIR/public/amtl" -I"$SOURCEMOD_DIR/public/safetyhook/include"
  -I"$MMS_DIR/core" -I"$MMS_DIR/core/sourcehook"
)
o13=()
for src in "$SRC/extension.cpp" "$SOURCEMOD_DIR/public/smsdk_ext.cpp" "$SOURCEMOD_DIR/public/CDetour/detours.cpp"; do
  o="$OUT/sm13/$(basename "${src%.cpp}").o"
  "$CXX" "${F13[@]}" "${CXXONLY[@]}" -std=c++20 -c "$src" -o "$o"
  o13+=("$o")
done
link_ext "$OUT/sm13/AntiDLL.ext.2.ep1.so" "${o13[@]}" "$safetyhook"
check_elf "$OUT/sm13/AntiDLL.ext.2.ep1.so"

# ---- sm17: SourceMod 1.7 SDK, Metamod 1.10 core-legacy (1.ep1) ----
mapfile -t SE17 < <(se_defines_17)
[[ "${#SE17[@]}" -gt 5 ]] || die "cannot read SE_* codes from SM 1.7 AMBuildScript"
api17="$(api_of "$SM17")"
echo "==> Compiling AntiDLL.ext.1.ep1.so (SourceMod 1.7 SDK, extension API ${api17})" >&2
F17=(
  "${COMMON[@]}" "${SE17[@]}"
  -I"$SM17/public" -I"$SM17/public/extensions" -I"$SM17/public/sourcepawn"
  -I"$SM17/public/amtl" -I"$SM17/public/jit" -I"$SM17/public/jit/x86"
  -I"$MM110/core-legacy" -I"$MM110/core-legacy/sourcehook"
)
o17=()
for src in "$SRC/extension.cpp" "$SM17/public/smsdk_ext.cpp" "$SM17/public/CDetour/detours.cpp"; do
  o="$OUT/sm17/$(basename "${src%.cpp}").o"
  "$CXX" "${F17[@]}" "${CXXONLY[@]}" -std=c++14 -fno-exceptions -c "$src" -o "$o"
  o17+=("$o")
done
"$CC" "${F17[@]}" -std=gnu99 -c "$SM17/public/asm/asm.c" -o "$OUT/sm17/asm.o"
o17+=("$OUT/sm17/asm.o")
link_ext "$OUT/sm17/AntiDLL.ext.1.ep1.so" "${o17[@]}"
check_elf "$OUT/sm17/AntiDLL.ext.1.ep1.so"

# ---- plugins ----
echo "==> Compiling AntiDLL.smx (spcomp of ${CSS34_LINE} and 1.7.3)" >&2
"$SPCOMP13" -i"$SM_PACKAGE_DIR/scripting/include" -i"$SRC/scripting/include" \
  -o"$OUT/sm13/AntiDLL.smx" "$SRC/scripting/AntiDLL.sp"
"$SPCOMP17" -i"$SM17_PKG/addons/sourcemod/scripting/include" -i"$SRC/scripting/include" \
  -o"$OUT/sm17/AntiDLL.smx" "$SRC/scripting/AntiDLL.sp"

# ---- archives (cstrike/ layout) ----
mkdir -p "$PACKAGES_DIR/antidll"
for v in sm13 sm17; do
  st="$OUT/stage-$v"; sm="$st/addons/sourcemod"
  rm -rf "$st"; mkdir -p "$sm"/{extensions,plugins,scripting/include,licenses/antidll}
  cp "$OUT/$v"/AntiDLL.ext.*.so "$sm/extensions/"
  cp "$OUT/$v/AntiDLL.smx" "$sm/plugins/"
  cp -r "$SRC/gamedata" "$SRC/configs" "$SRC/data" "$SRC/translations" "$sm/"
  cp "$SRC/scripting/AntiDLL.sp" "$sm/scripting/"
  cp "$SRC/scripting/include/antidll.inc" "$sm/scripting/include/"
  cp "$SRC/LICENSE" "$sm/licenses/antidll/"
  if [[ "$v" == sm13 ]]; then api="$api13" smc="$SOURCEMOD_COMMIT"; else api="$api17" smc="$ANTIDLL_SM17_COMMIT"; fi
  python3 - "$sm/licenses/antidll/css34-antidll.json" "$st" <<PY
import json, os, sys
root = sys.argv[2]
files = sorted(os.path.relpath(os.path.join(d, f), root) for d, _, fs in os.walk(root) for f in fs)
json.dump({
    "name": "AntiDLL", "variant": "$v", "version": "${ANTIDLL_VERSION}",
    "source": "${ANTIDLL_REPO}", "source_commit": "${ANTIDLL_COMMIT}",
    "source_tree_sha256": "${ANTIDLL_TREE_SHA256}", "line": "${CSS34_LINE}",
    "sm_commit": "$smc", "extension_api": int("$api"), "compiler": "${gcc_line}",
    "files": files + ["addons/sourcemod/licenses/antidll/css34-antidll.json"],
}, open(sys.argv[1], "w"), indent=2, sort_keys=True)
PY
  art="$PACKAGES_DIR/antidll/antidll-${ANTIDLL_VERSION}-${v}-css34-linux.tar.gz"
  tar --owner=0 --group=0 -czf "$art" -C "$st" addons
  echo "==> $(basename "$art") $(sha256sum "$art" | awk '{print $1}')" >&2
done
