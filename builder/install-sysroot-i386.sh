#!/usr/bin/env bash
# Trusty-era i386 libc + libstdc++4.8 for logic.so (rom4s used 14.04-era libstdc++).
# Core/extensions still compile against host gcc-9; logic alone uses this sysroot.
set -euo pipefail

DEPS_DIR="${1:?deps directory required}"
SYSROOT="$DEPS_DIR/sysroot-i386"
UBUNTU_OLD="${UBUNTU_OLD_RELEASES:-http://old-releases.ubuntu.com/ubuntu/pool/main}"
MARKER="$SYSROOT/.installed-trusty-i386-libcxx48"

if [[ -f "$MARKER" ]]; then
  echo "==> Trusty i386 sysroot already installed at $SYSROOT" >&2
  exit 0
fi

TMP="$(mktemp -d)"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

fetch_deb() {
  local url="$1"
  local out="$2"
  if [[ ! -f "$out" ]]; then
    curl -fsSL -o "$out" "$url"
  fi
  echo "$out"
}

echo "==> Installing Trusty i386 sysroot under $SYSROOT" >&2
rm -rf "$SYSROOT"
mkdir -p "$SYSROOT"

LIBC6_VER="${LIBC6_VER:-2.19-10ubuntu2.3}"
LINUX_LIBC_VER="${LINUX_LIBC_VER:-3.13.0-24.46}"
GCC48_VER="${GCC48_VER:-4.8.4-2ubuntu1~14.04.4}"

libc6="$(fetch_deb "${UBUNTU_OLD}/g/glibc/libc6_${LIBC6_VER}_i386.deb" "$TMP/libc6.deb")"
libc6dev="$(fetch_deb "${UBUNTU_OLD}/g/glibc/libc6-dev_${LIBC6_VER}_i386.deb" "$TMP/libc6-dev.deb")"
libstdcxx="$(fetch_deb "${UBUNTU_OLD}/g/gcc-4.8/libstdc++4.8-dev_${GCC48_VER}_i386.deb" "$TMP/libstdc++4.8-dev.deb")"
libgcc="$(fetch_deb "${UBUNTU_OLD}/g/gcc-4.8/libgcc-4.8-dev_${GCC48_VER}_i386.deb" "$TMP/libgcc-4.8-dev.deb")"

for deb in "$libc6" "$libc6dev" "$libstdcxx" "$libgcc"; do
  dpkg-deb -x "$deb" "$SYSROOT"
done

linuxlibc_name="linux-libc-dev_${LINUX_LIBC_VER}_i386.deb"
for pool in \
  "http://archive.ubuntu.com/ubuntu/pool/main/l/linux" \
  "${UBUNTU_OLD}/l/linux"; do
  if curl -fsSL -o "$TMP/$linuxlibc_name" "${pool}/${linuxlibc_name}" 2>/dev/null; then
    dpkg-deb -x "$TMP/$linuxlibc_name" "$SYSROOT"
    break
  fi
done

if [[ ! -f "$SYSROOT/usr/lib/gcc/i686-linux-gnu/4.8/libstdc++.a" ]]; then
  echo "Trusty libstdc++.a missing after sysroot install" >&2
  find "$SYSROOT/usr/lib/gcc" -name 'libstdc++.a' 2>/dev/null || true
  exit 1
fi

cat > "$DEPS_DIR/sysroot-i386.env" <<EOF
export SM_I386_SYSROOT="$SYSROOT"
export SM_LOGIC_CXX_SYSROOT="$SYSROOT"
EOF

date -u > "$MARKER"
echo "==> Sysroot ready: $SYSROOT" >&2
ls -la "$SYSROOT/usr/lib/gcc/i686-linux-gnu/4.8/libstdc++.a" >&2
