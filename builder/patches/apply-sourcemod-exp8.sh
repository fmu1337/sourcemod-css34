#!/usr/bin/env bash
set -euo pipefail

# Experiment #8: SDK include paths and symlink modes.
#
# Usage:
#   EXP8_VARIANT=narrow-includes apply-sourcemod-exp8.sh /path/to/sourcemod
#
# Symlink mode is controlled separately via EXP8_SYMLINK_MODE in checkout-deps.

WDIR="${WDIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
BUILDER_DIR="$WDIR/builder"

sourcemod_dir="${1:?sourcemod directory required}"
variant="${EXP8_VARIANT:-baseline}"
ambuild_script="$sourcemod_dir/AMBuildScript"

if [ "$variant" = "baseline" ]; then
  exec "$BUILDER_DIR/patches/apply-sourcemod.sh" "$sourcemod_dir"
fi

echo "Applying Experiment #8 variant: $variant" >&2

"$BUILDER_DIR/patches/apply-sourcemod.sh" "$sourcemod_dir"

EXP8_VARIANT="$variant" python3 - "$ambuild_script" <<'PY'
import os
import sys
from pathlib import Path

path = Path(sys.argv[1])
variant = os.environ["EXP8_VARIANT"]
text = path.read_text()

ep1_baseline = """    elif sdk.name == 'ep1':
      paths.append(['public', 'game', 'server'])
      paths.append(['public', 'toolframework'])
      paths.append(['public', 'dlls'])
      paths.append(['game_shared'])"""

ep1_narrow = """    elif sdk.name == 'ep1':
      paths.append(['public', 'dlls'])
      paths.append(['game_shared'])"""

ep1_wide = """    elif sdk.name == 'ep1':
      paths.append(['public', 'game', 'server'])
      paths.append(['public', 'toolframework'])
      paths.append(['public', 'dlls'])
      paths.append(['game_shared'])
      paths.append(['game', 'shared'])
      paths.append(['common'])"""

if variant == "narrow-includes":
    if ep1_baseline not in text:
        raise SystemExit("Failed to locate ep1 baseline include block")
    text = text.replace(ep1_baseline, ep1_narrow, 1)
elif variant == "wide-includes":
    if ep1_baseline not in text:
        raise SystemExit("Failed to locate ep1 baseline include block")
    text = text.replace(ep1_baseline, ep1_wide, 1)
elif variant == "minimal-symlinks":
    pass
else:
    raise SystemExit("Unknown EXP8 variant: {}".format(variant))

path.write_text(text)
print("Applied EXP8 variant: {}".format(variant), file=sys.stderr)
PY
