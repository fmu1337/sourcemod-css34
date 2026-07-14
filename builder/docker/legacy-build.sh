#!/usr/bin/env bash
# Build SourceMod css34 inside an old glibc container (rom4s-era hosts used 14.04).
# Jammy-native logic.so hangs srcds before the first SM mapchange line in smoke tests.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
IMAGE="${LEGACY_BUILD_IMAGE:-debian:11}"
PACKAGES_DIR="${PACKAGES_DIR:-$ROOT/packages}"

mkdir -p "$PACKAGES_DIR"

echo "==> Building SourceMod css34 in ${IMAGE}" >&2

docker run --rm --platform linux/amd64 \
  -v "$ROOT:/workspace" \
  -w /workspace \
  -e SKIP_APT_INSTALL=1 \
  -e SOURCEMOD_COMMIT="${SOURCEMOD_COMMIT:-bd1bde7def4c1e3e584c320dfb2ac974eb4d7433}" \
  -e SOURCEMOD_GIT_REV="${SOURCEMOD_GIT_REV:-7394}" \
  -e SOURCEMOD_MAJOR="${SOURCEMOD_MAJOR:-13}" \
  -e MMS_COMMIT="${MMS_COMMIT:-364cb6c26f66f7d9254d95a2fc533eac3557166b}" \
  -e USE_CLANG9=1 \
  -e WDIR=/workspace \
  -e DEPS_DIR=/workspace/deps \
  -e PACKAGES_DIR=/workspace/packages \
  -e SM_LOGIC_CXX_SYSROOT=/workspace/deps/sysroot-i386 \
  "$IMAGE" \
  bash -lc '
    set -euo pipefail
    export DEBIAN_FRONTEND=noninteractive
    dpkg --add-architecture i386
    # buster is EOL; deb.debian.org no longer serves Release files.
    if [[ -f /etc/os-release ]]; then
      # shellcheck disable=SC1091
      . /etc/os-release
      if [[ "${VERSION_ID:-}" == "10" || "${VERSION_CODENAME:-}" == "buster" ]]; then
        echo "==> Configuring archive.debian.org for buster" >&2
        rm -f /etc/apt/sources.list.d/* 2>/dev/null || true
        cat >/etc/apt/sources.list <<EOF
deb http://archive.debian.org/debian buster main contrib non-free
deb http://archive.debian.org/debian-security buster/updates main contrib non-free
deb http://archive.debian.org/debian buster-updates main contrib non-free
EOF
        cat >/etc/apt/apt.conf.d/99archive <<EOF
Acquire::Check-Valid-Until "false";
Acquire::AllowInsecureRepositories "true";
Acquire::AllowDowngradeToInsecureRepositories "true";
EOF
      fi
    fi
    apt_retry() {
      local attempt=1 max=5 delay=4
      while true; do
        if "$@"; then
          return 0
        fi
        if (( attempt >= max )); then
          echo "==> apt command failed after ${max} attempts: $*" >&2
          return 1
        fi
        echo "==> apt failed (attempt ${attempt}/${max}), retrying in ${delay}s..." >&2
        sleep "${delay}"
        delay=$((delay * 2))
        attempt=$((attempt + 1))
      done
    }
    apt_retry apt-get update -qq
    apt_retry apt-get install -y -qq \
      curl git python3 python3-pip \
      lib32stdc++6 lib32z1-dev libc6-dev-i386 linux-libc-dev \
      binutils ca-certificates \
      g++-9-multilib gcc-9-multilib \
      lib32stdc++-9-dev libstdc++-9-dev
    # Volume mount is owned by the host UID; git 2.35+ blocks submodule ops otherwise.
    # bullseye ships git 2.30 (no safe.directory=*); register mounted repos explicitly.
    register_git_safe_dirs() {
      local gd repo
      while IFS= read -r -d "" gd; do
        repo="${gd%/.git}"
        git config --global --add safe.directory "${repo}" 2>/dev/null || true
      done < <(find /workspace -name .git \( -type d -o -type f \) -print0 2>/dev/null || true)
    }
    register_git_safe_dirs

    export CC=gcc-9 CXX=g++-9
    chmod +x builder/run/linux.sh builder/checkout-deps.sh builder/package.sh \
      builder/package-metamod.sh builder/build-metamod.sh \
      builder/prepare-package.sh builder/py.sh builder/patches/*.sh \
      builder/install-clang9.sh builder/install-clang10.sh \
      builder/install-sysroot-i386.sh \
      builder/patches/patch-ambuild-linker.sh \
      builder/splice-reference-logic.sh builder/splice-reference-extras.sh
    builder/install-sysroot-i386.sh /workspace/deps
    # shellcheck source=/dev/null
    source /workspace/deps/sysroot-i386.env
    export DEPS_DIR=/workspace/deps SM_LOGIC_CXX_SYSROOT
    builder/run/linux.sh
  '

ARTIFACT="$(ls -1 "$PACKAGES_DIR"/sourcemod-*-css34-linux.tar.gz 2>/dev/null | head -n1)"
if [[ -z "${ARTIFACT}" || ! -f "${ARTIFACT}" ]]; then
  echo "Legacy docker build did not produce a package under ${PACKAGES_DIR}" >&2
  exit 1
fi

# SM 1.12 packs its own logic/extensions; splicing rom4s 1.11.0.6572 binaries
# would mask regressions and fail the logic splice-identity ABI check.
if [[ "${SOURCEMOD_MAJOR:-11}" -ge 12 ]]; then
  echo "==> Skipping rom4s logic/extras splice (SOURCEMOD_MAJOR=${SOURCEMOD_MAJOR})" >&2
else
  chmod +x "$ROOT/builder/splice-reference-extras.sh" "$ROOT/builder/splice-reference-logic.sh"
  "$ROOT/builder/splice-reference-extras.sh" "${ARTIFACT}"
  "$ROOT/builder/splice-reference-logic.sh" "${ARTIFACT}"
fi

echo "==> Legacy build complete: ${ARTIFACT}" >&2
ls -la "${ARTIFACT}" >&2
