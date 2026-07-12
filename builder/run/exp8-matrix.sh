#!/usr/bin/env bash
# Run Experiment #8 SDK symlink/include variants in one trusty Docker session.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
IMAGE="${REPRO_TRUSTY_IMAGE:-sourcemod-css34-repro-trusty}"
DOCKER="${DOCKER:-sudo docker}"
RESULTS_DIR="$ROOT/builder/exp8-results"
VARIANTS=(minimal-symlinks narrow-includes wide-includes)

mkdir -p "$RESULTS_DIR"
cd "$ROOT"

echo "==> Building Docker image ($IMAGE)"
$DOCKER build -f builder/docker/trusty/Dockerfile -t "$IMAGE" .

run_variant() {
  local variant="$1"
  local symlink_mode="full"
  local variant_failed=0
  if [ "$variant" = "minimal-symlinks" ]; then
    symlink_mode="minimal"
  fi

  echo ""
  echo "=========================================="
  echo "EXP8 variant: $variant (symlinks=$symlink_mode)"
  echo "=========================================="

  sudo rm -rf "$ROOT/deps" "$ROOT/sourcemod/build"

  # Scan SourceMod (not full SDK) for mixed-case includes when using minimal symlinks.
  local scan_root_arg=()
  if [ "$symlink_mode" = "minimal" ]; then
    scan_root_arg=(-e EXP8_SYMLINK_SCAN_ROOT="$ROOT/sourcemod")
  fi

  $DOCKER run --rm \
    -v "$ROOT:/src" \
    -w /src \
    -e WDIR=/src \
    -e EXP8_ENABLED=1 \
    -e EXP8_VARIANT="$variant" \
    -e EXP8_SYMLINK_MODE="$symlink_mode" \
    -e SKIP_COMPARE=1 \
    "${scan_root_arg[@]}" \
    "$IMAGE" \
    bash -lc 'chmod +x builder/run/linux-repro-trusty.sh builder/run/linux-repro.sh builder/install-clang9.sh builder/checkout-deps.sh builder/package.sh builder/prepare-package.sh builder/compare-release.sh builder/patches/*.sh && builder/run/linux-repro-trusty.sh' \
    2>&1 | tee "$RESULTS_DIR/${variant}.log" || variant_failed=1

  if [ "$variant_failed" -ne 0 ]; then
    echo "==> EXP8 variant $variant FAILED (see ${variant}.log)" >&2
    return 0
  fi

  local artifact
  artifact="$(ls -1 "$ROOT"/packages/sourcemod-*-css34-linux.tar.gz | tail -1)"
  cp "$artifact" "$RESULTS_DIR/${variant}.tar.gz"

  EXP8_VARIANT="$variant" "$ROOT/builder/compare-release.sh" "$artifact" \
    > "$RESULTS_DIR/${variant}-summary.txt" 2>&1 || true

  echo "==> Saved $RESULTS_DIR/${variant}-summary.txt"
}

for variant in "${VARIANTS[@]}"; do
  run_variant "$variant"
done

echo ""
echo "==> EXP8 matrix complete. Results in $RESULTS_DIR/"
python3 - "$RESULTS_DIR" <<'PY'
import re
import sys
from pathlib import Path

results = Path(sys.argv[1])
variants = ['minimal-symlinks', 'narrow-includes', 'wide-includes']
sdk_modules = [
    'addons/sourcemod/bin/sourcemod.1.ep1.so',
    'addons/sourcemod/extensions/sdkhooks.ext.1.ep1.so',
    'addons/sourcemod/extensions/sdktools.ext.1.ep1.so',
    'addons/sourcemod/extensions/game.cstrike.ext.1.ep1.so',
]

print('\n=== EXP8 SDK size matrix (delta vs original) ===')
header = '{:<55}'.format('module') + ''.join('{:>16}'.format(v) for v in variants)
print(header)
print('-' * len(header))

for module in sdk_modules:
    row = [module[-44:]]
    for variant in variants:
        summary = results / '{}-summary.txt'.format(variant)
        if not summary.is_file():
            row.append('n/a')
            continue
        text = summary.read_text()
        m = re.search(
            r'^\s+{}: orig=(\d+) built=(\d+) \(([+-]\d+)\)'.format(re.escape(module)),
            text,
            re.MULTILINE,
        )
        row.append(m.group(3) if m else '?')
    print('{:<55}'.format(row[0]) + ''.join('{:>16}'.format(v) for v in row[1:]))
PY
