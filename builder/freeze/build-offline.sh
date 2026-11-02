#!/usr/bin/env bash
# T2.7: rebuild a frozen line from its input archive with --network none.
#
#   builder/freeze/build-offline.sh ASSETS_DIR PACKAGES_OUT
#
# ASSETS_DIR holds the files of builder/freeze/collect-inputs.sh (release
# sm11-freeze-inputs). Run it from a fresh checkout of MANIFEST.json's
# builder_commit (tag sm11-freeze): the build container gets no network, every
# git URL resolves to the archived mirrors and every download to dl-* files.
# Compare the result with testing/scripts/compare-package-abi.py.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ASSETS="$(cd "${1:?assets directory required}" && pwd)"
OUT="${2:?package output directory required}"
docker_cmd() { if docker info >/dev/null 2>&1; then docker "$@"; else sudo docker "$@"; fi; }
die() { echo "FAIL: $*" >&2; exit 1; }

command -v zstd >/dev/null || die "zstd is required"
[[ -f "$ASSETS/MANIFEST.json" && -f "$ASSETS/SHA256SUMS" ]] || die "$ASSETS has no MANIFEST.json / SHA256SUMS"
[[ ! -e "$ROOT/deps" ]] || die "$ROOT/deps exists: rebuild in a fresh checkout"
[[ ! -e "$ROOT/sourcemod/.git" ]] || die "$ROOT/sourcemod is initialized: rebuild in a fresh checkout"

echo "==> Checking SHA256SUMS"
(cd "$ASSETS" && sha256sum -c --quiet SHA256SUMS) || die "input archive does not match SHA256SUMS"

mget() { python3 -c 'import functools, json, sys; print(functools.reduce(lambda v, k: v[k], sys.argv[2].split("."), json.load(open(sys.argv[1]))))' "$ASSETS/MANIFEST.json" "$1"; }
LINE="$(mget line)"
TAG="$(mget image.tag)"
ID="$(mget image.id)"
BUILDER="$(mget builder_commit)"
head="$(git -C "$ROOT" rev-parse HEAD)"
if [[ "$head" != "$BUILDER" ]]; then
  [[ "${CSS34_ALLOW_OTHER_BUILDER:-0}" == 1 ]] || die "checkout is $head, the inputs were collected at $BUILDER (CSS34_ALLOW_OTHER_BUILDER=1 to override)"
  echo "NOTE: builder checkout $head differs from the collection's $BUILDER" >&2
fi

work="$(mktemp -d "${TMPDIR:-/tmp}/css34-offline.XXXXXX")"
trap 'sudo rm -rf "$work" 2>/dev/null || rm -rf "$work"' EXIT
mkdir -p "$work/inputs/git" "$work/inputs/downloads"

echo "==> Loading the build image ${TAG}"
zstd -dc "$ASSETS/build-image.tar.zst" | docker_cmd load -q
got="$(docker_cmd image inspect --format '{{.Id}}' "$TAG")"
[[ "$got" == "$ID" ]] || die "loaded image $TAG is $got, MANIFEST.json says $ID"

echo "==> Unpacking mirrors and downloads"
for f in "$ASSETS"/git-*.tar.zst; do
  zstd -dc "$f" | tar -C "$work/inputs/git" -xf -
done
for f in "$ASSETS"/dl-*; do
  cp -f "$f" "$work/inputs/downloads/$(basename "${f#"$ASSETS/dl-"}")"
done

echo "==> Building ${LINE} with --network none"
CSS34_LINE="$LINE" ML2014_IMAGE="$TAG" CSS34_INPUTS_DIR="$work/inputs" PACKAGES_DIR="$OUT" \
  bash "$ROOT/builder/docker/build.sh"
echo "==> Offline packages of ${LINE} in ${OUT}"
ls -la "$OUT"
