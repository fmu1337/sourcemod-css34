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
  -e SOURCEMOD_COMMIT="${SOURCEMOD_COMMIT:-832519ab647cdecb85763918dbfed1cb5e79c6cb}" \
  -e SOURCEMOD_GIT_REV="${SOURCEMOD_GIT_REV:-6572}" \
  -e USE_CLANG9=1 \
  -e WDIR=/workspace \
  -e DEPS_DIR=/workspace/deps \
  -e PACKAGES_DIR=/workspace/packages \
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
    apt-get update -qq
    apt-get install -y -qq \
      curl git python3 python3-pip \
      lib32stdc++6 lib32z1-dev libc6-dev-i386 linux-libc-dev \
      binutils ca-certificates \
      g++-9-multilib gcc-9-multilib \
      lib32stdc++-9-dev libstdc++-9-dev

    export CC=gcc-9 CXX=g++-9
    chmod +x builder/run/linux.sh builder/checkout-deps.sh builder/package.sh \
      builder/prepare-package.sh builder/py.sh builder/patches/*.sh \
      builder/install-clang9.sh builder/install-clang10.sh
    # Legacy host: no jammy sysroot; logic links with g++-9 -static-libstdc++.
    unset SM_I386_SYSROOT
    builder/run/linux.sh
  '

ARTIFACT="$(ls -1 "$PACKAGES_DIR"/sourcemod-*-css34-linux.tar.gz 2>/dev/null | head -n1)"
if [[ -z "${ARTIFACT}" || ! -f "${ARTIFACT}" ]]; then
  echo "Legacy docker build did not produce a package under ${PACKAGES_DIR}" >&2
  exit 1
fi

echo "==> Legacy build complete: ${ARTIFACT}" >&2
ls -la "${ARTIFACT}" >&2
