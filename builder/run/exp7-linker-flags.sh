#!/usr/bin/env bash
set -euo pipefail

# Experiment #7: Linker Flags Investigation
# 
# Tests whether aggressive linker optimizations used by the original builder
# can reduce .text section size on SDK-heavy modules (sdkhooks, sdktools, etc.).
#
# Variants:
#   - EXP7_VARIANT=baseline (default): No changes, baseline repro
#   - EXP7_VARIANT=sections: Add -fdata-sections -ffunction-sections
#   - EXP7_VARIANT=gc: Add -Wl,--gc-sections with sections flags
#   - EXP7_VARIANT=symbolic: Add -Wl,-Bsymbolic (bind locally)
#   - EXP7_VARIANT=full: sections + gc + symbolic

WDIR="${WDIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
BUILDER_DIR="$WDIR/builder"

EXP7_VARIANT="${EXP7_VARIANT:-baseline}"

export EXP7_ENABLED=1
export EXP7_VARIANT="$EXP7_VARIANT"

echo "=========================================="
echo "Experiment #7: Linker Flags for Byte-Match"
echo "=========================================="
echo "Variant: $EXP7_VARIANT"
echo ""

if [ -x "$BUILDER_DIR/docker/trusty/run.sh" ]; then
  echo "Running in Docker trusty environment..."
  # Pass through EXP7 vars to the container
  "$BUILDER_DIR/docker/trusty/run.sh"
else
  echo "Running on host (Ubuntu 22.04 with clang-9 wrappers)..."
  exec "$BUILDER_DIR/run/linux-repro.sh"
fi
