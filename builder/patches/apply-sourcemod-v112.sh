#!/usr/bin/env bash
# CS:S v34 compatibility patches for SourceMod 1.12+ (hl2sdk-manifests / AMBuild 2.2).
set -euo pipefail

sourcemod_dir="${1:?sourcemod directory required}"
builder_dir="${2:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

bash "$builder_dir/patches/apply-sourcemod-common.sh" "$sourcemod_dir"

# gcc-9 + rom4s/hl2sdk-ep1c triggers -Werror=reorder and stringop-* in SDK headers.
ambuild_script="$sourcemod_dir/AMBuildScript"
if [ -f "$ambuild_script" ] && ! grep -q 'CSS34 SDK compatibility' "$ambuild_script"; then
  sed -i "/cxx.cflags += \['-Wno-maybe-uninitialized'\]/a\\
      cxx.cxxflags += ['-Wno-reorder', '-fpermissive', '-Wno-write-strings', '-Wno-sign-compare', '-Wno-ignored-attributes']  # CSS34 SDK compatibility\\
      cxx.cflags += ['-Wno-stringop-overflow', '-Wno-error=stringop-overflow', '-Wno-stringop-truncation', '-Wno-error=stringop-truncation', '-Wno-format-truncation', '-Wno-error=format-truncation', '-Wno-ignored-attributes']  # CSS34 SDK compatibility" \
    "$ambuild_script"
fi

# Install custom ep1 SDK manifest (rom4s/hl2sdk-ep1c with SE_CSS).
manifests_dir="$sourcemod_dir/hl2sdk-manifests/manifests"
if [ -d "$manifests_dir" ]; then
  cp -f "$builder_dir/assets/hl2sdk-manifests/ep1.json" "$manifests_dir/ep1.json"
fi

# Build cstrike extension for ep1 + episode1 (v34 needs both 1.ep1 and 2.ep1 binaries).
cstrike_ambuild="$sourcemod_dir/extensions/cstrike/AMBuilder"
if [ -f "$cstrike_ambuild" ]; then
  if ! grep -q "for sdk_name in \['ep1', 'episode1'" "$cstrike_ambuild"; then
    sed -i \
      "s/for sdk_name in \['css', 'csgo'\]:/for sdk_name in ['ep1', 'episode1', 'css', 'csgo']:/" \
      "$cstrike_ambuild"
  fi
fi

# gcc-9 + glibc fortify triggers -Werror=stringop-truncation in bundled libcurl.
curl_ambuild="$sourcemod_dir/extensions/curl/curl-src/lib/AMBuilder"
if [ -f "$curl_ambuild" ] && ! grep -q 'stringop-truncation' "$curl_ambuild"; then
  sed -i "/binary.compiler.defines += \['_GNU_SOURCE'\]/a\\
    binary.compiler.cflags += ['-Wno-stringop-truncation', '-Wno-error=stringop-truncation']" \
    "$curl_ambuild"
fi

# gcc-9 -Werror=sign-compare in SourcePawn (plugin-context, shell).
sp_ambuild="$sourcemod_dir/sourcepawn/AMBuildScript"
if [ -f "$sp_ambuild" ] && ! grep -q 'CSS34 sign-compare' "$sp_ambuild"; then
  sed -i "/'-Werror',/a\\
            '-Wno-sign-compare',  # CSS34 sign-compare" \
    "$sp_ambuild"
  sed -i "/cxx.cxxflags += \['-std=c++17'\]/a\\
        cxx.cxxflags += ['-Wno-sign-compare']  # CSS34 sign-compare" \
    "$sp_ambuild"
fi

# gcc-9 -Werror=sign-compare in SourcePawn shell tool.
shell_cpp="$sourcemod_dir/sourcepawn/vm/shell/shell.cpp"
if [ -f "$shell_cpp" ] && grep -q 'if (index > params\[0\])' "$shell_cpp"; then
  sed -i 's/if (index > params\[0\])/if (index > (size_t)params[0])/' "$shell_cpp"
fi

# MMS 1.12 headers lack engine constants referenced by SM 1.12.
for src in core/smn_halflife.cpp loader/loader.cpp; do
  target="$sourcemod_dir/$src"
  if [ -f "$target" ] && ! grep -q 'ifndef SOURCE_ENGINE_PVKII' "$target"; then
    sed -i '1i\
#ifndef SOURCE_ENGINE_PVKII\
#define SOURCE_ENGINE_PVKII 25\
#endif\
#ifndef SOURCE_ENGINE_MCV\
#define SOURCE_ENGINE_MCV 26\
#endif\
' "$target"
  fi
done
