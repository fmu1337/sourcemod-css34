#!/usr/bin/env bash
set -euo pipefail

# Extends apply-sourcemod.sh with Experiment #7 linker flag variations.
#
# Usage:
#   EXP7_VARIANT=sections apply-sourcemod-exp7.sh /path/to/sourcemod

WDIR="${WDIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
BUILDER_DIR="$WDIR/builder"

sourcemod_dir="${1:?sourcemod directory required}"
variant="${EXP7_VARIANT:-baseline}"
ambuild_script="$sourcemod_dir/AMBuildScript"

if [ "$variant" = "baseline" ]; then
  exec "$BUILDER_DIR/patches/apply-sourcemod.sh" "$sourcemod_dir"
fi

echo "Applying Experiment #7 variant: $variant" >&2

"$BUILDER_DIR/patches/apply-sourcemod.sh" "$sourcemod_dir"

EXP7_VARIANT="$variant" python3 - "$ambuild_script" <<'PY'
import os
import sys
from pathlib import Path

path = Path(sys.argv[1])
variant = os.environ["EXP7_VARIANT"]
text = path.read_text()

gcc_marker = "cxx.cxxflags += ['-Wno-reorder', '-fpermissive', '-Wno-write-strings']  # CSS34 SDK compatibility"
clang_marker = "cxx.cxxflags += ['-Wno-reorder', '-Wno-attributes', '-fpermissive']  # CSS34 SDK compatibility"
libstdcxx_anchor = (
    "        if '-lgcc_eh' in compiler.linkflags:\n"
    "          compiler.linkflags.remove('-lgcc_eh')"
)

def inject_sections_flags(content: str) -> str:
    if "EXP7 sections" in content or "EXP7 gc" in content or "EXP7 full" in content:
        return content
    if gcc_marker in content:
        return content.replace(
            gcc_marker,
            gcc_marker.replace(
                "']  # CSS34 SDK compatibility",
                "', '-fdata-sections', '-ffunction-sections']  # CSS34 SDK compatibility; EXP7 sections",
            ),
            1,
        )
    if clang_marker in content:
        return content.replace(
            clang_marker,
            clang_marker.replace(
                "']  # CSS34 SDK compatibility",
                "', '-fdata-sections', '-ffunction-sections']  # CSS34 SDK compatibility; EXP7 sections",
            ),
            1,
        )
    raise SystemExit("Failed to locate cxxflags marker for EXP7 sections injection")

def inject_link_flags(content: str, flags: list[str], comment: str) -> str:
    if all(flag in content for flag in flags):
        return content
    if libstdcxx_anchor not in content:
        raise SystemExit("Failed to locate dynamic libstdc++ block for EXP7 linker injection")
    joined = ", ".join(f"'{flag}'" for flag in flags)
    replacement = (
        f"{libstdcxx_anchor}\n"
        f"        # {comment}\n"
        f"        compiler.linkflags += [{joined}]"
    )
    return content.replace(libstdcxx_anchor, replacement, 1)

if variant == "sections":
    text = inject_sections_flags(text)
elif variant == "gc":
    text = inject_sections_flags(text)
    text = inject_link_flags(text, ["-Wl,--gc-sections"], "EXP7: garbage collect unused sections")
elif variant == "symbolic":
    text = inject_link_flags(text, ["-Wl,-Bsymbolic"], "EXP7: bind symbols locally")
elif variant == "full":
    text = inject_sections_flags(text)
    text = inject_link_flags(
        text,
        ["-Wl,--gc-sections", "-Wl,-Bsymbolic"],
        "EXP7 full: aggressive linker optimization",
    )
else:
    raise SystemExit(f"Unknown EXP7 variant: {variant}")

path.write_text(text)
print(f"Applied EXP7 variant: {variant}", file=sys.stderr)
PY
