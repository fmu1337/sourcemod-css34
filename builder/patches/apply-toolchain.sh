#!/usr/bin/env bash
# Extra compiler flags/patches for newer upstream SourceMod on gcc-9 multilib.
# Not required for the stable 6572 baseline; applied automatically when
# SOURCEMOD_GIT_REV >= 6800 or SOURCEMOD_TOOLCHAIN_PATCHES=1.
set -euo pipefail

sourcemod_dir="${1:?sourcemod directory required}"
BUILD_PLATFORM="${BUILD_PLATFORM:-linux}"
compiler="${CC:-gcc-9}"

case "$(basename "$compiler")" in
  clang*) exit 0 ;;
esac

ambuild_script="$sourcemod_dir/AMBuildScript"
if grep -q "CSS34 SDK compatibility" "$ambuild_script"; then
  if ! grep -q "'-Wno-sign-compare']  # CSS34 SDK compatibility" "$ambuild_script"; then
    sed -i "s/'-Wno-write-strings']  # CSS34 SDK compatibility/'-Wno-write-strings', '-Wno-sign-compare', '-Wno-ignored-attributes']  # CSS34 SDK compatibility/" "$ambuild_script"
  elif ! grep -q "'-Wno-ignored-attributes']  # CSS34 SDK compatibility" "$ambuild_script"; then
    sed -i "s/'-Wno-sign-compare']  # CSS34 SDK compatibility/'-Wno-sign-compare', '-Wno-ignored-attributes']  # CSS34 SDK compatibility/" "$ambuild_script"
  fi
fi

sp_script="$sourcemod_dir/sourcepawn/AMBuildScript"
if [ -f "$sp_script" ]; then
  python3 - "$sp_script" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()
sp_patch = "            '-Werror',\n            '-Wno-switch',"
if "'-std=c++17', '-Wno-sign-compare'" not in text and "cxx.cxxflags += ['-std=c++17']" in text:
    text = text.replace(
        "cxx.cxxflags += ['-std=c++17']",
        "cxx.cxxflags += ['-std=c++17', '-Wno-sign-compare']  # CSS34 gcc compatibility",
        1,
    )
elif "'-std=c++14', '-Wno-sign-compare'" not in text and "cxx.cxxflags += ['-std=c++14']" in text:
    text = text.replace(
        "cxx.cxxflags += ['-std=c++14']",
        "cxx.cxxflags += ['-std=c++14', '-Wno-sign-compare']  # CSS34 gcc compatibility",
        1,
    )
if sp_patch in text and "'-Wno-sign-compare',  # CSS34 gcc compatibility" not in text:
    text = text.replace(
        sp_patch,
        sp_patch + "\n            '-Wno-sign-compare',  # CSS34 gcc compatibility",
        1,
    )
path.write_text(text)
PY
fi

# -Wno-invalid-offsetof is C++-only; bundled DHooks (6970+) compiles C via the same toolchain.
sp_ambuild="$sourcemod_dir/sourcepawn/AMBuildScript"
if [ -f "$sp_ambuild" ] && grep -A2 "binary.compiler.cflags" "$sp_ambuild" | grep -q "Wno-invalid-offsetof"; then
  python3 - "$sp_ambuild" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text()
old = """            binary.compiler.cflags += [
                '-Wno-invalid-offsetof',
            ]"""
new = """            binary.compiler.cxxflags += [
                '-Wno-invalid-offsetof',
            ]"""
if old in text:
    path.write_text(text.replace(old, new, 1))
PY
fi
