#!/usr/bin/env bash
set -euo pipefail

# apply-sourcemod-exp7.sh
# 
# Extends apply-sourcemod.sh with Experiment #7 linker flag variations.
# 
# Usage:
#   EXP7_VARIANT=sections apply-sourcemod-exp7.sh /path/to/sourcemod
#   EXP7_VARIANT=gc apply-sourcemod-exp7.sh /path/to/sourcemod
#   EXP7_VARIANT=symbolic apply-sourcemod-exp7.sh /path/to/sourcemod
#   EXP7_VARIANT=full apply-sourcemod-exp7.sh /path/to/sourcemod

sourcemod_dir="${1:?sourcemod directory required}"
variant="${EXP7_VARIANT:-baseline}"

if [ "$variant" = "baseline" ]; then
  # No additional flags; just run the standard patches
  exec "$WDIR/builder/patches/apply-sourcemod.sh" "$sourcemod_dir"
fi

echo "Applying Experiment #7 variant: $variant" >&2

# First, apply all standard patches
"$WDIR/builder/patches/apply-sourcemod.sh" "$sourcemod_dir"

# Then apply variant-specific linker flags
ambuild_script="$sourcemod_dir/AMBuildScript"

case "$variant" in
  sections)
    # -fdata-sections -ffunction-sections: splits each function/data into its own section
    # Requires linker GC to be effective
    echo "  Adding: -fdata-sections -ffunction-sections" >&2
    python3 - <<'PY'
from pathlib import Path
import re

path = Path(__import__('sys').argv[1])
text = path.read_text()

# Find the linkflags section for ep1/css/episode1
# Pattern: if sdk.name in [...]: compiler.linkflags += [...]
# We'll inject these into cxxflags instead (compile-time, applies to all SDKs)

marker = "cxx.cxxflags += ['-Wno-reorder', '-fpermissive', '-Wno-write-strings']  # CSS34 SDK compatibility"
if 'EXP7' in text:
    print('Already patched for EXP7', file=__import__('sys').stderr)
else:
    # Add to existing compile flags for ALL SDKs
    new_flags = "cxx.cxxflags += ['-Wno-reorder', '-fpermissive', '-Wno-write-strings', '-fdata-sections', '-ffunction-sections']  # CSS34 SDK compatibility; EXP7 sections"
    if marker in text:
        text = text.replace(marker, new_flags)
        path.write_text(text)
        print('Injected -fdata-sections -ffunction-sections', file=__import__('sys').stderr)
    else:
        raise SystemExit('Failed to locate cxxflags for EXP7 sections injection')

__import__('sys').path.pop(0)
import sys
sys.argv = [sys.argv[0], str(path)]
PY
    ;;

  gc)
    # -fdata-sections -ffunction-sections + -Wl,--gc-sections (garbage collect unused sections)
    echo "  Adding: -fdata-sections -ffunction-sections -Wl,--gc-sections" >&2
    python3 - <<'PY'
from pathlib import Path

path = Path(__import__('sys').argv[1]) if len(__import__('sys').argv) > 1 else Path('.')
text = path.read_text()

# Add sections flags to cxxflags
marker = "cxx.cxxflags += ['-Wno-reorder', '-fpermissive', '-Wno-write-strings']  # CSS34 SDK compatibility"
new_flags = "cxx.cxxflags += ['-Wno-reorder', '-fpermissive', '-Wno-write-strings', '-fdata-sections', '-ffunction-sections']  # CSS34 SDK compatibility; EXP7 gc"

if 'EXP7' not in text:
    if marker in text:
        text = text.replace(marker, new_flags, 1)

# Add GC flags to linker for ep1/css/episode1
gc_marker = "if sdk.name in ['csgo', 'blade', 'ep1', 'css', 'episode1']:"
if gc_marker in text and '-Wl,--gc-sections' not in text:
    # Find the dynamic libstdc++ block and add gc flags there
    text = text.replace(
        "        if '-lgcc_eh' in compiler.linkflags:\n          compiler.linkflags.remove('-lgcc_eh')",
        "        if '-lgcc_eh' in compiler.linkflags:\n          compiler.linkflags.remove('-lgcc_eh')\n        # EXP7: garbage collect unused sections\n        compiler.linkflags += ['-Wl,--gc-sections']"
    )

path.write_text(text)
print('Injected -fdata-sections -ffunction-sections and -Wl,--gc-sections', file=__import__('sys').stderr)
PY
    ;;

  symbolic)
    # -Wl,-Bsymbolic: bind symbols locally, reduce GOT/PLT bloat
    echo "  Adding: -Wl,-Bsymbolic" >&2
    python3 - <<'PY'
from pathlib import Path

path = Path(__import__('sys').argv[1]) if len(__import__('sys').argv) > 1 else Path('.')
text = path.read_text()

if '-Wl,-Bsymbolic' not in text:
    # Add after the gc-sections flag (or create new block)
    if "'-Wl,--gc-sections'" in text:
        text = text.replace("'-Wl,--gc-sections'", "'-Wl,--gc-sections', '-Wl,-Bsymbolic'")
    else:
        # Add to dynamic libstdc++ block
        text = text.replace(
            "        # EXP7: garbage collect unused sections\n        compiler.linkflags += ['-Wl,--gc-sections']",
            "        # EXP7: bind symbols locally\n        compiler.linkflags += ['-Wl,-Bsymbolic']"
        )

path.write_text(text)
print('Injected -Wl,-Bsymbolic', file=__import__('sys').stderr)
PY
    ;;

  full)
    # Combine: sections + gc + symbolic
    echo "  Adding: -fdata-sections -ffunction-sections -Wl,--gc-sections -Wl,-Bsymbolic" >&2
    python3 - <<'PY'
from pathlib import Path

path = Path(__import__('sys').argv[1]) if len(__import__('sys').argv) > 1 else Path('.')
text = path.read_text()

# Inject all flags
marker = "cxx.cxxflags += ['-Wno-reorder', '-fpermissive', '-Wno-write-strings']  # CSS34 SDK compatibility"
new_flags = "cxx.cxxflags += ['-Wno-reorder', '-fpermissive', '-Wno-write-strings', '-fdata-sections', '-ffunction-sections']  # CSS34 SDK compatibility; EXP7 full"

if 'EXP7' not in text:
    if marker in text:
        text = text.replace(marker, new_flags, 1)
        # Add linker flags
        text = text.replace(
            "        if '-lgcc_eh' in compiler.linkflags:\n          compiler.linkflags.remove('-lgcc_eh')",
            "        if '-lgcc_eh' in compiler.linkflags:\n          compiler.linkflags.remove('-lgcc_eh')\n        # EXP7 full: aggressive linker optimization\n        compiler.linkflags += ['-Wl,--gc-sections', '-Wl,-Bsymbolic']"
        )

path.write_text(text)
print('Injected all EXP7 full flags', file=__import__('sys').stderr)
PY
    ;;

  *)
    echo "Unknown variant: $variant" >&2
    exit 1
    ;;
esac
