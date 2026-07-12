#!/usr/bin/env bash
# Install gcc/g++ 9.3.0-11ubuntu0~14.04 on Ubuntu 14.04 (trusty).
#
# Superseded PPA binaries are gone. Full dpkg-buildpackage pulls in nvptx/jit
# and takes 2+ hours on CI; bootstrap C/C++ multilib only (~20-30 min).
set -euo pipefail

GCC_DEB_VERSION='9.3.0-11ubuntu0~14.04'
GCC_PKG_VERSION="Ubuntu ${GCC_DEB_VERSION}"
BUILD_DIR="${GCC_BUILD_DIR:-/tmp/gcc9-build}"
ARCHIVE='https://archive.ubuntu.com/ubuntu/pool/main/g/gcc-9'

if command -v gcc-9 >/dev/null 2>&1 && gcc-9 --version 2>&1 | grep -qF "$GCC_DEB_VERSION"; then
  echo "==> gcc-9 ($GCC_DEB_VERSION) already installed"
  exit 0
fi

echo "==> Bootstrapping gcc-9 ($GCC_DEB_VERSION) (C/C++ multilib, no debian packaging)"

apt-get update -qq
apt-get install -y -qq \
  build-essential \
  bison \
  flex \
  texinfo \
  gawk \
  patch \
  make \
  gperf \
  libmpc-dev \
  libmpfr-dev \
  libgmp-dev \
  zlib1g-dev \
  lib32z1-dev \
  libc6-dev-i386 \
  libisl-dev \
  libcloog-isl-dev

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

curl -fsSL -o gcc-9_9.3.0.orig.tar.gz "$ARCHIVE/gcc-9_9.3.0.orig.tar.gz"
tar -xzf gcc-9_9.3.0.orig.tar.gz
cd gcc-9-9.3.0
tar -xJf gcc-9.3.0.tar.xz
cd gcc-9.3.0

# Trusty ships libisl10 (isl 0.12); gcc 9.3 needs isl >= 0.15.
curl -fsSL -o isl-0.18.tar.bz2 https://gcc.gnu.org/pub/gcc/infrastructure/isl-0.18.tar.bz2
tar -xjf isl-0.18.tar.bz2
mv isl-0.18 isl

mkdir -p build
cd build
../configure \
  --prefix=/usr \
  --infodir=/usr/share/info \
  --mandir=/usr/share/man \
  --enable-checking=release \
  --build=x86_64-linux-gnu \
  --host=x86_64-linux-gnu \
  --target=x86_64-linux-gnu \
  --with-arch-32=i686 \
  --with-multilib-list=m32,m64 \
  --enable-multilib \
  --enable-languages=c,c++ \
  --disable-bootstrap \
  --disable-libsanitizer \
  --with-gmp=/usr \
  --with-mpfr=/usr \
  --with-mpc=/usr \
  --with-pkgversion="$GCC_PKG_VERSION" \
  --with-bugurl=file:///usr/share/doc/gcc-9/README.Bugs \
  --program-suffix=-9

make -j"$(nproc)"
make install

if ! gcc-9 --version 2>&1 | grep -qF "$GCC_DEB_VERSION"; then
  echo "gcc-9 version mismatch after install:" >&2
  gcc-9 --version >&2 || true
  exit 1
fi

if ! echo 'int main(void){return 0;}' | gcc-9 -m32 -x c - -o /tmp/gcc9-m32-test 2>/dev/null; then
  echo "gcc-9 -m32 smoke test failed" >&2
  exit 1
fi
rm -f /tmp/gcc9-m32-test

echo "==> Installed $(gcc-9 --version | head -1)"
rm -rf "$BUILD_DIR"
