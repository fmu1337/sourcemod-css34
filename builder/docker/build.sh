#!/usr/bin/env bash
# Build SourceMod css34 in manylinux2014_i686 (glibc 2.17, devtoolset-10 GCC 10.2.1).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
IMAGE="${ML2014_IMAGE:-quay.io/pypa/manylinux2014_i686@sha256:30305867f278896ee117b0d162a8e4f9b7b16819e6590f6139e14c5ed5b23fdd}"
PACKAGES_DIR="${PACKAGES_DIR:-$ROOT/packages}"
PURE_SOURCE_BUILD="${PURE_SOURCE_BUILD:-1}"

# Resolve SM/MM pins on the host so the container gets concrete values.
# shellcheck source=../resolve-version.sh
source "$ROOT/builder/resolve-version.sh"

if [[ "${PURE_SOURCE_BUILD}" == "1" ]]; then
  export SPLICE_REFERENCE_EXTRAS=0
  export SPLICE_REFERENCE_LOGIC=0
  echo "==> Pure-source mode: reference binary splicing is disabled" >&2
fi

mkdir -p "$PACKAGES_DIR"
PACKAGES_DIR="$(cd "$PACKAGES_DIR" && pwd)"

docker_cmd() {
  if docker info >/dev/null 2>&1; then
    docker "$@"
  else
    sudo docker "$@"
  fi
}

echo "==> Building SourceMod css34 in ${IMAGE} (line ${CSS34_LINE})" >&2

docker_cmd run --rm -i --platform linux/386 \
  --entrypoint linux32 \
  -v "$ROOT:/workspace" \
  -v "$PACKAGES_DIR:/workspace/packages" \
  -w /workspace \
  -e CSS34_LINE="${CSS34_LINE}" \
  -e SOURCEMOD_COMMIT="${SOURCEMOD_COMMIT}" \
  -e SOURCEMOD_GIT_REV="${SOURCEMOD_GIT_REV}" \
  -e SOURCEMOD_MAJOR="${SOURCEMOD_MAJOR}" \
  -e MMS_COMMIT="${MMS_COMMIT}" \
  -e MMS_BRANCH="${MMS_BRANCH}" \
  -e MMS_DIRNAME="${MMS_DIRNAME}" \
  -e MMS_MODE="${MMS_MODE}" \
  -e MMS_GIT_REV="${MMS_GIT_REV:-}" \
  -e PURE_SOURCE_BUILD="${PURE_SOURCE_BUILD}" \
  -e CSS34_DEBUG_TRACE="${CSS34_DEBUG_TRACE:-0}" \
  -e SPLICE_REFERENCE_EXTRAS="${SPLICE_REFERENCE_EXTRAS:-0}" \
  -e SPLICE_REFERENCE_LOGIC="${SPLICE_REFERENCE_LOGIC:-0}" \
  -e SKIP_APT_INSTALL=1 \
  -e CC=gcc \
  -e CXX=g++ \
  -e WDIR=/workspace \
  -e DEPS_DIR=/workspace/deps \
  -e PACKAGES_DIR=/workspace/packages \
  -e HOST_UID="$(id -u)" \
  -e HOST_GID="$(id -g)" \
  "$IMAGE" \
  bash -s <<'INNER'
set -euo pipefail
# linux32 makes uname/platform.machine() report i686. Without it AMBuild
# treats the 64-bit kernel as the host arch inside this 32-bit image.
# enable references unset MANPATH / rpmlibdir32; this script uses set -u.
set +u
source /opt/rh/devtoolset-10/enable
set -u
export PATH="/opt/python/cp311-cp311/bin:${PATH}"
hash -r

gcc_line="$(gcc --version | head -1)"
echo "==> Compiler: ${gcc_line}" >&2
echo "==> Python: $(python3 -V)" >&2
echo "==> glibc: $(ldd --version | head -1)" >&2
echo "==> arch: $(uname -m) $(gcc -dumpmachine)" >&2
case "${gcc_line}" in
  *"10.2.1"*) ;;
  *)
    echo "FAIL: expected devtoolset-10 GCC 10.2.1, got: ${gcc_line}" >&2
    exit 1
    ;;
esac
case "$(python3 -V)" in
  "Python 3.11."*) ;;
  *)
    echo "FAIL: expected CPython 3.11 at /opt/python/cp311-cp311, got: $(python3 -V)" >&2
    exit 1
    ;;
esac
if [[ "$(uname -m)" != "i686" || "$(gcc -dumpmachine)" != i686-* ]]; then
  echo "FAIL: manylinux build must be i686 (uname=$(uname -m) dumpmachine=$(gcc -dumpmachine))" >&2
  exit 1
fi

if ! command -v git >/dev/null 2>&1; then
  yum install -y git
fi
git config --global --add safe.directory '*' || true
register_git_safe_dirs() {
  local gd repo
  while IFS= read -r -d "" gd; do
    repo="${gd%/.git}"
    git config --global --add safe.directory "${repo}" 2>/dev/null || true
  done < <(find /workspace -name .git \( -type d -o -type f \) -print0 2>/dev/null || true)
}
register_git_safe_dirs

chmod +x builder/run/linux.sh builder/checkout-deps.sh builder/package.sh \
  builder/package-metamod.sh builder/build-metamod.sh \
  builder/prepare-package.sh builder/py.sh builder/patches/*.sh \
  builder/splice-reference-logic.sh builder/splice-reference-extras.sh \
  builder/download-geolite2.sh
builder/run/linux.sh
if [[ -n "${HOST_UID:-}" && -n "${HOST_GID:-}" ]]; then
  chown -R "${HOST_UID}:${HOST_GID}" /workspace/deps /workspace/packages /workspace/sourcemod 2>/dev/null || true
fi
INNER

sudo chown -R "$(id -u):$(id -g)" "$ROOT/deps" "$ROOT/packages" "$ROOT/sourcemod" 2>/dev/null || true

source "$ROOT/builder/package-paths.sh"
ARTIFACT="$SM_PACKAGE"
if [[ -z "${ARTIFACT}" || ! -f "${ARTIFACT}" ]]; then
  echo "manylinux build did not produce a package under ${PACKAGES_DIR}" >&2
  exit 1
fi

if [[ "${PURE_SOURCE_BUILD}" == "1" || "${SOURCEMOD_MAJOR:-11}" -ge 12 ]]; then
  echo "==> Skipping rom4s logic/extras splice (PURE_SOURCE_BUILD=${PURE_SOURCE_BUILD} SOURCEMOD_MAJOR=${SOURCEMOD_MAJOR:-})" >&2
else
  chmod +x "$ROOT/builder/splice-reference-extras.sh" "$ROOT/builder/splice-reference-logic.sh"
  "$ROOT/builder/splice-reference-extras.sh" "${ARTIFACT}"
  "$ROOT/builder/splice-reference-logic.sh" "${ARTIFACT}"
fi

if [[ "${PURE_SOURCE_BUILD}" == "1" ]]; then
  echo "==> Pure-source package contains only binaries produced by this build" >&2
fi

echo "==> Build complete: ${ARTIFACT}" >&2
ls -la "${ARTIFACT}" >&2
