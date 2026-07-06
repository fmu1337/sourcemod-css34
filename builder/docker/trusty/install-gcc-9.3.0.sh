#!/usr/bin/env bash
# Install gcc/g++ 9.3.0-11ubuntu0~14.04 on Ubuntu 14.04 (trusty).
#
# Superseded PPA binaries are no longer in the Launchpad pool; we reconstruct
# the published source (orig + debian + Launchpad diff) and build locally.
set -euo pipefail

GCC_DEB_VERSION='9.3.0-11ubuntu0~14.04'
BUILD_DIR="${GCC_BUILD_DIR:-/tmp/gcc9-build}"
ARCHIVE='https://archive.ubuntu.com/ubuntu/pool/main/g/gcc-9'
PPA_FILES='https://launchpad.net/~ubuntu-toolchain-r/+archive/ubuntu/test/+files'

if command -v gcc-9 >/dev/null 2>&1 && gcc-9 --version 2>&1 | grep -qF "$GCC_DEB_VERSION"; then
  echo "==> gcc-9 ($GCC_DEB_VERSION) already installed"
  exit 0
fi

echo "==> Building gcc-9 ($GCC_DEB_VERSION) from Ubuntu source"

apt-get update -qq
apt-get install -y -qq \
  devscripts \
  debhelper \
  fakeroot \
  equivs \
  autoconf \
  automake \
  libtool \
  bison \
  flex \
  texinfo \
  gettext \
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
  libcloog-isl-dev \
  expect \
  dejagnu \
  chrpath \
  dwz

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

curl -fsSL -o gcc-9_9.3.0.orig.tar.gz "$ARCHIVE/gcc-9_9.3.0.orig.tar.gz"
curl -fsSL -o gcc-9_9.3.0-10ubuntu2.debian.tar.xz "$ARCHIVE/gcc-9_9.3.0-10ubuntu2.debian.tar.xz"
curl -fsSL -o gcc-9_9.3.0-11ubuntu0.diff.gz \
  "$PPA_FILES/gcc-9_9.3.0-10ubuntu2~14.04.1_9.3.0-11ubuntu0~14.04.diff.gz"

tar -xzf gcc-9_9.3.0.orig.tar.gz
tar -xJf gcc-9_9.3.0-10ubuntu2.debian.tar.xz -C gcc-9-9.3.0/

# diff expects 9.3.0-10ubuntu2~14.04.1 debian metadata as the base.
sed -i '1s/.*/gcc-9 (9.3.0-10ubuntu2~14.04.1) trusty; urgency=medium/' gcc-9-9.3.0/debian/changelog
sed -i 's/9\.3\.0-10ubuntu2/9.3.0-10ubuntu2~14.04.1/g' gcc-9-9.3.0/debian/rules.parameters

gunzip -c gcc-9_9.3.0-11ubuntu0.diff.gz | patch -p0 || true

# Ensure version metadata matches the original Travis toolchain.
sed -i '1s/.*/gcc-9 (9.3.0-11ubuntu0~14.04) trusty; urgency=medium/' gcc-9-9.3.0/debian/changelog
cat > gcc-9-9.3.0/debian/rules.parameters <<EOF
# configuration parameters taken from upstream source files
GCC_VERSION	:= 9.3.0
NEXT_GCC_VERSION	:= 9.3.1
BASE_VERSION	:= 9
SOURCE_VERSION	:= ${GCC_DEB_VERSION}
DEB_VERSION	:= ${GCC_DEB_VERSION}
DEB_EVERSION	:= 1:${GCC_DEB_VERSION}
DEB_GDC_VERSION	:= ${GCC_DEB_VERSION}
DEB_SOVERSION	:= 5
DEB_SOEVERSION	:= 1:5
DEB_LIBGCC_SOVERSION	:= 
DEB_LIBGCC_VERSION	:= 1:${GCC_DEB_VERSION}
DEB_STDCXX_SOVERSION	:= 5
DEB_GOMP_SOVERSION	:= 5
GCC_SONAME	:= 1
CXX_SONAME	:= 6
FORTRAN_SONAME	:= 5
OBJC_SONAME	:= 4
GDC_VERSION	:= 9
GNAT_VERSION	:= 9
GNAT_SONAME	:= 9
FFI_SONAME	:= 7
SSP_SONAME	:= 0
GOMP_SONAME	:= 1
ITM_SONAME	:= 1
ATOMIC_SONAME	:= 1
BTRACE_SONAME	:= 1
ASAN_SONAME	:= 5
LSAN_SONAME	:= 0
TSAN_SONAME	:= 0
UBSAN_SONAME	:= 1
VTV_SONAME	:= 0
QUADMATH_SONAME	:= 0
GO_SONAME		:= 14
CC1_SONAME	:= 0
GCCJIT_SONAME	:= 0
GPHOBOS_SONAME	:= 76
GDRUNTIME_SONAME	:= 76
GM2_SONAME	:= 0
HSAIL_SONAME	:= 0
LIBC_DEP		:= libc6
EOF

export DEB_BUILD_OPTIONS="parallel=$(nproc)"
export DEB_CFLAGS_APPEND='-Wno-error'
export DEB_CXXFLAGS_APPEND='-Wno-error'

dpkg-buildpackage -b -uc -us -j"$(nproc)"

shopt -s nullglob
debs=(*.deb)
if [ "${#debs[@]}" -eq 0 ]; then
  echo "gcc-9 build produced no .deb files" >&2
  exit 1
fi

dpkg -i ./*.deb || apt-get -f install -y -qq
rm -f ./*.deb

if ! gcc-9 --version 2>&1 | grep -qF "$GCC_DEB_VERSION"; then
  echo "gcc-9 version mismatch after install:" >&2
  gcc-9 --version >&2 || true
  exit 1
fi

echo "==> Installed $(gcc-9 --version | head -1)"
apt-mark hold gcc-9 g++-9 gcc-9-multilib g++-9-multilib gcc-9-base cpp-9 \
  libgcc-9-dev lib32gcc-9-dev libstdc++-9-dev lib32stdc++-9-dev lib32stdc++6 \
  libstdc++6 libcc1-0 libgomp1 libitm1 libatomic1 libasan5 liblsan0 libubsan1 \
  libquadmath0 2>/dev/null || true

rm -rf "$BUILD_DIR"
