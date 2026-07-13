#!/usr/bin/env bash
# Old i386 libstdc++8 for logic.so (pre-CXX11 ABI pollution on gcc-9 hosts).
# Core/extensions still use host gcc-9; logic alone uses this tree.
set -euo pipefail

DEPS_DIR="${1:?deps directory required}"
SYSROOT="$DEPS_DIR/sysroot-i386"
DEBIAN_ARCHIVE="${DEBIAN_ARCHIVE:-http://archive.debian.org/debian}"
POOL="${DEBIAN_ARCHIVE}/pool/main"
GCC8_VER="${GCC8_VER:-8.3.0-6}"
MARKER="$SYSROOT/.installed-buster-gcc8-i386"

if [[ -f "$MARKER" ]]; then
  echo "==> gcc-8 i386 logic sysroot already installed at $SYSROOT" >&2
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

echo "==> Installing buster gcc-8 i386 logic sysroot under $SYSROOT" >&2
rm -rf "$SYSROOT"
mkdir -p "$SYSROOT"

libstdcxx="$(fetch_deb "${POOL}/g/gcc-8/libstdc++-8-dev_${GCC8_VER}_amd64.deb" "$TMP/libstdc++-8-dev.deb")"
lib32stdcxx="$(fetch_deb "${POOL}/g/gcc-8/lib32stdc++-8-dev_${GCC8_VER}_amd64.deb" "$TMP/lib32stdc++-8-dev.deb")"
libgcc="$(fetch_deb "${POOL}/g/gcc-8/libgcc-8-dev_${GCC8_VER}_amd64.deb" "$TMP/libgcc-8-dev.deb")"
lib32gcc="$(fetch_deb "${POOL}/g/gcc-8/lib32gcc-8-dev_${GCC8_VER}_amd64.deb" "$TMP/lib32gcc-8-dev.deb")"

for deb in "$libstdcxx" "$lib32stdcxx" "$libgcc" "$lib32gcc"; do
  dpkg-deb -x "$deb" "$SYSROOT"
done

if [[ ! -f "$SYSROOT/usr/lib/gcc/x86_64-linux-gnu/8/32/libstdc++.a" \
  && ! -f "$SYSROOT/usr/lib/gcc/i686-linux-gnu/8/libstdc++.a" ]]; then
  echo "buster gcc-8 libstdc++.a missing after sysroot install" >&2
  find "$SYSROOT/usr/lib/gcc" -name 'libstdc++.a' 2>/dev/null || true
  exit 1
fi

cat > "$DEPS_DIR/sysroot-i386.env" <<EOF
export SM_I386_SYSROOT="$SYSROOT"
export SM_LOGIC_CXX_SYSROOT="$SYSROOT"
EOF

date -u > "$MARKER"
echo "==> Logic sysroot ready: $SYSROOT" >&2
ls -la "$SYSROOT/usr/lib/gcc/x86_64-linux-gnu/8/32/libstdc++.a" 2>/dev/null \
  || ls -la "$SYSROOT/usr/lib/gcc/i686-linux-gnu/8/libstdc++.a" >&2
