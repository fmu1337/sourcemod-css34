#!/usr/bin/env bash
# Build third-party extensions for a line in the release image (the image of
# builder/docker/build.sh: manylinux2014 i686, devtoolset-10 GCC 10.2.1, glibc 2.17).
#
#   CSS34_LINE=sm13-latest builder/third-party/build.sh socket
#
# Run builder/docker/build.sh for the same line first: the extension is compiled
# against the patched SourceMod tree and with the spcomp that build leaves behind.
# Output goes to packages/third-party/ (or PACKAGES_DIR/third-party), never into
# the SourceMod package.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ext="${1:?usage: CSS34_LINE=<line> builder/third-party/build.sh socket}"
[[ -f "$ROOT/builder/third-party/${ext}.sh" ]] || { echo "FAIL: unknown third-party extension: ${ext}" >&2; exit 1; }

# One copy of the image digest: builder/docker/build.sh.
default_image="$(sed -nE 's/^IMAGE="\$\{ML2014_IMAGE:-(.+)\}"$/\1/p' "$ROOT/builder/docker/build.sh")"
[[ "$default_image" == *@sha256:* ]] || { echo "FAIL: cannot read the image from builder/docker/build.sh" >&2; exit 1; }
IMAGE="${ML2014_IMAGE:-$default_image}"
PACKAGES_DIR="${PACKAGES_DIR:-$ROOT/packages}"
mkdir -p "$PACKAGES_DIR"
PACKAGES_DIR="$(cd "$PACKAGES_DIR" && pwd)"

# shellcheck source=../resolve-version.sh
source "$ROOT/builder/resolve-version.sh"
css34_require_buildable

extra_args=()
if [[ -n "${CSS34_DOWNLOADS:-}" ]]; then
  CSS34_DOWNLOADS="$(cd "$CSS34_DOWNLOADS" && pwd)"
  extra_args+=(-v "$CSS34_DOWNLOADS:/downloads:ro" -e CSS34_DOWNLOADS=/downloads)
fi

docker_cmd() {
  if docker info >/dev/null 2>&1; then
    docker "$@"
  else
    sudo docker "$@"
  fi
}

echo "==> Building third-party ${ext} for ${CSS34_LINE} in ${IMAGE}" >&2
docker_cmd run --rm -i --platform linux/386 \
  --entrypoint linux32 \
  ${extra_args[@]+"${extra_args[@]}"} \
  -v "$ROOT:/workspace" \
  -v "$PACKAGES_DIR:/workspace/packages" \
  -w /workspace \
  -e CSS34_LINE="$CSS34_LINE" \
  -e SOURCEMOD_COMMIT="$SOURCEMOD_COMMIT" \
  -e EXT="$ext" \
  -e WDIR=/workspace \
  -e DEPS_DIR=/workspace/deps \
  -e PACKAGES_DIR=/workspace/packages \
  -e HOST_UID="$(id -u)" \
  -e HOST_GID="$(id -g)" \
  "$IMAGE" \
  bash -s <<'INNER'
set -euo pipefail
set +u
source /opt/rh/devtoolset-10/enable
set -u
export PATH="/opt/python/cp311-cp311/bin:${PATH}" CC=gcc CXX=g++
hash -r
command -v git >/dev/null 2>&1 || yum install -y git
git config --global --add safe.directory '*'
status=0
bash "builder/third-party/${EXT}.sh" || status=$?
chown -R "${HOST_UID}:${HOST_GID}" /workspace/deps /workspace/packages 2>/dev/null || true
exit "$status"
INNER
