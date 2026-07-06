#!/usr/bin/env bash
set -euo pipefail

sourcemod_dir="${1:?sourcemod directory required}"
builder_dir="${2:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

product_version="$(tr -d '\r\n' < "$sourcemod_dir/product.version" 2>/dev/null || echo '1.11.0')"
major="${product_version%%.*}"
rest="${product_version#*.}"
minor="${rest%%.*}"

if [ "$major" -gt 1 ] || { [ "$major" -eq 1 ] && [ "$minor" -ge 12 ]; }; then
  exec bash "$builder_dir/patches/apply-sourcemod-v112.sh" "$sourcemod_dir" "$builder_dir"
fi

ambuild_script="$sourcemod_dir/AMBuildScript"

if grep -q "CSS34 SDK compatibility" "$ambuild_script"; then
  sed -i '/CSS34 SDK compatibility/d' "$ambuild_script"
fi
if grep -q "CSS34 clang compatibility" "$ambuild_script"; then
  sed -i '/CSS34 clang compatibility/d' "$ambuild_script"
fi

sp_ambuild_script="$sourcemod_dir/sourcepawn/AMBuildScript"
if [ -f "$sp_ambuild_script" ] && grep -q "CSS34 clang compatibility" "$sp_ambuild_script"; then
  sed -i '/CSS34 clang compatibility/d' "$sp_ambuild_script"
fi

BUILD_PLATFORM="${BUILD_PLATFORM:-linux}"

# Clang 15+ understands -Wno-deprecated-non-prototype; older distro clang does not.
# Probe with -Werror because SourceMod builds with -Werror and unknown -Wno-* is fatal then.
supports_deprecated_non_prototype=0
supports_reorder_ctor=0
compiler_flavor="gcc"
compiler="${CC:-gcc-9}"

if [ "$BUILD_PLATFORM" = "windows" ]; then
  compiler_flavor="msvc"
else
  case "$(basename "$compiler")" in
    clang*) compiler_flavor="clang" ;;
  esac
  if echo 'int main(void){return 0;}' | "$compiler" -m32 -Werror -Wno-deprecated-non-prototype -x c - -c -o /dev/null 2>/dev/null; then
    supports_deprecated_non_prototype=1
  fi
  if echo 'int main(void){return 0;}' | "$compiler" -m32 -Werror -Wno-reorder-ctor -x c - -c -o /dev/null 2>/dev/null; then
    supports_reorder_ctor=1
  fi
fi

SOURCEMOD_DIR="$sourcemod_dir" \
SUPPORTS_WNO_DEPRECATED_NON_PROTOTYPE="$supports_deprecated_non_prototype" \
SUPPORTS_WNO_REORDER_CTOR="$supports_reorder_ctor" \
COMPILER_FLAVOR="$compiler_flavor" \
python3 - <<'PY'
from pathlib import Path
import os

sourcemod_dir = os.environ['SOURCEMOD_DIR']
supports_deprecated_non_prototype = os.environ.get('SUPPORTS_WNO_DEPRECATED_NON_PROTOTYPE') == '1'
supports_reorder_ctor = os.environ.get('SUPPORTS_WNO_REORDER_CTOR') == '1'
compiler_flavor = os.environ.get('COMPILER_FLAVOR', 'gcc')

path = Path(sourcemod_dir) / 'AMBuildScript'
text = path.read_text()

ep1_marker = "'ep1':  SDK('HL2SDK', '1.ep1', '6', 'CSS', WinLinux, 'ep1'),"
episode1_anchor = "'episode1':  SDK('HL2SDK', '2.ep1', '1', 'EPISODEONE', WinLinux, 'episode1'),"
if ep1_marker not in text:
    if episode1_anchor not in text:
        raise SystemExit('Failed to locate episode1 SDK anchor in AMBuildScript')
    text = text.replace(episode1_anchor, episode1_anchor + "\n  " + ep1_marker, 1)

path_block_old = """    if sdk.name == 'episode1' or sdk.name == 'darkm':
      paths.append(['public', 'dlls'])
      paths.append(['game_shared'])"""
path_block_new = """    if sdk.name in ['episode1', 'darkm']:
      paths.append(['public', 'dlls'])
      paths.append(['game_shared'])
    elif sdk.name == 'ep1':
      paths.append(['public', 'game', 'server'])
      paths.append(['public', 'toolframework'])
      paths.append(['game', 'shared'])
      paths.append(['common'])"""
if path_block_old in text:
    text = text.replace(path_block_old, path_block_new, 1)
elif """    if sdk.name in ['episode1', 'darkm', 'ep1']:
      paths.append(['public', 'dlls'])
      paths.append(['game_shared'])""" in text:
    text = text.replace(
        """    if sdk.name in ['episode1', 'darkm', 'ep1']:
      paths.append(['public', 'dlls'])
      paths.append(['game_shared'])""",
        path_block_new,
        1,
    )
elif path_block_new not in text:
    raise SystemExit('Failed to patch SDK include paths in AMBuildScript')

lib_block_old = "      if sdk.name == 'episode1':\n        lib_folder = os.path.join(sdk.path, 'linux_sdk')"
lib_block_new = "      if sdk.name in ['episode1', 'ep1']:\n        lib_folder = os.path.join(sdk.path, 'linux_sdk')"
if lib_block_old in text:
    text = text.replace(lib_block_old, lib_block_new, 1)

gcc_flags_old = "      '-Wno-array-bounds',\n      '-msse',"
gcc_flags_new = """      '-Wno-array-bounds',
      '-Wno-stringop-overflow',
      '-Wno-error=stringop-overflow',
      '-Wno-stringop-truncation',
      '-Wno-error=stringop-truncation',
      '-Wno-format-truncation',
      '-Wno-error=format-truncation',
      '-msse',"""
if compiler_flavor == 'clang' and gcc_flags_new in text:
    text = text.replace(gcc_flags_new, gcc_flags_old, 1)
elif compiler_flavor == 'gcc' and gcc_flags_old in text and gcc_flags_new not in text:
    text = text.replace(gcc_flags_old, gcc_flags_new, 1)

needle = "      '-fvisibility=hidden',\n    ]\n"
insert = """      '-fvisibility=hidden',
    ]
"""
if compiler_flavor == 'clang':
    insert += """    cxx.cflags += ['-Wno-nonportable-include-path', '-Wno-macro-redefined', '-Wno-writable-strings']  # CSS34 SDK compatibility
    cxx.cxxflags += ['-Wno-reorder', '-Wno-attributes', '-fpermissive']  # CSS34 SDK compatibility
"""
    if supports_reorder_ctor:
        insert += "    cxx.cxxflags += ['-Wno-reorder-ctor']  # CSS34 clang compatibility\n"
    if supports_deprecated_non_prototype:
        insert += "    cxx.cflags += ['-Wno-deprecated-non-prototype']  # CSS34 clang compatibility\n"
elif compiler_flavor == 'gcc':
    insert += """    cxx.cxxflags += ['-Wno-reorder', '-fpermissive', '-Wno-write-strings']  # CSS34 SDK compatibility
"""
if needle not in text:
    raise SystemExit('Failed to locate compiler flags block in AMBuildScript')
text = text.replace(needle, insert, 1)

sp_script = Path(sourcemod_dir) / 'sourcepawn/AMBuildScript'
sp_text = sp_script.read_text()
if compiler_flavor == 'clang' and supports_deprecated_non_prototype and '-Wno-deprecated-non-prototype' not in sp_text:
    sp_text = sp_text.replace(
        "            '-Werror',\n            '-Wno-switch',",
        "            '-Werror',\n            '-Wno-switch',\n            '-Wno-deprecated-non-prototype',  # CSS34 clang compatibility",
    )
    sp_script.write_text(sp_text)

old_dynamic = (
    "      if sdk.name in ['css', 'hl2dm', 'dods', 'tf2', 'sdk2013', 'bms', 'nucleardawn', 'l4d2', 'insurgency', 'doi']:\n"
    "        dynamic_libs = ['libtier0_srv.so', 'libvstdlib_srv.so']"
)
new_dynamic = (
    "      if sdk.name in ['hl2dm', 'dods', 'tf2', 'sdk2013', 'bms', 'nucleardawn', 'l4d2', 'insurgency', 'doi']:\n"
    "        dynamic_libs = ['libtier0_srv.so', 'libvstdlib_srv.so']\n"
    "      elif sdk.name == 'css':\n"
    "        dynamic_libs = ['tier0_i486.so', 'vstdlib_i486.so']"
)
if old_dynamic not in text:
    raise SystemExit('Failed to locate dynamic_libs block in AMBuildScript')
text = text.replace(old_dynamic, new_dynamic, 1)

path.write_text(text)

cstrike_ambuild = Path(sourcemod_dir) / 'extensions/cstrike/AMBuilder'
if cstrike_ambuild.exists():
    cstrike_text = cstrike_ambuild.read_text()
    if "for sdk_name in ['ep1', 'episode1', 'css', 'csgo']:" not in cstrike_text:
        cstrike_text = cstrike_text.replace(
            "for sdk_name in ['css', 'csgo']:",
            "for sdk_name in ['ep1', 'episode1', 'css', 'csgo']:",
            1,
        )
        cstrike_ambuild.write_text(cstrike_text)

for rel in ('extensions/cstrike/forwards.cpp', 'extensions/cstrike/natives.cpp'):
    cstrike_src = Path(sourcemod_dir) / rel
    if cstrike_src.exists():
        cstrike_code = cstrike_src.read_text()
        cstrike_code = cstrike_code.replace(
            '#if SOURCE_ENGINE == SE_CSS',
            '#if SOURCE_ENGINE == SE_CSS || SOURCE_ENGINE == SE_EPISODEONE',
        )
        cstrike_src.write_text(cstrike_code)
PY

bash "$builder_dir/patches/apply-sourcemod-common.sh" "$sourcemod_dir"
