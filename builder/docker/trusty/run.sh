#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
IMAGE="${REPRO_TRUSTY_IMAGE:-sourcemod-css34-repro-trusty}"
DOCKER="${DOCKER:-sudo docker}"

cd "$ROOT"

echo "==> Building Docker image ($IMAGE) from Ubuntu 14.04"
$DOCKER build -f builder/docker/trusty/Dockerfile -t "$IMAGE" .

echo "==> Cleaning root-owned artifacts from any previous container run"
sudo rm -rf "$ROOT/deps" "$ROOT/sourcemod/build"

echo "==> Running trusty repro build in container"
$DOCKER run --rm \
  -v "$ROOT:/src" \
  -w /src \
  -e WDIR=/src \
  -e EXP7_ENABLED="${EXP7_ENABLED:-0}" \
  -e EXP7_VARIANT="${EXP7_VARIANT:-baseline}" \
  -e EXP8_ENABLED="${EXP8_ENABLED:-0}" \
  -e EXP8_VARIANT="${EXP8_VARIANT:-baseline}" \
  -e EXP8_SYMLINK_MODE="${EXP8_SYMLINK_MODE:-full}" \
  "$IMAGE" \
  bash -lc 'chmod +x builder/run/linux-repro-trusty.sh builder/run/linux-repro.sh builder/install-clang9.sh builder/checkout-deps.sh builder/package.sh builder/prepare-package.sh builder/compare-release.sh builder/patches/*.sh && builder/run/linux-repro-trusty.sh'

echo "==> Done. Artifact: $ROOT/packages/sourcemod-1.11.0-git6572-css34-linux.tar.gz"
