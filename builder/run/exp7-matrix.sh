#!/usr/bin/env bash
# Run Experiment #7 linker-flag variants in one trusty Docker session.
# Builds the image once, then rebuilds SourceMod for each variant.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
IMAGE="${REPRO_TRUSTY_IMAGE:-sourcemod-css34-repro-trusty}"
DOCKER="${DOCKER:-sudo docker}"
RESULTS_DIR="$ROOT/builder/exp7-results"
VARIANTS=(sections gc symbolic full)

mkdir -p "$RESULTS_DIR"
cd "$ROOT"

echo "==> Building Docker image ($IMAGE)"
$DOCKER build -f builder/docker/trusty/Dockerfile -t "$IMAGE" .

run_variant() {
  local variant="$1"
  echo ""
  echo "=========================================="
  echo "EXP7 variant: $variant"
  echo "=========================================="

  sudo rm -rf "$ROOT/deps" "$ROOT/sourcemod/build"

  $DOCKER run --rm \
    -v "$ROOT:/src" \
    -w /src \
    -e WDIR=/src \
    -e EXP7_ENABLED=1 \
    -e EXP7_VARIANT="$variant" \
    "$IMAGE" \
    bash -lc 'chmod +x builder/run/linux-repro-trusty.sh builder/run/linux-repro.sh builder/install-clang9.sh builder/checkout-deps.sh builder/package.sh builder/prepare-package.sh builder/compare-release.sh builder/patches/*.sh && builder/run/linux-repro-trusty.sh' \
    2>&1 | tee "$RESULTS_DIR/${variant}.log"

  local artifact
  artifact="$(ls -1 "$ROOT"/packages/sourcemod-*-css34-linux.tar.gz | tail -1)"
  cp "$artifact" "$RESULTS_DIR/${variant}.tar.gz"

  EXP7_VARIANT="$variant" "$ROOT/builder/compare-release.sh" "$artifact" \
    > "$RESULTS_DIR/${variant}-summary.txt" 2>&1 || true

  echo "==> Saved $RESULTS_DIR/${variant}-summary.txt"
}

for variant in "${VARIANTS[@]}"; do
  run_variant "$variant"
done

echo ""
echo "==> EXP7 matrix complete. Results in $RESULTS_DIR/"
python3 - "$RESULTS_DIR" <<'PY'
import os
import re
import sys
from pathlib import Path

results = Path(sys.argv[1])
variants = ['sections', 'gc', 'symbolic', 'full']
sdk_modules = [
    'addons/sourcemod/bin/sourcemod.1.ep1.so',
    'addons/sourcemod/extensions/sdkhooks.ext.1.ep1.so',
    'addons/sourcemod/extensions/sdktools.ext.1.ep1.so',
    'addons/sourcemod/extensions/game.cstrike.ext.1.ep1.so',
]

print('\n=== EXP7 SDK size matrix (built bytes, delta vs original) ===')
header = f"{'module':<55}" + ''.join(f'{v:>12}' for v in variants)
print(header)
print('-' * len(header))

for module in sdk_modules:
    row = [module[-44:]]
    for variant in variants:
        summary = results / f'{variant}-summary.txt'
        if not summary.is_file():
            row.append('n/a')
            continue
        text = summary.read_text()
        m = re.search(
            rf'^\s+{re.escape(module)}: orig=(\d+) built=(\d+) \(([+-]\d+)\)',
            text,
            re.MULTILINE,
        )
        row.append(m.group(3) if m else '?')
    print(f"{row[0]:<55}" + ''.join(f'{v:>12}' for v in row[1:]))
PY
